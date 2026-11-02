import 'dart:async';
import 'package:flutter/material.dart';
import '../../models/workspace.dart';
import '../../models/api_collection.dart';
import '../../models/api_folder.dart';
import '../../models/api_request.dart';
import 'status_badge.dart';
import 'browser_import_dialog.dart';
import '../folder_theme_config.dart';

/// 侧边栏配色方案配置
class SidebarPalette {
  final String id;
  final String name;
  final String subtitle;
  final Color backgroundColor;
  final Gradient? backgroundGradient;
  final Color headerBackgroundColor;
  final Color borderColor;
  final Color searchBoxBackgroundColor;
  final Color searchBoxBorderColor;
  final Color searchTextColor;
  final Color searchHintColor;
  final Color titleTextColor;
  final Color folderTextColor;
  final Color requestTextColor;
  final Color mutedIconColor;
  final Color badgeBackgroundColor;
  final Color badgeTextColor;
  final Color activeItemBackgroundColor;
  final Color activeItemBorderColor;
  final Color activeItemTextColor;
  final Color activeIndicatorColor;
  final List<BoxShadow>? activeItemShadows;
  final bool isDark;

  const SidebarPalette({
    required this.id,
    required this.name,
    required this.subtitle,
    required this.backgroundColor,
    this.backgroundGradient,
    required this.headerBackgroundColor,
    required this.borderColor,
    required this.searchBoxBackgroundColor,
    required this.searchBoxBorderColor,
    required this.searchTextColor,
    required this.searchHintColor,
    required this.titleTextColor,
    required this.folderTextColor,
    required this.requestTextColor,
    required this.mutedIconColor,
    required this.badgeBackgroundColor,
    required this.badgeTextColor,
    required this.activeItemBackgroundColor,
    required this.activeItemBorderColor,
    required this.activeItemTextColor,
    required this.activeIndicatorColor,
    this.activeItemShadows,
    this.isDark = false,
  });

  static const List<SidebarPalette> allThemes = [
    SidebarPalette(
      id: 'slate',
      name: '冷灰石板',
      subtitle: '柔和冷灰底色搭配纯白悬浮选中卡片',
      backgroundColor: Color(0xFFF1F5F9),
      headerBackgroundColor: Color(0xFFF1F5F9),
      borderColor: Color(0xFFCBD5E1),
      searchBoxBackgroundColor: Colors.white,
      searchBoxBorderColor: Color(0xFFCBD5E1),
      searchTextColor: Color(0xFF0F172A),
      searchHintColor: Color(0xFF94A3B8),
      titleTextColor: Color(0xFF0F172A),
      folderTextColor: Color(0xFF1E293B),
      requestTextColor: Color(0xFF334155),
      mutedIconColor: Color(0xFF64748B),
      badgeBackgroundColor: Color(0xFFE2E8F0),
      badgeTextColor: Color(0xFF475569),
      activeItemBackgroundColor: Colors.white,
      activeItemBorderColor: Color(0xFF93C5FD),
      activeItemTextColor: Color(0xFF1D4ED8),
      activeIndicatorColor: Color(0xFF2563EB),
      activeItemShadows: [
        BoxShadow(
          color: Color(0x120F172A),
          blurRadius: 3,
          offset: Offset(0, 1),
        ),
      ],
    ),
    SidebarPalette(
      id: 'ice',
      name: '极光冰蓝',
      subtitle: '清透冰川浅蓝调，与品牌蓝主色呼应',
      backgroundColor: Color(0xFFEEF4FF),
      headerBackgroundColor: Color(0xFFEEF4FF),
      borderColor: Color(0xFFBFDBFE),
      searchBoxBackgroundColor: Colors.white,
      searchBoxBorderColor: Color(0xFFBFDBFE),
      searchTextColor: Color(0xFF0F172A),
      searchHintColor: Color(0xFF94A3B8),
      titleTextColor: Color(0xFF1E3A8A),
      folderTextColor: Color(0xFF1E3A8A),
      requestTextColor: Color(0xFF1E293B),
      mutedIconColor: Color(0xFF3B82F6),
      badgeBackgroundColor: Color(0xFFDBEAFE),
      badgeTextColor: Color(0xFF1D4ED8),
      activeItemBackgroundColor: Colors.white,
      activeItemBorderColor: Color(0xFF60A5FA),
      activeItemTextColor: Color(0xFF1D4ED8),
      activeIndicatorColor: Color(0xFF2563EB),
      activeItemShadows: [
        BoxShadow(
          color: Color(0x1A2563EB),
          blurRadius: 4,
          offset: Offset(0, 1),
        ),
      ],
    ),
    SidebarPalette(
      id: 'dark',
      name: '深邃暗夜',
      subtitle: '经典左暗右亮高反差专业工作台布局',
      backgroundColor: Color(0xFF0F172A),
      headerBackgroundColor: Color(0xFF0F172A),
      borderColor: Color(0xFF1E293B),
      searchBoxBackgroundColor: Color(0xFF1E293B),
      searchBoxBorderColor: Color(0xFF334155),
      searchTextColor: Color(0xFFF8FAFC),
      searchHintColor: Color(0xFF64748B),
      titleTextColor: Color(0xFFF8FAFC),
      folderTextColor: Color(0xFFF1F5F9),
      requestTextColor: Color(0xFFCBD5E1),
      mutedIconColor: Color(0xFF94A3B8),
      badgeBackgroundColor: Color(0xFF1E293B),
      badgeTextColor: Color(0xFF94A3B8),
      activeItemBackgroundColor: Color(0xFF1E3A8A),
      activeItemBorderColor: Color(0xFF3B82F6),
      activeItemTextColor: Colors.white,
      activeIndicatorColor: Color(0xFF60A5FA),
      isDark: true,
    ),
    SidebarPalette(
      id: 'warm',
      name: '暖砂纸感',
      subtitle: '微暖石色底板，温润护眼减轻视觉疲劳',
      backgroundColor: Color(0xFFF5F5F4),
      headerBackgroundColor: Color(0xFFF5F5F4),
      borderColor: Color(0xFFD6D3D1),
      searchBoxBackgroundColor: Colors.white,
      searchBoxBorderColor: Color(0xFFD6D3D1),
      searchTextColor: Color(0xFF1C1917),
      searchHintColor: Color(0xFF78716C),
      titleTextColor: Color(0xFF1C1917),
      folderTextColor: Color(0xFF1C1917),
      requestTextColor: Color(0xFF44403C),
      mutedIconColor: Color(0xFF78716C),
      badgeBackgroundColor: Color(0xFFE7E5E4),
      badgeTextColor: Color(0xFF57534E),
      activeItemBackgroundColor: Colors.white,
      activeItemBorderColor: Color(0xFF93C5FD),
      activeItemTextColor: Color(0xFF1D4ED8),
      activeIndicatorColor: Color(0xFF2563EB),
      activeItemShadows: [
        BoxShadow(
          color: Color(0x121C1917),
          blurRadius: 3,
          offset: Offset(0, 1),
        ),
      ],
    ),
    SidebarPalette(
      id: 'gradient',
      name: '渐变微光',
      subtitle: '顶部极光紫蓝向底部冷灰柔和过渡',
      backgroundColor: Color(0xFFEEF2FF),
      backgroundGradient: LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xFFEEF2FF), Color(0xFFF1F5F9)],
      ),
      headerBackgroundColor: Colors.transparent,
      borderColor: Color(0xFFC7D2FE),
      searchBoxBackgroundColor: Colors.white,
      searchBoxBorderColor: Color(0xFFC7D2FE),
      searchTextColor: Color(0xFF0F172A),
      searchHintColor: Color(0xFF94A3B8),
      titleTextColor: Color(0xFF1E1B4B),
      folderTextColor: Color(0xFF1E293B),
      requestTextColor: Color(0xFF334155),
      mutedIconColor: Color(0xFF6366F1),
      badgeBackgroundColor: Color(0xFFE0E7FF),
      badgeTextColor: Color(0xFF4338CA),
      activeItemBackgroundColor: Colors.white,
      activeItemBorderColor: Color(0xFF818CF8),
      activeItemTextColor: Color(0xFF1D4ED8),
      activeIndicatorColor: Color(0xFF4F46E5),
      activeItemShadows: [
        BoxShadow(
          color: Color(0x1A4F46E5),
          blurRadius: 4,
          offset: Offset(0, 1),
        ),
      ],
    ),
  ];

  static SidebarPalette fromId(String? id) {
    return allThemes.firstWhere(
      (t) => t.id == id,
      orElse: () => allThemes.first,
    );
  }
}

/// 拖拽节点载荷
class DragNodePayload {
  final String id;
  final String name;
  final String type; // 'request' 或 'folder'
  final dynamic node; // ApiRequest 或 ApiFolder
  final dynamic sourceParent; // ApiCollection 或 ApiFolder

  DragNodePayload({
    required this.id,
    required this.name,
    required this.type,
    required this.node,
    required this.sourceParent,
  });
}

class ApiTreeView extends StatefulWidget {
  final Workspace workspace;
  final String? activeRequestId;
  final String? activeContainerId;
  final void Function(ApiRequest request) onRequestSelected;
  final void Function(dynamic container, bool isCollection)? onContainerSelected;
  final VoidCallback onWorkspaceChanged;
  final VoidCallback? onAddNewCollection;
  final FolderThemeConfig? folderThemeConfig;
  final Set<String>? initialExpandedIds;
  final void Function(Set<String> expandedIds)? onExpandedChanged;

  const ApiTreeView({
    super.key,
    required this.workspace,
    required this.activeRequestId,
    this.activeContainerId,
    required this.onRequestSelected,
    this.onContainerSelected,
    required this.onWorkspaceChanged,
    this.onAddNewCollection,
    this.folderThemeConfig,
    this.initialExpandedIds,
    this.onExpandedChanged,
  });

  @override
  State<ApiTreeView> createState() => ApiTreeViewState();
}

class ApiTreeViewState extends State<ApiTreeView> {
  // 解析当前有效的文件夹主题配置
  FolderThemeConfig get _folderTheme {
    if (widget.folderThemeConfig != null) return widget.folderThemeConfig!;
    final ext = Theme.of(context).extension<FolderThemeConfig>();
    if (ext != null) return ext;
    return FolderThemeConfig(
      colorPreset: FolderColorPreset.fromId(widget.workspace.folderColorTheme),
      iconStyle: FolderIconStyle.fromId(widget.workspace.folderIconStyle),
    );
  }

  // 记录所有展开的容器 ID
  final Set<String> _expandedIds = {};

  // 搜索关键字与控制器
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  // 记录当前拖拽悬停的目标容器 ID
  String? _hoverTargetId;

  // 记录最近一次点击目录的 ID、时间及单击防抖定时器（快速双击时不触发单击）
  String? _lastTappedContainerId;
  DateTime? _lastContainerTapTime;
  Timer? _singleTapTimer;

  @override
  void initState() {
    super.initState();
    if (widget.initialExpandedIds != null) {
      _expandedIds.addAll(widget.initialExpandedIds!);
    } else {
      _expandAll();
    }
  }

  @override
  void didUpdateWidget(covariant ApiTreeView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialExpandedIds != null &&
        oldWidget.initialExpandedIds != widget.initialExpandedIds) {
      _expandedIds.clear();
      _expandedIds.addAll(widget.initialExpandedIds!);
      setState(() {});
    }
  }

  void _notifyExpandedChanged() {
    widget.onExpandedChanged?.call(Set<String>.from(_expandedIds));
  }

  @override
  void dispose() {
    _singleTapTimer?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _expandAll() {
    for (final col in widget.workspace.collections) {
      _expandedIds.add(col.id);
      _expandFolderRecursive(col.folders);
    }
    _notifyExpandedChanged();
  }

  void _expandFolderRecursive(List<ApiFolder> folders) {
    for (final f in folders) {
      _expandedIds.add(f.id);
      _expandFolderRecursive(f.folders);
    }
  }

  void _toggleExpand(String id) {
    setState(() {
      if (_expandedIds.contains(id)) {
        _expandedIds.remove(id);
      } else {
        _expandedIds.add(id);
      }
    });
    _notifyExpandedChanged();
  }

  /// 处理目录节点点击：单击显示目录设置参数页，快速双击仅展开/折叠目录而不触发单击
  void _handleContainerTap(dynamic container, bool isCollection) {
    final id = (container as dynamic).id as String;
    final now = DateTime.now();
    if (_lastTappedContainerId == id &&
        _lastContainerTapTime != null &&
        now.difference(_lastContainerTapTime!) <
            const Duration(milliseconds: 280)) {
      // 快速双击：立即取消挂起的单击回调，仅触发目录展开/折叠
      _singleTapTimer?.cancel();
      _singleTapTimer = null;
      _lastTappedContainerId = null;
      _lastContainerTapTime = null;
      _toggleExpand(id);
      return;
    }

    _singleTapTimer?.cancel();
    _lastTappedContainerId = id;
    _lastContainerTapTime = now;
    _singleTapTimer = Timer(const Duration(milliseconds: 220), () {
      if (!mounted) return;
      _lastTappedContainerId = null;
      _lastContainerTapTime = null;
      widget.onContainerSelected?.call(container, isCollection);
    });
  }

  /// 定位当前激活的节点并在树中展开其所有父容器
  void locateActiveNode() {
    final activeId = widget.activeRequestId ?? widget.activeContainerId;
    if (activeId == null) return;

    bool found = false;
    for (final col in widget.workspace.collections) {
      // 检查是否就是顶层集合自身
      if (col.id == activeId) {
        _expandedIds.add(col.id);
        found = true;
        break;
      }
      // 查找是否为请求
      final chain = col.findParentChainForRequest(activeId);
      if (chain.length > 1 || (chain.isNotEmpty && col.requests.any((r) => r.id == activeId))) {
        for (final container in chain) {
          _expandedIds.add((container as dynamic).id as String);
        }
        found = true;
        break;
      }
      // 查找是否为嵌套目录
      if (_locateFolderChain(col, col.folders, activeId, [col.id])) {
        found = true;
        break;
      }
    }

    if (found) {
      _notifyExpandedChanged();
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('已在目录树中展开并定位到当前节点'),
          duration: Duration(milliseconds: 1500),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  bool _locateFolderChain(dynamic parent, List<ApiFolder> folders, String targetId, List<String> currentChain) {
    for (final f in folders) {
      final newChain = [...currentChain, f.id];
      if (f.id == targetId) {
        _expandedIds.addAll(newChain);
        return true;
      }
      if (_locateFolderChain(f, f.folders, targetId, newChain)) {
        return true;
      }
    }
    return false;
  }

  // 弹窗提示输入名称
  Future<void> _showRenameDialog({
    required String title,
    required String initialValue,
    required void Function(String newName) onConfirmed,
  }) async {
    final controller = TextEditingController(text: initialValue);
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title, style: const TextStyle(fontSize: 16)),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            isDense: true,
          ),
          onSubmitted: (val) {
            if (val.trim().isNotEmpty) {
              onConfirmed(val.trim());
              Navigator.of(ctx).pop();
            }
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () {
              if (controller.text.trim().isNotEmpty) {
                onConfirmed(controller.text.trim());
                Navigator.of(ctx).pop();
              }
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  // 弹窗确认删除
  Future<void> _showConfirmDeleteDialog({
    required String itemName,
    required VoidCallback onConfirmed,
  }) async {
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('确认删除', style: TextStyle(fontSize: 16)),
        content: Text('确定要删除【$itemName】吗？此操作将同时删除其下所有子节点且不可撤销。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('取消'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            onPressed: () {
              onConfirmed();
              Navigator.of(ctx).pop();
            },
            child: const Text('删除'),
          ),
        ],
      ),
    );
  }

  // 顶层目录右键/更多菜单
  Future<void> _showCollectionMenu(
      Offset position, ApiCollection col) async {
    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox?;
    if (overlay == null) return;

    final val = await showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        position & const Size(40, 40),
        Offset.zero & overlay.size,
      ),
      items: const [
        PopupMenuItem(
          value: 'add_req',
          child: Row(
            children: [
              Icon(Icons.add_link, size: 18, color: Color(0xFF3B82F6)),
              SizedBox(width: 8),
              Text('在此目录下新建 API', style: TextStyle(fontSize: 13)),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'import_browser',
          child: Row(
            children: [
              Icon(Icons.input_rounded, size: 18, color: Color(0xFF10B981)),
              SizedBox(width: 8),
              Text('从浏览器请求导入', style: TextStyle(fontSize: 13)),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'add_folder',
          child: Row(
            children: [
              Icon(Icons.create_new_folder_outlined,
                  size: 18, color: Color(0xFFF59E0B)),
              SizedBox(width: 8),
              Text('新建目录', style: TextStyle(fontSize: 13)),
            ],
          ),
        ),
        PopupMenuDivider(),
        PopupMenuItem(
          value: 'settings',
          child: Row(
            children: [
              Icon(Icons.settings_outlined, size: 18),
              SizedBox(width: 8),
              Text('目录公共配置与脚本', style: TextStyle(fontSize: 13)),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'rename',
          child: Row(
            children: [
              Icon(Icons.edit_outlined, size: 18),
              SizedBox(width: 8),
              Text('重命名目录', style: TextStyle(fontSize: 13)),
            ],
          ),
        ),
        PopupMenuDivider(),
        PopupMenuItem(
          value: 'delete',
          child: Row(
            children: [
              Icon(Icons.delete_outline, size: 18, color: Colors.red),
              SizedBox(width: 8),
              Text('删除目录', style: TextStyle(fontSize: 13, color: Colors.red)),
            ],
          ),
        ),
      ],
    );

    if (!mounted || val == null) return;
    if (val == 'add_req') {
      final newReq = ApiRequest(
        name: '新请求',
        collectionId: col.id,
        url: '{{baseUrl}}/get',
        method: HttpMethod.get,
      );
      col.requests.add(newReq);
      _expandedIds.add(col.id);
      _notifyExpandedChanged();
      widget.onWorkspaceChanged();
      widget.onRequestSelected(newReq);
    } else if (val == 'import_browser') {
      final importedReq = await showDialog<ApiRequest>(
        context: context,
        builder: (_) => BrowserImportDialog(
          folderName: col.name,
          collectionId: col.id,
        ),
      );
      if (importedReq != null && mounted) {
        col.requests.add(importedReq);
        _expandedIds.add(col.id);
        _notifyExpandedChanged();
        widget.onWorkspaceChanged();
        widget.onRequestSelected(importedReq);
      }
    } else if (val == 'add_folder') {
      _showRenameDialog(
        title: '在【${col.name}】下新建目录',
        initialValue: '新目录',
        onConfirmed: (name) {
          col.folders.add(ApiFolder(name: name));
          _expandedIds.add(col.id);
          _notifyExpandedChanged();
          widget.onWorkspaceChanged();
        },
      );
    } else if (val == 'settings') {
      widget.onContainerSelected?.call(col, true);
    } else if (val == 'rename') {
      _showRenameDialog(
        title: '重命名目录',
        initialValue: col.name,
        onConfirmed: (newName) {
          col.name = newName;
          widget.onWorkspaceChanged();
        },
      );
    } else if (val == 'delete') {
      _showConfirmDeleteDialog(
        itemName: col.name,
        onConfirmed: () {
          widget.workspace.collections.removeWhere((c) => c.id == col.id);
          widget.onWorkspaceChanged();
        },
      );
    }
  }

  // 目录右键/更多菜单
  Future<void> _showFolderMenu(
      Offset position, ApiFolder folder, dynamic parent) async {
    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox?;
    if (overlay == null) return;

    final val = await showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        position & const Size(40, 40),
        Offset.zero & overlay.size,
      ),
      items: const [
        PopupMenuItem(
          value: 'add_req',
          child: Row(
            children: [
              Icon(Icons.add_link, size: 18, color: Color(0xFF3B82F6)),
              SizedBox(width: 8),
              Text('在此目录下新建 API', style: TextStyle(fontSize: 13)),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'import_browser',
          child: Row(
            children: [
              Icon(Icons.input_rounded, size: 18, color: Color(0xFF10B981)),
              SizedBox(width: 8),
              Text('从浏览器请求导入', style: TextStyle(fontSize: 13)),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'add_subfolder',
          child: Row(
            children: [
              Icon(Icons.create_new_folder_outlined,
                  size: 18, color: Color(0xFFF59E0B)),
              SizedBox(width: 8),
              Text('新建目录', style: TextStyle(fontSize: 13)),
            ],
          ),
        ),
        PopupMenuDivider(),
        PopupMenuItem(
          value: 'settings',
          child: Row(
            children: [
              Icon(Icons.settings_outlined, size: 18),
              SizedBox(width: 8),
              Text('目录公共配置与脚本', style: TextStyle(fontSize: 13)),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'rename',
          child: Row(
            children: [
              Icon(Icons.edit_outlined, size: 18),
              SizedBox(width: 8),
              Text('重命名目录', style: TextStyle(fontSize: 13)),
            ],
          ),
        ),
        PopupMenuDivider(),
        PopupMenuItem(
          value: 'delete',
          child: Row(
            children: [
              Icon(Icons.delete_outline, size: 18, color: Colors.red),
              SizedBox(width: 8),
              Text('删除目录', style: TextStyle(fontSize: 13, color: Colors.red)),
            ],
          ),
        ),
      ],
    );

    if (!mounted || val == null) return;
    if (val == 'add_req') {
      final newReq = ApiRequest(
        name: '新请求',
        url: '{{baseUrl}}/get',
        method: HttpMethod.get,
      );
      folder.requests.add(newReq);
      _expandedIds.add(folder.id);
      _notifyExpandedChanged();
      widget.onWorkspaceChanged();
      widget.onRequestSelected(newReq);
    } else if (val == 'import_browser') {
      final importedReq = await showDialog<ApiRequest>(
        context: context,
        builder: (_) => BrowserImportDialog(
          folderName: folder.name,
        ),
      );
      if (importedReq != null && mounted) {
        folder.requests.add(importedReq);
        _expandedIds.add(folder.id);
        _notifyExpandedChanged();
        widget.onWorkspaceChanged();
        widget.onRequestSelected(importedReq);
      }
    } else if (val == 'add_subfolder') {
      _showRenameDialog(
        title: '在【${folder.name}】下新建目录',
        initialValue: '新目录',
        onConfirmed: (name) {
          folder.folders.add(ApiFolder(name: name));
          _expandedIds.add(folder.id);
          _notifyExpandedChanged();
          widget.onWorkspaceChanged();
        },
      );
    } else if (val == 'settings') {
      widget.onContainerSelected?.call(folder, false);
    } else if (val == 'rename') {
      _showRenameDialog(
        title: '重命名目录',
        initialValue: folder.name,
        onConfirmed: (newName) {
          folder.name = newName;
          widget.onWorkspaceChanged();
        },
      );
    } else if (val == 'delete') {
      _showConfirmDeleteDialog(
        itemName: folder.name,
        onConfirmed: () {
          if (parent is ApiCollection) {
            parent.folders.removeWhere((f) => f.id == folder.id);
          } else if (parent is ApiFolder) {
            parent.folders.removeWhere((f) => f.id == folder.id);
          }
          widget.onWorkspaceChanged();
        },
      );
    }
  }

  // 请求 API 右键/更多菜单
  Future<void> _showRequestMenu(
      Offset position, ApiRequest req, dynamic parent) async {
    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox?;
    if (overlay == null) return;

    final val = await showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        position & const Size(40, 40),
        Offset.zero & overlay.size,
      ),
      items: const [
        PopupMenuItem(
          value: 'open',
          child: Row(
            children: [
              Icon(Icons.open_in_new, size: 18, color: Color(0xFF3B82F6)),
              SizedBox(width: 8),
              Text('打开调试标签', style: TextStyle(fontSize: 13)),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'clone',
          child: Row(
            children: [
              Icon(Icons.copy, size: 18),
              SizedBox(width: 8),
              Text('复制副本', style: TextStyle(fontSize: 13)),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'rename',
          child: Row(
            children: [
              Icon(Icons.edit_outlined, size: 18),
              SizedBox(width: 8),
              Text('重命名 API', style: TextStyle(fontSize: 13)),
            ],
          ),
        ),
        PopupMenuDivider(),
        PopupMenuItem(
          value: 'delete',
          child: Row(
            children: [
              Icon(Icons.delete_outline, size: 18, color: Colors.red),
              SizedBox(width: 8),
              Text('删除 API', style: TextStyle(fontSize: 13, color: Colors.red)),
            ],
          ),
        ),
      ],
    );

    if (!mounted || val == null) return;
    if (val == 'open') {
      widget.onRequestSelected(req);
    } else if (val == 'clone') {
      final cloned = req.copyWith(
        id: null,
        name: '${req.name} - 副本',
      );
      if (parent is ApiCollection) {
        parent.requests.add(cloned);
      } else if (parent is ApiFolder) {
        parent.requests.add(cloned);
      }
      widget.onWorkspaceChanged();
      widget.onRequestSelected(cloned);
    } else if (val == 'rename') {
      _showRenameDialog(
        title: '重命名 API 请求',
        initialValue: req.name,
        onConfirmed: (newName) {
          req.name = newName;
          widget.onWorkspaceChanged();
        },
      );
    } else if (val == 'delete') {
      _showConfirmDeleteDialog(
        itemName: req.name,
        onConfirmed: () {
          if (parent is ApiCollection) {
            parent.requests.removeWhere((r) => r.id == req.id);
          } else if (parent is ApiFolder) {
            parent.requests.removeWhere((r) => r.id == req.id);
          }
          widget.onWorkspaceChanged();
        },
      );
    }
  }

  /// 节点拖拽移动放置逻辑处理
  void _handleNodeDrop(DragNodePayload payload, dynamic targetContainer) {
    // 1. 不能移动到自己的直属父容器或自身
    if (payload.sourceParent == targetContainer) return;
    final targetId = (targetContainer as dynamic).id as String;
    if (payload.id == targetId) return;

    // 2. 如果拖拽的是目录，不能移动到自身或自身的下级目录中 (防循环嵌套)
    if (payload.type == 'folder') {
      final subFolders = (payload.node as dynamic).folders as List<ApiFolder>;
      if (subFolders.any((f) => _isFolderDescendant(f, targetId))) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('不能将目录移动到自身或其下级目录中'),
            behavior: SnackBarBehavior.floating,
          ),
        );
        return;
      }
    }

    // 3. 从原父级容器中移除
    if (payload.sourceParent == null && payload.node is ApiCollection) {
      widget.workspace.collections.removeWhere((c) => c.id == payload.id);
    } else if (payload.sourceParent is ApiCollection) {
      if (payload.type == 'request') {
        payload.sourceParent.requests.removeWhere((r) => r.id == payload.id);
      } else {
        payload.sourceParent.folders.removeWhere((f) => f.id == payload.id);
      }
    } else if (payload.sourceParent is ApiFolder) {
      if (payload.type == 'request') {
        payload.sourceParent.requests.removeWhere((r) => r.id == payload.id);
      } else {
        payload.sourceParent.folders.removeWhere((f) => f.id == payload.id);
      }
    }

    // 4. 添加到新目标容器中（自动转换目录类型，无需区分根与子目录）
    ApiFolder toApiFolder(dynamic node) {
      if (node is ApiFolder) return node;
      final col = node as ApiCollection;
      return ApiFolder(
        id: col.id,
        name: col.name,
        description: col.description,
        headers: col.headers,
        variables: col.variables,
        preRequestScript: col.preRequestScript,
        postRequestScript: col.postRequestScript,
        folders: col.folders,
        requests: col.requests,
      );
    }

    if (targetContainer is ApiCollection) {
      if (payload.type == 'request') {
        targetContainer.requests.add(payload.node as ApiRequest);
      } else {
        targetContainer.folders.add(toApiFolder(payload.node));
      }
      _expandedIds.add(targetContainer.id);
    } else if (targetContainer is ApiFolder) {
      if (payload.type == 'request') {
        targetContainer.requests.add(payload.node as ApiRequest);
      } else {
        targetContainer.folders.add(toApiFolder(payload.node));
      }
      _expandedIds.add(targetContainer.id);
    }

    _notifyExpandedChanged();
    widget.onWorkspaceChanged();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
            '已将【${payload.name}】移动至【${(targetContainer as dynamic).name}】'),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  bool _isFolderDescendant(ApiFolder parent, String targetId) {
    if (parent.id == targetId) return true;
    for (final child in parent.folders) {
      if (_isFolderDescendant(child, targetId)) return true;
    }
    return false;
  }

  // 递归渲染文件夹节点 (包含拖拽起点与放置目标支持)
  Widget _buildFolderNode(
      ApiFolder folder, dynamic parent, int depth, SidebarPalette palette) {
    final isExpanded = _expandedIds.contains(folder.id);
    final totalChildCount = folder.requests.length + folder.folders.length;
    final isHovered = _hoverTargetId == folder.id;
    final isSelected = widget.activeContainerId == folder.id;

    // 搜索过滤匹配检查
    if (_searchQuery.isNotEmpty && !_isFolderMatches(folder, _searchQuery)) {
      return const SizedBox.shrink();
    }

    final folderContent = GestureDetector(
      onSecondaryTapDown: (details) {
        _showFolderMenu(details.globalPosition, folder, parent);
      },
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 0.5, horizontal: 4),
        decoration: BoxDecoration(
          color: isSelected || isHovered
              ? palette.activeItemBackgroundColor
              : Colors.transparent,
          border: isHovered
              ? Border.all(color: palette.activeIndicatorColor, width: 1)
              : (isSelected
                  ? Border.all(
                      color: palette.activeItemBorderColor, width: 0.9)
                  : null),
          boxShadow: isSelected ? palette.activeItemShadows : null,
          borderRadius: BorderRadius.circular(5),
        ),
        child: InkWell(
          onTap: () => _handleContainerTap(folder, false),
          borderRadius: BorderRadius.circular(5),
          child: Padding(
            padding: EdgeInsets.only(
                left: 6.0 + depth * 13.0, right: 6, top: 5.0, bottom: 5.0),
            child: Row(
              children: [
                if (isSelected)
                  Container(
                    width: 3,
                    height: 12,
                    margin: const EdgeInsets.only(right: 4),
                    decoration: BoxDecoration(
                      color: palette.activeIndicatorColor,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                InkWell(
                  borderRadius: BorderRadius.circular(4),
                  onTap: () => _toggleExpand(folder.id),
                  child: Icon(
                    isExpanded
                        ? Icons.keyboard_arrow_down_rounded
                        : Icons.keyboard_arrow_right_rounded,
                    size: 16,
                    color: palette.mutedIconColor,
                  ),
                ),
                const SizedBox(width: 3),
                FolderThemeIcon(
                  isExpanded: isExpanded,
                  size: 15,
                  config: _folderTheme,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    folder.name,
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: isSelected
                          ? palette.activeItemTextColor
                          : palette.folderTextColor,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '$totalChildCount',
                    style: const TextStyle(
                      fontSize: 10,
                      color: Color(0xFF64748B),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                InkWell(
                  borderRadius: BorderRadius.circular(4),
                  onTapDown: (details) {
                    _showFolderMenu(details.globalPosition, folder, parent);
                  },
                  child: Padding(
                    padding: const EdgeInsets.all(2.0),
                    child: Icon(Icons.more_horiz_rounded,
                        size: 15, color: palette.mutedIconColor),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    // 包装为可拖拽源与放置目标
    return DragTarget<DragNodePayload>(
      onWillAcceptWithDetails: (details) {
        setState(() => _hoverTargetId = folder.id);
        return details.data.id != folder.id;
      },
      onLeave: (_) {
        if (_hoverTargetId == folder.id) {
          setState(() => _hoverTargetId = null);
        }
      },
      onAcceptWithDetails: (details) {
        setState(() => _hoverTargetId = null);
        _handleNodeDrop(details.data, folder);
      },
      builder: (context, candidateData, rejectedData) {
        return Draggable<DragNodePayload>(
          data: DragNodePayload(
            id: folder.id,
            name: folder.name,
            type: 'folder',
            node: folder,
            sourceParent: parent,
          ),
          feedback: Material(
            elevation: 4,
            borderRadius: BorderRadius.circular(6),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                    color: _folderTheme.colorPreset.resolveColor(context)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  FolderThemeIcon(
                    isExpanded: isExpanded,
                    size: 16,
                    config: _folderTheme,
                  ),
                  const SizedBox(width: 6),
                  Text(folder.name,
                      style: const TextStyle(
                          fontSize: 12, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
          ),
          childWhenDragging: Opacity(opacity: 0.4, child: folderContent),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              folderContent,
              if (isExpanded) ...[
                for (final subFolder in folder.folders)
                  _buildFolderNode(subFolder, folder, depth + 1, palette),
                for (final req in folder.requests)
                  _buildRequestItem(req, folder, depth + 1, palette),
              ],
            ],
          ),
        );
      },
    );
  }

  // 渲染单个 API 请求叶子节点 (支持拖拽)
  Widget _buildRequestItem(
      ApiRequest req, dynamic parent, int depth, SidebarPalette palette) {
    final isSelected = widget.activeRequestId == req.id;

    // 搜索过滤检查
    if (_searchQuery.isNotEmpty && !_isRequestMatches(req, _searchQuery)) {
      return const SizedBox.shrink();
    }

    final requestContent = GestureDetector(
      onSecondaryTapDown: (details) {
        _showRequestMenu(details.globalPosition, req, parent);
      },
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 0.5, horizontal: 4),
        decoration: BoxDecoration(
          color: isSelected
              ? palette.activeItemBackgroundColor
              : Colors.transparent,
          borderRadius: BorderRadius.circular(5),
          border: isSelected
              ? Border.all(color: palette.activeItemBorderColor, width: 0.9)
              : null,
          boxShadow: isSelected ? palette.activeItemShadows : null,
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(5),
          onTap: () => widget.onRequestSelected(req),
          child: Padding(
            padding: EdgeInsets.only(
                left: 6.0 + depth * 13.0, right: 6, top: 5.0, bottom: 5.0),
            child: Row(
              children: [
                if (isSelected)
                  Container(
                    width: 3,
                    height: 12,
                    margin: const EdgeInsets.only(right: 5),
                    decoration: BoxDecoration(
                      color: palette.activeIndicatorColor,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                HttpMethodBadge(method: req.method, fontSize: 8.5),
                const SizedBox(width: 5),
                Expanded(
                  child: Text(
                    req.name,
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight:
                          isSelected ? FontWeight.w600 : FontWeight.normal,
                      color: isSelected
                          ? palette.activeItemTextColor
                          : palette.requestTextColor,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                InkWell(
                  borderRadius: BorderRadius.circular(4),
                  onTapDown: (details) {
                    _showRequestMenu(details.globalPosition, req, parent);
                  },
                  child: Padding(
                    padding: const EdgeInsets.all(2.0),
                    child: Icon(Icons.more_horiz_rounded,
                        size: 14, color: palette.mutedIconColor),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    return Draggable<DragNodePayload>(
      data: DragNodePayload(
        id: req.id,
        name: req.name,
        type: 'request',
        node: req,
        sourceParent: parent,
      ),
      feedback: Material(
        elevation: 4,
        borderRadius: BorderRadius.circular(6),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: const Color(0xFF3B82F6)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              HttpMethodBadge(method: req.method, fontSize: 9),
              const SizedBox(width: 6),
              Text(req.name,
                  style: const TextStyle(
                      fontSize: 12, fontWeight: FontWeight.bold)),
            ],
          ),
        ),
      ),
      childWhenDragging: Opacity(opacity: 0.3, child: requestContent),
      child: requestContent,
    );
  }

  bool _isRequestMatches(ApiRequest req, String query) {
    final q = query.toLowerCase();
    return req.name.toLowerCase().contains(q) ||
        req.url.toLowerCase().contains(q) ||
        req.method.nameString.toLowerCase().contains(q);
  }

  bool _isFolderMatches(ApiFolder folder, String query) {
    if (folder.name.toLowerCase().contains(query.toLowerCase())) return true;
    for (final r in folder.requests) {
      if (_isRequestMatches(r, query)) return true;
    }
    for (final sub in folder.folders) {
      if (_isFolderMatches(sub, query)) return true;
    }
    return false;
  }

  bool _isCollectionMatches(ApiCollection col, String query) {
    if (col.name.toLowerCase().contains(query.toLowerCase())) return true;
    for (final r in col.requests) {
      if (_isRequestMatches(r, query)) return true;
    }
    for (final f in col.folders) {
      if (_isFolderMatches(f, query)) return true;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final palette = SidebarPalette.fromId(widget.workspace.sidebarTheme);
    final totalRequests = widget.workspace.collections.fold<int>(
      0,
      (sum, col) => sum + col.findAllRequests().length,
    );

    return Container(
      decoration: BoxDecoration(
        color: palette.backgroundGradient == null
            ? palette.backgroundColor
            : null,
        gradient: palette.backgroundGradient,
      ),
      child: Column(
        children: [
          // 顶部操作工具栏与搜索框
          Container(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
            decoration: BoxDecoration(
              color: palette.headerBackgroundColor,
              border: Border(
                bottom: BorderSide(color: palette.borderColor),
              ),
            ),
            child: Column(
              children: [
                // 侧边栏标题与快捷工具栏
                Row(
                  children: [
                    Icon(Icons.layers_rounded,
                        size: 15, color: palette.activeIndicatorColor),
                    const SizedBox(width: 5),
                    Text(
                      '接口资源',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: palette.titleTextColor,
                      ),
                    ),
                    const SizedBox(width: 5),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 5, vertical: 1),
                      decoration: BoxDecoration(
                        color: palette.badgeBackgroundColor,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '$totalRequests',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: palette.badgeTextColor,
                        ),
                      ),
                    ),
                    const Spacer(),
                    if (widget.onAddNewCollection != null) ...[
                      Tooltip(
                        message: '新建目录',
                        child: InkWell(
                          borderRadius: BorderRadius.circular(4),
                          onTap: widget.onAddNewCollection,
                          child: Padding(
                            padding: const EdgeInsets.all(3.0),
                            child: Icon(Icons.create_new_folder_outlined,
                                size: 15,
                                color: palette.activeIndicatorColor),
                          ),
                        ),
                      ),
                      const SizedBox(width: 2),
                    ],
                    // 定位当前节点按钮
                    Tooltip(
                      message: '定位当前激活的节点',
                      child: InkWell(
                        borderRadius: BorderRadius.circular(4),
                        onTap: locateActiveNode,
                        child: Padding(
                          padding: const EdgeInsets.all(3.0),
                          child: Icon(Icons.my_location_rounded,
                              size: 14, color: palette.mutedIconColor),
                        ),
                      ),
                    ),
                    const SizedBox(width: 2),
                    // 全部展开
                    Tooltip(
                      message: '全部展开',
                      child: InkWell(
                        borderRadius: BorderRadius.circular(4),
                        onTap: () => setState(() => _expandAll()),
                        child: Padding(
                          padding: const EdgeInsets.all(3.0),
                          child: Icon(Icons.unfold_more_rounded,
                              size: 15, color: palette.mutedIconColor),
                        ),
                      ),
                    ),
                    const SizedBox(width: 2),
                    // 全部折叠
                    Tooltip(
                      message: '全部折叠',
                      child: InkWell(
                        borderRadius: BorderRadius.circular(4),
                        onTap: () {
                          setState(() => _expandedIds.clear());
                          _notifyExpandedChanged();
                        },
                        child: Padding(
                          padding: const EdgeInsets.all(3.0),
                          child: Icon(Icons.unfold_less_rounded,
                              size: 15, color: palette.mutedIconColor),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),

                // 搜索栏 (弱化边框，减轻视觉比重，更聚焦列表)
                Container(
                  height: 30,
                  decoration: BoxDecoration(
                    color: palette.searchBoxBackgroundColor.withValues(alpha: 0.85),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: palette.searchBoxBorderColor.withValues(alpha: 0.45),
                      width: 0.8,
                    ),
                  ),
                  child: TextField(
                    controller: _searchController,
                    style:
                        TextStyle(fontSize: 11.5, color: palette.searchTextColor),
                    decoration: InputDecoration(
                      filled: false,
                      hintText: '搜索目录 / 接口名称 / URL...',
                      hintStyle: TextStyle(
                          fontSize: 11,
                          color: palette.searchHintColor.withValues(alpha: 0.85)),
                      prefixIcon: Icon(Icons.search_rounded,
                          size: 15,
                          color: palette.searchHintColor.withValues(alpha: 0.8)),
                      suffixIcon: _searchQuery.isNotEmpty
                          ? InkWell(
                              onTap: () {
                                _searchController.clear();
                                setState(() => _searchQuery = '');
                              },
                              child: Icon(Icons.close_rounded,
                                  size: 13,
                                  color: palette.searchHintColor.withValues(alpha: 0.8)),
                            )
                          : null,
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(vertical: 7),
                    ),
                    onChanged: (val) {
                      setState(() {
                        _searchQuery = val.trim();
                        if (_searchQuery.isNotEmpty) {
                          _expandAll();
                        }
                      });
                    },
                  ),
                ),
              ],
            ),
          ),

          // 树形列表内容
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 3),
              itemCount: widget.workspace.collections.length,
              itemBuilder: (context, colIndex) {
                final col = widget.workspace.collections[colIndex];
                final isExpanded = _expandedIds.contains(col.id);
                final isHovered = _hoverTargetId == col.id;
                final isSelected = widget.activeContainerId == col.id;
                final totalChildCount =
                    col.requests.length + col.folders.length;

                if (_searchQuery.isNotEmpty &&
                    !_isCollectionMatches(col, _searchQuery)) {
                  return const SizedBox.shrink();
                }

                final colContent = GestureDetector(
                  onSecondaryTapDown: (details) {
                    _showCollectionMenu(details.globalPosition, col);
                  },
                  child: Container(
                    margin: const EdgeInsets.symmetric(
                        vertical: 0.5, horizontal: 4),
                    decoration: BoxDecoration(
                      color: isSelected || isHovered
                          ? palette.activeItemBackgroundColor
                          : Colors.transparent,
                      border: isHovered
                          ? Border.all(
                              color: palette.activeIndicatorColor, width: 1)
                          : (isSelected
                              ? Border.all(
                                  color: palette.activeItemBorderColor,
                                  width: 0.9)
                              : null),
                      boxShadow:
                          isSelected ? palette.activeItemShadows : null,
                      borderRadius: BorderRadius.circular(5),
                    ),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(5),
                      onTap: () => _handleContainerTap(col, true),
                      child: Padding(
                        padding: const EdgeInsets.only(
                            left: 6, right: 6, top: 5.5, bottom: 5.5),
                        child: Row(
                          children: [
                            if (isSelected)
                              Container(
                                width: 3,
                                height: 12,
                                margin: const EdgeInsets.only(right: 4),
                                decoration: BoxDecoration(
                                  color: palette.activeIndicatorColor,
                                  borderRadius: BorderRadius.circular(2),
                                ),
                              ),
                            InkWell(
                              borderRadius: BorderRadius.circular(4),
                              onTap: () => _toggleExpand(col.id),
                              child: Icon(
                                isExpanded
                                    ? Icons.keyboard_arrow_down_rounded
                                    : Icons.keyboard_arrow_right_rounded,
                                size: 16,
                                color: palette.mutedIconColor,
                              ),
                            ),
                            const SizedBox(width: 2),
                            // 加深顶层 Collection 图标对比度与辨识度
                            Icon(
                              isExpanded
                                  ? Icons.source_rounded
                                  : Icons.inventory_2_rounded,
                              size: 15,
                              color: palette.isDark
                                  ? const Color(0xFFFBBF24)
                                  : const Color(0xFFD97706),
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                col.name,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: isSelected
                                      ? palette.activeItemTextColor
                                      : palette.folderTextColor,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 5, vertical: 1.5),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF1F5F9),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                '$totalChildCount',
                                style: const TextStyle(
                                  fontSize: 10,
                                  color: Color(0xFF64748B),
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            const SizedBox(width: 4),
                            InkWell(
                              borderRadius: BorderRadius.circular(4),
                              onTapDown: (details) {
                                _showCollectionMenu(
                                    details.globalPosition, col);
                              },
                              child: Padding(
                                padding: const EdgeInsets.all(2.0),
                                child: Icon(Icons.more_horiz_rounded,
                                    size: 15, color: palette.mutedIconColor),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );

                // 目录作为拖拽起点与放置目标
                return DragTarget<DragNodePayload>(
                  onWillAcceptWithDetails: (details) {
                    setState(() => _hoverTargetId = col.id);
                    return details.data.id != col.id;
                  },
                  onLeave: (_) {
                    if (_hoverTargetId == col.id) {
                      setState(() => _hoverTargetId = null);
                    }
                  },
                  onAcceptWithDetails: (details) {
                    setState(() => _hoverTargetId = null);
                    _handleNodeDrop(details.data, col);
                  },
                  builder: (context, candidateData, rejectedData) {
                    return Draggable<DragNodePayload>(
                      data: DragNodePayload(
                        id: col.id,
                        name: col.name,
                        type: 'folder',
                        node: col,
                        sourceParent: null,
                      ),
                      feedback: Material(
                        elevation: 4,
                        borderRadius: BorderRadius.circular(6),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: const Color(0xFFD97706)),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.inventory_2_rounded,
                                  size: 16, color: Color(0xFFD97706)),
                              const SizedBox(width: 6),
                              Text(col.name,
                                  style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold)),
                            ],
                          ),
                        ),
                      ),
                      childWhenDragging:
                          Opacity(opacity: 0.4, child: colContent),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          colContent,
                          if (isExpanded) ...[
                            for (final folder in col.folders)
                              _buildFolderNode(folder, col, 1, palette),
                            for (final req in col.requests)
                              _buildRequestItem(req, col, 1, palette),
                          ],
                        ],
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
