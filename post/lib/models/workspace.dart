import 'package:uuid/uuid.dart';
import 'api_collection.dart';
import 'api_request.dart';
import 'environment.dart';

class Workspace {
  final String id;
  String name;
  String description;
  List<ApiCollection> collections;
  List<Environment> environments;
  String? activeEnvironmentId;
  List<VariableItem> globalVariables;

  Workspace({
    String? id,
    required this.name,
    this.description = '',
    List<ApiCollection>? collections,
    List<Environment>? environments,
    this.activeEnvironmentId,
    List<VariableItem>? globalVariables,
  })  : id = id ?? const Uuid().v4(),
        collections = collections ?? [],
        environments = environments ?? [],
        globalVariables = globalVariables ?? [];

  Environment? get activeEnvironment {
    if (activeEnvironmentId == null) return null;
    return environments.cast<Environment?>().firstWhere(
          (e) => e?.id == activeEnvironmentId,
          orElse: () => null,
        );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'description': description,
        'collections': collections.map((c) => c.toJson()).toList(),
        'environments': environments.map((e) => e.toJson()).toList(),
        'activeEnvironmentId': activeEnvironmentId,
        'globalVariables': globalVariables.map((v) => v.toJson()).toList(),
      };

  factory Workspace.fromJson(Map<String, dynamic> json) {
    return Workspace(
      id: json['id'] as String? ?? const Uuid().v4(),
      name: json['name'] as String? ?? '默认工作区',
      description: json['description'] as String? ?? '',
      collections: (json['collections'] as List<dynamic>?)
              ?.map((c) => ApiCollection.fromJson(c as Map<String, dynamic>))
              .toList() ??
          [],
      environments: (json['environments'] as List<dynamic>?)
              ?.map((e) => Environment.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      activeEnvironmentId: json['activeEnvironmentId'] as String?,
      globalVariables: (json['globalVariables'] as List<dynamic>?)
              ?.map((v) => VariableItem.fromJson(v as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }

  /// 创建内置演示工作区
  factory Workspace.createDemo() {
    final devEnv = Environment(
      id: 'env-dev',
      name: 'Dev 开发环境',
      baseUrl: 'https://httpbin.org',
      variables: [
        VariableItem(key: 'apiKey', value: 'dev_secret_key_998', isSecret: true),
        VariableItem(key: 'timeout', value: '5000'),
        VariableItem(key: 'apiVersion', value: 'v1'),
      ],
    );

    final testEnv = Environment(
      id: 'env-test',
      name: 'Test 测试环境',
      baseUrl: 'https://httpbin.org',
      variables: [
        VariableItem(key: 'apiKey', value: 'test_token_886', isSecret: true),
        VariableItem(key: 'timeout', value: '10000'),
        VariableItem(key: 'apiVersion', value: 'v1-beta'),
      ],
    );

    final prodEnv = Environment(
      id: 'env-prod',
      name: 'Prod 生产环境',
      baseUrl: 'https://httpbin.org',
      variables: [
        VariableItem(key: 'apiKey', value: 'prod_live_auth_777', isSecret: true),
        VariableItem(key: 'timeout', value: '3000'),
        VariableItem(key: 'apiVersion', value: 'v1'),
      ],
    );

    final reqGet = ApiRequest(
      id: 'req-get-user',
      name: '获取用户数据 (GET /get)',
      url: r'{{baseUrl}}/get?userId=1001&timestamp={{$timestamp}}',
      headers: [
        KeyValueItem(key: 'Authorization', value: 'Bearer {{apiKey}}'),
        KeyValueItem(key: 'Accept', value: 'application/json'),
      ],
      preRequestScript: '''
// 示例：前置脚本动态计算签名并增加 Headers
const timestamp = Date.now();
const sign = CryptoJS.MD5(timestamp + "salt").toString();
pm.request.headers.add({ key: "X-Sign", value: sign });
pm.environment.set("lastRequestTime", timestamp);
console.log("Pre-request script executed! Generated sign: " + sign);
''',
    );

    final reqPost = ApiRequest(
      id: 'req-post-data',
      name: '创建订单 (POST /post)',
      method: HttpMethod.post,
      url: '/post', // 测试隐式 Base URL 自动拼接
      bodyType: BodyType.json,
      bodyContent: r'''{
  "orderId": "ORD_{{$randomInt}}",
  "amount": 199.9,
  "clientToken": "{{apiKey}}",
  "createTime": "{{$timestamp}}"
}''',
      headers: [
        KeyValueItem(key: 'Content-Type', value: 'application/json'),
        KeyValueItem(key: 'X-Client-Id', value: 'PostMCP-Flutter'),
      ],
      preRequestScript: '''
// 前置脚本：打印请求前日志
console.log("准备发送创建订单请求，当前环境 baseUrl: " + pm.environment.get("baseUrl"));
''',
    );

    final reqSse = ApiRequest(
      id: 'req-stream-data',
      name: '流式响应测试 (GET /stream/5)',
      url: '{{baseUrl}}/stream/5',
      headers: [
        KeyValueItem(key: 'Accept', value: 'application/json'),
      ],
    );

    final collection = ApiCollection(
      id: 'col-demo',
      name: 'PostMCP 示范接口库',
      description: '示范接口集合，涵盖 GET、POST、前置脚本与环境变量联动',
      requests: [reqGet, reqPost, reqSse],
    );

    return Workspace(
      id: 'ws-default',
      name: '我的工作区',
      description: 'PostMCP 本地工程工作区',
      collections: [collection],
      environments: [devEnv, testEnv, prodEnv],
      activeEnvironmentId: 'env-dev',
      globalVariables: [
        VariableItem(key: 'appName', value: 'PostMCP'),
        VariableItem(key: 'platform', value: 'Desktop'),
      ],
    );
  }
}
