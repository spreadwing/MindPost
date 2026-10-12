import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/workspace.dart';
import '../models/api_collection.dart';
import '../models/api_request.dart';
import '../models/api_response.dart';
import '../models/environment.dart';
import '../services/http_client_service.dart';
import '../services/mcp_server_service.dart';
import '../services/storage_service.dart';
import '../engine/variable_resolver.dart';
import 'widgets/status_badge.dart';
import 'widgets/key_value_editor.dart';
import 'widgets/environment_dialog.dart';
import 'widgets/mcp_panel.dart';
import 'widgets/ai_copilot_drawer.dart';

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

  // 打开的请求标签页列表
  final List<ApiRequest> _openedRequests = [];
  int _activeTabIndex = 0;

  // 请求执行状态与响应映射
  final Map<String, bool> _requestLoading = {};
  final Map<String, ApiResponse?> _responses = {};

  // 当前请求编辑器的控制器
  final TextEditingController _urlController = TextEditingController();
  final TextEditingController _bodyController = TextEditingController();
  final TextEditingController _preScriptController = TextEditingController();
  final TextEditingController _postScriptController = TextEditingController();

  // Tab 控制器
  late TabController _reqTabController;
  late TabController _resTabController;

  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  @override
  void initState() {
    super.initState();
    _reqTabController = TabController(length: 5, vsync: this);
    _resTabController = TabController(length: 4, vsync: this);

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

    _initData();
  }

  Future<void> _initData() async {
    final loaded = await _storageService.loadWorkspace();
    setState(() {
      _workspace = loaded;
      _mcpServerService.updateWorkspace(_workspace);
      _isLoadingWorkspace = false;

      // 默认打开第一个接口
      if (_workspace.collections.isNotEmpty &&
          _workspace.collections.first.requests.isNotEmpty) {
        _openRequest(_workspace.collections.first.requests.first);
      }
    });

    // 默认自动启动 MCP Server
    await _mcpServerService.startServer();
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _mcpServerService.stopServer();
    _reqTabController.dispose();
    _resTabController.dispose();
    _urlController.dispose();
    _bodyController.dispose();
    _preScriptController.dispose();
    _postScriptController.dispose();
    super.dispose();
  }

  ApiRequest? get _currentRequest {
    if (_openedRequests.isEmpty || _activeTabIndex >= _openedRequests.length) {
      return null;
    }
    return _openedRequests[_activeTabIndex];
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
    final existingIndex =
        _openedRequests.indexWhere((r) => r.id == request.id);
    if (existingIndex >= 0) {
      setState(() {
        _activeTabIndex = existingIndex;
        _syncCurrentRequestToControllers();
      });
    } else {
      setState(() {
        _openedRequests.add(request);
        _activeTabIndex = _openedRequests.length - 1;
        _syncCurrentRequestToControllers();
      });
    }
  }

  void _closeTab(int index) {
    setState(() {
      _openedRequests.removeAt(index);
      if (_activeTabIndex >= _openedRequests.length) {
        _activeTabIndex = _openedRequests.length - 1;
      }
      _syncCurrentRequestToControllers();
    });
  }

  void _addNewTab() {
    final newReq = ApiRequest(
      name: '临时调试请求',
      url: '{{baseUrl}}/get',
      method: HttpMethod.get,
    );
    _openRequest(newReq);
  }

  Future<void> _sendCurrentRequest() async {
    final req = _currentRequest;
    if (req == null) return;

    // 同步控制器内容到模型
    req.url = _urlController.text;
    req.bodyContent = _bodyController.text;
    req.preRequestScript = _preScriptController.text;
    req.postRequestScript = _postScriptController.text;

    setState(() {
      _requestLoading[req.id] = true;
    });

    try {
      final execResult = await _httpClientService.executeRequest(
        request: req,
        workspace: _workspace,
      );

      setState(() {
        _responses[req.id] = execResult.response;

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
      _storageService.saveWorkspace(_workspace);
    } finally {
      if (mounted) {
        setState(() {
          _requestLoading[req.id] = false;
        });
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
      endDrawer: AiCopilotDrawer(
        activeRequest: _currentRequest,
        onRequestUpdated: () {
          setState(() {
            _syncCurrentRequestToControllers();
          });
        },
      ),
      body: Column(
        children: [
          // 顶部专业导航栏
          _buildTopNavigationBar(activeEnv),

          // 下方主体工作台（左侧导航 + 右侧请求响应区）
          Expanded(
            child: Row(
              children: [
                // 左侧集合与历史侧边栏
                _buildLeftSidebar(),

                const VerticalDivider(width: 1, thickness: 1),

                // 右侧多 Tab 调试主工作区
                Expanded(
                  child: _currentRequest == null
                      ? _buildEmptyWorkspace()
                      : _buildMainWorkspace(),
                ),
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

    return Container(
      height: 54,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        border: Border(bottom: BorderSide(color: Colors.grey.shade300)),
      ),
      child: Row(
        children: [
          // Logo & Title
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: const Color(0xFF3B82F6),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Icon(Icons.flash_on, color: Colors.white, size: 18),
              ),
              const SizedBox(width: 10),
              const Text(
                'PostMCP',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.blue.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Text(
                  'AI Native',
                  style: TextStyle(
                    color: Color(0xFF3B82F6),
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),

          const Spacer(),

          // 环境变量切换下拉框
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey.shade300),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(
              children: [
                const Icon(Icons.public, size: 16, color: Colors.grey),
                const SizedBox(width: 6),
                DropdownButtonHideUnderline(
                  child: DropdownButton<String?>(
                    value: _workspace.activeEnvironmentId,
                    hint: const Text('无环境 (No Env)', style: TextStyle(fontSize: 12)),
                    items: [
                      const DropdownMenuItem<String?>(
                        value: null,
                        child: Text('无环境 (No Environment)',
                            style: TextStyle(fontSize: 12)),
                      ),
                      ..._workspace.environments.map((e) {
                        return DropdownMenuItem<String?>(
                          value: e.id,
                          child: Text('${e.name} (${e.baseUrl})',
                              style: const TextStyle(fontSize: 12)),
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
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),

          // 环境管理弹窗按钮
          IconButton(
            tooltip: '管理环境变量与 URL 前缀',
            icon: const Icon(Icons.settings_outlined, size: 20),
            onPressed: () {
              showDialog(
                context: context,
                builder: (_) => EnvironmentDialog(
                  workspace: _workspace,
                  onSaved: () {
                    setState(() {});
                    _storageService.saveWorkspace(_workspace);
                  },
                ),
              );
            },
          ),
          const SizedBox(width: 8),

          // MCP Server 状态与控制面板入口
          InkWell(
            onTap: () {
              showDialog(
                context: context,
                builder: (_) => McpPanel(
                  mcpServerService: _mcpServerService,
                  onStateChanged: () => setState(() {}),
                ),
              );
            },
            borderRadius: BorderRadius.circular(6),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: (mcpRunning ? const Color(0xFF10B981) : Colors.grey)
                    .withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: (mcpRunning ? const Color(0xFF10B981) : Colors.grey)
                      .withValues(alpha: 0.4),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 7,
                    height: 7,
                    decoration: BoxDecoration(
                      color: mcpRunning ? const Color(0xFF10B981) : Colors.grey,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    mcpRunning ? 'MCP :${_mcpServerService.port}' : 'MCP 离线',
                    style: TextStyle(
                      color:
                          mcpRunning ? const Color(0xFF10B981) : Colors.grey,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),

          // AI Copilot 侧边栏按钮
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF8B5CF6),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            ),
            icon: const Icon(Icons.auto_awesome, size: 14),
            label: const Text('AI 调试副驾', style: TextStyle(fontSize: 12)),
            onPressed: () {
              _scaffoldKey.currentState?.openEndDrawer();
            },
          ),
        ],
      ),
    );
  }

  // 2. 左侧集合与请求导航树
  Widget _buildLeftSidebar() {
    return Container(
      width: 260,
      color: Theme.of(context).cardColor,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(
              children: [
                const Text(
                  'API 集合',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                ),
                const Spacer(),
                IconButton(
                  tooltip: '新建集合',
                  icon: const Icon(Icons.create_new_folder_outlined, size: 18),
                  onPressed: () {
                    final newCol = ApiCollection(
                      name: '新集合 ${_workspace.collections.length + 1}',
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
                  },
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView.builder(
              itemCount: _workspace.collections.length,
              itemBuilder: (context, colIndex) {
                final col = _workspace.collections[colIndex];
                return ExpansionTile(
                  key: PageStorageKey('col_${col.id}'),
                  initiallyExpanded: true,
                  leading: const Icon(Icons.folder_outlined,
                      size: 18, color: Color(0xFF3B82F6)),
                  title: Text(
                    col.name,
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.bold),
                  ),
                  trailing: IconButton(
                    icon: const Icon(Icons.add, size: 16),
                    tooltip: '添加接口',
                    onPressed: () {
                      final newReq = ApiRequest(
                        name: '新请求',
                        collectionId: col.id,
                        url: '{{baseUrl}}/get',
                        method: HttpMethod.get,
                      );
                      setState(() {
                        col.requests.add(newReq);
                      });
                      _storageService.saveWorkspace(_workspace);
                      _openRequest(newReq);
                    },
                  ),
                  children: col.requests.map((req) {
                    final isCurrent = _currentRequest?.id == req.id;
                    return ListTile(
                      dense: true,
                      selected: isCurrent,
                      selectedTileColor:
                          const Color(0xFF3B82F6).withValues(alpha: 0.1),
                      leading: HttpMethodBadge(method: req.method),
                      title: Text(
                        req.name,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: isCurrent
                              ? FontWeight.bold
                              : FontWeight.normal,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      onTap: () => _openRequest(req),
                    );
                  }).toList(),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  // 3. 空白工作区状态
  Widget _buildEmptyWorkspace() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.dashboard_customize_outlined,
              size: 48, color: Colors.grey),
          const SizedBox(height: 12),
          const Text('请从左侧选择一个接口，或新建调试请求',
              style: TextStyle(color: Colors.grey)),
          const SizedBox(height: 12),
          ElevatedButton.icon(
            onPressed: _addNewTab,
            icon: const Icon(Icons.add),
            label: const Text('新建请求标签页'),
          ),
        ],
      ),
    );
  }

  // 4. 多 Tab 主调试工作区
  Widget _buildMainWorkspace() {
    final req = _currentRequest!;
    final isLoading = _requestLoading[req.id] == true;
    final response = _responses[req.id];

    // 计算实时预览 URL
    final envVars = VariableResolver.buildVariableMap(workspace: _workspace);
    final resolvedPreviewUrl = VariableResolver.resolveUrl(
      rawUrl: _urlController.text,
      variables: envVars,
      currentBaseUrl: _workspace.activeEnvironment?.baseUrl,
    );

    return Column(
      children: [
        // 4.1 多标签栏 (Tabs Bar)
        Container(
          height: 38,
          color: Colors.grey.withValues(alpha: 0.04),
          child: Row(
            children: [
              Expanded(
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  itemCount: _openedRequests.length,
                  itemBuilder: (context, index) {
                    final tabReq = _openedRequests[index];
                    final isSelected = index == _activeTabIndex;
                    return InkWell(
                      onTap: () {
                        setState(() {
                          _activeTabIndex = index;
                          _syncCurrentRequestToControllers();
                        });
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? Theme.of(context).cardColor
                              : Colors.transparent,
                          border: Border(
                            bottom: BorderSide(
                              color: isSelected
                                  ? const Color(0xFF3B82F6)
                                  : Colors.transparent,
                              width: 2,
                            ),
                            right: BorderSide(color: Colors.grey.shade300),
                          ),
                        ),
                        child: Row(
                          children: [
                            HttpMethodBadge(
                                method: tabReq.method, fontSize: 10),
                            const SizedBox(width: 8),
                            Text(
                              tabReq.name,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: isSelected
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                              ),
                            ),
                            const SizedBox(width: 8),
                            InkWell(
                              onTap: () => _closeTab(index),
                              child: const Icon(Icons.close, size: 14),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
              IconButton(
                tooltip: '新建请求',
                icon: const Icon(Icons.add, size: 18),
                onPressed: _addNewTab,
              ),
            ],
          ),
        ),

        const Divider(height: 1),

        // 4.2 请求编辑与发送行
        Padding(
          padding: const EdgeInsets.all(12.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  // HTTP Method 下拉
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey.shade300),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<HttpMethod>(
                        value: req.method,
                        items: HttpMethod.values.map((m) {
                          return DropdownMenuItem(
                            value: m,
                            child: HttpMethodBadge(method: m),
                          );
                        }).toList(),
                        onChanged: (val) {
                          if (val != null) {
                            setState(() {
                              req.method = val;
                            });
                          }
                        },
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),

                  // URL 输入框
                  Expanded(
                    child: TextFormField(
                      controller: _urlController,
                      style: const TextStyle(
                          fontSize: 13, fontFamily: 'monospace'),
                      decoration: InputDecoration(
                        hintText:
                            '输入请求 URL 或相对路径（如 {{baseUrl}}/get 或 /api/v1/users）',
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 10),
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(6)),
                      ),
                      onChanged: (val) {
                        req.url = val;
                      },
                    ),
                  ),
                  const SizedBox(width: 8),

                  // 发送按钮
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF3B82F6),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 12),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(6)),
                    ),
                    onPressed: isLoading ? null : _sendCurrentRequest,
                    icon: isLoading
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.send, size: 16),
                    label: Text(isLoading ? '发送中...' : '发送 (Send)'),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              // 实时解析 URL 提示条
              Row(
                children: [
                  const Text('实际解析地址: ',
                      style: TextStyle(fontSize: 11, color: Colors.grey)),
                  Expanded(
                    child: Text(
                      resolvedPreviewUrl.isEmpty ? '(空)' : resolvedPreviewUrl,
                      style: const TextStyle(
                        fontSize: 11,
                        color: Color(0xFF3B82F6),
                        fontFamily: 'monospace',
                        fontWeight: FontWeight.w500,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),

        // 4.3 请求参数与前置脚本配置子标签
        Container(
          height: 36,
          decoration: BoxDecoration(
            border: Border(
              top: BorderSide(color: Colors.grey.shade300),
              bottom: BorderSide(color: Colors.grey.shade300),
            ),
          ),
          child: TabBar(
            controller: _reqTabController,
            isScrollable: true,
            labelColor: const Color(0xFF3B82F6),
            unselectedLabelColor: Colors.grey.shade600,
            labelStyle:
                const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
            tabs: [
              Tab(text: 'Params (${req.params.length})'),
              Tab(text: 'Headers (${req.headers.length})'),
              const Tab(text: 'Body'),
              const Tab(text: '⚡ Pre-request Script (前置脚本)'),
              const Tab(text: '🧪 Tests (断言测试)'),
            ],
          ),
        ),

        // 4.4 请求参数视图与响应区域 (上下分栏)
        Expanded(
          child: Column(
            children: [
              // 请求配置子面板 (Params/Headers/Body/PreScript/Tests)
              Expanded(
                flex: 4,
                child: TabBarView(
                  controller: _reqTabController,
                  children: [
                    // Params
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: SingleChildScrollView(
                        child: KeyValueEditor(
                          items: req.params,
                          onChanged: () => setState(() {}),
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
                          onChanged: () => setState(() {}),
                          keyPlaceholder: 'Header Name',
                        ),
                      ),
                    ),

                    // Body
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              DropdownButton<BodyType>(
                                value: req.bodyType,
                                items: const [
                                  DropdownMenuItem(
                                      value: BodyType.none,
                                      child: Text('none')),
                                  DropdownMenuItem(
                                      value: BodyType.json,
                                      child: Text('raw (JSON)')),
                                  DropdownMenuItem(
                                      value: BodyType.formUrlEncoded,
                                      child: Text('x-www-form-urlencoded')),
                                  DropdownMenuItem(
                                      value: BodyType.formData,
                                      child: Text('form-data')),
                                ],
                                onChanged: (val) {
                                  if (val != null) {
                                    setState(() {
                                      req.bodyType = val;
                                    });
                                  }
                                },
                              ),
                              const Spacer(),
                              if (req.bodyType == BodyType.json)
                                TextButton.icon(
                                  onPressed: _formatJsonBody,
                                  icon: const Icon(Icons.code, size: 14),
                                  label: const Text('格式化 JSON',
                                      style: TextStyle(fontSize: 12)),
                                ),
                            ],
                          ),
                          Expanded(
                            child: TextFormField(
                              controller: _bodyController,
                              maxLines: null,
                              expands: true,
                              style: const TextStyle(
                                  fontFamily: 'monospace', fontSize: 12),
                              decoration: const InputDecoration(
                                hintText: '在此输入 Request Body JSON 或内容...',
                                border: OutlineInputBorder(),
                              ),
                              onChanged: (val) {
                                req.bodyContent = val;
                              },
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
                                '沙箱 JavaScript 脚本，在请求发送前执行。支持 pm.environment / CryptoJS 签名',
                                style:
                                    TextStyle(fontSize: 11, color: Colors.grey),
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
                                },
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Expanded(
                            child: TextFormField(
                              controller: _preScriptController,
                              maxLines: null,
                              expands: true,
                              style: const TextStyle(
                                fontFamily: 'monospace',
                                fontSize: 12,
                                color: Color(0xFF0F172A),
                              ),
                              decoration: const InputDecoration(
                                hintText:
                                    '// 编写前置 JavaScript 脚本...\npm.environment.set("token", "xxx");',
                                border: OutlineInputBorder(),
                              ),
                              onChanged: (val) {
                                req.preRequestScript = val;
                              },
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
                                '后置测试与断言脚本。支持 pm.test() 与 pm.response',
                                style:
                                    TextStyle(fontSize: 11, color: Colors.grey),
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
                                },
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Expanded(
                            child: TextFormField(
                              controller: _postScriptController,
                              maxLines: null,
                              expands: true,
                              style: const TextStyle(
                                  fontFamily: 'monospace', fontSize: 12),
                              decoration: const InputDecoration(
                                hintText:
                                    '// 编写测试断言...\npm.test("Status 200", function() { ... });',
                                border: OutlineInputBorder(),
                              ),
                              onChanged: (val) {
                                req.postRequestScript = val;
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              const Divider(height: 1, thickness: 1),

              // 响应展示视图区域
              Expanded(
                flex: 5,
                child: response == null
                    ? Container(
                        alignment: Alignment.center,
                        child: Text(
                          '点击右上角【发送 (Send)】执行请求并查看响应',
                          style: TextStyle(
                              color: Colors.grey.shade400, fontSize: 13),
                        ),
                      )
                    : Column(
                        children: [
                          // 响应状态栏 (Status, Time, Size)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 8),
                            color: Colors.grey.withValues(alpha: 0.04),
                            child: Row(
                              children: [
                                StatusCodeBadge(
                                  statusCode: response.statusCode,
                                  statusMessage: response.statusMessage,
                                ),
                                const SizedBox(width: 12),
                                Text(
                                  '耗时: ${response.durationMs} ms',
                                  style: const TextStyle(
                                      fontSize: 12, color: Colors.grey),
                                ),
                                const SizedBox(width: 12),
                                Text(
                                  '大小: ${(response.sizeBytes / 1024).toStringAsFixed(2)} KB',
                                  style: const TextStyle(
                                      fontSize: 12, color: Colors.grey),
                                ),
                                const Spacer(),
                                IconButton(
                                  tooltip: '复制 Response Body',
                                  icon: const Icon(Icons.copy, size: 16),
                                  onPressed: () {
                                    Clipboard.setData(ClipboardData(
                                        text: response.body));
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(content: Text('已复制响应内容')),
                                    );
                                  },
                                ),
                              ],
                            ),
                          ),

                          // 响应视图子 Tab 标签
                          Container(
                            height: 32,
                            decoration: BoxDecoration(
                              border: Border(
                                bottom: BorderSide(color: Colors.grey.shade300),
                              ),
                            ),
                            child: TabBar(
                              controller: _resTabController,
                              isScrollable: true,
                              labelColor: const Color(0xFF3B82F6),
                              unselectedLabelColor: Colors.grey.shade600,
                              labelStyle: const TextStyle(fontSize: 11),
                              tabs: [
                                const Tab(text: 'Body (Pretty JSON)'),
                                Tab(text: 'Headers (${response.headers.length})'),
                                Tab(text: 'Tests (${response.testResults.length})'),
                                Tab(text: 'Console Logs (${response.consoleLogs.length})'),
                              ],
                            ),
                          ),

                          // 响应视图内容展示
                          Expanded(
                            child: TabBarView(
                              controller: _resTabController,
                              children: [
                                // Pretty Body
                                Container(
                                  padding: const EdgeInsets.all(12),
                                  color: Colors.grey.withValues(alpha: 0.02),
                                  child: SelectableText(
                                    response.prettyBody.isEmpty
                                        ? '(Empty Response Body)'
                                        : response.prettyBody,
                                    style: const TextStyle(
                                      fontFamily: 'monospace',
                                      fontSize: 12,
                                    ),
                                  ),
                                ),

                                // Headers
                                ListView(
                                  padding: const EdgeInsets.all(12),
                                  children: response.headers.entries.map((h) {
                                    return Padding(
                                      padding: const EdgeInsets.symmetric(
                                          vertical: 3),
                                      child: Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text('${h.key}: ',
                                              style: const TextStyle(
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 12)),
                                          Expanded(
                                            child: SelectableText(
                                              h.value,
                                              style: const TextStyle(
                                                  fontSize: 12,
                                                  fontFamily: 'monospace'),
                                            ),
                                          ),
                                        ],
                                      ),
                                    );
                                  }).toList(),
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
                                          final t = response.testResults[idx];
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
                                            padding: const EdgeInsets.symmetric(
                                                vertical: 2),
                                            child: SelectableText(
                                              response.consoleLogs[idx],
                                              style: const TextStyle(
                                                fontFamily: 'monospace',
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
          ),
        ),
      ],
    );
  }
}
