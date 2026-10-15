import 'package:uuid/uuid.dart';
import 'api_collection.dart';
import 'api_folder.dart';
import 'api_request.dart';
import 'environment.dart';
import 's3_sync_config.dart';

class AiConfig {
  String provider;
  String baseUrl;
  String apiKey;
  String model;

  AiConfig({
    this.provider = 'OpenAI 兼容',
    this.baseUrl = 'https://api.openai.com/v1',
    this.apiKey = '',
    this.model = 'gpt-4o-mini',
  });

  /// 是否已完成有效 AI 配置（未配置时主页面不展示 AI 入口）
  bool get isConfigured {
    if (provider == 'Ollama 本地') {
      return baseUrl.trim().isNotEmpty && model.trim().isNotEmpty;
    }
    return baseUrl.trim().isNotEmpty && apiKey.trim().isNotEmpty;
  }

  Map<String, dynamic> toJson() => {
        'provider': provider,
        'baseUrl': baseUrl,
        'apiKey': apiKey,
        'model': model,
      };

  factory AiConfig.fromJson(Map<String, dynamic> json) {
    return AiConfig(
      provider: json['provider'] as String? ?? 'OpenAI 兼容',
      baseUrl: json['baseUrl'] as String? ?? 'https://api.openai.com/v1',
      apiKey: json['apiKey'] as String? ?? '',
      model: json['model'] as String? ?? 'gpt-4o-mini',
    );
  }
}

class ApiHistoryItem {
  final String requestId;
  String name;
  HttpMethod method;
  String url;
  DateTime calledAt;
  int? statusCode;
  int? durationMs;
  ApiRequest? requestSnapshot;

  ApiHistoryItem({
    required this.requestId,
    required this.name,
    required this.method,
    required this.url,
    required this.calledAt,
    this.statusCode,
    this.durationMs,
    this.requestSnapshot,
  });

  Map<String, dynamic> toJson() => {
        'requestId': requestId,
        'name': name,
        'method': method.name,
        'url': url,
        'calledAt': calledAt.toIso8601String(),
        'statusCode': statusCode,
        'durationMs': durationMs,
        'requestSnapshot': requestSnapshot?.toJson(),
      };

  factory ApiHistoryItem.fromJson(Map<String, dynamic> json) {
    final methodStr = (json['method'] as String? ?? 'get').toLowerCase();
    final method = HttpMethod.values.firstWhere(
      (m) => m.name.toLowerCase() == methodStr,
      orElse: () => HttpMethod.get,
    );
    return ApiHistoryItem(
      requestId: json['requestId'] as String? ?? const Uuid().v4(),
      name: json['name'] as String? ?? '未命名接口',
      method: method,
      url: json['url'] as String? ?? '',
      calledAt: DateTime.tryParse(json['calledAt'] as String? ?? '') ??
          DateTime.now(),
      statusCode: json['statusCode'] as int?,
      durationMs: json['durationMs'] as int?,
      requestSnapshot: json['requestSnapshot'] is Map<String, dynamic>
          ? ApiRequest.fromJson(json['requestSnapshot'] as Map<String, dynamic>)
          : null,
    );
  }
}

class Workspace {
  final String id;
  String name;
  String description;
  List<ApiCollection> collections;
  List<Environment> environments;
  String? activeEnvironmentId;
  List<VariableItem> globalVariables;

  // 软件设置项
  bool doubleClickToCloseTab;
  bool showUrlPreviewBar;
  String sidebarTheme; // 'slate' | 'ice' | 'dark' | 'warm' | 'gradient'
  int historyLimit; // 历史列表最大显示条数，默认 10
  List<ApiHistoryItem> apiHistory;
  List<String> rightSidebarTools; // 右侧边栏启用的工具 ID 列表
  AiConfig aiConfig;
  S3SyncConfig s3Config;

  static const List<String> defaultRightSidebarTools = [
    'curl',
  ];

  Workspace({
    String? id,
    required this.name,
    this.description = '',
    List<ApiCollection>? collections,
    List<Environment>? environments,
    this.activeEnvironmentId,
    List<VariableItem>? globalVariables,
    this.doubleClickToCloseTab = true,
    this.showUrlPreviewBar = true,
    this.sidebarTheme = 'slate',
    this.historyLimit = 10,
    List<ApiHistoryItem>? apiHistory,
    List<String>? rightSidebarTools,
    AiConfig? aiConfig,
    S3SyncConfig? s3Config,
  })  : id = id ?? const Uuid().v4(),
        collections = collections ?? [],
        environments = environments ?? [],
        globalVariables = globalVariables ?? [],
        apiHistory = apiHistory ?? [],
        rightSidebarTools =
            rightSidebarTools ?? List<String>.from(defaultRightSidebarTools),
        aiConfig = aiConfig ?? AiConfig(),
        s3Config = s3Config ?? S3SyncConfig();

  Environment? get activeEnvironment {
    if (activeEnvironmentId == null) return null;
    return environments.cast<Environment?>().firstWhere(
          (e) => e?.id == activeEnvironmentId,
          orElse: () => null,
        );
  }

  /// 在工作区所有目录树中根据 ID 查找接口引用
  ApiRequest? findRequestById(String requestId) {
    for (final col in collections) {
      final all = col.findAllRequests();
      for (final r in all) {
        if (r.id == requestId) return r;
      }
    }
    return null;
  }

  /// 获取严格按调用时间倒序排列（最新调用排在最上方）且同一接口去重的历史记录列表
  List<ApiHistoryItem> get sortedDeduplicatedHistory {
    final sorted = List<ApiHistoryItem>.from(apiHistory)
      ..sort((a, b) => b.calledAt.compareTo(a.calledAt));
    final seenIds = <String>{};
    final result = <ApiHistoryItem>[];
    for (final item in sorted) {
      if (seenIds.add(item.requestId)) {
        result.add(item);
      }
    }
    return result.take(historyLimit).toList();
  }

  /// 记录一次接口调用：移除同一接口旧记录，按最新调用时间插入列表最上方并按调用时间倒序重排
  void recordApiCall(
    ApiRequest req, {
    int? statusCode,
    int? durationMs,
    DateTime? calledAt,
  }) {
    final timestamp = calledAt ?? DateTime.now();
    apiHistory.removeWhere((item) => item.requestId == req.id);
    final snapshot = ApiRequest.fromJson(req.toJson());
    apiHistory.insert(
      0,
      ApiHistoryItem(
        requestId: req.id,
        name: req.name.trim().isEmpty ? '未命名接口' : req.name.trim(),
        method: req.method,
        url: req.url,
        calledAt: timestamp,
        statusCode: statusCode,
        durationMs: durationMs,
        requestSnapshot: snapshot,
      ),
    );
    apiHistory.sort((a, b) => b.calledAt.compareTo(a.calledAt));
    if (apiHistory.length > 200) {
      apiHistory.removeRange(200, apiHistory.length);
    }
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'description': description,
        'collections': collections.map((c) => c.toJson()).toList(),
        'environments': environments.map((e) => e.toJson()).toList(),
        'activeEnvironmentId': activeEnvironmentId,
        'globalVariables': globalVariables.map((v) => v.toJson()).toList(),
        'doubleClickToCloseTab': doubleClickToCloseTab,
        'showUrlPreviewBar': showUrlPreviewBar,
        'sidebarTheme': sidebarTheme,
        'historyLimit': historyLimit,
        'apiHistory': apiHistory.map((h) => h.toJson()).toList(),
        'rightSidebarTools': rightSidebarTools,
        'aiConfig': aiConfig.toJson(),
        's3Config': s3Config.toJson(),
      };

  factory Workspace.fromJson(Map<String, dynamic> json) {
    final parsedLimit = json['historyLimit'] as int? ?? 10;
    final parsedHistory = (json['apiHistory'] as List<dynamic>?)
            ?.whereType<Map<String, dynamic>>()
            .map(ApiHistoryItem.fromJson)
            .toList() ??
        [];
    // 确保按调用时间倒序且同一 requestId 只保留最新一条
    parsedHistory.sort((a, b) => b.calledAt.compareTo(a.calledAt));
    final seenIds = <String>{};
    final dedupedHistory = <ApiHistoryItem>[];
    for (final item in parsedHistory) {
      if (seenIds.add(item.requestId)) {
        dedupedHistory.add(item);
      }
    }

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
      doubleClickToCloseTab: json['doubleClickToCloseTab'] as bool? ?? true,
      showUrlPreviewBar: json['showUrlPreviewBar'] as bool? ?? true,
      sidebarTheme: (json['sidebarTheme'] as String?)?.trim().isNotEmpty == true
          ? json['sidebarTheme'] as String
          : 'slate',
      historyLimit: parsedLimit.clamp(1, 200),
      apiHistory: dedupedHistory,
      rightSidebarTools: (json['rightSidebarTools'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .where((t) => t == 'curl' || t == 'ai')
              .toList() ??
          List<String>.from(defaultRightSidebarTools),
      aiConfig: json['aiConfig'] is Map<String, dynamic>
          ? AiConfig.fromJson(json['aiConfig'] as Map<String, dynamic>)
          : AiConfig(),
      s3Config: json['s3Config'] is Map<String, dynamic>
          ? S3SyncConfig.fromJson(json['s3Config'] as Map<String, dynamic>)
          : S3SyncConfig(),
    );
  }

  /// 创建内置演示工作区
  factory Workspace.createDemo() {
    final devEnv = Environment(
      id: 'env-dev',
      name: 'Dev 开发环境',
      variables: [
        VariableItem(
          key: 'baseUrl',
          value: 'https://httpbin.org',
          isEnum: true,
          enumOptions: [
            EnumOption(name: 'HttpBin 公共网关', value: 'https://httpbin.org'),
            EnumOption(name: '本地调试节点', value: 'http://127.0.0.1:8080'),
            EnumOption(name: '开发集群网关', value: 'https://dev-api.example.com'),
          ],
          showInHeader: true,
        ),
        VariableItem(key: 'apiKey', value: 'dev_secret_key_998', isSecret: true),
        VariableItem(key: 'timeout', value: '5000'),
        VariableItem(
          key: 'apiVersion',
          value: 'v1',
          isEnum: true,
          enumOptions: [
            EnumOption(name: 'V1 稳定版', value: 'v1'),
            EnumOption(name: 'V2 预览版', value: 'v2'),
            EnumOption(name: 'V1 灰度版', value: 'v1-beta'),
          ],
          showInHeader: false,
        ),
      ],
    );

    final testEnv = Environment(
      id: 'env-test',
      name: 'Test 测试环境',
      variables: [
        VariableItem(
          key: 'baseUrl',
          value: 'https://httpbin.org',
          isEnum: true,
          enumOptions: [
            EnumOption(name: 'HttpBin 公共网关', value: 'https://httpbin.org'),
            EnumOption(name: '测试集群网关', value: 'https://test-api.example.com'),
          ],
          showInHeader: true,
        ),
        VariableItem(key: 'apiKey', value: 'test_token_886', isSecret: true),
        VariableItem(key: 'timeout', value: '10000'),
        VariableItem(
          key: 'apiVersion',
          value: 'v1-beta',
          isEnum: true,
          enumOptions: [
            EnumOption(name: 'V1 灰度版', value: 'v1-beta'),
            EnumOption(name: 'V1 稳定版', value: 'v1'),
            EnumOption(name: 'V2 预览版', value: 'v2'),
          ],
          showInHeader: false,
        ),
      ],
    );

    final prodEnv = Environment(
      id: 'env-prod',
      name: 'Prod 生产环境',
      variables: [
        VariableItem(
          key: 'baseUrl',
          value: 'https://httpbin.org',
          isEnum: true,
          enumOptions: [
            EnumOption(name: 'HttpBin 公共网关', value: 'https://httpbin.org'),
            EnumOption(name: '生产主网关', value: 'https://api.example.com'),
          ],
          showInHeader: true,
        ),
        VariableItem(key: 'apiKey', value: 'prod_live_auth_777', isSecret: true),
        VariableItem(key: 'timeout', value: '3000'),
        VariableItem(key: 'apiVersion', value: 'v1'),
      ],
    );

    final reqGet = ApiRequest(
      id: 'req-get-user',
      name: '获取用户数据',
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
      name: '创建订单',
      method: HttpMethod.post,
      url: '/post',
      bodyType: BodyType.json,
      bodyContent: r'''{
  "orderId": "ORD_{{$randomInt}}",
  "amount": 199.9,
  "clientToken": "{{apiKey}}",
  "createTime": "{{$timestamp}}"
}''',
      headers: [
        KeyValueItem(key: 'Content-Type', value: 'application/json'),
        KeyValueItem(key: 'X-Client-Id', value: 'MindPost-Flutter'),
      ],
      preRequestScript: '''
// 前置脚本：打印请求前日志
console.log("准备发送创建订单请求，当前环境 baseUrl: " + pm.environment.get("baseUrl"));
''',
    );

    final reqSse = ApiRequest(
      id: 'req-stream-data',
      name: '流式响应测试',
      url: '{{baseUrl}}/stream/5',
      headers: [
        KeyValueItem(key: 'Accept', value: 'application/json'),
      ],
    );

    final reqUpload = ApiRequest(
      id: 'req-upload-data',
      name: '表单提交与文件',
      method: HttpMethod.post,
      url: '/post',
      bodyType: BodyType.formData,
      formDataFields: [
        KeyValueItem(key: 'username', value: 'developer', type: 'text'),
        KeyValueItem(key: 'clientVersion', value: '1.2.0', type: 'text'),
        KeyValueItem(
            key: 'fontAsset',
            value: 'assets/fonts/Inter-Regular.ttf',
            type: 'file'),
      ],
    );

    final subFolder = ApiFolder(
      id: 'folder-auth',
      name: '用户认证模块',
      headers: [
        KeyValueItem(key: 'X-Module', value: 'AuthService'),
      ],
      preRequestScript: '''// 目录级前置脚本：添加模块追踪 Header
pm.request.headers.add({ key: "X-Trace-Folder", value: "Auth" });''',
      requests: [reqGet],
    );

    final collection = ApiCollection(
      id: 'col-demo',
      name: 'MindPost 示范接口库',
      description: '示范接口集合，涵盖多层级目录、公共Header、表单文件与脚本继承',
      headers: [
        KeyValueItem(key: 'X-Global-App', value: 'MindPost-Desktop'),
      ],
      preRequestScript: '''// 集合根节点前置脚本
console.log("执行根集合前置公共配置");''',
      folders: [subFolder],
      requests: [reqPost, reqUpload, reqSse],
    );

    return Workspace(
      id: 'ws-default',
      name: '我的工作区',
      description: 'MindPost 本地工程工作区',
      collections: [collection],
      environments: [devEnv, testEnv, prodEnv],
      activeEnvironmentId: 'env-dev',
      globalVariables: [
        VariableItem(key: 'appName', value: 'MindPost'),
      ],
    );
  }
}
