import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:dio/dio.dart';

import '../models/workspace.dart';
import '../models/api_collection.dart';
import '../models/api_folder.dart';
import '../models/api_container.dart';
import '../models/api_request.dart';
import '../models/api_response.dart';
import '../models/environment.dart';
import '../models/workbench_tab.dart';
import '../services/http_client_service.dart';
import '../services/mcp_server_service.dart';
import '../services/storage_service.dart';
import '../services/apipost_migration_service.dart';
import '../services/s3_sync_service.dart';
import '../engine/variable_resolver.dart';
import 'widgets/status_badge.dart';
import 'widgets/key_value_editor.dart';
import 'widgets/environment_dialog.dart';
import 'widgets/mcp_panel.dart';
import 'widgets/ai_copilot_drawer.dart';
import 'widgets/api_tree_view.dart';
import 'widgets/container_settings_view.dart';
import 'widgets/json_syntax_highlighter.dart';
import 'widgets/help_dialog.dart';
import 'widgets/modern_dropdown.dart';
import 'folder_theme_config.dart';
import 'app_fonts.dart';
import '../services/tray_window_service.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with TickerProviderStateMixin {
  final StorageService _storageService = StorageService();
  final HttpClientService _httpClientService = HttpClientService();
  late McpServerService _mcpServerService;

  Workspace _workspace = Workspace.createDemo();
  bool _isLoadingWorkspace = true;
  bool _isMigratingApipost = false;
  bool _isSyncingS3 = false;
  String _s3SyncStatus = '';
  bool _s3SyncSuccess = true;

  // 打开的工作区标签页列表 (支持 API 调试页与容器公共配置页)
  final List<WorkbenchTab> _tabs = [];
  int _activeTabIndex = 0;

  // 记住的工作区 UI 状态：边侧栏展开节点集合与工作台状态持久化防抖
  final Set<String> _expandedNodeIds = {};
  bool _hasLoadedWorkbenchState = false;
  Timer? _persistWorkbenchDebounceTimer;

  void _schedulePersistWorkbenchState() {
    if (!_hasLoadedWorkbenchState) return;
    _persistWorkbenchDebounceTimer?.cancel();
    _persistWorkbenchDebounceTimer =
        Timer(const Duration(milliseconds: 300), () {
      _persistWorkbenchStateNow();
    });
  }

  void _persistWorkbenchStateNow() {
    if (!_hasLoadedWorkbenchState) return;
    _persistWorkbenchDebounceTimer?.cancel();
    _persistWorkbenchDebounceTimer = null;

    final openTabsState = _tabs.map((tab) {
      return WorkbenchTabState(
        id: tab.id,
        type: tab.type == TabType.request ? 'request' : 'container',
        isCollection: tab.isCollection,
      );
    }).toList();

    final state = WorkbenchState(
      openTabs: openTabsState,
      activeTabIndex: _activeTabIndex,
      expandedNodeIds: _expandedNodeIds.toList(),
    );

    _storageService.saveWorkbenchStateSync(state);
  }

  void _removeStaleTabs() {
    _tabs.removeWhere((tab) {
      if (tab.type == TabType.request) {
        return _workspace.findRequestById(tab.id) == null;
      } else {
        return _workspace.findContainerById(tab.id,
                isCollection: tab.isCollection) ==
            null;
      }
    });
    if (_tabs.isEmpty) {
      _activeTabIndex = 0;
    } else if (_activeTabIndex >= _tabs.length) {
      _activeTabIndex = _tabs.length - 1;
    }
    _syncCurrentRequestToControllers();
  }

  // 请求执行状态与响应映射
  final Map<String, bool> _requestLoading = {};
  final Map<String, ApiResponse?> _responses = {};
  final Map<String, CancelToken> _requestCancelTokens = {};
  final Map<String, DateTime> _requestStartTimes = {};
  Timer? _requestDurationTimer;

  void _startDurationTimerIfNeeded() {
    if (_requestDurationTimer != null && _requestDurationTimer!.isActive) return;
    _requestDurationTimer =
        Timer.periodic(const Duration(milliseconds: 100), (timer) {
      if (!mounted) {
        timer.cancel();
        _requestDurationTimer = null;
        return;
      }
      final hasActiveRequest =
          _requestLoading.values.any((loading) => loading);
      if (hasActiveRequest) {
        setState(() {});
      } else {
        timer.cancel();
        _requestDurationTimer = null;
      }
    });
  }

  void _stopDurationTimerIfNoActiveRequests() {
    final hasActiveRequest =
        _requestLoading.values.any((loading) => loading);
    if (!hasActiveRequest) {
      _requestDurationTimer?.cancel();
      _requestDurationTimer = null;
    }
  }

  String _getCurrentRequestDurationText(String requestId) {
    final startTime = _requestStartTimes[requestId];
    if (startTime == null) return '0 ms';
    final elapsedMs = DateTime.now().difference(startTime).inMilliseconds;
    if (elapsedMs < 1000) {
      return '$elapsedMs ms';
    } else {
      return '${(elapsedMs / 1000).toStringAsFixed(1)} s';
    }
  }

  void _cancelRequest(String requestId) {
    final token = _requestCancelTokens[requestId];
    if (token != null && !token.isCancelled) {
      token.cancel('用户已取消请求');
    }
  }

  // 当前请求编辑器的控制器 (Body 与前后置脚本均采用语法高亮)
  final TextEditingController _urlController = TextEditingController();
  final JsonSyntaxHighlightController _bodyController =
      JsonSyntaxHighlightController();
  final JsSyntaxHighlightController _preScriptController =
      JsSyntaxHighlightController();
  final JsSyntaxHighlightController _postScriptController =
      JsSyntaxHighlightController();

  // Tab 控制器
  late TabController _reqTabController;
  late TabController _resTabController;

  // 可拖拽调整大小的布局分栏状态
  double _sidebarWidth = 270.0;
  bool _isHoveringSidebarSplitter = false;
  bool _isDraggingSidebarSplitter = false;

  double _requestPanelRatio = 0.45;
  bool _isHoveringVerticalSplitter = false;
  bool _isDraggingVerticalSplitter = false;

  // 标签页双击关闭检测状态
  String? _lastTappedTabId;
  DateTime? _lastTabTapTime;

  // 左侧功能边侧栏模式 ('api' | 'history') 与右侧展开面板 ('ai' | 'curl' | null)
  String _leftNavMode = 'api';
  String? _activeRightPanel;

  // 响应区域查找 (Ctrl+F) 与视图切换 (JSON / 表格) 状态
  bool _showResponseSearch = false;
  final TextEditingController _responseSearchController =
      TextEditingController();
  final FocusNode _responseSearchFocusNode = FocusNode();
  String _responseSearchQuery = '';
  int _responseSearchActiveIndex = 0;
  int _responseSearchMatchCount = 0;
  String _responseViewMode = 'json'; // 'json' | 'table'
  String? _selectedResponseArrayPath;
  bool _editorDarkMode = false; // 代码编辑器与响应报文暗色高亮模式

  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  @override
  void initState() {
    super.initState();
    _reqTabController = TabController(length: 5, vsync: this);
    _resTabController = TabController(length: 4, vsync: this);
    HardwareKeyboard.instance.addHandler(_handleGlobalKeyEvent);

    // 标签与节点状态在 _initData() 异步加载完成后再统一恢复，避免初次渲染时被 Demo 数据覆盖

    _mcpServerService = McpServerService(
      httpClientService: _httpClientService,
      workspace: _workspace,
      onWorkspaceUpdated: (updated) {
        setState(() {
          _workspace = updated;
        });
        _storageService.saveWorkspace(_workspace);
      },
      onMcpLog: (_) {
        setState(() {});
      },
    );

    TrayWindowService.instance.init(
      onBeforeClose: () => _persistWorkbenchStateNow(),
      shouldMinimizeToTray: () => _workspace.minimizeToTrayOnClose,
    );

    _initData();
  }

  bool _handleGlobalKeyEvent(KeyEvent event) {
    if (event is KeyDownEvent) {
      final isCtrlOrMeta = HardwareKeyboard.instance.isControlPressed ||
          HardwareKeyboard.instance.isMetaPressed;
      if (event.logicalKey == LogicalKeyboardKey.keyS && isCtrlOrMeta) {
        _saveCurrentTab();
        return true;
      }
      if (event.logicalKey == LogicalKeyboardKey.keyF && isCtrlOrMeta) {
        _openResponseSearch();
        return true;
      }
      if (event.logicalKey == LogicalKeyboardKey.escape &&
          _showResponseSearch) {
        _closeResponseSearch();
        return true;
      }
    }
    return false;
  }

  void _openResponseSearch() {
    if (_resTabController.index != 0) {
      _resTabController.animateTo(0);
    }
    setState(() {
      _showResponseSearch = true;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _responseSearchFocusNode.requestFocus();
        if (_responseSearchController.text.isNotEmpty) {
          _responseSearchController.selection = TextSelection(
            baseOffset: 0,
            extentOffset: _responseSearchController.text.length,
          );
        }
      }
    });
  }

  void _closeResponseSearch() {
    setState(() {
      _showResponseSearch = false;
      _responseSearchQuery = '';
      _responseSearchActiveIndex = 0;
      _responseSearchMatchCount = 0;
    });
    _responseSearchFocusNode.unfocus();
  }

  void _nextResponseSearchMatch() {
    if (_responseSearchMatchCount <= 0) return;
    setState(() {
      _responseSearchActiveIndex =
          (_responseSearchActiveIndex + 1) % _responseSearchMatchCount;
    });
  }

  void _prevResponseSearchMatch() {
    if (_responseSearchMatchCount <= 0) return;
    setState(() {
      _responseSearchActiveIndex =
          (_responseSearchActiveIndex - 1 + _responseSearchMatchCount) %
              _responseSearchMatchCount;
    });
  }

  void _collectAllFolderIds(List<ApiFolder> folders, Set<String> target) {
    for (final f in folders) {
      target.add(f.id);
      _collectAllFolderIds(f.folders, target);
    }
  }

  Future<void> _initData() async {
    try {
      final loaded = await _storageService.loadWorkspace();
      if (!mounted) return;
      _workspace = loaded;
      _mcpServerService.updateWorkspace(_workspace);

      // 若当前工作区尚未包含 Apipost 迁移的「吉利」根目录，自动通过 Apipost MCP 迁移
      if (!_workspace.collections.any((c) => c.id == '1f727e84f71160')) {
        await _migrateFromApipostMcp(silent: true);
      }

      final savedState = await _storageService.loadWorkbenchState();
      if (!mounted) return;

      final restoredTabs = <WorkbenchTab>[];
      if (savedState != null) {
        _expandedNodeIds.clear();
        if (savedState.expandedNodeIds.isNotEmpty) {
          _expandedNodeIds.addAll(savedState.expandedNodeIds);
        } else {
          for (final col in _workspace.collections) {
            _expandedNodeIds.add(col.id);
            _collectAllFolderIds(col.folders, _expandedNodeIds);
          }
        }

        for (final tabState in savedState.openTabs) {
          if (tabState.type == 'request') {
            final req = _workspace.findRequestById(tabState.id);
            if (req != null) {
              restoredTabs.add(WorkbenchTab.request(req));
            }
          } else if (tabState.type == 'container') {
            final container = _workspace.findContainerById(
              tabState.id,
              isCollection: tabState.isCollection,
            );
            if (container != null) {
              restoredTabs.add(WorkbenchTab.container(
                container,
                isCollection: tabState.isCollection,
              ));
            }
          }
        }
      } else {
        _expandedNodeIds.clear();
        for (final col in _workspace.collections) {
          _expandedNodeIds.add(col.id);
          _collectAllFolderIds(col.folders, _expandedNodeIds);
        }
      }

      // 如果没有可恢复的 Tab（例如首次运行或所有引用的接口失效），兜底打开工作区的第一个有效接口
      if (restoredTabs.isEmpty && _workspace.collections.isNotEmpty) {
        final allReqs = _workspace.collections.first.findAllRequests();
        if (allReqs.isNotEmpty) {
          restoredTabs.add(WorkbenchTab.request(allReqs.first));
        } else if (_workspace.collections.first.requests.isNotEmpty) {
          restoredTabs.add(WorkbenchTab.request(_workspace.collections.first.requests.first));
        }
      }

      final targetActiveIndex = (savedState != null && restoredTabs.isNotEmpty)
          ? savedState.activeTabIndex.clamp(0, restoredTabs.length - 1)
          : 0;

      if (mounted) {
        setState(() {
          _tabs.clear();
          _tabs.addAll(restoredTabs);
          _activeTabIndex = targetActiveIndex;
          _hasLoadedWorkbenchState = true;
          _isLoadingWorkspace = false;
          _syncCurrentRequestToControllers();
        });
      }

      // 在内存成功恢复后，刷新一次当前有效状态到磁盘，覆盖可能存在的脏数据
      _persistWorkbenchStateNow();
    } catch (e) {
      if (mounted) {
        setState(() {
          _workspace = Workspace.createDemo();
          _hasLoadedWorkbenchState = true;
          _isLoadingWorkspace = false;
        });
      }
    }

    // 默认自动启动 MCP Server
    try {
      await _mcpServerService.startServer();
    } catch (_) {}
    if (mounted) setState(() {});
  }

  Future<void> _migrateFromApipostMcp({
    bool silent = false,
    void Function(void Function())? setModalState,
  }) async {
    if (_isMigratingApipost) return;
    setState(() {
      _isMigratingApipost = true;
    });
    debugPrint('正在连接 Apipost MCP...');
    setModalState?.call(() {});

    try {
      final result = await ApipostMigrationService.migrateFromMcp(
        onProgress: (completed, total, itemName) {
          if (!mounted) return;
          debugPrint('正在迁移 $completed / $total · $itemName');
          setModalState?.call(() {});
        },
      );

      if (!mounted) return;
      final migratedIds = result.collections.map((c) => c.id).toSet();
      final remainingCollections = _workspace.collections
          .where((c) =>
              !migratedIds.contains(c.id) &&
              c.id != 'col-user' &&
              c.id != 'col-order' &&
              c.name != 'PostMCP 示范接口库' &&
              c.name != 'MindPost 示范接口库')
          .toList();

      // 补充吉利项目常用网关到默认环境 baseUrl 枚举中
      if (_workspace.environments.isNotEmpty) {
        final devEnv = _workspace.environments.first;
        VariableItem? baseUrlVar;
        for (final v in devEnv.variables) {
          if (v.key == 'baseUrl') {
            baseUrlVar = v;
            break;
          }
        }
        if (baseUrlVar != null) {
          baseUrlVar.isEnum = true;
          baseUrlVar.showInHeader = true;
          final geelyOptions = [
            EnumOption(name: '数据管理服务 8085', value: 'http://127.0.0.1:8085'),
            EnumOption(name: '查询管理服务 8187', value: 'http://127.0.0.1:8187'),
            EnumOption(name: '认证权限服务 8082', value: 'http://127.0.0.1:8082'),
            EnumOption(
                name: '测试网关 9528',
                value: 'http://192.168.110.25:9528/pandroid-api'),
          ];
          for (final gOpt in geelyOptions.reversed) {
            if (!baseUrlVar.enumOptions.any((o) => o.value == gOpt.value)) {
              baseUrlVar.enumOptions.insert(0, gOpt);
            }
          }
          baseUrlVar.value = 'http://127.0.0.1:8085';
        }
      }

      setState(() {
        _workspace.collections = [
          ...result.collections,
          ...remainingCollections,
        ];
        _isMigratingApipost = false;
      });
      debugPrint('已完成迁移：${result.folderCount} 个目录，${result.apiCount} 个接口');
      setModalState?.call(() {});

      _mcpServerService.updateWorkspace(_workspace);
      await _storageService.saveWorkspace(_workspace);

      if (!silent && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                '已从 Apipost MCP 迁移 ${result.folderCount} 个目录、${result.apiCount} 个接口'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isMigratingApipost = false;
      });
      debugPrint('迁移失败: $e');
      setModalState?.call(() {});
      if (!silent) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Apipost MCP 迁移失败: $e'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  @override
  void dispose() {
    _requestDurationTimer?.cancel();
    _persistWorkbenchDebounceTimer?.cancel();
    _persistWorkbenchStateNow();
    HardwareKeyboard.instance.removeHandler(_handleGlobalKeyEvent);
    _mcpServerService.stopServer();
    _reqTabController.dispose();
    _resTabController.dispose();
    _urlController.dispose();
    _bodyController.dispose();
    _preScriptController.dispose();
    _postScriptController.dispose();
    _responseSearchController.dispose();
    _responseSearchFocusNode.dispose();
    TrayWindowService.instance.dispose();
    super.dispose();
  }

  WorkbenchTab? get _currentTab {
    if (_tabs.isEmpty || _activeTabIndex < 0 || _activeTabIndex >= _tabs.length) {
      return null;
    }
    return _tabs[_activeTabIndex];
  }

  ApiRequest? get _currentRequest {
    final tab = _currentTab;
    if (tab != null && tab.type == TabType.request) {
      return tab.request;
    }
    return null;
  }

  void _markCurrentTabDirty() {
    final tab = _currentTab;
    if (tab != null && !tab.isDirty) {
      setState(() {
        tab.isDirty = true;
      });
    }
  }

  void _flushActiveTabToModel() {
    final req = _currentRequest;
    if (req != null) {
      req.url = _urlController.text;
      req.bodyContent = _bodyController.text;
      req.preRequestScript = _preScriptController.text;
      req.postRequestScript = _postScriptController.text;
    }
  }

  Future<void> _testS3Connection({
    void Function(void Function())? setModalState,
  }) async {
    if (_isSyncingS3) return;
    setState(() {
      _isSyncingS3 = true;
      _s3SyncStatus = '正在测试 S3 连接...';
      _s3SyncSuccess = true;
    });
    setModalState?.call(() {});

    final result = await S3SyncService.testConnection(_workspace.s3Config);
    if (!mounted) return;
    setState(() {
      _isSyncingS3 = false;
      _s3SyncStatus = result.message;
      _s3SyncSuccess = result.success;
    });
    setModalState?.call(() {});
  }

  Future<void> _uploadToS3({
    bool silent = false,
    void Function(void Function())? setModalState,
  }) async {
    if (!_workspace.s3Config.isConfigured) {
      if (!silent && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('请先在设置中完成 S3 配置'),
            behavior: SnackBarBehavior.floating,
          ),
        );
        _showAppSettingsDialog(initialTab: 3);
      }
      return;
    }
    if (_isSyncingS3) return;

    _flushActiveTabToModel();
    setState(() {
      _isSyncingS3 = true;
      _s3SyncStatus = '正在上传工作区数据至 S3...';
      _s3SyncSuccess = true;
    });
    setModalState?.call(() {});

    final result = await S3SyncService.uploadWorkspace(
      _workspace.s3Config,
      _workspace,
    );
    if (!mounted) return;

    setState(() {
      _isSyncingS3 = false;
      _s3SyncStatus = result.message;
      _s3SyncSuccess = result.success;
    });
    setModalState?.call(() {});

    if (result.success) {
      await _storageService.saveWorkspace(_workspace);
    }

    if (!silent && mounted) {
      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result.message),
          backgroundColor: result.success ? null : Colors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _downloadFromS3({
    void Function(void Function())? setModalState,
  }) async {
    if (!_workspace.s3Config.isConfigured) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('请先在设置中完成 S3 配置'),
            behavior: SnackBarBehavior.floating,
          ),
        );
        _showAppSettingsDialog(initialTab: 3);
      }
      return;
    }
    if (_isSyncingS3) return;

    setState(() {
      _isSyncingS3 = true;
      _s3SyncStatus = '正在从 S3 拉取工作区数据...';
      _s3SyncSuccess = true;
    });
    setModalState?.call(() {});

    final result = await S3SyncService.downloadWorkspace(_workspace.s3Config);
    if (!mounted) return;

    if (result.success && result.workspace != null) {
      setState(() {
        _workspace = result.workspace!;
        _isSyncingS3 = false;
        _s3SyncStatus = result.message;
        _s3SyncSuccess = true;
        _tabs.clear();
        _activeTabIndex = 0;
        if (_workspace.collections.isNotEmpty) {
          final allReqs = _workspace.collections.first.findAllRequests();
          if (allReqs.isNotEmpty) {
            _openRequest(allReqs.first);
          }
        }
      });
      setModalState?.call(() {});
      _mcpServerService.updateWorkspace(_workspace);
      await _storageService.saveWorkspace(_workspace);
    } else {
      setState(() {
        _isSyncingS3 = false;
        _s3SyncStatus = result.message;
        _s3SyncSuccess = false;
      });
      setModalState?.call(() {});
    }

    if (mounted) {
      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result.message),
          backgroundColor: result.success ? null : Colors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  void _saveTabAtIndex(int index, {bool showToast = true}) {
    if (index < 0 || index >= _tabs.length) return;
    final tab = _tabs[index];
    if (tab.type == TabType.request && tab.request != null) {
      if (index == _activeTabIndex) {
        tab.request!.url = _urlController.text;
        tab.request!.bodyContent = _bodyController.text;
        tab.request!.preRequestScript = _preScriptController.text;
        tab.request!.postRequestScript = _postScriptController.text;
      }
      tab.title = tab.request!.name;
    } else if (tab.type == TabType.container && tab.container != null) {
      tab.title = (tab.container as dynamic).name as String;
    }
    setState(() {
      tab.isDirty = false;
    });
    _storageService.saveWorkspace(_workspace);
    if (_workspace.s3Config.isConfigured &&
        _workspace.s3Config.autoSyncOnSave) {
      _uploadToS3(silent: true);
    }
    if (showToast && mounted) {
      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('已保存「${tab.title}」'),
          duration: const Duration(milliseconds: 1100),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  void _saveCurrentTab() {
    if (_tabs.isEmpty || _activeTabIndex < 0 || _activeTabIndex >= _tabs.length) {
      return;
    }
    _saveTabAtIndex(_activeTabIndex);
  }

  void _syncCurrentRequestToControllers() {
    final req = _currentRequest;
    if (req != null) {
      _urlController.text = req.url;
      _bodyController.text = req.bodyContent;
      _preScriptController.text = req.preRequestScript;
      _postScriptController.text = req.postRequestScript;
    }
  }

  void _openRequest(ApiRequest request) {
    final existingIndex = _tabs.indexWhere(
        (t) => t.type == TabType.request && t.id == request.id);
    if (existingIndex >= 0) {
      setState(() {
        _activeTabIndex = existingIndex;
        _syncCurrentRequestToControllers();
      });
    } else {
      setState(() {
        _tabs.add(WorkbenchTab.request(request));
        _activeTabIndex = _tabs.length - 1;
        _syncCurrentRequestToControllers();
      });
    }
    _schedulePersistWorkbenchState();
  }

  void _openContainer(ApiContainer container, bool isCollection) {
    final id = container.id;
    final existingIndex = _tabs.indexWhere(
        (t) => t.type == TabType.container && t.id == id);
    if (existingIndex >= 0) {
      setState(() {
        _activeTabIndex = existingIndex;
      });
    } else {
      setState(() {
        _tabs.add(
            WorkbenchTab.container(container, isCollection: isCollection));
        _activeTabIndex = _tabs.length - 1;
      });
    }
    _schedulePersistWorkbenchState();
  }

  void _handleTabTap(int index) {
    if (index < 0 || index >= _tabs.length) return;
    final tab = _tabs[index];
    final now = DateTime.now();
    if (_workspace.doubleClickToCloseTab &&
        _lastTappedTabId == tab.id &&
        _lastTabTapTime != null &&
        now.difference(_lastTabTapTime!).inMilliseconds < 280) {
      _lastTappedTabId = null;
      _lastTabTapTime = null;
      _closeTab(index);
      return;
    }
    _lastTappedTabId = tab.id;
    _lastTabTapTime = now;
    if (_activeTabIndex != index) {
      setState(() {
        _activeTabIndex = index;
        _syncCurrentRequestToControllers();
      });
      _schedulePersistWorkbenchState();
    }
  }

  void _closeTab(int index) {
    if (index < 0 || index >= _tabs.length) return;
    setState(() {
      _tabs.removeAt(index);
      if (_tabs.isEmpty) {
        _activeTabIndex = 0;
      } else if (_activeTabIndex >= _tabs.length) {
        _activeTabIndex = _tabs.length - 1;
      } else if (index < _activeTabIndex) {
        _activeTabIndex -= 1;
      }
      _syncCurrentRequestToControllers();
    });
    _schedulePersistWorkbenchState();
  }

  void _closeOtherTabs(int keepIndex) {
    if (keepIndex < 0 || keepIndex >= _tabs.length) return;
    final keepTab = _tabs[keepIndex];
    setState(() {
      _tabs
        ..clear()
        ..add(keepTab);
      _activeTabIndex = 0;
      _syncCurrentRequestToControllers();
    });
    _schedulePersistWorkbenchState();
  }

  void _closeTabsToRight(int index) {
    if (index < 0 || index >= _tabs.length - 1) return;
    setState(() {
      _tabs.removeRange(index + 1, _tabs.length);
      if (_activeTabIndex >= _tabs.length) {
        _activeTabIndex = _tabs.length - 1;
      }
      _syncCurrentRequestToControllers();
    });
    _schedulePersistWorkbenchState();
  }

  void _closeTabsToLeft(int index) {
    if (index <= 0 || index >= _tabs.length) return;
    final currentActiveId = _currentTab?.id;
    setState(() {
      _tabs.removeRange(0, index);
      final foundIdx = _tabs.indexWhere((t) => t.id == currentActiveId);
      _activeTabIndex = foundIdx >= 0 ? foundIdx : 0;
      _syncCurrentRequestToControllers();
    });
    _schedulePersistWorkbenchState();
  }

  void _closeSavedTabs() {
    final currentActiveId = _currentTab?.id;
    setState(() {
      _tabs.removeWhere((t) => !t.isDirty);
      if (_tabs.isEmpty) {
        _activeTabIndex = 0;
      } else {
        final foundIdx = _tabs.indexWhere((t) => t.id == currentActiveId);
        _activeTabIndex = foundIdx >= 0 ? foundIdx : 0;
      }
      _syncCurrentRequestToControllers();
    });
    _schedulePersistWorkbenchState();
  }

  void _closeAllTabs() {
    setState(() {
      _tabs.clear();
      _activeTabIndex = 0;
    });
    _schedulePersistWorkbenchState();
  }

  void _addNewTab() {
    final newReq = ApiRequest(
      name: '临时调试请求',
      url: '{{baseUrl}}/get',
      method: HttpMethod.get,
    );
    _openRequest(newReq);
  }

  /// 记录接口调用历史：按调用时间倒序排列，最新调用置于最上方，同一接口只保留最新一条记录
  void _recordApiHistory(
    ApiRequest req,
    ApiResponse? response, {
    DateTime? calledAt,
  }) {
    _workspace.recordApiCall(
      req,
      statusCode: response?.statusCode,
      durationMs: response?.durationMs,
      calledAt: calledAt,
    );
  }

  Future<void> _sendCurrentRequest() async {
    final req = _currentRequest;
    if (req == null) return;

    // 同步控制器内容到模型
    req.url = _urlController.text;
    req.bodyContent = _bodyController.text;
    req.preRequestScript = _preScriptController.text;
    req.postRequestScript = _postScriptController.text;

    final calledTime = DateTime.now();
    final cancelToken = CancelToken();
    _requestCancelTokens[req.id] = cancelToken;
    _requestStartTimes[req.id] = calledTime;

    setState(() {
      _requestLoading[req.id] = true;
      _responses[req.id] = null; // 关键：立即清空上次响应，不在请求中保持旧状态
      _showResponseSearch = false;
      _responseSearchQuery = '';
      _recordApiHistory(req, null, calledAt: calledTime);
    });
    _startDurationTimerIfNeeded();
    unawaited(_storageService.saveWorkspace(_workspace));

    try {
      final execResult = await _httpClientService.executeRequest(
        request: req,
        workspace: _workspace,
        cancelToken: cancelToken,
      );

      if (mounted) {
        setState(() {
          _responses[req.id] = execResult.response;
          _recordApiHistory(
            req,
            execResult.response,
            calledAt: calledTime,
          );

          // 如果脚本修改了环境变量，回写
          if (execResult.updatedEnvironmentVariables.isNotEmpty &&
              _workspace.activeEnvironment != null) {
            final env = _workspace.activeEnvironment!;
            for (final entry in execResult.updatedEnvironmentVariables.entries) {
              final existing = env.variables.cast<VariableItem?>().firstWhere(
                    (v) => v?.key == entry.key,
                    orElse: () => null,
                  );
              if (existing != null) {
                existing.value = entry.value;
              } else {
                env.variables.add(VariableItem(key: entry.key, value: entry.value));
              }
            }
          }
        });
      }
      unawaited(_storageService.saveWorkspace(_workspace));
    } finally {
      _requestCancelTokens.remove(req.id);
      _requestStartTimes.remove(req.id);
      if (mounted) {
        setState(() {
          _requestLoading[req.id] = false;
        });
        _stopDurationTimerIfNoActiveRequests();
      }
    }
  }

  void _formatJsonBody() {
    try {
      final decoded = json.decode(_bodyController.text);
      _bodyController.text =
          const JsonEncoder.withIndent('  ').convert(decoded);
      if (_currentRequest != null) {
        _currentRequest!.bodyContent = _bodyController.text;
      }
      _markCurrentTabDirty();
    } catch (_) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Body 内容不是合法 JSON，无法格式化')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoadingWorkspace) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final activeEnv = _workspace.activeEnvironment;

    return Scaffold(
      key: _scaffoldKey,
      body: Column(
        children: [
          // 顶部专业导航栏
          _buildTopNavigationBar(activeEnv),

          // 下方主体工作台
          Expanded(
            child: Row(
              children: [
                // 左侧功能边侧栏 (API / 历史)
                _buildLeftFunctionSidebar(),

                // 左侧目录树或历史列表面板
                _buildLeftSidebar(),

                // 左右侧边栏宽度拖拽手柄
                _buildSidebarResizer(),

                // 中间多 Tab 调试主工作区
                Expanded(
                  child: _currentTab == null
                      ? _buildEmptyWorkspace()
                      : _buildMainWorkspace(),
                ),

                // 右侧展开工具面板 (AI 助手 / cURL 代码预览)
                if (_activeRightPanel == 'ai' &&
                    _workspace.aiConfig.isConfigured &&
                    _workspace.rightSidebarTools.contains('ai'))
                  AiCopilotDrawer(
                    activeRequest: _currentRequest,
                    aiConfig: _workspace.aiConfig,
                    onRequestUpdated: () {
                      setState(() {
                        _syncCurrentRequestToControllers();
                      });
                      _markCurrentTabDirty();
                    },
                    onOpenAiSettings: () => _showAppSettingsDialog(initialTab: 2),
                    onClose: () => setState(() => _activeRightPanel = null),
                  ),
                if (_activeRightPanel == 'curl' &&
                    _workspace.rightSidebarTools.contains('curl'))
                  _buildRightCurlPanel(),

                // 右侧工具边侧栏 (AI / MCP / 环境 / 同步 / cURL)
                _buildRightToolSidebar(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // 1. 顶部全局导航栏
  Widget _buildTopNavigationBar(Environment? activeEnv) {
    final mcpRunning = _mcpServerService.isRunning;
    final headerEnumVars = activeEnv == null
        ? <VariableItem>[]
        : activeEnv.variables
            .where((v) =>
                v.isEnabled &&
                v.isEnum &&
                v.showInHeader &&
                v.key.trim().isNotEmpty)
            .toList();

    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Color(0xFFE2E8F0))),
      ),
      child: Row(
        children: [
          // Logo & Title
          Row(
            children: [
              Image.asset(
                'assets/app_logo.png',
                width: 28,
                height: 28,
                filterQuality: FilterQuality.medium,
              ),
              const SizedBox(width: 9),
              const Text(
                'MindPost',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 17,
                  color: Color(0xFF0F172A),
                  letterSpacing: -0.5,
                ),
              ),
            ],
          ),

          const Spacer(),

          // 顶部环境选择器聚合底座容器（无阴影纯平设计）
          Container(
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              color: const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFFE2E8F0), width: 0.5),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 顶栏快速切换枚举变量区域
                if (headerEnumVars.isNotEmpty)
                  ...headerEnumVars.map((v) {
                    final Map<String, EnumOption> optMap = {};
                    for (final o in v.enumOptions) {
                      if (o.value.trim().isNotEmpty &&
                          !optMap.containsKey(o.value)) {
                        optMap[o.value] = o;
                      }
                    }
                    if (v.value.trim().isNotEmpty &&
                        !optMap.containsKey(v.value)) {
                      optMap[v.value] =
                          EnumOption(name: v.value, value: v.value);
                    }
                    final options = optMap.values.toList();
                    if (options.isEmpty) {
                      options.add(EnumOption(name: '空值', value: ''));
                    }
                    final currentVal =
                        options.any((o) => o.value == v.value)
                            ? v.value
                            : options.first.value;
                    final currentOpt = options.firstWhere(
                      (o) => o.value == currentVal,
                      orElse: () => options.first,
                    );

                    return ModernDropdown<String>(
                      value: currentVal,
                      menuWidth: 160,
                      tooltip: '切换 ${v.key} 枚举变量',
                      items: options.map((opt) {
                        return ModernDropdownItem<String>(
                          value: opt.value,
                          label: opt.displayLabel,
                        );
                      }).toList(),
                      onChanged: (newVal) {
                        setState(() {
                          v.value = newVal;
                        });
                        _mcpServerService.updateWorkspace(_workspace);
                        _storageService.saveWorkspace(_workspace);
                      },
                      child: Container(
                        height: 28,
                        margin: const EdgeInsets.only(right: 2),
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                              color: const Color(0xFFE2E8F0), width: 0.8),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 5, vertical: 1.5),
                              decoration: BoxDecoration(
                                color: const Color(0xFFEFF6FF),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                v.key,
                                style: AppFonts.code(
                                  fontSize: 10.0,
                                  fontWeight: FontWeight.w700,
                                  color: const Color(0xFF2563EB),
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 160),
                              child: Text(
                                currentOpt.displayLabel,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 11.5,
                                  color: Color(0xFF0F172A),
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            const SizedBox(width: 3),
                            const Icon(
                              Icons.keyboard_arrow_down_rounded,
                              size: 14,
                              color: Color(0xFF64748B),
                            ),
                          ],
                        ),
                      ),
                    );
                  }),

                // 现代环境切换下拉框（优雅下挂浮层、消除粗重原生灰块选中态）
                ModernDropdown<String?>(
                  value: _workspace.activeEnvironmentId,
                  menuWidth: 160,
                  tooltip: '切换当前运行环境',
                  items: [
                    const ModernDropdownItem<String?>(
                      value: null,
                      label: '无环境',
                      icon: Icon(Icons.public_off_rounded,
                          size: 14, color: Color(0xFF94A3B8)),
                    ),
                    ..._workspace.environments.map((e) {
                      return ModernDropdownItem<String?>(
                        value: e.id,
                        label: e.name,
                        icon: Container(
                          width: 7,
                          height: 7,
                          decoration: const BoxDecoration(
                            color: Color(0xFF10B981),
                            shape: BoxShape.circle,
                          ),
                        ),
                      );
                    }),
                  ],
                  onChanged: (val) {
                    setState(() {
                      _workspace.activeEnvironmentId = val;
                    });
                    _mcpServerService.updateWorkspace(_workspace);
                    _storageService.saveWorkspace(_workspace);
                  },
                  child: Container(
                    height: 28,
                    margin: const EdgeInsets.only(right: 2),
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                          color: const Color(0xFFE2E8F0), width: 0.8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (activeEnv != null)
                          Container(
                            width: 6,
                            height: 6,
                            margin: const EdgeInsets.only(right: 5),
                            decoration: const BoxDecoration(
                              color: Color(0xFF10B981),
                              shape: BoxShape.circle,
                            ),
                          )
                        else
                          const Padding(
                            padding: EdgeInsets.only(right: 4),
                            child: Icon(Icons.public_rounded,
                                size: 13, color: Color(0xFF94A3B8)),
                          ),
                        Text(
                          activeEnv?.name ?? '无环境',
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: activeEnv != null
                                ? FontWeight.w600
                                : FontWeight.normal,
                            color: activeEnv != null
                                ? const Color(0xFF0F172A)
                                : const Color(0xFF64748B),
                          ),
                        ),
                        const SizedBox(width: 4),
                        const Icon(
                          Icons.keyboard_arrow_down_rounded,
                          size: 15,
                          color: Color(0xFF64748B),
                        ),
                      ],
                    ),
                  ),
                ),

                // 环境管理弹窗按钮（白色背景、6.0 圆角）
                Tooltip(
                  message: '管理环境变量',
                  child: InkWell(
                    borderRadius: BorderRadius.circular(6),
                    onTap: () {
                      showDialog<void>(
                        context: context,
                        builder: (_) => EnvironmentDialog(
                          workspace: _workspace,
                          onSaved: () {
                            setState(() {});
                            _mcpServerService.updateWorkspace(_workspace);
                            _storageService.saveWorkspace(_workspace);
                          },
                        ),
                      );
                    },
                    child: Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                            color: const Color(0xFFE2E8F0), width: 0.8),
                      ),
                      child: const Icon(Icons.tune_rounded,
                          size: 14, color: Color(0xFF475569)),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),

          // MCP Server 状态与控制面板入口
          InkWell(
            onTap: () {
              showDialog<void>(
                context: context,
                builder: (_) => McpPanel(
                  mcpServerService: _mcpServerService,
                  onStateChanged: () => setState(() {}),
                ),
              );
            },
            borderRadius: BorderRadius.circular(7),
            child: Container(
              height: 32,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                color: mcpRunning
                    ? const Color(0xFFECFDF5)
                    : const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(7),
                border: Border.all(
                  color: mcpRunning
                      ? const Color(0xFFA7F3D0)
                      : const Color(0xFFE2E8F0),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 7,
                    height: 7,
                    decoration: BoxDecoration(
                      color: mcpRunning
                          ? const Color(0xFF059669)
                          : const Color(0xFF94A3B8),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    mcpRunning ? 'MCP :${_mcpServerService.port}' : 'MCP 离线',
                    style: TextStyle(
                      color: mcpRunning
                          ? const Color(0xFF059669)
                          : const Color(0xFF64748B),
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),

          // S3 云同步快捷入口与菜单
          PopupMenuButton<String>(
            tooltip: _workspace.s3Config.lastSyncTime != null
                ? 'S3 同步 · 上次同步 ${_workspace.s3Config.lastSyncTime}'
                : 'S3 数据同步',
            offset: const Offset(0, 36),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            onSelected: (action) {
              if (action == 'upload') {
                _uploadToS3();
              } else if (action == 'download') {
                _downloadFromS3();
              } else if (action == 'settings') {
                _showAppSettingsDialog(initialTab: 3);
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem<String>(
                value: 'upload',
                height: 36,
                child: Row(
                  children: [
                    Icon(Icons.cloud_upload_outlined,
                        size: 16, color: Color(0xFF2563EB)),
                    SizedBox(width: 8),
                    Text('上传同步到 S3', style: TextStyle(fontSize: 12.5)),
                  ],
                ),
              ),
              const PopupMenuDivider(height: 8),
              const PopupMenuItem<String>(
                value: 'download',
                height: 36,
                child: Row(
                  children: [
                    Icon(Icons.cloud_download_outlined,
                        size: 16, color: Color(0xFF059669)),
                    SizedBox(width: 8),
                    Text('从 S3 拉取同步', style: TextStyle(fontSize: 12.5)),
                  ],
                ),
              ),
              const PopupMenuDivider(height: 8),
              const PopupMenuItem<String>(
                value: 'settings',
                height: 36,
                child: Row(
                  children: [
                    Icon(Icons.settings_suggest_outlined,
                        size: 16, color: Color(0xFF475569)),
                    SizedBox(width: 8),
                    Text('S3 同步配置', style: TextStyle(fontSize: 12.5)),
                  ],
                ),
              ),
            ],
            child: Container(
              height: 32,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                color: _workspace.s3Config.isConfigured
                    ? const Color(0xFFEFF6FF)
                    : const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: _workspace.s3Config.isConfigured
                      ? const Color(0xFFBFDBFE)
                      : const Color(0xFFE2E8F0),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_isSyncingS3)
                    const SizedBox(
                      width: 13,
                      height: 13,
                      child: CircularProgressIndicator(
                        strokeWidth: 1.8,
                        color: Color(0xFF2563EB),
                      ),
                    )
                  else
                    Icon(
                      _workspace.s3Config.isConfigured
                          ? Icons.cloud_done_outlined
                          : Icons.cloud_sync_outlined,
                      size: 15,
                      color: _workspace.s3Config.isConfigured
                          ? const Color(0xFF2563EB)
                          : const Color(0xFF64748B),
                    ),
                  const SizedBox(width: 5),
                  Text(
                    _isSyncingS3 ? '同步中' : '同步',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: _workspace.s3Config.isConfigured
                          ? const Color(0xFF1D4ED8)
                          : const Color(0xFF475569),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 帮助与文档中心弹窗
  void _showHelpDialog({int initialTab = 0}) {
    HelpDialog.show(
      context,
      workspace: _workspace,
      initialTab: initialTab,
      onWorkspaceChanged: () {
        setState(() {});
        _storageService.saveWorkspace(_workspace);
      },
    );
  }

  /// 软件设置弹窗
  void _showAppSettingsDialog({int initialTab = 0}) {
    final s3 = _workspace.s3Config;
    final ai = _workspace.aiConfig;
    final endpointCtrl = TextEditingController(text: s3.endpoint);
    final regionCtrl = TextEditingController(text: s3.region);
    final bucketCtrl = TextEditingController(text: s3.bucket);
    final objectKeyCtrl = TextEditingController(text: s3.objectKey);
    final accessKeyCtrl = TextEditingController(text: s3.accessKeyId);
    final secretKeyCtrl = TextEditingController(text: s3.secretAccessKey);
    final aiBaseUrlCtrl = TextEditingController(text: ai.baseUrl);
    final aiApiKeyCtrl = TextEditingController(text: ai.apiKey);
    final aiModelCtrl = TextEditingController(text: ai.model);
    final historyLimitCtrl =
        TextEditingController(text: '${_workspace.historyLimit}');
    bool obscureSecret = true;
    bool obscureAiKey = true;
    int selectedSection = initialTab.clamp(0, 3);

    void syncControllersToConfig() {
      s3.endpoint = endpointCtrl.text.trim();
      s3.region = regionCtrl.text.trim().isEmpty
          ? 'us-east-1'
          : regionCtrl.text.trim();
      s3.bucket = bucketCtrl.text.trim();
      s3.objectKey = objectKeyCtrl.text.trim().isEmpty
          ? 'mindpost/workspace.json'
          : objectKeyCtrl.text.trim();
      s3.accessKeyId = accessKeyCtrl.text.trim();
      s3.secretAccessKey = secretKeyCtrl.text.trim();

      ai.baseUrl = aiBaseUrlCtrl.text.trim();
      ai.apiKey = aiApiKeyCtrl.text.trim();
      ai.model = aiModelCtrl.text.trim().isEmpty
          ? 'gpt-4o-mini'
          : aiModelCtrl.text.trim();

      final parsedLimit = int.tryParse(historyLimitCtrl.text.trim());
      if (parsedLimit != null) {
        _workspace.historyLimit = parsedLimit.clamp(1, 200);
      }

      if (!ai.isConfigured && _activeRightPanel == 'ai') {
        _activeRightPanel = null;
      }

      _storageService.saveWorkspace(_workspace);
      if (mounted) setState(() {});
    }

    final navItems = <Map<String, dynamic>>[
      {
        'icon': Icons.palette_outlined,
        'title': '外观与主题',
        'subtitle': '侧边栏配色方案与界面视图偏好',
      },
      {
        'icon': Icons.view_sidebar_outlined,
        'title': '工具栏与历史',
        'subtitle': '配置右侧工具栏显示项与左侧历史调用记录条数',
      },
      {
        'icon': Icons.auto_awesome_outlined,
        'title': 'AI 助手配置',
        'subtitle': '配置大模型连接参数，未配置时主页面自动隐藏 AI 入口',
      },
      {
        'icon': Icons.cloud_sync_outlined,
        'title': 'S3 云端同步',
        'subtitle': '通过兼容 S3 的对象存储多端同步工作区',
      },
    ];

    showDialog<void>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final currentNav = navItems[selectedSection];
            final activePalette =
                SidebarPalette.fromId(_workspace.sidebarTheme);

            return Dialog(
              backgroundColor: Colors.white,
              surfaceTintColor: Colors.transparent,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              clipBehavior: Clip.antiAlias,
              child: SizedBox(
                width: 800,
                height: 580,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // 左侧设置分类导航栏
                    Container(
                      width: 204,
                      decoration: const BoxDecoration(
                        color: Color(0xFFF8FAFC),
                        border: Border(
                          right: BorderSide(color: Color(0xFFE2E8F0)),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(18, 20, 16, 16),
                            child: Row(
                              children: [
                                Container(
                                  width: 28,
                                  height: 28,
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF2563EB),
                                    borderRadius: BorderRadius.circular(7),
                                  ),
                                  child: const Icon(
                                    Icons.tune_rounded,
                                    color: Colors.white,
                                    size: 16,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                const Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        '设置',
                                        style: TextStyle(
                                          fontSize: 14.5,
                                          fontWeight: FontWeight.w700,
                                          color: Color(0xFF0F172A),
                                        ),
                                      ),
                                      SizedBox(height: 1),
                                      Text(
                                        'MindPost 配置中心',
                                        style: TextStyle(
                                          fontSize: 10.5,
                                          color: Color(0xFF64748B),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const Divider(height: 1, color: Color(0xFFE2E8F0)),
                          const SizedBox(height: 10),
                          Expanded(
                            child: ListView.separated(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 10),
                              itemCount: navItems.length,
                              separatorBuilder: (_, _) =>
                                  const SizedBox(height: 4),
                              itemBuilder: (context, index) {
                                final item = navItems[index];
                                final isSelected = selectedSection == index;
                                return InkWell(
                                  borderRadius: BorderRadius.circular(8),
                                  onTap: () {
                                    setModalState(() {
                                      selectedSection = index;
                                    });
                                  },
                                  child: AnimatedContainer(
                                    duration: const Duration(milliseconds: 140),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 10,
                                    ),
                                    decoration: BoxDecoration(
                                      color: isSelected
                                          ? const Color(0xFFEFF6FF)
                                          : Colors.transparent,
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(
                                        color: isSelected
                                            ? const Color(0xFFBFDBFE)
                                            : Colors.transparent,
                                      ),
                                    ),
                                    child: Row(
                                      children: [
                                        Icon(
                                          item['icon'] as IconData,
                                          size: 17,
                                          color: isSelected
                                              ? const Color(0xFF2563EB)
                                              : const Color(0xFF64748B),
                                        ),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          child: Text(
                                            item['title'] as String,
                                            style: TextStyle(
                                              fontSize: 12.5,
                                              fontWeight: isSelected
                                                  ? FontWeight.w700
                                                  : FontWeight.w500,
                                              color: isSelected
                                                  ? const Color(0xFF1D4ED8)
                                                  : const Color(0xFF334155),
                                            ),
                                          ),
                                        ),
                                        if (isSelected)
                                          Container(
                                            width: 5,
                                            height: 5,
                                            decoration: const BoxDecoration(
                                              color: Color(0xFF2563EB),
                                              shape: BoxShape.circle,
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                          Container(
                            margin: const EdgeInsets.all(12),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(7),
                              border:
                                  Border.all(color: const Color(0xFFE2E8F0)),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  width: 14,
                                  height: 14,
                                  decoration: BoxDecoration(
                                    color: activePalette.backgroundColor,
                                    borderRadius: BorderRadius.circular(4),
                                    border: Border.all(
                                      color: const Color(0xFF94A3B8),
                                      width: 0.8,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    '当前主题：${activePalette.name}',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                      color: Color(0xFF475569),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),

                    // 右侧设置内容面板
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // 右侧顶部标题栏
                          Container(
                            padding: const EdgeInsets.fromLTRB(24, 16, 16, 14),
                            decoration: const BoxDecoration(
                              color: Colors.white,
                              border: Border(
                                bottom: BorderSide(color: Color(0xFFE2E8F0)),
                              ),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        currentNav['title'] as String,
                                        style: const TextStyle(
                                          fontSize: 15.5,
                                          fontWeight: FontWeight.w700,
                                          color: Color(0xFF0F172A),
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        currentNav['subtitle'] as String,
                                        style: const TextStyle(
                                          fontSize: 11.5,
                                          color: Color(0xFF64748B),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                IconButton(
                                  tooltip: '关闭设置',
                                  icon: const Icon(
                                    Icons.close_rounded,
                                    size: 19,
                                    color: Color(0xFF64748B),
                                  ),
                                  onPressed: () {
                                    syncControllersToConfig();
                                    Navigator.of(ctx).pop();
                                  },
                                ),
                              ],
                            ),
                          ),

                          // 右侧主内容滚动区
                          Expanded(
                            child: SingleChildScrollView(
                              padding: const EdgeInsets.all(24),
                              child: _buildSettingsSectionBody(
                                sectionIndex: selectedSection,
                                setModalState: setModalState,
                                syncControllersToConfig:
                                    syncControllersToConfig,
                                endpointCtrl: endpointCtrl,
                                regionCtrl: regionCtrl,
                                bucketCtrl: bucketCtrl,
                                objectKeyCtrl: objectKeyCtrl,
                                accessKeyCtrl: accessKeyCtrl,
                                secretKeyCtrl: secretKeyCtrl,
                                obscureSecret: obscureSecret,
                                onToggleObscureSecret: () {
                                  setModalState(() {
                                    obscureSecret = !obscureSecret;
                                  });
                                },
                                aiBaseUrlCtrl: aiBaseUrlCtrl,
                                aiApiKeyCtrl: aiApiKeyCtrl,
                                aiModelCtrl: aiModelCtrl,
                                obscureAiKey: obscureAiKey,
                                onToggleObscureAiKey: () {
                                  setModalState(() {
                                    obscureAiKey = !obscureAiKey;
                                  });
                                },
                                historyLimitCtrl: historyLimitCtrl,
                              ),
                            ),
                          ),

                          // 右侧底部操作栏
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 24,
                              vertical: 12,
                            ),
                            decoration: const BoxDecoration(
                              color: Color(0xFFF8FAFC),
                              border: Border(
                                top: BorderSide(color: Color(0xFFE2E8F0)),
                              ),
                            ),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.check_circle_outline_rounded,
                                  size: 15,
                                  color: Color(0xFF10B981),
                                ),
                                const SizedBox(width: 6),
                                const Text(
                                  '所有更改将自动保存到本地工作区',
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    color: Color(0xFF64748B),
                                  ),
                                ),
                                const Spacer(),
                                ElevatedButton(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFF2563EB),
                                    foregroundColor: Colors.white,
                                    elevation: 0,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 22,
                                      vertical: 10,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(7),
                                    ),
                                  ),
                                  onPressed: () {
                                    syncControllersToConfig();
                                    Navigator.of(ctx).pop();
                                  },
                                  child: const Text(
                                    '完成',
                                    style: TextStyle(
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  /// 构建设置弹窗右侧不同分类页签的内容
  Widget _buildSettingsSectionBody({
    required int sectionIndex,
    required StateSetter setModalState,
    required VoidCallback syncControllersToConfig,
    required TextEditingController endpointCtrl,
    required TextEditingController regionCtrl,
    required TextEditingController bucketCtrl,
    required TextEditingController objectKeyCtrl,
    required TextEditingController accessKeyCtrl,
    required TextEditingController secretKeyCtrl,
    required bool obscureSecret,
    required VoidCallback onToggleObscureSecret,
    required TextEditingController aiBaseUrlCtrl,
    required TextEditingController aiApiKeyCtrl,
    required TextEditingController aiModelCtrl,
    required bool obscureAiKey,
    required VoidCallback onToggleObscureAiKey,
    required TextEditingController historyLimitCtrl,
  }) {
    switch (sectionIndex) {
      case 0:
        return _buildAppearanceSettingsSection(setModalState);
      case 1:
        return _buildSidebarsAndHistorySettingsSection(
          setModalState: setModalState,
          syncControllersToConfig: syncControllersToConfig,
          historyLimitCtrl: historyLimitCtrl,
        );
      case 2:
        return _buildAiSettingsSection(
          setModalState: setModalState,
          syncControllersToConfig: syncControllersToConfig,
          aiBaseUrlCtrl: aiBaseUrlCtrl,
          aiApiKeyCtrl: aiApiKeyCtrl,
          aiModelCtrl: aiModelCtrl,
          obscureAiKey: obscureAiKey,
          onToggleObscureAiKey: onToggleObscureAiKey,
        );
      case 3:
      default:
        return _buildS3SyncSettingsSection(
          setModalState: setModalState,
          syncControllersToConfig: syncControllersToConfig,
          endpointCtrl: endpointCtrl,
          regionCtrl: regionCtrl,
          bucketCtrl: bucketCtrl,
          objectKeyCtrl: objectKeyCtrl,
          accessKeyCtrl: accessKeyCtrl,
          secretKeyCtrl: secretKeyCtrl,
          obscureSecret: obscureSecret,
          onToggleObscureSecret: onToggleObscureSecret,
        );
    }
  }

  /// 分区 0：外观与主题（含 5 套侧边栏 API 树配色方案可视化切换卡片）
  Widget _buildAppearanceSettingsSection(StateSetter setModalState) {
    final currentThemeId = _workspace.sidebarTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '侧边栏 API 树配色方案',
          style: TextStyle(
            fontSize: 13.5,
            fontWeight: FontWeight.w700,
            color: Color(0xFF0F172A),
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          '为左侧接口目录树选择独立的视觉底色，增强与右侧纯白工作区的边界层次感，点击任意卡片即可实时生效',
          style: TextStyle(
            fontSize: 12,
            color: Color(0xFF64748B),
          ),
        ),
        const SizedBox(height: 14),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: SidebarPalette.allThemes.map((palette) {
            final isSelected = palette.id == currentThemeId;
            return _buildSidebarThemePreviewCard(
              palette: palette,
              isSelected: isSelected,
              onSelect: () {
                setModalState(() {
                  _workspace.sidebarTheme = palette.id;
                });
                setState(() {});
                _storageService.saveWorkspace(_workspace);
              },
            );
          }).toList(),
        ),
        const SizedBox(height: 22),
        const Text(
          '目录树文件夹外观',
          style: TextStyle(
            fontSize: 13.5,
            fontWeight: FontWeight.w700,
            color: Color(0xFF0F172A),
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          '自定义左侧目录树中文件夹的强调配色与图标视觉形态，切换后实时响应生效',
          style: TextStyle(
            fontSize: 12,
            color: Color(0xFF64748B),
          ),
        ),
        const SizedBox(height: 12),
        _buildFolderAppearanceSettingsCard(setModalState),
        const SizedBox(height: 22),
        const Text(
          '工作区视图与系统交互',
          style: TextStyle(
            fontSize: 13.5,
            fontWeight: FontWeight.w700,
            color: Color(0xFF0F172A),
          ),
        ),
        const SizedBox(height: 10),
        _buildSettingSwitchCard(
          icon: Icons.link_rounded,
          title: '显示解析后请求目标栏',
          subtitle: '在请求地址输入框下方实时展示环境变量替换后的完整请求地址',
          value: _workspace.showUrlPreviewBar,
          onChanged: (val) {
            setModalState(() {
              _workspace.showUrlPreviewBar = val;
            });
            setState(() {});
            _storageService.saveWorkspace(_workspace);
          },
        ),
        const SizedBox(height: 10),
        _buildSettingSwitchCard(
          icon: Icons.archive_outlined,
          title: '关闭主窗口时缩小到系统托盘',
          subtitle: '开启后点击窗口右上角关闭按钮将最小化常驻在系统托盘，不退出后台任务与调试进程',
          value: _workspace.minimizeToTrayOnClose,
          onChanged: (val) {
            setModalState(() {
              _workspace.minimizeToTrayOnClose = val;
            });
            setState(() {});
            _storageService.saveWorkspace(_workspace);
          },
        ),
      ],
    );
  }

  /// 目录树文件夹外观配置卡片（双色调/线性/实心 + 6种预设配色圆形色卡）
  Widget _buildFolderAppearanceSettingsCard(StateSetter setModalState) {
    final currentColorId = _workspace.folderColorTheme;
    final currentStyleId = _workspace.folderIconStyle;
    final currentIconStyle = FolderIconStyle.fromId(currentStyleId);
    final currentConfig = FolderThemeConfig(
      colorPreset: FolderColorPreset.fromId(currentColorId),
      iconStyle: currentIconStyle,
    );

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE2E8F0), width: 1.0),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 第一行：图标形态切换 (SegmentedButton) 与即时视觉效果展示
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const Text(
                '图标形态',
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF334155),
                ),
              ),
              const SizedBox(width: 14),
              SegmentedButton<FolderIconStyle>(
                segments: FolderIconStyle.values.map((style) {
                  return ButtonSegment<FolderIconStyle>(
                    value: style,
                    label: Text(style.label,
                        style: const TextStyle(fontSize: 11.5)),
                    icon: Icon(style.icon, size: 15),
                  );
                }).toList(),
                selected: {currentIconStyle},
                onSelectionChanged: (newSelection) {
                  final newStyle = newSelection.first;
                  setModalState(() {
                    _workspace.folderIconStyle = newStyle.id;
                  });
                  setState(() {});
                  _storageService.saveWorkspace(_workspace);
                },
                style: ButtonStyle(
                  visualDensity: VisualDensity.compact,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  elevation: WidgetStateProperty.all(0),
                  backgroundColor: WidgetStateProperty.resolveWith((states) {
                    if (states.contains(WidgetState.selected)) {
                      return Colors.white;
                    }
                    return const Color(0xFFF1F5F9);
                  }),
                  foregroundColor: WidgetStateProperty.resolveWith((states) {
                    if (states.contains(WidgetState.selected)) {
                      return const Color(0xFF2563EB);
                    }
                    return const Color(0xFF475569);
                  }),
                  side: WidgetStateProperty.all(
                    const BorderSide(color: Color(0xFFE2E8F0), width: 1.0),
                  ),
                ),
              ),
              const Spacer(),
              // 即时动态效果展示
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(6),
                  border:
                      Border.all(color: const Color(0xFFE2E8F0), width: 1.0),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    FolderThemeIcon(
                      isExpanded: false,
                      size: 15,
                      config: currentConfig,
                    ),
                    const SizedBox(width: 6),
                    FolderThemeIcon(
                      isExpanded: true,
                      size: 15,
                      config: currentConfig,
                    ),
                    const SizedBox(width: 8),
                    const Text(
                      '效果预览',
                      style: TextStyle(
                        fontSize: 11,
                        color: Color(0xFF64748B),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Divider(height: 1, color: Color(0xFFE2E8F0)),
          const SizedBox(height: 14),

          // 第二行：预设配色方案圆形色卡选择器
          const Text(
            '预设配色方案',
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: Color(0xFF334155),
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: FolderColorPreset.presets.map((preset) {
              final isSelected = preset.id == currentColorId;
              final color = preset.resolveColor(context);

              return Tooltip(
                message: preset.name,
                child: InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: () {
                    setModalState(() {
                      _workspace.folderColorTheme = preset.id;
                    });
                    setState(() {});
                    _storageService.saveWorkspace(_workspace);
                  },
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                    decoration: BoxDecoration(
                      color: isSelected ? Colors.white : Colors.transparent,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: isSelected
                            ? const Color(0xFF2563EB)
                            : Colors.transparent,
                        width: 1.0,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // 圆形色卡
                        Container(
                          width: 22,
                          height: 22,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: color,
                            border: Border.all(
                              color: isSelected
                                  ? Colors.white
                                  : const Color(0xFFCBD5E1),
                              width: isSelected ? 2.0 : 0.8,
                            ),
                          ),
                          child: isSelected
                              ? const Icon(
                                  Icons.check_rounded,
                                  size: 13,
                                  color: Colors.white,
                                )
                              : null,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          preset.name,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: isSelected
                                ? FontWeight.w600
                                : FontWeight.normal,
                            color: isSelected
                                ? const Color(0xFF0F172A)
                                : const Color(0xFF475569),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  /// 单个侧边栏主题的微缩可视化预览卡片
  Widget _buildSidebarThemePreviewCard({
    required SidebarPalette palette,
    required bool isSelected,
    required VoidCallback onSelect,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onSelect,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: 254,
        padding: const EdgeInsets.all(11),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFFF8FAFC) : Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected
                ? const Color(0xFF2563EB)
                : const Color(0xFFE2E8F0),
            width: isSelected ? 1.5 : 1.0,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 微缩左树右工作区对比预览图
            Container(
              height: 76,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(7),
                border: Border.all(color: const Color(0xFFCBD5E1), width: 0.8),
              ),
              clipBehavior: Clip.antiAlias,
              child: Row(
                children: [
                  // 左侧微缩 API 树
                  Container(
                    width: 112,
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: palette.backgroundGradient == null
                          ? palette.backgroundColor
                          : null,
                      gradient: palette.backgroundGradient,
                      border: Border(
                        right: BorderSide(color: palette.borderColor),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // 迷你搜索栏
                        Container(
                          height: 11,
                          decoration: BoxDecoration(
                            color: palette.searchBoxBackgroundColor,
                            borderRadius: BorderRadius.circular(3),
                            border: Border.all(
                              color: palette.searchBoxBorderColor,
                              width: 0.6,
                            ),
                          ),
                        ),
                        const SizedBox(height: 5),
                        // 迷你目录行
                        Row(
                          children: [
                            Icon(
                              Icons.folder_rounded,
                              size: 9,
                              color: palette.mutedIconColor,
                            ),
                            const SizedBox(width: 4),
                            Container(
                              width: 46,
                              height: 5,
                              decoration: BoxDecoration(
                                color: palette.folderTextColor
                                    .withValues(alpha: 0.65),
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 5),
                        // 迷你选中接口胶囊
                        Container(
                          height: 17,
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          decoration: BoxDecoration(
                            color: palette.activeItemBackgroundColor,
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(
                              color: palette.activeItemBorderColor,
                              width: 0.7,
                            ),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 2,
                                height: 9,
                                decoration: BoxDecoration(
                                  color: palette.activeIndicatorColor,
                                  borderRadius: BorderRadius.circular(1),
                                ),
                              ),
                              const SizedBox(width: 3),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 3,
                                  vertical: 1,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF2563EB)
                                      .withValues(alpha: 0.18),
                                  borderRadius: BorderRadius.circular(2),
                                ),
                                child: Text(
                                  'POST',
                                  style: TextStyle(
                                    fontSize: 6.5,
                                    fontWeight: FontWeight.w800,
                                    color: palette.isDark
                                        ? const Color(0xFF60A5FA)
                                        : const Color(0xFF2563EB),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Container(
                                  height: 4.5,
                                  decoration: BoxDecoration(
                                    color: palette.activeItemTextColor
                                        .withValues(alpha: 0.8),
                                    borderRadius: BorderRadius.circular(2),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 4),
                        // 迷你未选中接口行
                        Padding(
                          padding: const EdgeInsets.only(left: 5),
                          child: Row(
                            children: [
                              Container(
                                width: 14,
                                height: 4.5,
                                decoration: BoxDecoration(
                                  color: const Color(0xFF059669)
                                      .withValues(alpha: 0.65),
                                  borderRadius: BorderRadius.circular(2),
                                ),
                              ),
                              const SizedBox(width: 4),
                              Container(
                                width: 38,
                                height: 4,
                                decoration: BoxDecoration(
                                  color: palette.requestTextColor
                                      .withValues(alpha: 0.45),
                                  borderRadius: BorderRadius.circular(2),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  // 右侧纯白工作区对照
                  Expanded(
                    child: Container(
                      color: Colors.white,
                      padding: const EdgeInsets.all(6),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                width: 22,
                                height: 6,
                                decoration: BoxDecoration(
                                  color: const Color(0xFFE2E8F0),
                                  borderRadius: BorderRadius.circular(2),
                                ),
                              ),
                              const SizedBox(width: 4),
                              Container(
                                width: 28,
                                height: 6,
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF1F5F9),
                                  borderRadius: BorderRadius.circular(2),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Container(
                            height: 12,
                            decoration: BoxDecoration(
                              color: const Color(0xFFF8FAFC),
                              borderRadius: BorderRadius.circular(3),
                              border: Border.all(
                                color: const Color(0xFFE2E8F0),
                                width: 0.6,
                              ),
                            ),
                            child: Row(
                              children: [
                                const Spacer(),
                                Container(
                                  width: 18,
                                  margin: const EdgeInsets.all(1.5),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF2563EB),
                                    borderRadius: BorderRadius.circular(2),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 6),
                          Expanded(
                            child: Container(
                              decoration: BoxDecoration(
                                color: const Color(0xFFF8FAFC),
                                borderRadius: BorderRadius.circular(3),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 9),
            Row(
              children: [
                Text(
                  palette.name,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: isSelected
                        ? const Color(0xFF1D4ED8)
                        : const Color(0xFF0F172A),
                  ),
                ),
                if (palette.id == 'slate') ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 5,
                      vertical: 1.5,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEFF6FF),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: const Color(0xFFBFDBFE)),
                    ),
                    child: const Text(
                      '默认推荐',
                      style: TextStyle(
                        fontSize: 9.5,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF2563EB),
                      ),
                    ),
                  ),
                ],
                const Spacer(),
                Icon(
                  isSelected
                      ? Icons.check_circle_rounded
                      : Icons.radio_button_unchecked_rounded,
                  size: 16,
                  color: isSelected
                      ? const Color(0xFF2563EB)
                      : const Color(0xFFCBD5E1),
                ),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              palette.subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 11,
                color: Color(0xFF64748B),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 分区 1：工具栏与历史记录设置
  Widget _buildSidebarsAndHistorySettingsSection({
    required StateSetter setModalState,
    required VoidCallback syncControllersToConfig,
    required TextEditingController historyLimitCtrl,
  }) {
    final availableTools = <Map<String, dynamic>>[
      {
        'id': 'curl',
        'title': 'cURL 代码生成',
        'subtitle': '在右侧停靠面板实时查看与复制当前请求的 cURL 命令',
        'icon': Icons.terminal_rounded,
        'color': const Color(0xFFD97706),
      },
      {
        'id': 'ai',
        'title': 'AI 智能助手',
        'subtitle': '在右侧停靠栏显示 AI 入口，需同时在 AI 助手配置中填写有效参数后生效',
        'icon': Icons.auto_awesome_rounded,
        'color': const Color(0xFF7C3AED),
      },
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '工具栏与历史记录',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: Color(0xFF0F172A),
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          '配置左侧历史调用列表展示条数，以及定制右侧工具边侧栏显示的功能入口。',
          style: TextStyle(fontSize: 12.5, color: Color(0xFF64748B)),
        ),
        const SizedBox(height: 20),

        // 卡片 1：左侧历史记录数量设置
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.history_rounded,
                    size: 16,
                    color: Color(0xFF2563EB),
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    '最近使用 API 显示条数',
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF0F172A),
                    ),
                  ),
                  const Spacer(),
                  if (_workspace.apiHistory.isNotEmpty)
                    TextButton.icon(
                      onPressed: () {
                        setState(() {
                          _workspace.apiHistory.clear();
                        });
                        setModalState(() {});
                        _storageService.saveWorkspace(_workspace);
                      },
                      style: TextButton.styleFrom(
                        foregroundColor: const Color(0xFFEF4444),
                        visualDensity: VisualDensity.compact,
                      ),
                      icon: const Icon(Icons.delete_sweep_outlined, size: 15),
                      label: const Text('清空历史记录', style: TextStyle(fontSize: 12)),
                    ),
                ],
              ),
              const SizedBox(height: 4),
              const Text(
                '左侧历史面板按接口最新调用时间倒序排列，同一接口多次调用仅保留最新一条记录，默认显示 10 条。',
                style: TextStyle(fontSize: 11.5, color: Color(0xFF64748B)),
              ),
              const SizedBox(height: 14),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  SizedBox(
                    width: 140,
                    child: _buildS3ConfigField(
                      controller: historyLimitCtrl,
                      label: '最大显示条数',
                      hint: '10',
                      onChanged: (_) => syncControllersToConfig(),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Wrap(
                    spacing: 8,
                    children: [5, 10, 20, 30, 50].map((preset) {
                      final isCurrent = _workspace.historyLimit == preset &&
                          historyLimitCtrl.text.trim() == '$preset';
                      return InkWell(
                        borderRadius: BorderRadius.circular(6),
                        onTap: () {
                          historyLimitCtrl.text = '$preset';
                          syncControllersToConfig();
                          setModalState(() {});
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: isCurrent
                                ? const Color(0xFFEFF6FF)
                                : Colors.white,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: isCurrent
                                  ? const Color(0xFF3B82F6)
                                  : const Color(0xFFCBD5E1),
                            ),
                          ),
                          child: Text(
                            '$preset 条',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: isCurrent
                                  ? FontWeight.w700
                                  : FontWeight.w500,
                              color: isCurrent
                                  ? const Color(0xFF1D4ED8)
                                  : const Color(0xFF475569),
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                  const Spacer(),
                  FilledButton(
                    onPressed: () {
                      syncControllersToConfig();
                      setModalState(() {});
                    },
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF2563EB),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                    ),
                    child: const Text('应用条数', style: TextStyle(fontSize: 12)),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // 卡片 2：右侧工具边侧栏显示项定制
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(
                    Icons.view_sidebar_outlined,
                    size: 16,
                    color: Color(0xFF2563EB),
                  ),
                  SizedBox(width: 8),
                  Text(
                    '右侧工具边侧栏显示配置',
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF0F172A),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              const Text(
                '勾选需要在主界面右侧工具栏常驻显示的工具入口，取消勾选后将立即从右侧栏隐藏。',
                style: TextStyle(fontSize: 11.5, color: Color(0xFF64748B)),
              ),
              const SizedBox(height: 12),
              ...availableTools.map((tool) {
                final id = tool['id'] as String;
                final enabled = _workspace.rightSidebarTools.contains(id);
                final isAiUnconfigured =
                    id == 'ai' && !_workspace.aiConfig.isConfigured;
                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: (tool['color'] as Color).withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(
                          tool['icon'] as IconData,
                          size: 17,
                          color: tool['color'] as Color,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Text(
                                  tool['title'] as String,
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFF1E293B),
                                  ),
                                ),
                                if (isAiUnconfigured) ...[
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 6,
                                      vertical: 1.5,
                                    ),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFFEF3C7),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: const Text(
                                      '未配置 AI，主页暂不显示',
                                      style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w600,
                                        color: Color(0xFFB45309),
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                            const SizedBox(height: 2),
                            Text(
                              tool['subtitle'] as String,
                              style: const TextStyle(
                                fontSize: 11.5,
                                color: Color(0xFF64748B),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Switch(
                        value: enabled,
                        activeThumbColor: const Color(0xFF2563EB),
                        onChanged: (val) {
                          setState(() {
                            if (val) {
                              if (!_workspace.rightSidebarTools.contains(id)) {
                                _workspace.rightSidebarTools.add(id);
                              }
                            } else {
                              _workspace.rightSidebarTools.remove(id);
                              if (_activeRightPanel == id) {
                                _activeRightPanel = null;
                              }
                            }
                          });
                          setModalState(() {});
                          _storageService.saveWorkspace(_workspace);
                        },
                      ),
                    ],
                  ),
                );
              }),
            ],
          ),
        ),
      ],
    );
  }

  /// 分区 2：AI 助手配置
  Widget _buildAiSettingsSection({
    required StateSetter setModalState,
    required VoidCallback syncControllersToConfig,
    required TextEditingController aiBaseUrlCtrl,
    required TextEditingController aiApiKeyCtrl,
    required TextEditingController aiModelCtrl,
    required bool obscureAiKey,
    required VoidCallback onToggleObscureAiKey,
  }) {
    final configured = _workspace.aiConfig.isConfigured;
    final presets = <Map<String, String>>[
      {
        'provider': 'openai',
        'label': 'OpenAI 官方',
        'baseUrl': 'https://api.openai.com/v1',
        'model': 'gpt-4o-mini',
      },
      {
        'provider': 'deepseek',
        'label': 'DeepSeek',
        'baseUrl': 'https://api.deepseek.com/v1',
        'model': 'deepseek-chat',
      },
      {
        'provider': 'ollama',
        'label': 'Ollama 本地',
        'baseUrl': 'http://127.0.0.1:11434/v1',
        'model': 'qwen2.5-coder:7b',
      },
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'AI 助手配置',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF0F172A),
                    ),
                  ),
                  SizedBox(height: 4),
                  Text(
                    '配置大模型接口地址与密钥后，右侧工具栏将自动开启 AI 助手入口；未配置时主页面自动隐藏 AI 入口。',
                    style: TextStyle(fontSize: 12.5, color: Color(0xFF64748B)),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: configured
                    ? const Color(0xFFECFDF5)
                    : const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: configured
                      ? const Color(0xFFA7F3D0)
                      : const Color(0xFFE2E8F0),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    configured
                        ? Icons.check_circle_rounded
                        : Icons.visibility_off_outlined,
                    size: 14,
                    color: configured
                        ? const Color(0xFF059669)
                        : const Color(0xFF64748B),
                  ),
                  const SizedBox(width: 5),
                  Text(
                    configured ? '已配置，主页显示入口' : '未配置，主页隐藏入口',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: configured
                          ? const Color(0xFF059669)
                          : const Color(0xFF64748B),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '快捷填入服务商预设',
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF475569),
                ),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                children: presets.map((p) {
                  final isSelected =
                      _workspace.aiConfig.provider == p['provider'];
                  return InkWell(
                    borderRadius: BorderRadius.circular(6),
                    onTap: () {
                      _workspace.aiConfig.provider = p['provider']!;
                      aiBaseUrlCtrl.text = p['baseUrl']!;
                      aiModelCtrl.text = p['model']!;
                      if (p['provider'] == 'ollama' &&
                          aiApiKeyCtrl.text.trim().isEmpty) {
                        aiApiKeyCtrl.text = 'local';
                      }
                      syncControllersToConfig();
                      setModalState(() {});
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color:
                            isSelected ? const Color(0xFFEFF6FF) : Colors.white,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: isSelected
                              ? const Color(0xFF3B82F6)
                              : const Color(0xFFCBD5E1),
                        ),
                      ),
                      child: Text(
                        p['label']!,
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight:
                              isSelected ? FontWeight.w700 : FontWeight.w500,
                          color: isSelected
                              ? const Color(0xFF1D4ED8)
                              : const Color(0xFF475569),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 14),
              _buildS3ConfigField(
                controller: aiBaseUrlCtrl,
                label: '接口基础地址 Base URL',
                hint: '例如 https://api.openai.com/v1 或 https://api.deepseek.com/v1',
                onChanged: (_) {
                  syncControllersToConfig();
                  setModalState(() {});
                },
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: _buildS3ConfigField(
                      controller: aiApiKeyCtrl,
                      label: 'API Key 密钥',
                      hint: '输入 sk-... 密钥，本地模型可填 local',
                      obscureText: obscureAiKey,
                      suffixIcon: InkWell(
                        onTap: onToggleObscureAiKey,
                        child: Icon(
                          obscureAiKey
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                          size: 15,
                          color: const Color(0xFF64748B),
                        ),
                      ),
                      onChanged: (_) {
                        syncControllersToConfig();
                        setModalState(() {});
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: _buildS3ConfigField(
                      controller: aiModelCtrl,
                      label: '模型名称 Model',
                      hint: '例如 gpt-4o-mini 或 deepseek-chat',
                      onChanged: (_) {
                        syncControllersToConfig();
                        setModalState(() {});
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  FilledButton.icon(
                    onPressed: () {
                      syncControllersToConfig();
                      setModalState(() {});
                    },
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF2563EB),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 10,
                      ),
                    ),
                    icon: const Icon(Icons.save_outlined, size: 15),
                    label: const Text('保存 AI 配置', style: TextStyle(fontSize: 12.5)),
                  ),
                  const SizedBox(width: 10),
                  if (configured)
                    OutlinedButton.icon(
                      onPressed: () {
                        aiBaseUrlCtrl.clear();
                        aiApiKeyCtrl.clear();
                        syncControllersToConfig();
                        setModalState(() {});
                      },
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFFEF4444),
                        side: const BorderSide(color: Color(0xFFFECACA)),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 10,
                        ),
                      ),
                      icon: const Icon(Icons.clear_rounded, size: 15),
                      label: const Text(
                        '清空配置并隐藏入口',
                        style: TextStyle(fontSize: 12.5),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }



  /// 分区 2：S3 云端同步设置
  Widget _buildS3SyncSettingsSection({
    required StateSetter setModalState,
    required VoidCallback syncControllersToConfig,
    required TextEditingController endpointCtrl,
    required TextEditingController regionCtrl,
    required TextEditingController bucketCtrl,
    required TextEditingController objectKeyCtrl,
    required TextEditingController accessKeyCtrl,
    required TextEditingController secretKeyCtrl,
    required bool obscureSecret,
    required VoidCallback onToggleObscureSecret,
  }) {
    final s3 = _workspace.s3Config;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 顶部同步状态概览条
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          decoration: BoxDecoration(
            color: const Color(0xFFEFF6FF).withValues(alpha: 0.7),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFFBFDBFE)),
          ),
          child: Row(
            children: [
              const Icon(
                Icons.cloud_done_outlined,
                size: 18,
                color: Color(0xFF2563EB),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  s3.lastSyncTime != null && s3.lastSyncTime!.isNotEmpty
                      ? '最近一次云端同步时间：${s3.lastSyncTime}'
                      : '支持 AWS S3、MinIO、阿里云 OSS、腾讯云 COS、Cloudflare R2 等兼容对象存储',
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF1E40AF),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // S3 连接参数表单卡片
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: _buildS3ConfigField(
                      label: 'Endpoint 服务端点',
                      hint:
                          'https://s3.amazonaws.com 或 http://127.0.0.1:9000',
                      controller: endpointCtrl,
                      onChanged: (_) => syncControllersToConfig(),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: _buildS3ConfigField(
                      label: 'Region 区域',
                      hint: 'us-east-1',
                      controller: regionCtrl,
                      onChanged: (_) => syncControllersToConfig(),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: _buildS3ConfigField(
                      label: 'Bucket 存储桶名称',
                      hint: '输入 Bucket 名称',
                      controller: bucketCtrl,
                      onChanged: (_) => syncControllersToConfig(),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 3,
                    child: _buildS3ConfigField(
                      label: 'Object Key 对象路径',
                      hint: 'mindpost/workspace.json',
                      controller: objectKeyCtrl,
                      onChanged: (_) => syncControllersToConfig(),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _buildS3ConfigField(
                      label: 'Access Key ID',
                      hint: '输入访问密钥 ID',
                      controller: accessKeyCtrl,
                      onChanged: (_) => syncControllersToConfig(),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildS3ConfigField(
                      label: 'Secret Access Key',
                      hint: '输入私有访问密钥',
                      controller: secretKeyCtrl,
                      obscureText: obscureSecret,
                      suffixIcon: InkWell(
                        onTap: onToggleObscureSecret,
                        child: Icon(
                          obscureSecret
                              ? Icons.visibility_off_outlined
                              : Icons.visibility_outlined,
                          size: 15,
                          color: const Color(0xFF64748B),
                        ),
                      ),
                      onChanged: (_) => syncControllersToConfig(),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              const Divider(height: 1, color: Color(0xFFE2E8F0)),
              const SizedBox(height: 12),
              Row(
                children: [
                  InkWell(
                    borderRadius: BorderRadius.circular(4),
                    onTap: () {
                      setModalState(() {
                        s3.forcePathStyle = !s3.forcePathStyle;
                      });
                      syncControllersToConfig();
                    },
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: 18,
                          height: 18,
                          child: Checkbox(
                            value: s3.forcePathStyle,
                            activeColor: const Color(0xFF2563EB),
                            onChanged: (v) {
                              setModalState(() {
                                s3.forcePathStyle = v ?? true;
                              });
                              syncControllersToConfig();
                            },
                          ),
                        ),
                        const SizedBox(width: 6),
                        const Text(
                          '使用 Path-Style 路径寻址模式',
                          style: TextStyle(
                            fontSize: 12,
                            color: Color(0xFF334155),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 24),
                  InkWell(
                    borderRadius: BorderRadius.circular(4),
                    onTap: () {
                      setModalState(() {
                        s3.autoSyncOnSave = !s3.autoSyncOnSave;
                      });
                      syncControllersToConfig();
                    },
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: 18,
                          height: 18,
                          child: Checkbox(
                            value: s3.autoSyncOnSave,
                            activeColor: const Color(0xFF2563EB),
                            onChanged: (v) {
                              setModalState(() {
                                s3.autoSyncOnSave = v ?? false;
                              });
                              syncControllersToConfig();
                            },
                          ),
                        ),
                        const SizedBox(width: 6),
                        const Text(
                          '保存标签页时自动上传同步到 S3',
                          style: TextStyle(
                            fontSize: 12,
                            color: Color(0xFF334155),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // S3 立即操作按钮栏
        Row(
          children: [
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              ),
              onPressed: _isSyncingS3
                  ? null
                  : () {
                      syncControllersToConfig();
                      _testS3Connection(setModalState: setModalState);
                    },
              icon: const Icon(Icons.wifi_tethering_rounded, size: 15),
              label: const Text('测试连接', style: TextStyle(fontSize: 12)),
            ),
            const SizedBox(width: 10),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF2563EB),
                foregroundColor: Colors.white,
                elevation: 0,
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              ),
              onPressed: _isSyncingS3
                  ? null
                  : () {
                      syncControllersToConfig();
                      _uploadToS3(setModalState: setModalState);
                    },
              icon: const Icon(Icons.cloud_upload_outlined, size: 15),
              label: const Text('上传同步到 S3', style: TextStyle(fontSize: 12)),
            ),
            const SizedBox(width: 10),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFF059669),
                side: const BorderSide(color: Color(0xFF059669)),
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              ),
              onPressed: _isSyncingS3
                  ? null
                  : () {
                      syncControllersToConfig();
                      _downloadFromS3(setModalState: setModalState);
                    },
              icon: const Icon(Icons.cloud_download_outlined, size: 15),
              label: const Text('从 S3 拉取覆盖', style: TextStyle(fontSize: 12)),
            ),
          ],
        ),
        if (_s3SyncStatus.isNotEmpty) ...[
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: BoxDecoration(
              color: _s3SyncSuccess
                  ? const Color(0xFFECFDF5)
                  : const Color(0xFFFEF2F2),
              borderRadius: BorderRadius.circular(7),
              border: Border.all(
                color: _s3SyncSuccess
                    ? const Color(0xFFA7F3D0)
                    : const Color(0xFFFECACA),
              ),
            ),
            child: Text(
              _s3SyncStatus,
              style: TextStyle(
                fontSize: 12,
                color: _s3SyncSuccess
                    ? const Color(0xFF059669)
                    : const Color(0xFFDC2626),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ],
    );
  }



  /// 通用设置项开关卡片
  Widget _buildSettingSwitchCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(7),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Icon(icon, size: 16, color: const Color(0xFF2563EB)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF0F172A),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontSize: 11.5,
                    color: Color(0xFF64748B),
                  ),
                ),
              ],
            ),
          ),
          Switch(
            value: value,
            activeTrackColor: const Color(0xFF2563EB),
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }


  Widget _buildS3ConfigField({
    required String label,
    required String hint,
    required TextEditingController controller,
    bool obscureText = false,
    Widget? suffixIcon,
    ValueChanged<String>? onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w600,
            color: Color(0xFF475569),
          ),
        ),
        const SizedBox(height: 4),
        SizedBox(
          height: 32,
          child: TextField(
            controller: controller,
            obscureText: obscureText,
            style: AppFonts.code(fontSize: 12),
            decoration: InputDecoration(
              hintText: hint,
              hintStyle:
                  const TextStyle(fontSize: 11, color: Color(0xFF94A3B8)),
              filled: true,
              fillColor: Colors.white,
              isDense: true,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              suffixIcon: suffixIcon != null
                  ? Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: suffixIcon,
                    )
                  : null,
              suffixIconConstraints:
                  const BoxConstraints(minWidth: 24, minHeight: 24),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(5),
                borderSide: const BorderSide(color: Color(0xFFE2E8F0), width: 1.0),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(5),
                borderSide: const BorderSide(color: Color(0xFFE2E8F0), width: 1.0),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(5),
                borderSide:
                    const BorderSide(color: Color(0xFF2563EB), width: 1.2),
              ),
            ),
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }

  /// 标签页右键上下文菜单
  Future<void> _showTabContextMenu(Offset position, int index) async {
    if (index < 0 || index >= _tabs.length) return;
    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox?;
    if (overlay == null) return;

    final hasOthers = _tabs.length > 1;
    final hasRight = index < _tabs.length - 1;
    final hasLeft = index > 0;
    final hasSaved = _tabs.any((t) => !t.isDirty);

    final action = await showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        position & const Size(40, 40),
        Offset.zero & overlay.size,
      ),
      items: [
        const PopupMenuItem<String>(
          value: 'save',
          height: 36,
          child: Row(
            children: [
              Icon(Icons.save_outlined, size: 16, color: Color(0xFF2563EB)),
              SizedBox(width: 8),
              Expanded(child: Text('保存当前标签', style: TextStyle(fontSize: 12.5))),
              Text('Ctrl+S',
                  style: TextStyle(fontSize: 11, color: Color(0xFF94A3B8))),
            ],
          ),
        ),
        const PopupMenuDivider(height: 8),
        const PopupMenuItem<String>(
          value: 'close_current',
          height: 36,
          child: Row(
            children: [
              Icon(Icons.close_rounded, size: 16, color: Color(0xFF475569)),
              SizedBox(width: 8),
              Text('关闭当前标签', style: TextStyle(fontSize: 12.5)),
            ],
          ),
        ),
        PopupMenuItem<String>(
          value: 'close_others',
          enabled: hasOthers,
          height: 36,
          child: const Row(
            children: [
              Icon(Icons.tab_unselected_rounded,
                  size: 16, color: Color(0xFF475569)),
              SizedBox(width: 8),
              Text('关闭其他标签', style: TextStyle(fontSize: 12.5)),
            ],
          ),
        ),
        PopupMenuItem<String>(
          value: 'close_right',
          enabled: hasRight,
          height: 36,
          child: const Row(
            children: [
              Icon(Icons.keyboard_tab_rounded,
                  size: 16, color: Color(0xFF475569)),
              SizedBox(width: 8),
              Text('关闭右侧标签', style: TextStyle(fontSize: 12.5)),
            ],
          ),
        ),
        PopupMenuItem<String>(
          value: 'close_left',
          enabled: hasLeft,
          height: 36,
          child: const Row(
            children: [
              Icon(Icons.west_rounded, size: 16, color: Color(0xFF475569)),
              SizedBox(width: 8),
              Text('关闭左侧标签', style: TextStyle(fontSize: 12.5)),
            ],
          ),
        ),
        const PopupMenuDivider(height: 8),
        PopupMenuItem<String>(
          value: 'close_saved',
          enabled: hasSaved,
          height: 36,
          child: const Row(
            children: [
              Icon(Icons.done_all_rounded,
                  size: 16, color: Color(0xFF475569)),
              SizedBox(width: 8),
              Text('关闭已保存标签', style: TextStyle(fontSize: 12.5)),
            ],
          ),
        ),
        const PopupMenuItem<String>(
          value: 'close_all',
          height: 36,
          child: Row(
            children: [
              Icon(Icons.clear_all_rounded, size: 16, color: Color(0xFFEF4444)),
              SizedBox(width: 8),
              Text('关闭所有标签',
                  style: TextStyle(fontSize: 12.5, color: Color(0xFFEF4444))),
            ],
          ),
        ),
      ],
    );

    if (!mounted || action == null) return;
    switch (action) {
      case 'save':
        _saveTabAtIndex(index);
        break;
      case 'close_current':
        _closeTab(index);
        break;
      case 'close_others':
        _closeOtherTabs(index);
        break;
      case 'close_right':
        _closeTabsToRight(index);
        break;
      case 'close_left':
        _closeTabsToLeft(index);
        break;
      case 'close_saved':
        _closeSavedTabs();
        break;
      case 'close_all':
        _closeAllTabs();
        break;
    }
  }

  void _addNewCollection() {
    final newCol = ApiCollection(
      name: '新目录 ${_workspace.collections.length + 1}',
      requests: [
        ApiRequest(
          name: '示例接口',
          url: '{{baseUrl}}/get',
          method: HttpMethod.get,
        )
      ],
    );
    setState(() {
      _workspace.collections.add(newCol);
    });
    _storageService.saveWorkspace(_workspace);
    _openContainer(newCol, true);
    _schedulePersistWorkbenchState();
  }

  // 2a. 最左侧功能导航窄竖栏：切换 API 树与历史记录
  Widget _buildLeftFunctionSidebar() {
    final palette = SidebarPalette.fromId(_workspace.sidebarTheme);
    final bgColor = palette.isDark
        ? const Color(0xFF090D16)
        : Color.alphaBlend(
            Colors.black.withValues(alpha: 0.035),
            palette.backgroundColor,
          );
    final borderColor = palette.borderColor;

    Widget buildNavItem({
      required String mode,
      required IconData icon,
      required IconData activeIcon,
      required String label,
      int? badgeCount,
    }) {
      final isSelected = _leftNavMode == mode;
      final fgColor = isSelected
          ? (palette.isDark ? const Color(0xFF60A5FA) : const Color(0xFF2563EB))
          : (palette.isDark
              ? const Color(0xFF94A3B8)
              : const Color(0xFF64748B));
      final itemBg = isSelected
          ? (palette.isDark
              ? const Color(0xFF1E293B)
              : Colors.white)
          : Colors.transparent;

      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () {
            setState(() {
              _leftNavMode = mode;
            });
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            width: 44,
            padding: const EdgeInsets.symmetric(vertical: 8),
            decoration: BoxDecoration(
              color: itemBg,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: isSelected
                    ? (palette.isDark
                        ? const Color(0xFF3B82F6).withValues(alpha: 0.45)
                        : const Color(0xFFBFDBFE))
                    : Colors.transparent,
              ),

            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Icon(
                      isSelected ? activeIcon : icon,
                      size: 19,
                      color: fgColor,
                    ),
                    if (badgeCount != null && badgeCount > 0)
                      Positioned(
                        right: -7,
                        top: -5,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 4,
                            vertical: 1,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFF2563EB),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            badgeCount > 99 ? '99+' : '$badgeCount',
                            style: const TextStyle(
                              fontSize: 8.5,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                    color: fgColor,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final historyCount = _workspace.sortedDeduplicatedHistory.length;

    return Container(
      width: 56,
      decoration: BoxDecoration(
        color: bgColor,
        border: Border(right: BorderSide(color: borderColor, width: 1)),
      ),
      child: Column(
        children: [
          const SizedBox(height: 8),
          buildNavItem(
            mode: 'api',
            icon: Icons.folder_copy_outlined,
            activeIcon: Icons.folder_copy_rounded,
            label: 'API',
          ),
          buildNavItem(
            mode: 'history',
            icon: Icons.history_rounded,
            activeIcon: Icons.manage_history_rounded,
            label: '历史',
            badgeCount: historyCount,
          ),
          const Spacer(),
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Tooltip(
              message: '帮助与快捷键',
              child: InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: () => _showHelpDialog(),
                child: Container(
                  width: 44,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.transparent,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.help_outline_rounded,
                        size: 19,
                        color: palette.isDark
                            ? const Color(0xFF94A3B8)
                            : const Color(0xFF64748B),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '帮助',
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w500,
                          color: palette.isDark
                              ? const Color(0xFF94A3B8)
                              : const Color(0xFF64748B),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Tooltip(
              message: '设置',
              child: InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: () => _showAppSettingsDialog(),
                child: Container(
                  width: 44,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.transparent,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.settings_outlined,
                        size: 19,
                        color: palette.isDark
                            ? const Color(0xFF94A3B8)
                            : const Color(0xFF64748B),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '设置',
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w500,
                          color: palette.isDark
                              ? const Color(0xFF94A3B8)
                              : const Color(0xFF64748B),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // 2b. 左侧目录与请求导航树 / 历史记录面板
  Widget _buildLeftSidebar() {
    final palette = SidebarPalette.fromId(_workspace.sidebarTheme);
    return SizedBox(
      width: _sidebarWidth,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: palette.backgroundColor,
        ),
        child: _leftNavMode == 'history'
            ? _buildHistorySidebarPanel(palette)
            : ApiTreeView(
                workspace: _workspace,
                activeRequestId: _currentRequest?.id,
                activeContainerId: _currentTab?.type == TabType.container
                    ? _currentTab!.id
                    : null,
                initialExpandedIds:
                    _hasLoadedWorkbenchState ? _expandedNodeIds : null,
                onExpandedChanged: (ids) {
                  _expandedNodeIds.clear();
                  _expandedNodeIds.addAll(ids);
                  _hasLoadedWorkbenchState = true;
                  _schedulePersistWorkbenchState();
                },
                onRequestSelected: _openRequest,
                onContainerSelected: _openContainer,
                onAddNewCollection: _addNewCollection,
                onWorkspaceChanged: () {
                  setState(() {
                    for (final tab in _tabs) {
                      if (tab.type == TabType.request && tab.request != null) {
                        tab.title = tab.request!.name;
                      } else if (tab.type == TabType.container &&
                          tab.container != null) {
                        tab.title = (tab.container as dynamic).name as String;
                      }
                    }
                    _removeStaleTabs();
                  });
                  _storageService.saveWorkspace(_workspace);
                  _schedulePersistWorkbenchState();
                },
              ),
      ),
    );
  }

  /// 左侧历史调用面板：按调用时间倒序展示，最新调用排在最上方，同一接口只保留最新一条记录
  Widget _buildHistorySidebarPanel(SidebarPalette palette) {
    final displayedHistory = _workspace.sortedDeduplicatedHistory;
    final titleColor = palette.titleTextColor;
    final subColor = palette.mutedIconColor;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: palette.headerBackgroundColor,
            border: Border(
              bottom: BorderSide(color: palette.borderColor, width: 1),
            ),
          ),
          child: Row(
            children: [
              Icon(
                Icons.history_rounded,
                size: 16,
                color: palette.isDark
                    ? const Color(0xFF60A5FA)
                    : const Color(0xFF2563EB),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  '最近调用 API',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: titleColor,
                  ),
                ),
              ),
              InkWell(
                borderRadius: BorderRadius.circular(5),
                onTap: () => _showAppSettingsDialog(initialTab: 1),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: palette.badgeBackgroundColor,
                    borderRadius: BorderRadius.circular(5),
                  ),
                  child: Text(
                    '上限 ${_workspace.historyLimit} 条',
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w600,
                      color: palette.badgeTextColor,
                    ),
                  ),
                ),
              ),
              if (_workspace.apiHistory.isNotEmpty) ...[
                const SizedBox(width: 4),
                Tooltip(
                  message: '清空历史记录',
                  child: InkWell(
                    borderRadius: BorderRadius.circular(5),
                    onTap: () {
                      setState(() {
                        _workspace.apiHistory.clear();
                      });
                      _storageService.saveWorkspace(_workspace);
                    },
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: Icon(
                        Icons.delete_sweep_outlined,
                        size: 15,
                        color: subColor,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        Expanded(
          child: displayedHistory.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.history_toggle_off_rounded,
                          size: 36,
                          color: subColor.withValues(alpha: 0.45),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          '暂无最近调用记录',
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            color: subColor,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '发送接口请求后，最新调用的接口将排在列表最上方',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 11,
                            color: subColor.withValues(alpha: 0.8),
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 8,
                  ),
                  itemCount: displayedHistory.length,
                  itemBuilder: (context, index) {
                    final item = displayedHistory[index];
                    final isCurrent = _currentRequest?.id == item.requestId;
                    final isRunning = _requestLoading[item.requestId] == true;
                    final methodColor = _getHistoryMethodColor(item.method);
                    final timeText = _formatHistoryTime(item.calledAt);

                    return Padding(
                      key: ValueKey(
                        '${item.requestId}_${item.calledAt.microsecondsSinceEpoch}',
                      ),
                      padding: const EdgeInsets.only(bottom: 4),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(8),
                        onTap: () => _openHistoryItem(item),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: isCurrent
                                ? palette.activeItemBackgroundColor
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: isCurrent
                                  ? palette.activeItemBorderColor
                                  : Colors.transparent,
                            ),
                            boxShadow:
                                isCurrent ? palette.activeItemShadows : null,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 5,
                                      vertical: 1.5,
                                    ),
                                    decoration: BoxDecoration(
                                      color: methodColor.withValues(
                                        alpha: palette.isDark ? 0.2 : 0.12,
                                      ),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      item.method.nameString,
                                      style: TextStyle(
                                        fontSize: 9.5,
                                        fontWeight: FontWeight.w800,
                                        color: methodColor,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      item.name.isEmpty ? '未命名接口' : item.name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 12.5,
                                        fontWeight: isCurrent
                                            ? FontWeight.w700
                                            : FontWeight.w600,
                                        color: isCurrent
                                            ? palette.activeItemTextColor
                                            : palette.requestTextColor,
                                      ),
                                    ),
                                  ),
                                  if (index == 0) ...[
                                    const SizedBox(width: 4),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 4.5,
                                        vertical: 1,
                                      ),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF2563EB)
                                            .withValues(alpha: 0.12),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text(
                                        '最新',
                                        style: TextStyle(
                                          fontSize: 9,
                                          fontWeight: FontWeight.w700,
                                          color: palette.isDark
                                              ? const Color(0xFF60A5FA)
                                              : const Color(0xFF2563EB),
                                        ),
                                      ),
                                    ),
                                  ],
                                  if (isRunning) ...[
                                    const SizedBox(width: 6),
                                    const SizedBox(
                                      width: 10,
                                      height: 10,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 1.6,
                                        color: Color(0xFF2563EB),
                                      ),
                                    ),
                                  ] else if (item.statusCode != null) ...[
                                    const SizedBox(width: 4),
                                    Text(
                                      '${item.statusCode}',
                                      style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w700,
                                        color: (item.statusCode! >= 200 &&
                                                item.statusCode! < 300)
                                            ? const Color(0xFF10B981)
                                            : const Color(0xFFEF4444),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      item.url.isEmpty ? '未填写 URL' : item.url,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 10.5,
                                        fontFamily: AppFonts.codeFamily, fontFamilyFallback: AppFonts.codeFallback,
                                        color: subColor,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    timeText,
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontFamily: AppFonts.codeFamily, fontFamilyFallback: AppFonts.codeFallback,
                                      color: subColor.withValues(alpha: 0.85),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  void _openHistoryItem(ApiHistoryItem item) {
    final existing = _workspace.findRequestById(item.requestId);
    if (existing != null) {
      _openRequest(existing);
      return;
    }
    if (item.requestSnapshot != null) {
      _openRequest(item.requestSnapshot!);
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('原接口已被移除，无法打开'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  Color _getHistoryMethodColor(HttpMethod method) {
    switch (method) {
      case HttpMethod.get:
        return const Color(0xFF059669);
      case HttpMethod.post:
        return const Color(0xFFD97706);
      case HttpMethod.put:
        return const Color(0xFF2563EB);
      case HttpMethod.delete:
        return const Color(0xFFDC2626);
      case HttpMethod.patch:
        return const Color(0xFF7C3AED);
      case HttpMethod.head:
      case HttpMethod.options:
        return const Color(0xFF475569);
    }
  }

  String _formatHistoryTime(DateTime dt) {
    final now = DateTime.now();
    final hh = dt.hour.toString().padLeft(2, '0');
    final mm = dt.minute.toString().padLeft(2, '0');
    final ss = dt.second.toString().padLeft(2, '0');
    if (now.year == dt.year && now.month == dt.month && now.day == dt.day) {
      return '$hh:$mm:$ss';
    }
    final mo = dt.month.toString().padLeft(2, '0');
    final dd = dt.day.toString().padLeft(2, '0');
    return '$mo-$dd $hh:$mm:$ss';
  }

  // 2c. 最右侧工具边侧栏：按设置动态显示 AI、cURL 等入口
  Widget _buildRightToolSidebar() {
    final enabledTools = _workspace.rightSidebarTools;
    final showAi =
        enabledTools.contains('ai') && _workspace.aiConfig.isConfigured;
    final showCurl = enabledTools.contains('curl');

    if (!showAi && !showCurl) {
      return const SizedBox.shrink();
    }

    Widget buildToolBtn({
      required String id,
      required IconData icon,
      required String label,
      required Color accentColor,
      required VoidCallback onTap,
      bool isActive = false,
    }) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
        child: InkWell(
          borderRadius: BorderRadius.circular(9),
          onTap: onTap,
          child: Container(
            width: 42,
            padding: const EdgeInsets.symmetric(vertical: 7),
            decoration: BoxDecoration(
              color: isActive
                  ? accentColor.withValues(alpha: 0.1)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(9),
              border: Border.all(
                color: isActive
                    ? accentColor.withValues(alpha: 0.35)
                    : Colors.transparent,
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  icon,
                  size: 18,
                  color: isActive ? accentColor : const Color(0xFF475569),
                ),
                const SizedBox(height: 3),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                    color: isActive ? accentColor : const Color(0xFF64748B),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Container(
      width: 52,
      decoration: const BoxDecoration(
        color: Color(0xFFF8FAFC),
        border: Border(left: BorderSide(color: Color(0xFFE2E8F0), width: 1)),
      ),
      child: Column(
        children: [
          const SizedBox(height: 8),
          if (showAi)
            buildToolBtn(
              id: 'ai',
              icon: Icons.auto_awesome_rounded,
              label: 'AI',
              accentColor: const Color(0xFF7C3AED),
              isActive: _activeRightPanel == 'ai',
              onTap: () {
                setState(() {
                  _activeRightPanel = _activeRightPanel == 'ai' ? null : 'ai';
                });
              },
            ),
          if (showCurl)
            buildToolBtn(
              id: 'curl',
              icon: Icons.terminal_rounded,
              label: 'cURL',
              accentColor: const Color(0xFFD97706),
              isActive: _activeRightPanel == 'curl',
              onTap: () {
                setState(() {
                  _activeRightPanel =
                      _activeRightPanel == 'curl' ? null : 'curl';
                });
              },
            ),
        ],
      ),
    );
  }

  /// 生成当前接口的 cURL 命令字符串
  String _generateCurrentRequestCurl(ApiRequest req) {
    final vars = VariableResolver.buildVariableMap(workspace: _workspace);
    var url = VariableResolver.resolveUrl(
      rawUrl: req.url,
      variables: vars,
    ).trim();
    final enabledParams =
        req.params.where((p) => p.isEnabled && p.key.trim().isNotEmpty);
    if (enabledParams.isNotEmpty) {
      final qs = enabledParams
          .map((p) =>
              '${Uri.encodeQueryComponent(VariableResolver.interpolate(p.key, vars))}=${Uri.encodeQueryComponent(VariableResolver.interpolate(p.value, vars))}')
          .join('&');
      url = url.contains('?') ? '$url&$qs' : '$url?$qs';
    }
    final lines = <String>[
      'curl -X ${req.method.nameString} "$url"',
    ];
    for (final h in req.headers) {
      if (h.isEnabled && h.key.trim().isNotEmpty) {
        final k = VariableResolver.interpolate(h.key, vars);
        final v = VariableResolver.interpolate(h.value, vars);
        lines.add('  -H "$k: $v"');
      }
    }
    if (req.bodyType != BodyType.none && req.bodyContent.trim().isNotEmpty) {
      final resolvedBody = VariableResolver.interpolate(req.bodyContent, vars)
          .replaceAll("'", r"'\''");
      lines.add("  -d '$resolvedBody'");
    }
    return lines.join(' \\\n');
  }

  /// 右侧停靠的 cURL 代码生成面板
  Widget _buildRightCurlPanel() {
    final req = _currentRequest;
    final curlText = req != null
        ? _generateCurrentRequestCurl(req)
        : '# 请先在左侧选择一个 API 接口';

    return Container(
      width: 340,
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(left: BorderSide(color: Color(0xFFE2E8F0))),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
            decoration: const BoxDecoration(
              color: Color(0xFFF8FAFC),
              border: Border(bottom: BorderSide(color: Color(0xFFE2E8F0))),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.terminal_rounded,
                  size: 16,
                  color: Color(0xFFD97706),
                ),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'cURL 命令实时预览',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF0F172A),
                    ),
                  ),
                ),
                if (req != null)
                  TextButton.icon(
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: curlText));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('已复制 cURL 到剪贴板'),
                          duration: Duration(seconds: 2),
                        ),
                      );
                    },
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                    ),
                    icon: const Icon(Icons.copy_rounded, size: 14),
                    label: const Text('复制', style: TextStyle(fontSize: 12)),
                  ),
                IconButton(
                  onPressed: () => setState(() => _activeRightPanel = null),
                  icon: const Icon(
                    Icons.close_rounded,
                    size: 16,
                    color: Color(0xFF64748B),
                  ),
                  constraints: const BoxConstraints(
                    minWidth: 28,
                    minHeight: 28,
                  ),
                  padding: EdgeInsets.zero,
                ),
              ],
            ),
          ),
          Expanded(
            child: Container(
              margin: const EdgeInsets.all(12),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF0F172A),
                borderRadius: BorderRadius.circular(10),
              ),
              child: SingleChildScrollView(
                child: SelectableText(
                  curlText,
                  style: const TextStyle(
                    fontFamily: AppFonts.codeFamily, fontFamilyFallback: AppFonts.codeFallback,
                    fontSize: 12,
                    height: 1.5,
                    color: Color(0xFFE2E8F0),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }


  /// 左侧边栏与右侧工作区之间的竖向拖拽调整宽度手柄
  Widget _buildSidebarResizer() {
    final active = _isHoveringSidebarSplitter || _isDraggingSidebarSplitter;
    final palette = SidebarPalette.fromId(_workspace.sidebarTheme);
    return MouseRegion(
      cursor: SystemMouseCursors.resizeLeftRight,
      onEnter: (_) => setState(() => _isHoveringSidebarSplitter = true),
      onExit: (_) => setState(() => _isHoveringSidebarSplitter = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragStart: (_) {
          setState(() => _isDraggingSidebarSplitter = true);
        },
        onHorizontalDragUpdate: (details) {
          setState(() {
            _sidebarWidth = (_sidebarWidth + details.delta.dx).clamp(180.0, 560.0);
          });
        },
        onHorizontalDragEnd: (_) {
          setState(() => _isDraggingSidebarSplitter = false);
        },
        onHorizontalDragCancel: () {
          setState(() => _isDraggingSidebarSplitter = false);
        },
        child: Container(
          width: 6,
          color: active
              ? const Color(0xFF2563EB).withValues(alpha: 0.12)
              : Colors.transparent,
          alignment: Alignment.center,
          child: Container(
            width: active ? 2 : 1,
            height: double.infinity,
            color: active ? const Color(0xFF2563EB) : palette.borderColor,
          ),
        ),
      ),
    );
  }

  /// 请求参数区与下方响应展示区之间的横向拖拽调整高度手柄
  Widget _buildVerticalResizer(double availableHeight) {
    final active = _isHoveringVerticalSplitter || _isDraggingVerticalSplitter;
    return MouseRegion(
      cursor: SystemMouseCursors.resizeUpDown,
      onEnter: (_) => setState(() => _isHoveringVerticalSplitter = true),
      onExit: (_) => setState(() => _isHoveringVerticalSplitter = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onVerticalDragStart: (_) {
          setState(() => _isDraggingVerticalSplitter = true);
        },
        onVerticalDragUpdate: (details) {
          if (availableHeight <= 0) return;
          setState(() {
            final nextRatio =
                _requestPanelRatio + (details.delta.dy / availableHeight);
            _requestPanelRatio = nextRatio.clamp(0.18, 0.82);
          });
        },
        onVerticalDragEnd: (_) {
          setState(() => _isDraggingVerticalSplitter = false);
        },
        onVerticalDragCancel: () {
          setState(() => _isDraggingVerticalSplitter = false);
        },
        child: Container(
          height: 7,
          width: double.infinity,
          decoration: BoxDecoration(
            color: active
                ? const Color(0xFF2563EB).withValues(alpha: 0.10)
                : const Color(0xFFF8FAFC),
            border: Border(
              top: BorderSide(
                color: active
                    ? const Color(0xFF2563EB)
                    : const Color(0xFFE2E8F0),
                width: active ? 1.5 : 1,
              ),
              bottom: BorderSide(
                color: active
                    ? const Color(0xFF2563EB).withValues(alpha: 0.4)
                    : const Color(0xFFE2E8F0),
                width: 0.5,
              ),
            ),
          ),
          alignment: Alignment.center,
          child: Container(
            width: 36,
            height: 3,
            decoration: BoxDecoration(
              color: active
                  ? const Color(0xFF2563EB)
                  : const Color(0xFFCBD5E1),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
      ),
    );
  }

  /// 响应区初始空状态视图（尚未发起请求）
  Widget _buildResponseEmptyView() {
    return Center(
      child: SingleChildScrollView(
        child: Container(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 40,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: const Color(0xFFEFF6FF),
                  shape: BoxShape.circle,
                  border: Border.all(
                      color: const Color(0xFFDBEAFE),
                      width: 1.0),
                ),
                child: const Icon(Icons.bolt_rounded,
                    size: 20, color: Color(0xFF2563EB)),
              ),
              const SizedBox(height: 10),
              const Text(
                '准备就绪',
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF0F172A),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '点击上方【发送】执行请求，在此查看响应报文、响应头与断言测试结果',
                style: TextStyle(
                    color: Colors.grey.shade500,
                    fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 响应区正在请求中状态视图（体现正在请求与长请求保持连接，绝不显示上次请求旧状态）
  Widget _buildResponseLoadingView(ApiRequest req) {
    final durationText = _getCurrentRequestDurationText(req.id);

    return Column(
      children: [
        // 响应状态栏 (体现正在请求状态)
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          decoration: const BoxDecoration(
            color: Color(0xFFF8FAFC),
            border: Border(
              bottom: BorderSide(color: Color(0xFFE2E8F0)),
            ),
          ),
          child: Row(
            children: [
              const RequestPendingBadge(label: '正在请求'),
              const SizedBox(width: 8),
              // 实时动态耗时（等宽数字防抖动）
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFFBEB),
                  border: Border.all(color: const Color(0xFFFDE68A), width: 0.8),
                  borderRadius: BorderRadius.circular(5),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.speed_rounded,
                        size: 13, color: Color(0xFFD97706)),
                    const SizedBox(width: 4),
                    Text(
                      durationText,
                      style: const TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFFB45309),
                        fontFeatures: [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              // 长连接保持中标识
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
                decoration: BoxDecoration(
                  color: const Color(0xFFF0FDF4),
                  border: Border.all(color: const Color(0xFFBBF7D0), width: 0.8),
                  borderRadius: BorderRadius.circular(5),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.all_inclusive_rounded,
                        size: 13, color: Color(0xFF16A34A)),
                    SizedBox(width: 4),
                    Text(
                      'Keep-Alive',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF15803D),
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              // 取消请求轻量按钮
              InkWell(
                onTap: () => _cancelRequest(req.id),
                borderRadius: BorderRadius.circular(5),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFEF2F2),
                    border: Border.all(color: const Color(0xFFFECACA), width: 0.8),
                    borderRadius: BorderRadius.circular(5),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.close_rounded, size: 13, color: Color(0xFFDC2626)),
                      SizedBox(width: 4),
                      Text(
                        '取消请求',
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFFDC2626),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),

        // 主体极简加载状态（与准备就绪空状态保持统一视觉层级）
        Expanded(
          child: Center(
            child: SingleChildScrollView(
              child: Container(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 40,
                      height: 40,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          Container(
                            width: 40,
                            height: 40,
                            decoration: const BoxDecoration(
                              color: Color(0xFFEFF6FF),
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(
                            width: 40,
                            height: 40,
                            child: CircularProgressIndicator(
                              strokeWidth: 1.8,
                              color: Color(0xFF2563EB),
                              backgroundColor: Color(0xFFDBEAFE),
                            ),
                          ),
                          const Icon(
                            Icons.bolt_rounded,
                            size: 18,
                            color: Color(0xFF2563EB),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      '正在等待服务端响应...',
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF0F172A),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text.rich(
                      TextSpan(
                        style: TextStyle(
                          color: Colors.grey.shade500,
                          fontSize: 12,
                        ),
                        children: [
                          const TextSpan(text: '已等待 '),
                          TextSpan(
                            text: durationText,
                            style: const TextStyle(
                              color: Color(0xFF2563EB),
                              fontWeight: FontWeight.w600,
                              fontFeatures: [FontFeature.tabularFigures()],
                            ),
                          ),
                          const TextSpan(text: ' · 持久长连接保持中，正在接收响应报文'),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  // 3. 空白工作区状态
  Widget _buildEmptyWorkspace() {
    return Center(
      child: Container(
        padding: const EdgeInsets.all(32),
        constraints: const BoxConstraints(maxWidth: 420),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFFEFF6FF),
                shape: BoxShape.circle,
                border: Border.all(color: const Color(0xFFBFDBFE)),
              ),
              child: const Icon(Icons.rocket_launch_rounded,
                  size: 36, color: Color(0xFF2563EB)),
            ),
            const SizedBox(height: 16),
            const Text(
              '开始 API 调试工作流',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Color(0xFF0F172A),
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              '从左侧资源树中选择已有接口，或点击下方按钮新建快捷请求标签页进行调试与验证。',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12.5, color: Color(0xFF64748B), height: 1.5),
            ),
            const SizedBox(height: 18),
            ElevatedButton.icon(
              onPressed: _addNewTab,
              icon: const Icon(Icons.add_rounded, size: 16),
              label: const Text('新建请求标签页'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF2563EB),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // 4. 多 Tab 主调试工作区
  Widget _buildMainWorkspace() {
    if (_tabs.isEmpty || _currentTab == null) {
      return _buildEmptyWorkspace();
    }

    final currentTab = _currentTab!;

    return Column(
      children: [
        // 4.1 多标签栏 (支持省略标题、悬浮提示、未保存圆点、双击关闭、右键菜单)
        Container(
          height: 38,
          decoration: const BoxDecoration(
            color: Color(0xFFF8FAFC),
            border: Border(bottom: BorderSide(color: Color(0xFFE2E8F0))),
          ),
          child: Row(
            children: [
              Expanded(
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  itemCount: _tabs.length,
                  itemBuilder: (context, index) {
                    final tab = _tabs[index];
                    final isSelected = index == _activeTabIndex;
                    final tooltipMessage = tab.type == TabType.request
                        ? '${tab.request!.method.nameString} · ${tab.title}${tab.isDirty ? " · 未保存" : ""}\n${tab.request!.url}'
                        : '目录 · ${tab.title}${tab.isDirty ? " · 未保存" : ""}';

                    return Tooltip(
                      message: tooltipMessage,
                      waitDuration: const Duration(milliseconds: 350),
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onSecondaryTapDown: (details) {
                          _showTabContextMenu(details.globalPosition, index);
                        },
                        child: InkWell(
                          onTap: () => _handleTabTap(index),
                          child: Container(
                            constraints: const BoxConstraints(
                              minWidth: 110,
                              maxWidth: 185,
                            ),
                            padding: const EdgeInsets.symmetric(horizontal: 10),
                            decoration: BoxDecoration(
                              color:
                                  isSelected ? Colors.white : Colors.transparent,
                              border: Border(
                                top: BorderSide(
                                  color: isSelected
                                      ? const Color(0xFF2563EB)
                                      : Colors.transparent,
                                  width: 2,
                                ),
                                bottom: BorderSide(
                                  color: isSelected
                                      ? Colors.transparent
                                      : const Color(0xFFE2E8F0),
                                ),
                                right:
                                    const BorderSide(color: Color(0xFFE2E8F0)),
                                left: isSelected && index > 0
                                    ? const BorderSide(color: Color(0xFFE2E8F0))
                                    : BorderSide.none,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (tab.type == TabType.request)
                                  HttpMethodBadge(
                                      method: tab.request!.method,
                                      fontSize: 9.5)
                                else
                                  const Icon(
                                    Icons.folder_rounded,
                                    size: 15,
                                    color: Color(0xFFF59E0B),
                                  ),
                                const SizedBox(width: 6),
                                Flexible(
                                  child: Text(
                                    tab.title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: isSelected
                                          ? FontWeight.w600
                                          : FontWeight.normal,
                                      color: isSelected
                                          ? const Color(0xFF0F172A)
                                          : const Color(0xFF64748B),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 6),
                                if (tab.isDirty) ...[
                                  Container(
                                    width: 7,
                                    height: 7,
                                    decoration: const BoxDecoration(
                                      color: Color(0xFFF59E0B),
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                ],
                                InkWell(
                                  borderRadius: BorderRadius.circular(4),
                                  onTap: () => _closeTab(index),
                                  child: const Padding(
                                    padding: EdgeInsets.all(2.0),
                                    child: Icon(Icons.close_rounded,
                                        size: 13, color: Color(0xFF94A3B8)),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
              Tooltip(
                message: '新建请求标签页',
                child: InkWell(
                  borderRadius: BorderRadius.circular(4),
                  onTap: _addNewTab,
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 6),
                    padding: const EdgeInsets.all(5),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Icon(Icons.add_rounded,
                        size: 15, color: Color(0xFF2563EB)),
                  ),
                ),
              ),
            ],
          ),
        ),

        const Divider(height: 1),

        // 4.2 根据当前 Tab 类型展示内容
        Expanded(
          child: currentTab.type == TabType.container
              ? ContainerSettingsView(
                  key: ValueKey(currentTab.id),
                  container: currentTab.container!,
                  isCollection: currentTab.isCollection,
                  onChanged: () {
                    setState(() {
                      currentTab.title = currentTab.container!.name;
                      currentTab.isDirty = true;
                    });
                  },
                  onSaved: () {
                    setState(() {
                      currentTab.title = currentTab.container!.name;
                      currentTab.isDirty = false;
                    });
                    _storageService.saveWorkspace(_workspace);
                  },
                )
              : _buildRequestContent(currentTab.request!),
        ),
      ],
    );
  }

  // 渲染单接口的完整调试工作区
  Widget _buildRequestContent(ApiRequest req) {
    final isLoading = _requestLoading[req.id] == true;
    final response = _responses[req.id];
    final isCurrentDirty = _currentTab?.isDirty == true;

    // 查找所属父目录链以合并目录级变量
    List<ApiContainer> parentChain = [];
    for (final col in _workspace.collections) {
      if (col.findRequestById(req.id) != null) {
        parentChain = col.findParentChainForRequest(req.id);
        break;
      }
    }

    // 计算实时预览 URL
    final envVars = VariableResolver.buildVariableMap(
      workspace: _workspace,
      parentContainers: parentChain,
    );
    final resolvedPreviewUrl = VariableResolver.resolveUrl(
      rawUrl: _urlController.text,
      variables: envVars,
      currentBaseUrl: _workspace.activeEnvironment?.baseUrl,
    );

    return Column(
      children: [
        // 请求编辑与发送行 (突出 URL 核心操作区，独立保存与发送按钮，优化点击热区)
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  // 核心 URL 操作输入框区域（纯平柔和边框，无阴影）
                  Expanded(
                    child: Container(
                      height: 40,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                            color: const Color(0xFFE2E8F0), width: 1.0),
                      ),
                      child: Row(
                        children: [
                          // HTTP Method 现代下拉选择器
                          ModernDropdown<HttpMethod>(
                            value: req.method,
                            menuWidth: 120,
                            tooltip: '切换 HTTP 请求方法',
                            items: HttpMethod.values.map((m) {
                              return ModernDropdownItem<HttpMethod>(
                                value: m,
                                label: m.name.toUpperCase(),
                                customContent: HttpMethodBadge(method: m),
                              );
                            }).toList(),
                            onChanged: (val) {
                              setState(() {
                                req.method = val;
                              });
                              _markCurrentTabDirty();
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 8),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  HttpMethodBadge(method: req.method),
                                  const SizedBox(width: 4),
                                  const Icon(
                                    Icons.keyboard_arrow_down_rounded,
                                    size: 16,
                                    color: Color(0xFF64748B),
                                  ),
                                ],
                              ),
                            ),
                          ),

                          Container(width: 1, height: 20, color: const Color(0xFFE2E8F0)),

                          // URL 输入框
                          Expanded(
                            child: TextFormField(
                              controller: _urlController,
                              style: const TextStyle(
                                fontSize: 13,
                                fontFamily: AppFonts.codeFamily,
                                fontFamilyFallback: AppFonts.codeFallback,
                                color: Color(0xFF0F172A),
                              ),
                              decoration: const InputDecoration(
                                hintText:
                                    '输入请求 URL 或相对路径，如 {{baseUrl}}/get 或 /api/v1/users',
                                hintStyle: TextStyle(
                                    fontSize: 12, color: Color(0xFF94A3B8)),
                                filled: false,
                                isDense: true,
                                contentPadding:
                                    EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                border: InputBorder.none,
                                enabledBorder: InputBorder.none,
                                focusedBorder: InputBorder.none,
                              ),
                              onChanged: (val) {
                                setState(() {
                                  req.url = val;
                                });
                                _markCurrentTabDirty();
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),

                  // 保存按钮 (独立次要操作，清晰热区与状态反馈)
                  Tooltip(
                    message: '保存当前请求 (Ctrl+S)',
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(8),
                        onTap: _saveCurrentTab,
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          height: 40,
                          padding: const EdgeInsets.symmetric(horizontal: 13),
                          decoration: BoxDecoration(
                            color: isCurrentDirty
                                ? const Color(0xFFFFFBEB)
                                : const Color(0xFFF8FAFC),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: isCurrentDirty
                                  ? const Color(0xFFFBBF24)
                                  : const Color(0xFFE2E8F0),
                              width: 1.0,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.save_outlined,
                                size: 15,
                                color: isCurrentDirty
                                    ? const Color(0xFFD97706)
                                    : const Color(0xFF475569),
                              ),
                              const SizedBox(width: 4),
                              Text(
                                '保存',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: isCurrentDirty
                                      ? FontWeight.w700
                                      : FontWeight.w600,
                                  color: isCurrentDirty
                                      ? const Color(0xFFD97706)
                                      : const Color(0xFF475569),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),

                  // 发送 / 取消 按钮 (独立主操作按钮，长请求支持一键中止)
                  Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(8),
                      onTap: isLoading
                          ? () => _cancelRequest(req.id)
                          : _sendCurrentRequest,
                      child: Container(
                        height: 40,
                        padding: const EdgeInsets.symmetric(horizontal: 18),
                        decoration: BoxDecoration(
                          color: isLoading
                              ? const Color(0xFFEF4444)
                              : const Color(0xFF2563EB),
                          borderRadius: BorderRadius.circular(8),
                          boxShadow: [
                            BoxShadow(
                              color: (isLoading
                                      ? const Color(0xFFEF4444)
                                      : const Color(0xFF2563EB))
                                  .withValues(alpha: 0.25),
                              blurRadius: 6,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (isLoading)
                              const Icon(Icons.close_rounded,
                                  size: 15, color: Colors.white)
                            else
                              const Icon(Icons.send_rounded,
                                  size: 14, color: Colors.white),
                            const SizedBox(width: 6),
                            Text(
                              isLoading ? '取消请求' : '发送',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12.5,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              if (_workspace.showUrlPreviewBar) ...[
                const SizedBox(height: 5),

                // 实际解析目标预览 (弱化呈现，节省垂直空间，支持悬浮完整提示与复制)
                Tooltip(
                  message: resolvedPreviewUrl.isEmpty
                      ? '未配置请求目标'
                      : '实际解析目标完整 URL: $resolvedPreviewUrl\n点击可快捷复制',
                  child: InkWell(
                    borderRadius: BorderRadius.circular(4),
                    onTap: resolvedPreviewUrl.isNotEmpty
                        ? () {
                            Clipboard.setData(
                                ClipboardData(text: resolvedPreviewUrl));
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('已复制解析后完整 URL'),
                                duration: Duration(milliseconds: 1200),
                                behavior: SnackBarBehavior.floating,
                              ),
                            );
                          }
                        : null,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                      child: Row(
                        children: [
                          const Icon(Icons.link_rounded,
                              size: 13, color: Color(0xFF94A3B8)),
                          const SizedBox(width: 4),
                          const Text(
                            '实际请求: ',
                            style: TextStyle(
                              fontSize: 10.5,
                              color: Color(0xFF94A3B8),
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          Expanded(
                            child: Text(
                              resolvedPreviewUrl.isEmpty
                                  ? '未填写'
                                  : resolvedPreviewUrl,
                              style: const TextStyle(
                                fontSize: 10.5,
                                color: Color(0xFF64748B),
                                fontFamily: AppFonts.codeFamily,
                                fontFamilyFallback: AppFonts.codeFallback,
                                fontWeight: FontWeight.w500,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (resolvedPreviewUrl.isNotEmpty) ...[
                            const SizedBox(width: 4),
                            const Icon(Icons.copy_rounded,
                                size: 11, color: Color(0xFF94A3B8)),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),

        // 4.3 请求参数与前置脚本配置子标签 (纯平纯粹底座 + 2px 蓝色下划线指示器)
        Container(
          height: 38,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: const BoxDecoration(
            color: Color(0xFFF8FAFC),
            border: Border(
              bottom: BorderSide(color: Color(0xFFE2E8F0), width: 1.0),
            ),
          ),
          child: TabBar(
            controller: _reqTabController,
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            splashFactory: NoSplash.splashFactory,
            overlayColor: WidgetStateProperty.all(Colors.transparent),
            labelColor: const Color(0xFF2563EB),
            unselectedLabelColor: const Color(0xFF64748B),
            indicatorSize: TabBarIndicatorSize.label,
            indicator: const UnderlineTabIndicator(
              borderSide: BorderSide(color: Color(0xFF2563EB), width: 2.0),
              insets: EdgeInsets.symmetric(horizontal: -2),
            ),
            labelStyle:
                const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
            unselectedLabelStyle:
                const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
            tabs: [
              Tab(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('Params'),
                      if (req.params.isNotEmpty) ...[
                        const SizedBox(width: 5),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 5, vertical: 1),
                          decoration: BoxDecoration(
                            color: const Color(0xFFEFF6FF),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            '${req.params.length}',
                            style: const TextStyle(
                                fontSize: 10,
                                color: Color(0xFF2563EB),
                                fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              Tab(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('Headers'),
                      if (req.headers.isNotEmpty) ...[
                        const SizedBox(width: 5),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 5, vertical: 1),
                          decoration: BoxDecoration(
                            color: const Color(0xFFEFF6FF),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            '${req.headers.length}',
                            style: const TextStyle(
                                fontSize: 10,
                                color: Color(0xFF2563EB),
                                fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              Tab(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('Body'),
                      if (req.bodyType != BodyType.none) ...[
                        const SizedBox(width: 5),
                        Container(
                          width: 5,
                          height: 5,
                          decoration: const BoxDecoration(
                            color: Color(0xFF2563EB),
                            shape: BoxShape.circle,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              Tab(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('⚡ 前置脚本'),
                      if (req.preRequestScript.trim().isNotEmpty) ...[
                        const SizedBox(width: 5),
                        Container(
                          width: 5,
                          height: 5,
                          decoration: const BoxDecoration(
                            color: Color(0xFF10B981),
                            shape: BoxShape.circle,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              Tab(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('🧪 测试断言'),
                      if (req.postRequestScript.trim().isNotEmpty) ...[
                        const SizedBox(width: 5),
                        Container(
                          width: 5,
                          height: 5,
                          decoration: const BoxDecoration(
                            color: Color(0xFF10B981),
                            shape: BoxShape.circle,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),

        // 4.4 请求参数视图与响应区域 (支持上下边缘拖拽调整高度比例)
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              const splitterHeight = 7.0;
              final usableHeight = (constraints.maxHeight - splitterHeight)
                  .clamp(120.0, 4000.0);
              final minPanelHeight =
                  usableHeight > 220.0 ? 90.0 : usableHeight * 0.25;
              final topHeight = (usableHeight * _requestPanelRatio)
                  .clamp(minPanelHeight, usableHeight - minPanelHeight);
              final bottomHeight =
                  (usableHeight - topHeight).clamp(0.0, usableHeight);

              return Column(
                children: [
                  // 上半部分：请求配置子面板 (Params/Headers/Body/PreScript/Tests)
                  SizedBox(
                    height: topHeight,
                    child: TabBarView(
                      controller: _reqTabController,
                      children: [
                        // Params
                        Padding(
                          padding: const EdgeInsets.all(12),
                          child: SingleChildScrollView(
                            child: KeyValueEditor(
                              items: req.params,
                              onChanged: () {
                                setState(() {});
                                _markCurrentTabDirty();
                              },
                              keyPlaceholder: 'Query Parameter',
                            ),
                          ),
                        ),

                        // Headers
                        Padding(
                          padding: const EdgeInsets.all(12),
                          child: SingleChildScrollView(
                            child: KeyValueEditor(
                              items: req.headers,
                              onChanged: () {
                                setState(() {});
                                _markCurrentTabDirty();
                              },
                              keyPlaceholder: 'Header Name',
                            ),
                          ),
                        ),

                        // Body
                        Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              // Body 类型分段控制器 (Segmented Control) + Raw 格式下拉选择 + 暗色代码模式
                              Container(
                                height: 34,
                                margin: const EdgeInsets.only(bottom: 8),
                                child: Row(
                                  children: [
                                    // 现代化分段控制器替代传统单选圆圈
                                    Container(
                                      padding: const EdgeInsets.all(2.5),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFF1F5F9),
                                        borderRadius: BorderRadius.circular(7),
                                        border: Border.all(color: const Color(0xFFE2E8F0)),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          _buildBodySegmentItem(
                                            label: 'none',
                                            isSelected: req.bodyType == BodyType.none,
                                            onTap: () {
                                              setState(() {
                                                req.bodyType = BodyType.none;
                                              });
                                              _markCurrentTabDirty();
                                            },
                                          ),
                                          _buildBodySegmentItem(
                                            label: 'form-data',
                                            isSelected: req.bodyType == BodyType.formData,
                                            onTap: () {
                                              setState(() {
                                                req.bodyType = BodyType.formData;
                                              });
                                              _markCurrentTabDirty();
                                            },
                                          ),
                                          _buildBodySegmentItem(
                                            label: 'urlencoded',
                                            isSelected: req.bodyType == BodyType.formUrlEncoded,
                                            onTap: () {
                                              setState(() {
                                                req.bodyType = BodyType.formUrlEncoded;
                                              });
                                              _markCurrentTabDirty();
                                            },
                                          ),
                                          _buildBodySegmentItem(
                                            label: 'raw',
                                            isSelected: req.bodyType == BodyType.json || req.bodyType == BodyType.raw,
                                            onTap: () {
                                              setState(() {
                                                req.bodyType = BodyType.raw;
                                              });
                                              _markCurrentTabDirty();
                                            },
                                          ),
                                        ],
                                      ),
                                    ),

                                    if (req.bodyType == BodyType.json ||
                                        req.bodyType == BodyType.raw) ...[
                                      const SizedBox(width: 8),
                                      ModernDropdown<String>(
                                        value: const [
                                          'json',
                                          'text',
                                          'xml',
                                          'html',
                                          'javascript'
                                        ].contains(req.rawFormat.toLowerCase())
                                            ? req.rawFormat.toLowerCase()
                                            : 'json',
                                        menuWidth: 120,
                                        tooltip: '切换请求体格式',
                                        items: const [
                                          ModernDropdownItem(value: 'json', label: 'JSON'),
                                          ModernDropdownItem(value: 'text', label: 'Text'),
                                          ModernDropdownItem(value: 'xml', label: 'XML'),
                                          ModernDropdownItem(value: 'html', label: 'HTML'),
                                          ModernDropdownItem(value: 'javascript', label: 'JavaScript'),
                                        ],
                                        onChanged: (val) {
                                          setState(() {
                                            req.rawFormat = val;
                                            req.bodyType = val == 'json'
                                                ? BodyType.json
                                                : BodyType.raw;
                                          });
                                          _markCurrentTabDirty();
                                        },
                                        child: Container(
                                          height: 28,
                                          padding: const EdgeInsets.symmetric(horizontal: 8),
                                          decoration: BoxDecoration(
                                            color: Colors.white,
                                            borderRadius: BorderRadius.circular(6),
                                            border: Border.all(
                                                color: const Color(0xFFE2E8F0), width: 1.0),
                                          ),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Text(
                                                req.rawFormat.toUpperCase(),
                                                style: const TextStyle(
                                                  fontSize: 11.5,
                                                  fontWeight: FontWeight.w700,
                                                  color: Color(0xFF2563EB),
                                                ),
                                              ),
                                              const SizedBox(width: 3),
                                              const Icon(
                                                Icons.keyboard_arrow_down_rounded,
                                                size: 15,
                                                color: Color(0xFF2563EB),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ],

                                    const Spacer(),

                                    // 代码编辑器深浅主题切换按钮
                                    Tooltip(
                                      message: _editorDarkMode
                                          ? '切换为明亮代码区'
                                          : '切换为暗色代码模式 (突出代码高亮)',
                                      child: InkWell(
                                        borderRadius: BorderRadius.circular(5),
                                        onTap: () {
                                          setState(() {
                                            _editorDarkMode = !_editorDarkMode;
                                            _bodyController.isDark = _editorDarkMode;
                                            _preScriptController.isDark = _editorDarkMode;
                                            _postScriptController.isDark = _editorDarkMode;
                                          });
                                        },
                                        child: Container(
                                          height: 26,
                                          padding: const EdgeInsets.symmetric(horizontal: 7),
                                          decoration: BoxDecoration(
                                            color: _editorDarkMode
                                                ? const Color(0xFF1E293B)
                                                : const Color(0xFFF1F5F9),
                                            borderRadius: BorderRadius.circular(5),
                                            border: Border.all(
                                              color: _editorDarkMode
                                                  ? const Color(0xFF334155)
                                                  : const Color(0xFFE2E8F0),
                                            ),
                                          ),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(
                                                _editorDarkMode
                                                    ? Icons.light_mode_rounded
                                                    : Icons.dark_mode_rounded,
                                                size: 13,
                                                color: _editorDarkMode
                                                    ? const Color(0xFFFBBF24)
                                                    : const Color(0xFF64748B),
                                              ),
                                              const SizedBox(width: 4),
                                              Text(
                                                _editorDarkMode ? '暗色代码' : '明亮代码',
                                                style: TextStyle(
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.w600,
                                                  color: _editorDarkMode
                                                      ? const Color(0xFFF8FAFC)
                                                      : const Color(0xFF475569),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),

                                    if ((req.bodyType == BodyType.json ||
                                            req.bodyType == BodyType.raw) &&
                                        req.rawFormat.toLowerCase() == 'json')
                                      TextButton.icon(
                                        onPressed: _formatJsonBody,
                                        style: TextButton.styleFrom(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 8, vertical: 2),
                                          minimumSize: Size.zero,
                                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                        ),
                                        icon: const Icon(
                                            Icons.auto_fix_high_rounded,
                                            size: 13.5),
                                        label: const Text('格式化 JSON',
                                            style: TextStyle(
                                                fontSize: 11.5,
                                                fontWeight: FontWeight.w600)),
                                      ),
                                  ],
                                ),
                              ),
                              if (req.bodyType == BodyType.formData)
                                Expanded(
                                  child: SingleChildScrollView(
                                    child: KeyValueEditor(
                                      items: req.formDataFields,
                                      isFormData: true,
                                      keyPlaceholder: '表单字段',
                                      valuePlaceholder: '表单值',
                                      onChanged: () {
                                        setState(() {});
                                        _markCurrentTabDirty();
                                      },
                                    ),
                                  ),
                                )
                              else if (req.bodyType == BodyType.formUrlEncoded)
                                Expanded(
                                  child: SingleChildScrollView(
                                    child: KeyValueEditor(
                                      items: req.formDataFields,
                                      isFormData: false,
                                      keyPlaceholder: '参数名',
                                      valuePlaceholder: '参数值',
                                      onChanged: () {
                                        setState(() {});
                                        _markCurrentTabDirty();
                                      },
                                    ),
                                  ),
                                )
                              else if (req.bodyType == BodyType.none)
                                Expanded(
                                  child: Container(
                                    alignment: Alignment.center,
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFF8FAFC),
                                      borderRadius: BorderRadius.circular(6),
                                      border: Border.all(
                                          color: const Color(0xFFE2E8F0)),
                                    ),
                                    child: Text(
                                      '该请求无 Request Body',
                                      style: TextStyle(
                                          color: Colors.grey.shade500,
                                          fontSize: 12.5),
                                    ),
                                  ),
                                )
                              else
                                Expanded(
                                  child: AnimatedContainer(
                                    duration: const Duration(milliseconds: 150),
                                    decoration: BoxDecoration(
                                      color: _editorDarkMode
                                          ? const Color(0xFF0F172A)
                                          : const Color(0xFFF8FAFC),
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(
                                        color: _editorDarkMode
                                            ? const Color(0xFF334155)
                                            : const Color(0xFFE2E8F0),
                                        width: 1.0,
                                      ),
                                    ),
                                    child: TextFormField(
                                      controller: _bodyController,
                                      maxLines: null,
                                      expands: true,
                                      textAlign: TextAlign.left,
                                      textAlignVertical: TextAlignVertical.top,
                                      cursorColor: _editorDarkMode
                                          ? const Color(0xFF60A5FA)
                                          : const Color(0xFF2563EB),
                                      style: TextStyle(
                                        fontFamily: AppFonts.codeFamily,
                                        fontFamilyFallback: AppFonts.codeFallback,
                                        fontSize: 13,
                                        height: 1.45,
                                        color: _editorDarkMode
                                            ? const Color(0xFFF8FAFC)
                                            : const Color(0xFF0F172A),
                                      ),
                                      decoration: InputDecoration(
                                        hintText:
                                            '在此输入 ${req.rawFormat.toUpperCase()} 请求体内容...',
                                        hintStyle: TextStyle(
                                            color: _editorDarkMode
                                                ? const Color(0xFF64748B)
                                                : Colors.grey.shade400,
                                            fontSize: 12),
                                        filled: false,
                                        border: InputBorder.none,
                                        enabledBorder: InputBorder.none,
                                        focusedBorder: InputBorder.none,
                                        contentPadding: const EdgeInsets.all(12),
                                      ),
                                      onChanged: (val) {
                                        req.bodyContent = val;
                                        _markCurrentTabDirty();
                                      },
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),

                        // Pre-request Script
                        Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  const Text(
                                    '沙箱 JavaScript 脚本，在请求发送前执行，支持 pm.environment 与 CryptoJS 签名',
                                    style: TextStyle(
                                        fontSize: 11, color: Colors.grey),
                                  ),
                                  const Spacer(),
                                  ActionChip(
                                    label: const Text('插入 HMAC 签名示例',
                                        style: TextStyle(fontSize: 10)),
                                    onPressed: () {
                                      _preScriptController.text += '''\n
// 插入时间戳与动态 HMAC 签名
const ts = Date.now();
const sign = CryptoJS.MD5(ts + "my_secret").toString();
pm.request.headers.add({ key: "X-Sign", value: sign });
pm.environment.set("lastSign", sign);
console.log("签名计算完成: " + sign);
''';
                                      req.preRequestScript =
                                          _preScriptController.text;
                                      _markCurrentTabDirty();
                                    },
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Expanded(
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 150),
                                  decoration: BoxDecoration(
                                    color: _editorDarkMode
                                        ? const Color(0xFF0F172A)
                                        : const Color(0xFFF8FAFC),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: _editorDarkMode
                                          ? const Color(0xFF334155)
                                          : const Color(0xFFE2E8F0),
                                      width: 1.0,
                                    ),
                                  ),
                                  child: TextFormField(
                                    controller: _preScriptController,
                                    maxLines: null,
                                    expands: true,
                                    textAlign: TextAlign.left,
                                    textAlignVertical: TextAlignVertical.top,
                                    cursorColor: _editorDarkMode
                                        ? const Color(0xFF60A5FA)
                                        : const Color(0xFF2563EB),
                                    style: TextStyle(
                                      fontFamily: AppFonts.codeFamily,
                                      fontFamilyFallback: AppFonts.codeFallback,
                                      fontSize: 12.5,
                                      height: 1.45,
                                      color: _editorDarkMode
                                          ? const Color(0xFFF8FAFC)
                                          : const Color(0xFF0F172A),
                                    ),
                                    decoration: InputDecoration(
                                      hintText:
                                          '// 编写前置 JavaScript 脚本...\npm.environment.set("token", "xxx");',
                                      hintStyle: TextStyle(
                                        color: _editorDarkMode
                                            ? const Color(0xFF64748B)
                                            : Colors.grey.shade400,
                                        fontSize: 12,
                                      ),
                                      filled: false,
                                      border: InputBorder.none,
                                      enabledBorder: InputBorder.none,
                                      focusedBorder: InputBorder.none,
                                      contentPadding: const EdgeInsets.all(12),
                                    ),
                                    onChanged: (val) {
                                      req.preRequestScript = val;
                                      _markCurrentTabDirty();
                                    },
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),

                        // Tests
                        Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  const Text(
                                    '后置测试与断言脚本，支持 pm.test 与 pm.response',
                                    style: TextStyle(
                                        fontSize: 11, color: Colors.grey),
                                  ),
                                  const Spacer(),
                                  ActionChip(
                                    label: const Text('插入 200 断言',
                                        style: TextStyle(fontSize: 10)),
                                    onPressed: () {
                                      _postScriptController.text += '''\n
pm.test("Status code is 200", function () {
    pm.response.to.have.status(200);
});
''';
                                      req.postRequestScript =
                                          _postScriptController.text;
                                      _markCurrentTabDirty();
                                    },
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Expanded(
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 150),
                                  decoration: BoxDecoration(
                                    color: _editorDarkMode
                                        ? const Color(0xFF0F172A)
                                        : const Color(0xFFF8FAFC),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: _editorDarkMode
                                          ? const Color(0xFF334155)
                                          : const Color(0xFFE2E8F0),
                                      width: 1.0,
                                    ),
                                  ),
                                  child: TextFormField(
                                    controller: _postScriptController,
                                    maxLines: null,
                                    expands: true,
                                    textAlign: TextAlign.left,
                                    textAlignVertical: TextAlignVertical.top,
                                    cursorColor: _editorDarkMode
                                        ? const Color(0xFF60A5FA)
                                        : const Color(0xFF2563EB),
                                    style: TextStyle(
                                      fontFamily: AppFonts.codeFamily,
                                      fontFamilyFallback: AppFonts.codeFallback,
                                      fontSize: 12.5,
                                      height: 1.45,
                                      color: _editorDarkMode
                                          ? const Color(0xFFF8FAFC)
                                          : const Color(0xFF0F172A),
                                    ),
                                    decoration: InputDecoration(
                                      hintText:
                                          '// 编写测试断言...\npm.test("Status 200", function() { ... });',
                                      hintStyle: TextStyle(
                                        color: _editorDarkMode
                                            ? const Color(0xFF64748B)
                                            : Colors.grey.shade400,
                                        fontSize: 12,
                                      ),
                                      filled: false,
                                      border: InputBorder.none,
                                      enabledBorder: InputBorder.none,
                                      focusedBorder: InputBorder.none,
                                      contentPadding: const EdgeInsets.all(12),
                                    ),
                                    onChanged: (val) {
                                      req.postRequestScript = val;
                                      _markCurrentTabDirty();
                                    },
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  // 中间上下分栏拖拽调整手柄
                  _buildVerticalResizer(usableHeight),

                  // 下半部分：响应展示视图区域
                  SizedBox(
                    height: bottomHeight,
                    child: isLoading
                        ? _buildResponseLoadingView(req)
                        : response == null
                            ? _buildResponseEmptyView()
                            : Column(
                            children: [
                              // 响应状态栏
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 14, vertical: 7),
                                decoration: const BoxDecoration(
                                  color: Color(0xFFF8FAFC),
                                  border: Border(
                                    bottom:
                                        BorderSide(color: Color(0xFFE2E8F0)),
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    StatusCodeBadge(
                                      statusCode: response.statusCode,
                                      statusMessage: response.statusMessage,
                                    ),
                                    const SizedBox(width: 8),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 8, vertical: 3.5),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFFFFBEB),
                                        border: Border.all(
                                            color: const Color(0xFFFDE68A),
                                            width: 0.8),
                                        borderRadius: BorderRadius.circular(5),
                                      ),
                                      child: Row(
                                        children: [
                                          const Icon(Icons.speed_rounded,
                                              size: 13,
                                              color: Color(0xFFD97706)),
                                          const SizedBox(width: 4),
                                          Text(
                                            '${response.durationMs} ms',
                                            style: const TextStyle(
                                              fontSize: 11.5,
                                              fontWeight: FontWeight.w600,
                                              color: Color(0xFFB45309),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 8, vertical: 3.5),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFEEF2FF),
                                        border: Border.all(
                                            color: const Color(0xFFC7D2FE),
                                            width: 0.8),
                                        borderRadius: BorderRadius.circular(5),
                                      ),
                                      child: Row(
                                        children: [
                                          const Icon(Icons.inventory_2_outlined,
                                              size: 13,
                                              color: Color(0xFF6366F1)),
                                          const SizedBox(width: 4),
                                          Text(
                                            '${(response.sizeBytes / 1024).toStringAsFixed(2)} KB',
                                            style: const TextStyle(
                                              fontSize: 11.5,
                                              fontWeight: FontWeight.w600,
                                              color: Color(0xFF4338CA),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const Spacer(),
                                    // JSON / 表格 视图切换开关
                                    Container(
                                      height: 26,
                                      padding: const EdgeInsets.all(2),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFE2E8F0),
                                        borderRadius: BorderRadius.circular(5),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          InkWell(
                                            onTap: () {
                                              setState(() {
                                                _responseViewMode = 'json';
                                              });
                                            },
                                            borderRadius:
                                                BorderRadius.circular(4),
                                            child: Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                      horizontal: 8,
                                                      vertical: 2),
                                              decoration: BoxDecoration(
                                                color: _responseViewMode ==
                                                        'json'
                                                    ? Colors.white
                                                    : Colors.transparent,
                                                borderRadius:
                                                    BorderRadius.circular(4),
                                              ),
                                              child: Row(
                                                children: [
                                                  Icon(
                                                    Icons.data_object_rounded,
                                                    size: 12,
                                                    color: _responseViewMode ==
                                                            'json'
                                                        ? const Color(
                                                            0xFF2563EB)
                                                        : const Color(
                                                            0xFF64748B),
                                                  ),
                                                  const SizedBox(width: 3),
                                                  Text(
                                                    'JSON',
                                                    style: TextStyle(
                                                      fontSize: 11,
                                                      fontWeight:
                                                          FontWeight.w600,
                                                      color:
                                                          _responseViewMode ==
                                                                  'json'
                                                              ? const Color(
                                                                  0xFF2563EB)
                                                              : const Color(
                                                                  0xFF64748B),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                          InkWell(
                                            onTap: () {
                                              setState(() {
                                                _responseViewMode = 'table';
                                              });
                                            },
                                            borderRadius:
                                                BorderRadius.circular(4),
                                            child: Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                      horizontal: 8,
                                                      vertical: 2),
                                              decoration: BoxDecoration(
                                                color: _responseViewMode ==
                                                        'table'
                                                    ? Colors.white
                                                    : Colors.transparent,
                                                borderRadius:
                                                    BorderRadius.circular(4),
                                              ),
                                              child: Row(
                                                children: [
                                                  Icon(
                                                    Icons
                                                        .table_chart_outlined,
                                                    size: 12,
                                                    color: _responseViewMode ==
                                                            'table'
                                                        ? const Color(
                                                            0xFF2563EB)
                                                        : const Color(
                                                            0xFF64748B),
                                                  ),
                                                  const SizedBox(width: 3),
                                                  Text(
                                                    '表格',
                                                    style: TextStyle(
                                                      fontSize: 11,
                                                      fontWeight:
                                                          FontWeight.w600,
                                                      color:
                                                          _responseViewMode ==
                                                                  'table'
                                                              ? const Color(
                                                                  0xFF2563EB)
                                                              : const Color(
                                                                  0xFF64748B),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Tooltip(
                                      message: '查找响应内容 Ctrl+F',
                                      child: OutlinedButton.icon(
                                        style: OutlinedButton.styleFrom(
                                          foregroundColor: _showResponseSearch
                                              ? const Color(0xFF2563EB)
                                              : const Color(0xFF334155),
                                          backgroundColor: _showResponseSearch
                                              ? const Color(0xFFEFF6FF)
                                              : Colors.white,
                                          side: BorderSide(
                                            color: _showResponseSearch
                                                ? const Color(0xFF93C5FD)
                                                : const Color(0xFFE2E8F0),
                                          ),
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 9, vertical: 4),
                                          minimumSize: Size.zero,
                                          tapTargetSize:
                                              MaterialTapTargetSize.shrinkWrap,
                                          shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(5)),
                                        ),
                                        icon: const Icon(Icons.search_rounded,
                                            size: 13),
                                        label: const Text('查找',
                                            style: TextStyle(
                                                fontSize: 11,
                                                fontWeight: FontWeight.w500)),
                                        onPressed: () {
                                          if (_showResponseSearch) {
                                            _closeResponseSearch();
                                          } else {
                                            _openResponseSearch();
                                          }
                                        },
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Tooltip(
                                      message: '复制响应 Body',
                                      child: OutlinedButton.icon(
                                        style: OutlinedButton.styleFrom(
                                          foregroundColor:
                                              const Color(0xFF334155),
                                          backgroundColor: Colors.white,
                                          side: const BorderSide(
                                              color: Color(0xFFE2E8F0)),
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 10, vertical: 4),
                                          minimumSize: Size.zero,
                                          tapTargetSize:
                                              MaterialTapTargetSize.shrinkWrap,
                                          shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(5)),
                                        ),
                                        icon: const Icon(Icons.copy_rounded,
                                            size: 13),
                                        label: const Text('复制响应',
                                            style: TextStyle(
                                                fontSize: 11,
                                                fontWeight: FontWeight.w500)),
                                        onPressed: () {
                                          Clipboard.setData(ClipboardData(
                                              text: response.body));
                                          ScaffoldMessenger.of(context)
                                              .showSnackBar(
                                            const SnackBar(
                                              content: Text('已复制响应报文内容'),
                                              duration:
                                                  Duration(milliseconds: 1200),
                                              behavior:
                                                  SnackBarBehavior.floating,
                                            ),
                                          );
                                        },
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Tooltip(
                                      message: _editorDarkMode
                                          ? '切换明亮代码模式'
                                          : '切换暗色代码模式',
                                      child: OutlinedButton.icon(
                                        style: OutlinedButton.styleFrom(
                                          foregroundColor: _editorDarkMode
                                              ? const Color(0xFFF1F5F9)
                                              : const Color(0xFF334155),
                                          backgroundColor: _editorDarkMode
                                              ? const Color(0xFF1E293B)
                                              : Colors.white,
                                          side: BorderSide(
                                            color: _editorDarkMode
                                                ? const Color(0xFF475569)
                                                : const Color(0xFFE2E8F0),
                                          ),
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 9, vertical: 4),
                                          minimumSize: Size.zero,
                                          tapTargetSize:
                                              MaterialTapTargetSize.shrinkWrap,
                                          shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(5)),
                                        ),
                                        icon: Icon(
                                          _editorDarkMode
                                              ? Icons.dark_mode_rounded
                                              : Icons.light_mode_outlined,
                                          size: 13,
                                          color: _editorDarkMode
                                              ? const Color(0xFFFBBF24)
                                              : const Color(0xFF64748B),
                                        ),
                                        label: Text(
                                          _editorDarkMode ? '深色' : '浅色',
                                          style: const TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.w500),
                                        ),
                                        onPressed: () {
                                          setState(() {
                                            _editorDarkMode = !_editorDarkMode;
                                            _bodyController.isDark =
                                                _editorDarkMode;
                                            _preScriptController.isDark =
                                                _editorDarkMode;
                                            _postScriptController.isDark =
                                                _editorDarkMode;
                                          });
                                        },
                                      ),
                                    ),
                                  ],
                                ),
                              ),

                              // 响应视图子 Tab 标签 (精致下划线与徽章设计，区别于上方请求胶囊切换器)
                              Container(
                                height: 34,
                                decoration: const BoxDecoration(
                                  color: Color(0xFFFAFAFA),
                                  border: Border(
                                    bottom:
                                        BorderSide(color: Color(0xFFE2E8F0)),
                                  ),
                                ),
                                child: TabBar(
                                  controller: _resTabController,
                                  isScrollable: true,
                                  tabAlignment: TabAlignment.start,
                                  labelColor: const Color(0xFF2563EB),
                                  unselectedLabelColor: const Color(0xFF64748B),
                                  indicatorColor: const Color(0xFF2563EB),
                                  indicatorWeight: 2.5,
                                  indicatorSize: TabBarIndicatorSize.label,
                                  labelStyle: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600),
                                  unselectedLabelStyle: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.normal),
                                  tabs: [
                                    const Tab(text: '响应'),
                                    Tab(
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          const Text('Headers'),
                                          const SizedBox(width: 5),
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 5, vertical: 1),
                                            decoration: BoxDecoration(
                                              color: const Color(0xFFF1F5F9),
                                              borderRadius:
                                                  BorderRadius.circular(10),
                                            ),
                                            child: Text(
                                              '${response.headers.length}',
                                              style: const TextStyle(
                                                fontSize: 10,
                                                color: Color(0xFF64748B),
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    Tab(
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          const Text('Tests'),
                                          const SizedBox(width: 5),
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 5, vertical: 1),
                                            decoration: BoxDecoration(
                                              color: response
                                                      .testResults.isEmpty
                                                  ? const Color(0xFFF1F5F9)
                                                  : response.testResults.every(
                                                          (t) => t.passed)
                                                      ? const Color(0xFFECFDF5)
                                                      : const Color(0xFFFEF2F2),
                                              borderRadius:
                                                  BorderRadius.circular(10),
                                            ),
                                            child: Text(
                                              '${response.testResults.length}',
                                              style: TextStyle(
                                                fontSize: 10,
                                                color: response
                                                        .testResults.isEmpty
                                                    ? const Color(0xFF64748B)
                                                    : response.testResults
                                                            .every(
                                                                (t) => t.passed)
                                                        ? const Color(
                                                            0xFF059669)
                                                        : const Color(
                                                            0xFFDC2626),
                                                fontWeight: FontWeight.w700,
                                              ),
                                            ),
                                          ),
                                          if (response
                                              .testResults.isNotEmpty) ...[
                                            const SizedBox(width: 4),
                                            Container(
                                              width: 6,
                                              height: 6,
                                              decoration: BoxDecoration(
                                                color: response.testResults
                                                        .every((t) => t.passed)
                                                    ? const Color(0xFF10B981)
                                                    : const Color(0xFFEF4444),
                                                shape: BoxShape.circle,
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                    ),
                                    Tab(
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          const Text('Console'),
                                          if (response
                                              .consoleLogs.isNotEmpty) ...[
                                            const SizedBox(width: 5),
                                            Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                      horizontal: 5,
                                                      vertical: 1),
                                              decoration: BoxDecoration(
                                                color: const Color(0xFFF1F5F9),
                                                borderRadius:
                                                    BorderRadius.circular(10),
                                              ),
                                              child: Text(
                                                '${response.consoleLogs.length}',
                                                style: const TextStyle(
                                                  fontSize: 10,
                                                  color: Color(0xFF64748B),
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),

                              // 响应视图内容展示
                              Expanded(
                                child: TabBarView(
                                  controller: _resTabController,
                                  children: [
                                    // 响应 Body (支持 Ctrl+F 查找与 JSON / 表格双视图切换)
                                    Column(
                                      children: [
                                        if (_showResponseSearch)
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 12, vertical: 6),
                                            decoration: const BoxDecoration(
                                              color: Color(0xFFF1F5F9),
                                              border: Border(
                                                bottom: BorderSide(
                                                    color: Color(0xFFE2E8F0)),
                                              ),
                                            ),
                                            child: Row(
                                              children: [
                                                const Icon(
                                                    Icons.search_rounded,
                                                    size: 15,
                                                    color: Color(0xFF64748B)),
                                                const SizedBox(width: 8),
                                                SizedBox(
                                                  width: 240,
                                                  height: 28,
                                                  child: TextField(
                                                    controller:
                                                        _responseSearchController,
                                                    focusNode:
                                                        _responseSearchFocusNode,
                                                    style: const TextStyle(
                                                        fontSize: 12),
                                                    decoration: InputDecoration(
                                                      hintText: '查找响应内容...',
                                                      hintStyle:
                                                          const TextStyle(
                                                        fontSize: 11.5,
                                                        color:
                                                            Color(0xFF94A3B8),
                                                      ),
                                                      filled: true,
                                                      fillColor: Colors.white,
                                                      contentPadding:
                                                          const EdgeInsets
                                                              .symmetric(
                                                              horizontal: 8,
                                                              vertical: 0),
                                                      border:
                                                          OutlineInputBorder(
                                                        borderRadius:
                                                            BorderRadius
                                                                .circular(5),
                                                        borderSide:
                                                            const BorderSide(
                                                                color: Color(
                                                                    0xFFE2E8F0),
                                                                width: 1.0),
                                                      ),
                                                      enabledBorder:
                                                          OutlineInputBorder(
                                                        borderRadius:
                                                            BorderRadius
                                                                .circular(5),
                                                        borderSide:
                                                            const BorderSide(
                                                                color: Color(
                                                                    0xFFE2E8F0),
                                                                width: 1.0),
                                                      ),
                                                      focusedBorder:
                                                          OutlineInputBorder(
                                                        borderRadius:
                                                            BorderRadius
                                                                .circular(5),
                                                        borderSide:
                                                            const BorderSide(
                                                                color: Color(
                                                                    0xFF2563EB)),
                                                      ),
                                                    ),
                                                    onChanged: (val) {
                                                      setState(() {
                                                        _responseSearchQuery =
                                                            val;
                                                        _responseSearchActiveIndex =
                                                            0;
                                                      });
                                                    },
                                                    onSubmitted: (_) =>
                                                        _nextResponseSearchMatch(),
                                                  ),
                                                ),
                                                const SizedBox(width: 8),
                                                if (_responseSearchQuery
                                                    .trim()
                                                    .isNotEmpty)
                                                  Container(
                                                    padding: const EdgeInsets
                                                        .symmetric(
                                                        horizontal: 7,
                                                        vertical: 2),
                                                    decoration: BoxDecoration(
                                                      color: _responseSearchMatchCount >
                                                              0
                                                          ? const Color(
                                                              0xFFEFF6FF)
                                                          : const Color(
                                                              0xFFFEF2F2),
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                              4),
                                                      border: Border.all(
                                                        color: _responseSearchMatchCount >
                                                                0
                                                            ? const Color(
                                                                0xFFBFDBFE)
                                                            : const Color(
                                                                0xFFFECACA),
                                                      ),
                                                    ),
                                                    child: Text(
                                                      _responseSearchMatchCount >
                                                              0
                                                          ? '${_responseSearchActiveIndex + 1} / $_responseSearchMatchCount'
                                                          : '无匹配',
                                                      style: TextStyle(
                                                        fontSize: 11,
                                                        fontFamily: AppFonts.codeFamily, fontFamilyFallback: AppFonts.codeFallback,
                                                        fontWeight:
                                                            FontWeight.w600,
                                                        color: _responseSearchMatchCount >
                                                                0
                                                            ? const Color(
                                                                0xFF1D4ED8)
                                                            : const Color(
                                                                0xFFDC2626),
                                                      ),
                                                    ),
                                                  ),
                                                const SizedBox(width: 4),
                                                Tooltip(
                                                  message: '上一个匹配项',
                                                  child: InkWell(
                                                    onTap:
                                                        _prevResponseSearchMatch,
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                            4),
                                                    child: const Padding(
                                                      padding:
                                                          EdgeInsets.all(4),
                                                      child: Icon(
                                                          Icons
                                                              .keyboard_arrow_up_rounded,
                                                          size: 16,
                                                          color: Color(
                                                              0xFF475569)),
                                                    ),
                                                  ),
                                                ),
                                                Tooltip(
                                                  message: '下一个匹配项',
                                                  child: InkWell(
                                                    onTap:
                                                        _nextResponseSearchMatch,
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                            4),
                                                    child: const Padding(
                                                      padding:
                                                          EdgeInsets.all(4),
                                                      child: Icon(
                                                          Icons
                                                              .keyboard_arrow_down_rounded,
                                                          size: 16,
                                                          color: Color(
                                                              0xFF475569)),
                                                    ),
                                                  ),
                                                ),
                                                const Spacer(),
                                                Tooltip(
                                                  message: '关闭查找 Esc',
                                                  child: InkWell(
                                                    onTap:
                                                        _closeResponseSearch,
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                            4),
                                                    child: const Padding(
                                                      padding:
                                                          EdgeInsets.all(4),
                                                      child: Icon(
                                                          Icons.close_rounded,
                                                          size: 15,
                                                          color: Color(
                                                              0xFF64748B)),
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        Expanded(
                                          child: Container(
                                            padding: const EdgeInsets.all(12),
                                            color: _editorDarkMode
                                                ? const Color(0xFF0F172A)
                                                : const Color(0xFFF8FAFC),
                                            child: response.prettyBody.isEmpty
                                                ? Align(
                                                    alignment:
                                                        Alignment.topLeft,
                                                    child: Text(
                                                      '响应体为空',
                                                      style: TextStyle(
                                                          color: _editorDarkMode
                                                              ? const Color(0xFF64748B)
                                                              : Colors.grey,
                                                          fontSize: 12),
                                                    ),
                                                  )
                                                : _responseViewMode == 'table'
                                                    ? ResponseTableViewer(
                                                        jsonText:
                                                            response.prettyBody,
                                                        selectedArrayPath:
                                                            _selectedResponseArrayPath,
                                                        searchQuery:
                                                            _responseSearchQuery,
                                                        activeMatchIndex:
                                                            _responseSearchActiveIndex,
                                                        onMatchCountChanged:
                                                            (count) {
                                                          if (_responseSearchMatchCount !=
                                                              count) {
                                                            setState(() {
                                                              _responseSearchMatchCount =
                                                                  count;
                                                              if (_responseSearchActiveIndex >=
                                                                      count &&
                                                                  count > 0) {
                                                                _responseSearchActiveIndex =
                                                                    0;
                                                              }
                                                            });
                                                          }
                                                        },
                                                        onArrayPathChanged:
                                                            (path) {
                                                          setState(() {
                                                            _selectedResponseArrayPath =
                                                                path;
                                                            _responseSearchActiveIndex =
                                                                0;
                                                          });
                                                        },
                                                        onSwitchToJson: () {
                                                          setState(() {
                                                            _responseViewMode =
                                                                'json';
                                                          });
                                                        },
                                                      )
                                                    : SingleChildScrollView(
                                                        child:
                                                            JsonHighlightedViewer(
                                                          jsonText: response
                                                              .prettyBody,
                                                          searchQuery:
                                                              _responseSearchQuery,
                                                          activeMatchIndex:
                                                              _responseSearchActiveIndex,
                                                          isDark:
                                                              _editorDarkMode,
                                                          onMatchCountChanged:
                                                              (count) {
                                                            if (_responseSearchMatchCount !=
                                                                count) {
                                                              setState(() {
                                                                _responseSearchMatchCount =
                                                                    count;
                                                                if (_responseSearchActiveIndex >=
                                                                        count &&
                                                                    count > 0) {
                                                                  _responseSearchActiveIndex =
                                                                      0;
                                                                }
                                                              });
                                                            }
                                                          },
                                                          onViewArrayAsTable:
                                                              (path, keyName,
                                                                  arrayData) {
                                                            setState(() {
                                                              _selectedResponseArrayPath =
                                                                  path;
                                                              _responseViewMode =
                                                                  'table';
                                                              _responseSearchActiveIndex =
                                                                  0;
                                                            });
                                                          },
                                                          style:
                                                              TextStyle(
                                                            fontFamily: AppFonts.codeFamily, fontFamilyFallback: AppFonts.codeFallback,
                                                            fontSize: 12.5,
                                                            height: 1.45,
                                                            color: _editorDarkMode
                                                                ? const Color(0xFFE2E8F0)
                                                                : const Color(0xFF1E293B),
                                                          ),
                                                        ),
                                                      ),
                                          ),
                                        ),
                                      ],
                                    ),

                                    // Headers
                                    SingleChildScrollView(
                                      padding: const EdgeInsets.all(12),
                                      child: Container(
                                        decoration: BoxDecoration(
                                          color: Colors.white,
                                          borderRadius:
                                              BorderRadius.circular(6),
                                          border: Border.all(
                                              color: const Color(0xFFE2E8F0)),
                                        ),
                                        clipBehavior: Clip.antiAlias,
                                        child: Column(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Container(
                                              height: 32,
                                              decoration: const BoxDecoration(
                                                color: Color(0xFFF1F5F9),
                                                border: Border(
                                                  bottom: BorderSide(
                                                      color:
                                                          Color(0xFFE2E8F0)),
                                                ),
                                              ),
                                              child: Row(
                                                children: [
                                                  Expanded(
                                                    flex: 3,
                                                    child: Container(
                                                      padding: const EdgeInsets
                                                          .symmetric(
                                                          horizontal: 10),
                                                      alignment:
                                                          Alignment.centerLeft,
                                                      decoration:
                                                          const BoxDecoration(
                                                        border: Border(
                                                          right: BorderSide(
                                                              color: Color(
                                                                  0xFFE2E8F0)),
                                                        ),
                                                      ),
                                                      child: const Text(
                                                        '响应头名称',
                                                        style: TextStyle(
                                                          fontSize: 11.5,
                                                          fontWeight:
                                                              FontWeight.w700,
                                                          color:
                                                              Color(0xFF475569),
                                                        ),
                                                      ),
                                                    ),
                                                  ),
                                                  const Expanded(
                                                    flex: 7,
                                                    child: Padding(
                                                      padding:
                                                          EdgeInsets.symmetric(
                                                              horizontal: 10),
                                                      child: Text(
                                                        '响应头数值',
                                                        style: TextStyle(
                                                          fontSize: 11.5,
                                                          fontWeight:
                                                              FontWeight.w700,
                                                          color:
                                                              Color(0xFF475569),
                                                        ),
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                            ...response.headers.entries
                                                .map((h) => Container(
                                                      decoration:
                                                          const BoxDecoration(
                                                        border: Border(
                                                          bottom: BorderSide(
                                                              color: Color(
                                                                  0xFFE2E8F0)),
                                                        ),
                                                      ),
                                                      child: IntrinsicHeight(
                                                        child: Row(
                                                          crossAxisAlignment:
                                                              CrossAxisAlignment
                                                                  .stretch,
                                                          children: [
                                                            Expanded(
                                                              flex: 3,
                                                              child: Container(
                                                                padding: const EdgeInsets
                                                                    .symmetric(
                                                                    horizontal:
                                                                        10,
                                                                    vertical:
                                                                        7),
                                                                decoration:
                                                                    const BoxDecoration(
                                                                  color: Color(
                                                                      0xFFF8FAFC),
                                                                  border:
                                                                      Border(
                                                                    right: BorderSide(
                                                                        color: Color(
                                                                            0xFFE2E8F0)),
                                                                  ),
                                                                ),
                                                                child:
                                                                    SelectableText(
                                                                  h.key,
                                                                  style: const TextStyle(
                                                                    fontWeight:
                                                                        FontWeight
                                                                            .w600,
                                                                    fontSize:
                                                                        12,
                                                                    fontFamily: AppFonts.codeFamily, fontFamilyFallback: AppFonts.codeFallback,
                                                                    color: Color(
                                                                        0xFF1E293B),
                                                                  ),
                                                                ),
                                                              ),
                                                            ),
                                                            Expanded(
                                                              flex: 7,
                                                              child: Container(
                                                                padding: const EdgeInsets
                                                                    .symmetric(
                                                                    horizontal:
                                                                        10,
                                                                    vertical:
                                                                        7),
                                                                child:
                                                                    SelectableText(
                                                                  h.value,
                                                                  style: const TextStyle(
                                                                    fontSize:
                                                                        12,
                                                                    fontFamily: AppFonts.codeFamily, fontFamilyFallback: AppFonts.codeFallback,
                                                                    color: Color(
                                                                        0xFF334155),
                                                                  ),
                                                                ),
                                                              ),
                                                            ),
                                                          ],
                                                        ),
                                                      ),
                                                    )),
                                          ],
                                        ),
                                      ),
                                    ),

                                    // Test Results
                                    response.testResults.isEmpty
                                        ? const Center(
                                            child: Text('无断言测试结果',
                                                style: TextStyle(
                                                    color: Colors.grey,
                                                    fontSize: 12)),
                                          )
                                        : ListView.builder(
                                            padding: const EdgeInsets.all(12),
                                            itemCount:
                                                response.testResults.length,
                                            itemBuilder: (context, idx) {
                                              final t =
                                                  response.testResults[idx];
                                              return ListTile(
                                                dense: true,
                                                leading: Icon(
                                                  t.passed
                                                      ? Icons.check_circle
                                                      : Icons.cancel,
                                                  color: t.passed
                                                      ? Colors.green
                                                      : Colors.red,
                                                  size: 18,
                                                ),
                                                title: Text(t.title,
                                                    style: const TextStyle(
                                                        fontSize: 12)),
                                                subtitle: t.error != null
                                                    ? Text(t.error!,
                                                        style: const TextStyle(
                                                            color: Colors.red,
                                                            fontSize: 11))
                                                    : null,
                                              );
                                            },
                                          ),

                                    // Console Logs
                                    response.consoleLogs.isEmpty
                                        ? const Center(
                                            child: Text('脚本未打印日志',
                                                style: TextStyle(
                                                    color: Colors.grey,
                                                    fontSize: 12)),
                                          )
                                        : ListView.builder(
                                            padding: const EdgeInsets.all(12),
                                            itemCount:
                                                response.consoleLogs.length,
                                            itemBuilder: (context, idx) {
                                              return Padding(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                        vertical: 2),
                                                child: SelectableText(
                                                  response.consoleLogs[idx],
                                                  style: const TextStyle(
                                                    fontFamily: AppFonts.codeFamily, fontFamilyFallback: AppFonts.codeFallback,
                                                    fontSize: 11,
                                                    color: Color(0xFF334155),
                                                  ),
                                                ),
                                              );
                                            },
                                          ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  /// 构建现代化 Body 类型 Segmented Control 单项 (none / form-data / urlencoded / raw)
  Widget _buildBodySegmentItem({
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(5),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: isSelected ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(5),
          border: isSelected
              ? Border.all(color: const Color(0xFFE2E8F0), width: 1.0)
              : Border.all(color: Colors.transparent, width: 1.0),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
            color: isSelected ? const Color(0xFF2563EB) : const Color(0xFF64748B),
          ),
        ),
      ),
    );
  }
}
