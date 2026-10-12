import 'package:uuid/uuid.dart';

enum HttpMethod { get, post, put, delete, patch, head, options }

extension HttpMethodExt on HttpMethod {
  String get nameString => name.toUpperCase();

  static HttpMethod fromString(String val) {
    switch (val.toUpperCase()) {
      case 'GET':
        return HttpMethod.get;
      case 'POST':
        return HttpMethod.post;
      case 'PUT':
        return HttpMethod.put;
      case 'DELETE':
        return HttpMethod.delete;
      case 'PATCH':
        return HttpMethod.patch;
      case 'HEAD':
        return HttpMethod.head;
      case 'OPTIONS':
        return HttpMethod.options;
      default:
        return HttpMethod.get;
    }
  }
}

enum BodyType { none, json, formUrlEncoded, formData, raw }

class KeyValueItem {
  String key;
  String value;
  bool isEnabled;
  String description;

  KeyValueItem({
    required this.key,
    required this.value,
    this.isEnabled = true,
    this.description = '',
  });

  KeyValueItem copyWith({
    String? key,
    String? value,
    bool? isEnabled,
    String? description,
  }) {
    return KeyValueItem(
      key: key ?? this.key,
      value: value ?? this.value,
      isEnabled: isEnabled ?? this.isEnabled,
      description: description ?? this.description,
    );
  }

  Map<String, dynamic> toJson() => {
        'key': key,
        'value': value,
        'isEnabled': isEnabled,
        'description': description,
      };

  factory KeyValueItem.fromJson(Map<String, dynamic> json) {
    return KeyValueItem(
      key: json['key'] as String? ?? '',
      value: json['value'] as String? ?? '',
      isEnabled: json['isEnabled'] as bool? ?? true,
      description: json['description'] as String? ?? '',
    );
  }
}

class ApiRequest {
  final String id;
  String name;
  String collectionId;
  HttpMethod method;
  String url;
  List<KeyValueItem> headers;
  List<KeyValueItem> params;
  BodyType bodyType;
  String bodyContent;
  List<KeyValueItem> formDataFields;
  String preRequestScript;
  String postRequestScript;
  String description;

  ApiRequest({
    String? id,
    this.name = '未命名请求',
    this.collectionId = '',
    this.method = HttpMethod.get,
    this.url = '',
    List<KeyValueItem>? headers,
    List<KeyValueItem>? params,
    this.bodyType = BodyType.none,
    this.bodyContent = '',
    List<KeyValueItem>? formDataFields,
    this.preRequestScript = '',
    this.postRequestScript = '',
    this.description = '',
  })  : id = id ?? const Uuid().v4(),
        headers = headers ?? [],
        params = params ?? [],
        formDataFields = formDataFields ?? [];

  ApiRequest copyWith({
    String? id,
    String? name,
    String? collectionId,
    HttpMethod? method,
    String? url,
    List<KeyValueItem>? headers,
    List<KeyValueItem>? params,
    BodyType? bodyType,
    String? bodyContent,
    List<KeyValueItem>? formDataFields,
    String? preRequestScript,
    String? postRequestScript,
    String? description,
  }) {
    return ApiRequest(
      id: id ?? this.id,
      name: name ?? this.name,
      collectionId: collectionId ?? this.collectionId,
      method: method ?? this.method,
      url: url ?? this.url,
      headers: headers ?? this.headers.map((e) => e.copyWith()).toList(),
      params: params ?? this.params.map((e) => e.copyWith()).toList(),
      bodyType: bodyType ?? this.bodyType,
      bodyContent: bodyContent ?? this.bodyContent,
      formDataFields: formDataFields ??
          this.formDataFields.map((e) => e.copyWith()).toList(),
      preRequestScript: preRequestScript ?? this.preRequestScript,
      postRequestScript: postRequestScript ?? this.postRequestScript,
      description: description ?? this.description,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'collectionId': collectionId,
        'method': method.nameString,
        'url': url,
        'headers': headers.map((h) => h.toJson()).toList(),
        'params': params.map((p) => p.toJson()).toList(),
        'bodyType': bodyType.name,
        'bodyContent': bodyContent,
        'formDataFields': formDataFields.map((f) => f.toJson()).toList(),
        'preRequestScript': preRequestScript,
        'postRequestScript': postRequestScript,
        'description': description,
      };

  factory ApiRequest.fromJson(Map<String, dynamic> json) {
    return ApiRequest(
      id: json['id'] as String? ?? const Uuid().v4(),
      name: json['name'] as String? ?? '未命名请求',
      collectionId: json['collectionId'] as String? ?? '',
      method: HttpMethodExt.fromString(json['method'] as String? ?? 'GET'),
      url: json['url'] as String? ?? '',
      headers: (json['headers'] as List<dynamic>?)
              ?.map((e) => KeyValueItem.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      params: (json['params'] as List<dynamic>?)
              ?.map((e) => KeyValueItem.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      bodyType: BodyType.values.firstWhere(
        (e) => e.name == (json['bodyType'] as String? ?? 'none'),
        orElse: () => BodyType.none,
      ),
      bodyContent: json['bodyContent'] as String? ?? '',
      formDataFields: (json['formDataFields'] as List<dynamic>?)
              ?.map((e) => KeyValueItem.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      preRequestScript: json['preRequestScript'] as String? ?? '',
      postRequestScript: json['postRequestScript'] as String? ?? '',
      description: json['description'] as String? ?? '',
    );
  }
}
