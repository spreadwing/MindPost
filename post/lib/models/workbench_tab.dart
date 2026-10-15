import 'api_request.dart';

enum TabType { request, container }

/// 工作区顶部 Tab 标签数据模型
class WorkbenchTab {
  final String id;
  String title;
  final TabType type;
  final ApiRequest? request;
  final dynamic container; // ApiCollection 或 ApiFolder
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
  })  : id = (container as dynamic).id as String,
        title = (container as dynamic).name as String,
        type = TabType.container,
        request = null;
}
