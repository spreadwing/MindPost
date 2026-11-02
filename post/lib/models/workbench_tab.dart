import 'api_request.dart';
import 'api_container.dart';

enum TabType { request, container }

/// 工作区顶部 Tab 标签数据模型
class WorkbenchTab {
  final String id;
  String title;
  final TabType type;
  final ApiRequest? request;
  final ApiContainer? container;
  final bool isCollection;
  bool isDirty;

  WorkbenchTab.request(this.request, {this.isDirty = false})
      : id = request!.id,
        title = request.name,
        type = TabType.request,
        container = null,
        isCollection = false;

  WorkbenchTab.container(
    this.container, {
    required this.isCollection,
    this.isDirty = false,
  })  : id = container!.id,
        title = container.name,
        type = TabType.container,
        request = null;
}

/// 单个持久化保存的 Tab 标签状态
class WorkbenchTabState {
  final String id;
  final String type; // 'request' | 'container'
  final bool isCollection;

  WorkbenchTabState({
    required this.id,
    required this.type,
    this.isCollection = false,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type,
        'isCollection': isCollection,
      };

  factory WorkbenchTabState.fromJson(Map<String, dynamic> json) {
    return WorkbenchTabState(
      id: json['id'] as String? ?? '',
      type: json['type'] as String? ?? 'request',
      isCollection: json['isCollection'] as bool? ?? false,
    );
  }
}

/// 工作台持久化会话状态（打开的标签页、激活索引、边侧节点展开集合）
class WorkbenchState {
  final List<WorkbenchTabState> openTabs;
  final int activeTabIndex;
  final List<String> expandedNodeIds;

  WorkbenchState({
    required this.openTabs,
    required this.activeTabIndex,
    required this.expandedNodeIds,
  });

  Map<String, dynamic> toJson() => {
        'openTabs': openTabs.map((t) => t.toJson()).toList(),
        'activeTabIndex': activeTabIndex,
        'expandedNodeIds': expandedNodeIds,
      };

  factory WorkbenchState.fromJson(Map<String, dynamic> json) {
    final tabsList = (json['openTabs'] as List<dynamic>?)
            ?.whereType<Map<String, dynamic>>()
            .map(WorkbenchTabState.fromJson)
            .toList() ??
        [];
    final activeIndex = json['activeTabIndex'] as int? ?? 0;
    final expanded = (json['expandedNodeIds'] as List<dynamic>?)
            ?.map((e) => e.toString())
            .toList() ??
        [];
    return WorkbenchState(
      openTabs: tabsList,
      activeTabIndex: activeIndex,
      expandedNodeIds: expanded,
    );
  }
}
