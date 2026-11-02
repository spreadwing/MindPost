import 'package:uuid/uuid.dart';
import 'api_request.dart';
import 'api_folder.dart';
import 'environment.dart';

class ApiCollection {
  final String id;
  String name;
  String description;
  List<KeyValueItem> headers;
  List<VariableItem> variables;
  String preRequestScript;
  String postRequestScript;
  List<ApiFolder> folders;
  List<ApiRequest> requests;

  ApiCollection({
    String? id,
    required this.name,
    this.description = '',
    List<KeyValueItem>? headers,
    List<VariableItem>? variables,
    this.preRequestScript = '',
    this.postRequestScript = '',
    List<ApiFolder>? folders,
    List<ApiRequest>? requests,
  })  : id = id ?? const Uuid().v4(),
        headers = headers ?? [],
        variables = variables ?? [],
        folders = folders ?? [],
        requests = requests ?? [];

  ApiCollection copyWith({
    String? id,
    String? name,
    String? description,
    List<KeyValueItem>? headers,
    List<VariableItem>? variables,
    String? preRequestScript,
    String? postRequestScript,
    List<ApiFolder>? folders,
    List<ApiRequest>? requests,
  }) {
    return ApiCollection(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      headers: headers ?? this.headers.map((h) => h.copyWith()).toList(),
      variables: variables ?? this.variables.map((v) => v.copyWith()).toList(),
      preRequestScript: preRequestScript ?? this.preRequestScript,
      postRequestScript: postRequestScript ?? this.postRequestScript,
      folders: folders ?? this.folders.map((f) => f.copyWith()).toList(),
      requests: requests ?? this.requests.map((r) => r.copyWith()).toList(),
    );
  }

  /// 递归查找目标请求
  ApiRequest? findRequestById(String targetId) {
    for (final req in requests) {
      if (req.id == targetId) return req;
    }
    for (final folder in folders) {
      final found = folder.findRequestById(targetId);
      if (found != null) return found;
    }
    return null;
  }

  /// 递归查找子目录
  ApiFolder? findFolderById(String targetId) {
    for (final folder in folders) {
      final found = folder.findFolderById(targetId);
      if (found != null) return found;
    }
    return null;
  }

  /// 收集该集合下全部请求
  List<ApiRequest> findAllRequests() {
    final list = <ApiRequest>[...requests];
    for (final f in folders) {
      list.addAll(f.findAllRequests());
    }
    return list;
  }

  /// 查找请求所属容器链 (包含当前集合和各级父文件夹)
  List<dynamic> findParentChainForRequest(String targetId) {
    final chain = <dynamic>[this];
    for (final req in requests) {
      if (req.id == targetId) return chain;
    }
    for (final folder in folders) {
      if (folder.findParentChain(targetId, chain)) {
        return chain;
      }
    }
    return chain;
  }

  /// 递归删除请求或文件夹
  bool deleteById(String targetId) {
    final reqIndex = requests.indexWhere((r) => r.id == targetId);
    if (reqIndex >= 0) {
      requests.removeAt(reqIndex);
      return true;
    }
    final folderIndex = folders.indexWhere((f) => f.id == targetId);
    if (folderIndex >= 0) {
      folders.removeAt(folderIndex);
      return true;
    }
    for (final folder in folders) {
      if (folder.deleteById(targetId)) return true;
    }
    return false;
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'description': description,
        'headers': headers.map((h) => h.toJson()).toList(),
        'variables': variables.map((v) => v.toJson()).toList(),
        'preRequestScript': preRequestScript,
        'postRequestScript': postRequestScript,
        'folders': folders.map((f) => f.toJson()).toList(),
        'requests': requests.map((r) => r.toJson()).toList(),
      };

  factory ApiCollection.fromJson(Map<String, dynamic> json) {
    return ApiCollection(
      id: json['id'] as String? ?? const Uuid().v4(),
      name: json['name'] as String? ?? '未命名集合',
      description: json['description'] as String? ?? '',
      headers: (json['headers'] as List<dynamic>?)
              ?.map((h) => KeyValueItem.fromJson(h as Map<String, dynamic>))
              .toList() ??
          [],
      variables: (json['variables'] as List<dynamic>?)
              ?.map((v) => VariableItem.fromJson(v as Map<String, dynamic>))
              .toList() ??
          [],
      preRequestScript: json['preRequestScript'] as String? ?? '',
      postRequestScript: json['postRequestScript'] as String? ?? '',
      folders: (json['folders'] as List<dynamic>?)
              ?.map((f) => ApiFolder.fromJson(f as Map<String, dynamic>))
              .toList() ??
          [],
      requests: (json['requests'] as List<dynamic>?)
              ?.map((r) => ApiRequest.fromJson(r as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }
}
