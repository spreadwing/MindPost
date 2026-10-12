/// 环境变量定义项
class VariableItem {
  String key;
  String value;
  bool isSecret;
  bool isEnabled;
  String description;

  VariableItem({
    required this.key,
    required this.value,
    this.isSecret = false,
    this.isEnabled = true,
    this.description = '',
  });

  VariableItem copyWith({
    String? key,
    String? value,
    bool? isSecret,
    bool? isEnabled,
    String? description,
  }) {
    return VariableItem(
      key: key ?? this.key,
      value: value ?? this.value,
      isSecret: isSecret ?? this.isSecret,
      isEnabled: isEnabled ?? this.isEnabled,
      description: description ?? this.description,
    );
  }

  Map<String, dynamic> toJson() => {
        'key': key,
        'value': value,
        'isSecret': isSecret,
        'isEnabled': isEnabled,
        'description': description,
      };

  factory VariableItem.fromJson(Map<String, dynamic> json) {
    return VariableItem(
      key: json['key'] as String? ?? '',
      value: json['value'] as String? ?? '',
      isSecret: json['isSecret'] as bool? ?? false,
      isEnabled: json['isEnabled'] as bool? ?? true,
      description: json['description'] as String? ?? '',
    );
  }
}

/// 环境配置实体（如 Dev, Test, Prod）
class Environment {
  final String id;
  String name;
  String baseUrl;
  List<VariableItem> variables;
  String description;

  Environment({
    required this.id,
    required this.name,
    this.baseUrl = '',
    List<VariableItem>? variables,
    this.description = '',
  }) : variables = variables ?? [];

  Environment copyWith({
    String? id,
    String? name,
    String? baseUrl,
    List<VariableItem>? variables,
    String? description,
  }) {
    return Environment(
      id: id ?? this.id,
      name: name ?? this.name,
      baseUrl: baseUrl ?? this.baseUrl,
      variables: variables ?? this.variables.map((e) => e.copyWith()).toList(),
      description: description ?? this.description,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'baseUrl': baseUrl,
        'description': description,
        'variables': variables.map((v) => v.toJson()).toList(),
      };

  factory Environment.fromJson(Map<String, dynamic> json) {
    return Environment(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '未命名环境',
      baseUrl: json['baseUrl'] as String? ?? '',
      description: json['description'] as String? ?? '',
      variables: (json['variables'] as List<dynamic>?)
              ?.map((v) => VariableItem.fromJson(v as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }

  /// 转换为键值对 Map（仅包含启用的变量）
  Map<String, String> toMap() {
    final map = <String, String>{};
    if (baseUrl.isNotEmpty) {
      map['baseUrl'] = baseUrl;
    }
    for (final v in variables) {
      if (v.isEnabled && v.key.isNotEmpty) {
        map[v.key] = v.value;
      }
    }
    return map;
  }
}
