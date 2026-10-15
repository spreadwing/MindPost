/// 枚举候选配置项
class EnumOption {
  String name;
  String value;

  EnumOption({
    required this.name,
    required this.value,
  });

  /// 下拉展示文本：优先显示名称，若名称为空则回退显示值
  String get displayLabel =>
      name.trim().isNotEmpty ? name.trim() : (value.isNotEmpty ? value : '空值');

  EnumOption copyWith({
    String? name,
    String? value,
  }) {
    return EnumOption(
      name: name ?? this.name,
      value: value ?? this.value,
    );
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        'value': value,
      };

  factory EnumOption.fromJson(dynamic json) {
    if (json is Map<String, dynamic>) {
      final val = json['value'] as String? ?? '';
      final nm = json['name'] as String? ?? '';
      return EnumOption(name: nm, value: val);
    }
    final str = json?.toString() ?? '';
    return EnumOption(name: str, value: str);
  }
}

/// 环境变量定义项
class VariableItem {
  String key;
  String value;
  bool isSecret;
  bool isEnabled;
  String description;
  bool isEnum;
  List<EnumOption> enumOptions;
  bool showInHeader;

  VariableItem({
    required this.key,
    required this.value,
    this.isSecret = false,
    this.isEnabled = true,
    this.description = '',
    this.isEnum = false,
    List<EnumOption>? enumOptions,
    this.showInHeader = false,
  }) : enumOptions = enumOptions ?? [];

  VariableItem copyWith({
    String? key,
    String? value,
    bool? isSecret,
    bool? isEnabled,
    String? description,
    bool? isEnum,
    List<EnumOption>? enumOptions,
    bool? showInHeader,
  }) {
    return VariableItem(
      key: key ?? this.key,
      value: value ?? this.value,
      isSecret: isSecret ?? this.isSecret,
      isEnabled: isEnabled ?? this.isEnabled,
      description: description ?? this.description,
      isEnum: isEnum ?? this.isEnum,
      enumOptions:
          enumOptions ?? this.enumOptions.map((o) => o.copyWith()).toList(),
      showInHeader: showInHeader ?? this.showInHeader,
    );
  }

  Map<String, dynamic> toJson() => {
        'key': key,
        'value': value,
        'isSecret': isSecret,
        'isEnabled': isEnabled,
        'description': description,
        'isEnum': isEnum,
        'enumOptions': enumOptions.map((o) => o.toJson()).toList(),
        'showInHeader': showInHeader,
      };

  factory VariableItem.fromJson(Map<String, dynamic> json) {
    final List<EnumOption> parsedOptions = [];
    if (json['enumOptions'] is List) {
      for (final item in (json['enumOptions'] as List<dynamic>)) {
        parsedOptions.add(EnumOption.fromJson(item));
      }
    } else if (json['enumValues'] is List) {
      for (final item in (json['enumValues'] as List<dynamic>)) {
        parsedOptions.add(EnumOption.fromJson(item));
      }
    }

    final val = json['value'] as String? ?? '';
    final isEnumVal = json['isEnum'] as bool? ?? false;
    if (isEnumVal &&
        val.isNotEmpty &&
        !parsedOptions.any((o) => o.value == val)) {
      parsedOptions.insert(0, EnumOption(name: val, value: val));
    }
    return VariableItem(
      key: json['key'] as String? ?? '',
      value: val,
      isSecret: json['isSecret'] as bool? ?? false,
      isEnabled: json['isEnabled'] as bool? ?? true,
      description: json['description'] as String? ?? '',
      isEnum: isEnumVal,
      enumOptions: parsedOptions,
      showInHeader: json['showInHeader'] as bool? ?? false,
    );
  }
}

/// 环境配置实体
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
    final parsedVars = (json['variables'] as List<dynamic>?)
            ?.map((v) => VariableItem.fromJson(v as Map<String, dynamic>))
            .toList() ??
        [];
    final legacyBaseUrl = (json['baseUrl'] as String? ?? '').trim();
    if (legacyBaseUrl.isNotEmpty &&
        !parsedVars.any((v) => v.key.trim() == 'baseUrl')) {
      parsedVars.insert(
        0,
        VariableItem(
          key: 'baseUrl',
          value: legacyBaseUrl,
          isEnum: true,
          enumOptions: [
            EnumOption(name: '默认网关', value: legacyBaseUrl),
          ],
          showInHeader: true,
        ),
      );
    }
    return Environment(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '未命名环境',
      baseUrl: '',
      description: json['description'] as String? ?? '',
      variables: parsedVars,
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
