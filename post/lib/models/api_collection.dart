import 'package:uuid/uuid.dart';
import 'api_request.dart';
import 'environment.dart';

class ApiCollection {
  final String id;
  String name;
  String description;
  List<ApiRequest> requests;
  List<VariableItem> variables;
  String preRequestScript;

  ApiCollection({
    String? id,
    required this.name,
    this.description = '',
    List<ApiRequest>? requests,
    List<VariableItem>? variables,
    this.preRequestScript = '',
  })  : id = id ?? const Uuid().v4(),
        requests = requests ?? [],
        variables = variables ?? [];

  ApiCollection copyWith({
    String? id,
    String? name,
    String? description,
    List<ApiRequest>? requests,
    List<VariableItem>? variables,
    String? preRequestScript,
  }) {
    return ApiCollection(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      requests: requests ?? this.requests.map((r) => r.copyWith()).toList(),
      variables: variables ?? this.variables.map((v) => v.copyWith()).toList(),
      preRequestScript: preRequestScript ?? this.preRequestScript,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'description': description,
        'requests': requests.map((r) => r.toJson()).toList(),
        'variables': variables.map((v) => v.toJson()).toList(),
        'preRequestScript': preRequestScript,
      };

  factory ApiCollection.fromJson(Map<String, dynamic> json) {
    return ApiCollection(
      id: json['id'] as String? ?? const Uuid().v4(),
      name: json['name'] as String? ?? '未命名集合',
      description: json['description'] as String? ?? '',
      requests: (json['requests'] as List<dynamic>?)
              ?.map((r) => ApiRequest.fromJson(r as Map<String, dynamic>))
              .toList() ??
          [],
      variables: (json['variables'] as List<dynamic>?)
              ?.map((v) => VariableItem.fromJson(v as Map<String, dynamic>))
              .toList() ??
          [],
      preRequestScript: json['preRequestScript'] as String? ?? '',
    );
  }
}
