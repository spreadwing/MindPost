import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';
import 'package:uuid/uuid.dart';
import '../models/workspace.dart';
import '../models/api_collection.dart';
import '../models/api_container.dart';
import '../models/api_folder.dart';
import '../models/api_request.dart';
import '../models/environment.dart';
import '../engine/variable_resolver.dart';
import 'http_client_service.dart';

class McpLogEntry {
  final DateTime time;
  final String toolName;
  final Map<String, dynamic> params;
  final String status;
  final String resultSummary;

  McpLogEntry({
    required this.time,
    required this.toolName,
    required this.params,
    required this.status,
    required this.resultSummary,
  });
}

class _RequestLocation {
  final ApiCollection collection;
  final ApiFolder? folder;
  final String folderPath;
  final List<ApiRequest> parentRequestList;
  final ApiRequest request;

  _RequestLocation({
    required this.collection,
    required this.folder,
    required this.folderPath,
    required this.parentRequestList,
    required this.request,
  });
}

class _ContainerLocation {
  final ApiCollection collection;
  final ApiContainer container;
  final bool isCollection;
  final String folderPath;
  final ApiContainer? parentContainer;

  _ContainerLocation({
    required this.collection,
    required this.container,
    required this.isCollection,
    required this.folderPath,
    this.parentContainer,
  });
}

class McpServerService {
  HttpServer? _server;
  final HttpClientService httpClientService;
  Workspace workspace;
  final void Function(Workspace updatedWorkspace)? onWorkspaceUpdated;
  final void Function(McpLogEntry log)? onMcpLog;

  final List<McpLogEntry> logs = [];
  final Map<String, StreamController<String>> _sseSessions = {};
  bool isRunning = false;
  int port = 8765;

  McpServerService({
    required this.httpClientService,
    required this.workspace,
    this.onWorkspaceUpdated,
    this.onMcpLog,
  });

  void updateWorkspace(Workspace newWorkspace) {
    workspace = newWorkspace;
  }

  /// 获取当前暴露的 MCP 工具定义列表
  List<Map<String, dynamic>> get toolDefinitions => _getMcpToolsDefinitions();

  /// 启动内置本地 MCP Server (HTTP & SSE)
  Future<bool> startServer({int targetPort = 8765}) async {
    if (isRunning) return true;
    port = targetPort;

    try {
      final router = Router();

      // 1. GET / 或 /status: 健康探针
      router.get('/', (Request request) {
        return Response.ok(
          json.encode({
            'status': 'running',
            'server': 'MindPost Model Context Protocol Server',
            'version': '1.1.0',
            'toolsCount': _getMcpToolsDefinitions().length,
            'activeEnvironment': workspace.activeEnvironment?.name ?? 'None',
          }),
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      });

      // 2. GET /sse: 标准 MCP SSE 长连接端点
      router.get('/sse', (Request request) {
        final sessionId = const Uuid().v4();
        late final StreamController<String> controller;
        controller = StreamController<String>.broadcast(
          onCancel: () {
            _sseSessions.remove(sessionId);
            controller.close();
          },
        );
        _sseSessions[sessionId] = controller;

        // 发送标准 MCP 握手事件
        Timer.run(() {
          if (!controller.isClosed) {
            controller.add('event: endpoint\ndata: /messages?sessionId=$sessionId\n\n');
          }
        });

        return Response.ok(
          controller.stream.transform(utf8.encoder),
          headers: {
            'content-type': 'text/event-stream; charset=utf-8',
            'cache-control': 'no-cache',
            'connection': 'keep-alive',
            'access-control-allow-origin': '*',
          },
        );
      });

      // 3. POST /sse: 支持直连 JSON-RPC / Streamable 端点
      router.post('/sse', (Request request) async {
        final bodyStr = await request.readAsString();
        final jsonBody = json.decode(bodyStr);
        final responsePayload = await _handleJsonRpc(jsonBody);

        return Response.ok(
          json.encode(responsePayload),
          headers: {
            'content-type': 'application/json; charset=utf-8',
            'access-control-allow-origin': '*',
          },
        );
      });

      // 4. POST /messages: 处理 MCP SSE 客户端请求
      router.post('/messages', (Request request) async {
        final bodyStr = await request.readAsString();
        final jsonBody = json.decode(bodyStr);
        final responsePayload = await _handleJsonRpc(jsonBody);

        final sessionId = request.url.queryParameters['sessionId'];
        if (sessionId != null && _sseSessions.containsKey(sessionId)) {
          // ignore: close_sinks
          final sseController = _sseSessions[sessionId];
          if (sseController != null && !sseController.isClosed) {
            sseController.add('event: message\ndata: ${json.encode(responsePayload)}\n\n');
          }
        }

        return Response.ok(
          json.encode(responsePayload),
          headers: {
            'content-type': 'application/json; charset=utf-8',
            'access-control-allow-origin': '*',
          },
        );
      });

      // 5. POST /mcp: 直连 JSON-RPC 端点（用于 Agent 或工具快速调用）
      router.post('/mcp', (Request request) async {
        final bodyStr = await request.readAsString();
        final jsonBody = json.decode(bodyStr);
        final responsePayload = await _handleJsonRpc(jsonBody);

        return Response.ok(
          json.encode(responsePayload),
          headers: {
            'content-type': 'application/json; charset=utf-8',
            'access-control-allow-origin': '*',
          },
        );
      });

      final handler = const Pipeline()
          .addMiddleware(logRequests())
          .addHandler(router.call);

      _server = await shelf_io.serve(handler, InternetAddress.loopbackIPv4, port);
      isRunning = true;
      return true;
    } catch (e) {
      isRunning = false;
      return false;
    }
  }

  /// 停止本地 MCP Server
  Future<void> stopServer() async {
    for (final controller in _sseSessions.values) {
      await controller.close();
    }
    _sseSessions.clear();
    await _server?.close(force: true);
    _server = null;
    isRunning = false;
  }

  /// 处理 JSON-RPC 2.0 MCP 协议请求
  Future<Map<String, dynamic>> _handleJsonRpc(dynamic body) async {
    if (body is! Map<String, dynamic>) {
      return {
        'jsonrpc': '2.0',
        'error': {'code': -32600, 'message': 'Invalid Request'},
        'id': null,
      };
    }

    final id = body['id'];
    final method = body['method'] as String? ?? '';
    final params = body['params'] as Map<String, dynamic>? ?? {};

    switch (method) {
      case 'initialize':
        return {
          'jsonrpc': '2.0',
          'id': id,
          'result': {
            'protocolVersion': '2024-11-05',
            'capabilities': {
              'tools': {'listChanged': true},
              'resources': <String, dynamic>{},
            },
            'serverInfo': {
              'name': 'mindpost-workbench',
              'version': '1.1.0',
            },
          },
        };

      case 'notifications/initialized':
        return {'jsonrpc': '2.0', 'id': id, 'result': <String, dynamic>{}};

      case 'tools/list':
        return {
          'jsonrpc': '2.0',
          'id': id,
          'result': {
            'tools': _getMcpToolsDefinitions(),
          },
        };

      case 'tools/call':
        final toolName = params['name'] as String? ?? '';
        final arguments = params['arguments'] as Map<String, dynamic>? ?? {};
        final toolResult = await executeToolDirectly(toolName, arguments);

        return {
          'jsonrpc': '2.0',
          'id': id,
          'result': {
            'content': [
              {
                'type': 'text',
                'text': json.encode(toolResult),
              }
            ],
            'isError': toolResult['success'] == false,
          },
        };

      default:
        return {
          'jsonrpc': '2.0',
          'id': id,
          'error': {
            'code': -32601,
            'message': 'Method not found: $method',
          },
        };
    }
  }

  /// 暴露的标准 MCP Tools 定义列表（8 大核心工具）
  List<Map<String, dynamic>> _getMcpToolsDefinitions() {
    return [
      {
        'name': 'list_collections_and_apis',
        'description':
            '获取 MindPost 桌面客户端中所有接口集合、递归多级文件夹树及 API 请求列表（含请求 ID、名称、方法、URL 模板及所属目录路径）。支持按集合、目录路径、关键字和请求方法过滤。',
        'inputSchema': {
          'type': 'object',
          'properties': {
            'collection_id': {
              'type': 'string',
              'description': '可选：指定特定集合 ID 过滤，不传则返回全部集合',
            },
            'folder_path': {
              'type': 'string',
              'description': '可选：按文件夹路径前缀过滤（如 "用户认证模块" 或 "dqs/simReport"）',
            },
            'keyword': {
              'type': 'string',
              'description': '可选：按接口名称或 URL 关键字模糊搜索（不区分大小写）',
            },
            'method': {
              'type': 'string',
              'description': '可选：按 HTTP 方法过滤（如 GET、POST、PUT、DELETE）',
            },
          },
        },
      },
      {
        'name': 'get_api_detail',
        'description':
            '根据请求 ID 获取接口完整定义（包含 Headers、Params、Body、FormData、前置脚本和后置断言），同时返回所属目录路径及从父级集合/目录级联继承的公共配置。',
        'inputSchema': {
          'type': 'object',
          'properties': {
            'request_id': {
              'type': 'string',
              'description': '请求的唯一标识符 ID',
            },
          },
          'required': ['request_id'],
        },
      },
      {
        'name': 'execute_api_request',
        'description':
            '调度客户端引擎执行 API 请求。支持按已有 request_id 执行，也支持临时覆盖 Method、URL、Headers、Params、BodyType、Body、FormData、前后置脚本及临时指定执行环境（不改变 UI 当前激活环境，且脚本修改的变量回写至目标环境）。',
        'inputSchema': {
          'type': 'object',
          'properties': {
            'request_id': {
              'type': 'string',
              'description': '已有请求的 ID（可选）',
            },
            'method': {
              'type': 'string',
              'enum': ['GET', 'POST', 'PUT', 'DELETE', 'PATCH', 'HEAD', 'OPTIONS'],
              'description': 'HTTP 方法（不传则使用已存请求的 Method）',
            },
            'url': {
              'type': 'string',
              'description': '请求 URL，支持相对路径如 /users 或包含 {{baseUrl}}/users',
            },
            'headers': {
              'type': 'object',
              'description': '额外的自定义 Headers 键值对',
            },
            'params': {
              'type': 'object',
              'description': '额外的 Query 参数键值对',
            },
            'body_type': {
              'type': 'string',
              'enum': ['none', 'json', 'formUrlEncoded', 'formData', 'raw'],
              'description': '请求体类型（可选）',
            },
            'raw_format': {
              'type': 'string',
              'enum': ['json', 'text', 'xml', 'html', 'javascript'],
              'description': '当 body_type 为 raw 或 json 时的语法格式',
            },
            'body': {
              'type': 'string',
              'description': '请求体内容（字符串格式，如 JSON 文本）',
            },
            'form_data_fields': {
              'type': 'array',
              'description': '表单字段数组（用于 formData 或 formUrlEncoded），每项包含 key, value, type("text"|"file"), isEnabled',
              'items': {'type': 'object'},
            },
            'pre_request_script': {
              'type': 'string',
              'description': '临时覆盖执行的前置 JavaScript 脚本',
            },
            'post_request_script': {
              'type': 'string',
              'description': '临时覆盖执行的后置测试断言 JavaScript 脚本',
            },
            'environment_id': {
              'type': 'string',
              'description': '本次执行临时绑定的环境 ID（不传则使用当前激活环境）',
            },
          },
        },
      },
      {
        'name': 'upsert_api_request',
        'description':
            '向工作区新增或局部更新（Patch 语义）一个 API 请求。支持传入 request_id 精确修改已有接口（含重命名、修改前后置脚本、切换 Body 类型及跨目录迁移），也支持按目录路径 + 名称新增或更新，修改即时生效并持久化到本地。',
        'inputSchema': {
          'type': 'object',
          'properties': {
            'request_id': {
              'type': 'string',
              'description': '已有请求 ID（可选：传入时按 ID 精确局部更新，未传字段保留原值）',
            },
            'collection_id': {
              'type': 'string',
              'description': '目标集合 ID（可选，新建时默认使用第一个集合；更新时若传入可将接口迁移至该集合）',
            },
            'folder_id': {
              'type': 'string',
              'description': '目标文件夹 ID（可选，优先级高于 folder_path）',
            },
            'folder_path': {
              'type': 'string',
              'description': '文件夹路径，例如 "dqs/simReport" 或 "auth"，传 "/" 表示集合根目录，若目录不存在将自动创建',
            },
            'name': {
              'type': 'string',
              'description': '请求名称（新建接口时必填，按 request_id 更新时可选）',
            },
            'method': {
              'type': 'string',
              'enum': ['GET', 'POST', 'PUT', 'DELETE', 'PATCH', 'HEAD', 'OPTIONS'],
              'description': 'HTTP 请求方法',
            },
            'url': {
              'type': 'string',
              'description': '请求 URL',
            },
            'headers': {
              'description': 'Headers 键值对 Map 或 [{key, value, isEnabled, description}] 数组',
            },
            'params': {
              'description': 'Query 参数键值对 Map 或 [{key, value, isEnabled, description}] 数组',
            },
            'body_type': {
              'type': 'string',
              'enum': ['none', 'json', 'formUrlEncoded', 'formData', 'raw'],
              'description': '请求体类型（可选：若传了 body 且未指定，默认设为 json）',
            },
            'raw_format': {
              'type': 'string',
              'enum': ['json', 'text', 'xml', 'html', 'javascript'],
              'description': 'Raw 格式类型（默认 json）',
            },
            'body': {
              'type': 'string',
              'description': '请求体内容（字符串格式，如 JSON）',
            },
            'form_data_fields': {
              'description': '表单字段列表（数组或键值 Map，用于 formData / formUrlEncoded）',
            },
            'description': {
              'type': 'string',
              'description': '接口功能描述与注释',
            },
            'pre_request_script': {
              'type': 'string',
              'description': '前置处理/动态签名脚本',
            },
            'post_request_script': {
              'type': 'string',
              'description': '后置断言/变量提取脚本',
            },
          },
        },
      },
      {
        'name': 'manage_api_request',
        'description': '对已有 API 请求执行删除 (delete)、移动目录 (move) 或复制副本 (duplicate) 操作。',
        'inputSchema': {
          'type': 'object',
          'properties': {
            'action': {
              'type': 'string',
              'enum': ['delete', 'move', 'duplicate'],
              'description': '操作类型：delete（删除接口）、move（移动到目标集合/目录）、duplicate（复制接口）',
            },
            'request_id': {
              'type': 'string',
              'description': '目标请求 ID',
            },
            'request_ids': {
              'type': 'array',
              'items': {'type': 'string'},
              'description': '可选：批量删除或移动时的请求 ID 列表',
            },
            'target_collection_id': {
              'type': 'string',
              'description': 'move / duplicate 的目标集合 ID（不传则保持原所属集合）',
            },
            'target_folder_id': {
              'type': 'string',
              'description': 'move / duplicate 的目标文件夹 ID',
            },
            'target_folder_path': {
              'type': 'string',
              'description': 'move / duplicate 的目标文件夹路径（如 "auth/v2"，传 "" 或 "/" 表示移动到集合根目录，不存在则自动创建）',
            },
            'new_name': {
              'type': 'string',
              'description': 'duplicate 复制时的新接口名称（可选，默认追加 " - 副本"）',
            },
          },
          'required': ['action'],
        },
      },
      {
        'name': 'manage_containers',
        'description':
            '管理集合 (Collection) 与多级文件夹 (Folder) 的结构（查询详情、创建、更新、移动、删除）以及容器级公共配置（公共 Headers、目录变量、公共前置脚本、公共后置断言）。',
        'inputSchema': {
          'type': 'object',
          'properties': {
            'action': {
              'type': 'string',
              'enum': [
                'get_detail',
                'create_collection',
                'create_folder',
                'update',
                'move_folder',
                'delete',
              ],
              'description': '执行动作类型',
            },
            'container_id': {
              'type': 'string',
              'description': '目标集合或文件夹的唯一 ID（用于 get_detail / update / move_folder / delete）',
            },
            'collection_id': {
              'type': 'string',
              'description': '所属或目标集合 ID（可配合 folder_path 定位或创建文件夹）',
            },
            'folder_path': {
              'type': 'string',
              'description': '文件夹路径，如 "用户认证模块/子模块"（用于按路径定位或递归创建多级目录）',
            },
            'parent_id': {
              'type': 'string',
              'description': 'create_folder 或 move_folder 时的父容器 ID（可为集合 ID 或父文件夹 ID）',
            },
            'name': {
              'type': 'string',
              'description': '集合或文件夹名称（create 时必填，update 时可选重命名）',
            },
            'description': {
              'type': 'string',
              'description': '集合或目录说明描述',
            },
            'headers': {
              'description': '容器级公共 Headers（支持键值 Map 或 [{key, value, isEnabled, description}] 数组）',
            },
            'variables': {
              'description': '容器级目录参数/变量（支持键值 Map 或 [{key, value, isEnabled, description}] 数组）',
            },
            'pre_request_script': {
              'type': 'string',
              'description': '容器级公共前置脚本',
            },
            'post_request_script': {
              'type': 'string',
              'description': '容器级公共后置断言脚本',
            },
          },
          'required': ['action'],
        },
      },
      {
        'name': 'manage_environment_variables',
        'description':
            '全面管理工作区环境（列表查询、切换激活环境、创建/更新/删除环境）、环境变量（读取、设置、删除变量，支持配置枚举候选项 enumOptions、isSecret、showInHeader）以及工作区全局变量 (Global Variables)。',
        'inputSchema': {
          'type': 'object',
          'properties': {
            'action': {
              'type': 'string',
              'enum': [
                'list_environments',
                'switch_active',
                'create_environment',
                'update_environment',
                'delete_environment',
                'get_variables',
                'set_variable',
                'delete_variable',
                'get_global_variables',
                'set_global_variable',
                'delete_global_variable',
              ],
              'description': '执行动作类型',
            },
            'environment_id': {
              'type': 'string',
              'description': '目标环境 ID（不传则默认使用当前激活环境）',
            },
            'name': {
              'type': 'string',
              'description': '环境名称（create_environment / update_environment 时使用）',
            },
            'base_url': {
              'type': 'string',
              'description': '环境默认 Base URL（create_environment / update_environment 时使用）',
            },
            'description': {
              'type': 'string',
              'description': '环境说明或变量说明',
            },
            'set_active': {
              'type': 'boolean',
              'description': 'create_environment 创建后是否立即切换为当前激活环境',
            },
            'key': {
              'type': 'string',
              'description': '变量名（set_variable / delete_variable / set_global_variable / delete_global_variable 时使用）',
            },
            'value': {
              'type': 'string',
              'description': '变量值',
            },
            'variables': {
              'description': '可选：批量设置多个变量（支持键值 Map 或变量对象数组）',
            },
            'is_secret': {
              'type': 'boolean',
              'description': '是否为敏感密钥变量（UI 掩码显示）',
            },
            'is_enabled': {
              'type': 'boolean',
              'description': '是否启用该变量（默认 true）',
            },
            'is_enum': {
              'type': 'boolean',
              'description': '是否为枚举下拉变量',
            },
            'enum_options': {
              'type': 'array',
              'description': '枚举候选项列表，每项为 {"name": "网关名", "value": "https://..."} 或字符串',
              'items': <String, dynamic>{},
            },
            'show_in_header': {
              'type': 'boolean',
              'description': '是否在主界面顶部导航栏显示快捷切换下拉框（仅枚举变量生效）',
            },
          },
          'required': ['action'],
        },
      },
      {
        'name': 'get_execution_history_logs',
        'description': '查询最近由桌面客户端或 AI Agent 执行的真实 API 接口调试历史记录（apiHistory）和 MCP 调度审计日志（mcpLogs）。',
        'inputSchema': {
          'type': 'object',
          'properties': {
            'log_type': {
              'type': 'string',
              'enum': ['all', 'api_history', 'mcp_audit'],
              'description': '返回日志类型：all（默认同时返回两者）、api_history（仅接口调用历史）、mcp_audit（仅 MCP 审计日志）',
            },
            'request_id': {
              'type': 'string',
              'description': '可选：按指定 request_id 过滤接口调用历史',
            },
            'limit': {
              'type': 'integer',
              'description': '最多返回的条数，默认 10，最大 200',
            },
            'include_snapshot': {
              'type': 'boolean',
              'description': '是否在 apiHistory 中包含完整的请求参数快照（默认 false）',
            },
          },
        },
      },
    ];
  }

  /// 直接执行指定 MCP Tool（可供内部测试与 JSON-RPC 共同调用）
  Future<Map<String, dynamic>> executeToolDirectly(
    String toolName,
    Map<String, dynamic> arguments,
  ) =>
      _executeMcpTool(toolName, arguments);

  /// 调度执行具体 MCP Tool
  Future<Map<String, dynamic>> _executeMcpTool(
    String toolName,
    Map<String, dynamic> arguments,
  ) async {
    final startTime = DateTime.now();
    try {
      Map<String, dynamic> result;

      switch (toolName) {
        case 'list_collections_and_apis':
          result = _handleListCollectionsAndApis(arguments);
          break;

        case 'get_api_detail':
          result = _handleGetApiDetail(arguments);
          break;

        case 'execute_api_request':
          result = await _handleExecuteApiRequest(arguments);
          break;

        case 'upsert_api_request':
          result = _handleUpsertApiRequest(arguments);
          break;

        case 'manage_api_request':
          result = _handleManageApiRequest(arguments);
          break;

        case 'manage_containers':
          result = _handleManageContainers(arguments);
          break;

        case 'manage_environment_variables':
          result = _handleManageEnvironmentVariables(arguments);
          break;

        case 'get_execution_history_logs':
          result = _handleGetExecutionHistoryLogs(arguments);
          break;

        default:
          result = {'success': false, 'error': '未实现的 MCP 工具: $toolName'};
      }

      final logEntry = McpLogEntry(
        time: startTime,
        toolName: toolName,
        params: arguments,
        status: result['success'] == true ? 'SUCCESS' : 'FAILED',
        resultSummary: result.toString().length > 120
            ? '${result.toString().substring(0, 120)}...'
            : result.toString(),
      );
      logs.insert(0, logEntry);
      onMcpLog?.call(logEntry);

      return result;
    } catch (e) {
      final logEntry = McpLogEntry(
        time: startTime,
        toolName: toolName,
        params: arguments,
        status: 'ERROR',
        resultSummary: e.toString(),
      );
      logs.insert(0, logEntry);
      onMcpLog?.call(logEntry);
      return {'success': false, 'error': e.toString()};
    }
  }

  // ===========================================================================
  // 1. list_collections_and_apis
  // ===========================================================================
  Map<String, dynamic> _handleListCollectionsAndApis(
    Map<String, dynamic> arguments,
  ) {
    final targetCollectionId = arguments['collection_id'] as String?;
    final folderPathFilter = _normalizeFolderPath(
      arguments['folder_path'] as String? ?? '',
    );
    final keyword = (arguments['keyword'] as String? ?? '').trim().toLowerCase();
    final methodFilter =
        (arguments['method'] as String? ?? '').trim().toUpperCase();

    bool matchesRequest(ApiRequest r, String currentFolderPath) {
      if (folderPathFilter.isNotEmpty) {
        final normCurrent = currentFolderPath.toLowerCase();
        final normFilter = folderPathFilter.toLowerCase();
        if (normCurrent != normFilter &&
            !normCurrent.startsWith('$normFilter/')) {
          return false;
        }
      }
      if (methodFilter.isNotEmpty && r.method.nameString != methodFilter) {
        return false;
      }
      if (keyword.isNotEmpty) {
        final matchName = r.name.toLowerCase().contains(keyword);
        final matchUrl = r.url.toLowerCase().contains(keyword);
        final matchDesc = r.description.toLowerCase().contains(keyword);
        if (!matchName && !matchUrl && !matchDesc) {
          return false;
        }
      }
      return true;
    }

    Map<String, dynamic> serializeRequestSummary(
      ApiRequest r, {
      required String? folderId,
      required String folderPath,
    }) {
      return {
        'id': r.id,
        'name': r.name,
        'method': r.method.nameString,
        'url': r.url,
        'folderId': folderId,
        'folderPath': folderPath,
      };
    }

    Map<String, dynamic>? buildFolderTree(
      ApiFolder folder,
      String parentPath,
      List<Map<String, dynamic>> flatRequestsCollector,
    ) {
      final currentPath =
          parentPath.isEmpty ? folder.name : '$parentPath/${folder.name}';

      final matchedRequests = folder.requests
          .where((r) => matchesRequest(r, currentPath))
          .map((r) {
        final summary = serializeRequestSummary(
          r,
          folderId: folder.id,
          folderPath: currentPath,
        );
        flatRequestsCollector.add(summary);
        return summary;
      }).toList();

      final childFolderTrees = <Map<String, dynamic>>[];
      for (final sub in folder.folders) {
        final subTree = buildFolderTree(sub, currentPath, flatRequestsCollector);
        if (subTree != null) {
          childFolderTrees.add(subTree);
        }
      }

      final hasFilter = folderPathFilter.isNotEmpty ||
          keyword.isNotEmpty ||
          methodFilter.isNotEmpty;
      if (hasFilter && matchedRequests.isEmpty && childFolderTrees.isEmpty) {
        // 若指定了 folder_path 过滤且正好命中当前空目录，仍保留展示
        final isExactFolderMatch = folderPathFilter.isNotEmpty &&
            keyword.isEmpty &&
            methodFilter.isEmpty &&
            currentPath.toLowerCase() == folderPathFilter.toLowerCase();
        if (!isExactFolderMatch) {
          return null;
        }
      }

      return {
        'id': folder.id,
        'name': folder.name,
        'path': currentPath,
        'description': folder.description,
        'subFoldersCount': folder.folders.length,
        'requestsCount': matchedRequests.length,
        'folders': childFolderTrees,
        'requests': matchedRequests,
      };
    }

    final collections = workspace.collections.where((c) {
      return targetCollectionId == null ||
          targetCollectionId.isEmpty ||
          c.id == targetCollectionId;
    }).map((c) {
      final flatRequests = <Map<String, dynamic>>[];
      final rootRequests = c.requests
          .where((r) => matchesRequest(r, ''))
          .map((r) {
        final summary = serializeRequestSummary(
          r,
          folderId: null,
          folderPath: '',
        );
        flatRequests.add(summary);
        return summary;
      }).toList();

      final folderTrees = <Map<String, dynamic>>[];
      for (final f in c.folders) {
        final tree = buildFolderTree(f, '', flatRequests);
        if (tree != null) {
          folderTrees.add(tree);
        }
      }

      return {
        'id': c.id,
        'name': c.name,
        'description': c.description,
        'foldersCount': c.folders.length,
        'totalRequestsCount': flatRequests.length,
        'folders': folderTrees,
        'rootRequests': rootRequests,
        'requests': flatRequests,
      };
    }).toList();

    return {'success': true, 'collections': collections};
  }

  // ===========================================================================
  // 2. get_api_detail
  // ===========================================================================
  Map<String, dynamic> _handleGetApiDetail(Map<String, dynamic> arguments) {
    final requestId = (arguments['request_id'] as String? ?? '').trim();
    if (requestId.isEmpty) {
      return {'success': false, 'error': '请提供有效的 request_id'};
    }

    final loc = _findRequestLocationById(requestId);
    if (loc == null) {
      return {'success': false, 'error': '未找到 ID 为 $requestId 的请求'};
    }

    final parentChain = loc.collection.findParentChainForRequest(requestId);
    final inheritedHeaders = <String, Map<String, dynamic>>{};
    final containerVariables = <String, String>{};
    final preScripts = <Map<String, dynamic>>[];
    final postScripts = <Map<String, dynamic>>[];

    for (final container in parentChain) {
      final isCol = container is ApiCollection;
      for (final h in container.headers) {
        if (h.isEnabled && h.key.isNotEmpty) {
          inheritedHeaders[h.key] = {
            'key': h.key,
            'value': h.value,
            'description': h.description,
            'sourceContainerId': container.id,
            'sourceContainerName': container.name,
          };
        }
      }
      for (final v in container.variables) {
        if (v.isEnabled && v.key.isNotEmpty) {
          containerVariables[v.key] = v.value;
        }
      }
      if (container.preRequestScript.trim().isNotEmpty) {
        preScripts.add({
          'containerId': container.id,
          'containerName': container.name,
          'type': isCol ? 'collection' : 'folder',
          'script': container.preRequestScript,
        });
      }
      if (container.postRequestScript.trim().isNotEmpty) {
        postScripts.add({
          'containerId': container.id,
          'containerName': container.name,
          'type': isCol ? 'collection' : 'folder',
          'script': container.postRequestScript,
        });
      }
    }

    final resolvedVariables = VariableResolver.buildVariableMap(
      workspace: workspace,
      collection: loc.collection,
      parentContainers: parentChain,
    );

    return {
      'success': true,
      'request': loc.request.toJson(),
      'collectionId': loc.collection.id,
      'collectionName': loc.collection.name,
      'folderId': loc.folder?.id,
      'folderPath': loc.folderPath,
      'parentChain': parentChain
          .map((c) => {
                'id': c.id,
                'name': c.name,
                'type': c is ApiCollection ? 'collection' : 'folder',
              })
          .toList(),
      'inheritedContext': {
        'inheritedHeaders': inheritedHeaders.values.toList(),
        'containerVariables': containerVariables,
        'effectiveVariables': resolvedVariables,
        'parentPreRequestScripts': preScripts,
        'parentPostRequestScripts': postScripts,
      },
    };
  }

  // ===========================================================================
  // 3. execute_api_request
  // ===========================================================================
  Future<Map<String, dynamic>> _handleExecuteApiRequest(
    Map<String, dynamic> arguments,
  ) async {
    final requestId = (arguments['request_id'] as String?)?.trim();
    ApiRequest? targetRequest;
    ApiCollection? parentCollection;

    if (requestId != null && requestId.isNotEmpty) {
      final loc = _findRequestLocationById(requestId);
      if (loc != null) {
        targetRequest = loc.request.copyWith();
        parentCollection = loc.collection;
      }
    }

    targetRequest ??= ApiRequest(name: 'Agent 临时执行请求');

    if (arguments['method'] != null) {
      targetRequest.method =
          HttpMethodExt.fromString(arguments['method'].toString());
    }
    if (arguments['url'] != null) {
      targetRequest.url = arguments['url'].toString();
    }
    if (arguments['pre_request_script'] != null) {
      targetRequest.preRequestScript =
          arguments['pre_request_script'].toString();
    }
    if (arguments['post_request_script'] != null) {
      targetRequest.postRequestScript =
          arguments['post_request_script'].toString();
    }
    if (arguments['raw_format'] != null) {
      targetRequest.rawFormat = arguments['raw_format'].toString();
    }
    if (arguments['body_type'] != null) {
      targetRequest.bodyType =
          _parseBodyType(arguments['body_type'].toString());
    }
    if (arguments['body'] != null) {
      if (arguments['body_type'] == null &&
          targetRequest.bodyType == BodyType.none) {
        targetRequest.bodyType = BodyType.json;
      }
      targetRequest.bodyContent = arguments['body'].toString();
    }
    if (arguments['form_data_fields'] != null) {
      targetRequest.formDataFields =
          _parseKeyValueItems(arguments['form_data_fields']);
      if (arguments['body_type'] == null &&
          targetRequest.bodyType == BodyType.none) {
        targetRequest.bodyType = BodyType.formData;
      }
    }
    if (arguments['headers'] != null) {
      final extraHeaders = _parseKeyValueItems(arguments['headers']);
      final merged = <String, KeyValueItem>{
        for (final h in targetRequest.headers) h.key: h,
      };
      for (final h in extraHeaders) {
        merged[h.key] = h;
      }
      targetRequest.headers = merged.values.toList();
    }
    if (arguments['params'] != null) {
      final extraParams = _parseKeyValueItems(arguments['params']);
      final merged = <String, KeyValueItem>{
        for (final p in targetRequest.params) p.key: p,
      };
      for (final p in extraParams) {
        merged[p.key] = p;
      }
      targetRequest.params = merged.values.toList();
    }

    final envIdOverride = (arguments['environment_id'] as String?)?.trim();
    if (envIdOverride != null && envIdOverride.isNotEmpty) {
      final envExists = workspace.environments.any((e) => e.id == envIdOverride);
      if (!envExists) {
        return {
          'success': false,
          'error': '未找到指定的 environment_id: $envIdOverride',
        };
      }
    }

    final calledTime = DateTime.now();
    workspace.recordApiCall(targetRequest, calledAt: calledTime);
    onWorkspaceUpdated?.call(workspace);

    final execRes = await httpClientService.executeRequest(
      request: targetRequest,
      workspace: workspace,
      collection: parentCollection,
      environmentIdOverride: envIdOverride,
    );

    workspace.recordApiCall(
      targetRequest,
      statusCode: execRes.response.statusCode,
      durationMs: execRes.response.durationMs,
      calledAt: calledTime,
    );

    // 若前置/后置脚本更新了环境变量，同步回写至目标环境（优先 environment_id，其次当前激活环境）
    final targetEnvId = (envIdOverride != null && envIdOverride.isNotEmpty)
        ? envIdOverride
        : workspace.activeEnvironmentId;
    final targetEnv = targetEnvId == null
        ? null
        : workspace.environments.cast<Environment?>().firstWhere(
              (e) => e?.id == targetEnvId,
              orElse: () => null,
            );

    if (execRes.updatedEnvironmentVariables.isNotEmpty && targetEnv != null) {
      for (final entry in execRes.updatedEnvironmentVariables.entries) {
        final existing = targetEnv.variables.cast<VariableItem?>().firstWhere(
              (v) => v?.key == entry.key,
              orElse: () => null,
            );
        if (existing != null) {
          existing.value = entry.value;
        } else {
          targetEnv.variables.add(VariableItem(key: entry.key, value: entry.value));
        }
      }
    }
    onWorkspaceUpdated?.call(workspace);

    return {
      'success': true,
      'environmentId': targetEnv?.id,
      'environmentName': targetEnv?.name,
      'resolvedUrl': execRes.resolvedUrl,
      'resolvedHeaders': execRes.resolvedHeaders,
      'statusCode': execRes.response.statusCode,
      'statusMessage': execRes.response.statusMessage,
      'durationMs': execRes.response.durationMs,
      'responseHeaders': execRes.response.headers,
      'responseBody': execRes.response.body,
      'consoleLogs': execRes.response.consoleLogs,
      'testResults': execRes.response.testResults.map((t) => t.toJson()).toList(),
      'updatedEnvironmentVariables': execRes.updatedEnvironmentVariables,
    };
  }

  // ===========================================================================
  // 4. upsert_api_request
  // ===========================================================================
  Map<String, dynamic> _handleUpsertApiRequest(Map<String, dynamic> arguments) {
    if (workspace.collections.isEmpty) {
      return {'success': false, 'error': '工作区中不存在任何集合，请先创建集合'};
    }

    final reqIdArg = (arguments['request_id'] as String?)?.trim();
    final colIdArg = (arguments['collection_id'] as String?)?.trim();
    final folderIdArg = (arguments['folder_id'] as String?)?.trim();
    final hasFolderPathArg = arguments.containsKey('folder_path');
    final folderPathArg = _normalizeFolderPath(
      arguments['folder_path'] as String? ?? '',
    );

    // 1. 尝试按 request_id 查找已存在请求
    _RequestLocation? existingLoc;
    if (reqIdArg != null && reqIdArg.isNotEmpty) {
      existingLoc = _findRequestLocationById(reqIdArg);
    }

    // 2. 确定目标集合与目标文件夹
    late ApiCollection targetCol;
    if (colIdArg != null && colIdArg.isNotEmpty) {
      final foundCol =
          workspace.collections.where((c) => c.id == colIdArg).firstOrNull;
      if (foundCol == null) {
        return {'success': false, 'error': '未找到指定的集合 ID: $colIdArg'};
      }
      targetCol = foundCol;
    } else if (existingLoc != null) {
      targetCol = existingLoc.collection;
    } else {
      targetCol = workspace.collections.first;
    }

    List<ApiRequest> targetRequestList = targetCol.requests;
    ApiFolder? targetFolder;
    String resolvedFolderPath = '';

    if (folderIdArg != null && folderIdArg.isNotEmpty) {
      final foundFolderLoc = _findContainerLocationById(folderIdArg);
      if (foundFolderLoc == null || foundFolderLoc.isCollection) {
        return {'success': false, 'error': '未找到指定的文件夹 ID: $folderIdArg'};
      }
      targetCol = foundFolderLoc.collection;
      targetFolder = foundFolderLoc.container as ApiFolder;
      targetRequestList = targetFolder.requests;
      resolvedFolderPath = foundFolderLoc.folderPath;
    } else if (hasFolderPathArg) {
      if (folderPathArg.isNotEmpty) {
        targetFolder = _findOrCreateFolderByPath(targetCol, folderPathArg);
        targetRequestList = targetFolder.requests;
        resolvedFolderPath = folderPathArg;
      } else {
        targetFolder = null;
        targetRequestList = targetCol.requests;
        resolvedFolderPath = '';
      }
    } else if (existingLoc != null && existingLoc.collection.id == targetCol.id) {
      targetFolder = existingLoc.folder;
      targetRequestList = existingLoc.parentRequestList;
      resolvedFolderPath = existingLoc.folderPath;
    }

    // 3. 确定目标 ApiRequest 对象（按 ID 命中、按名称命中、或新建）
    ApiRequest? targetApi = existingLoc?.request;
    bool isCreate = false;

    if (targetApi != null) {
      // 如果指定了新的目录或集合，将接口从旧列表迁移到新列表
      if (!identical(existingLoc!.parentRequestList, targetRequestList)) {
        existingLoc.parentRequestList.removeWhere((r) => r.id == targetApi!.id);
        if (!targetRequestList.any((r) => r.id == targetApi!.id)) {
          targetRequestList.add(targetApi);
        }
      }
    } else {
      final reqName = (arguments['name'] as String?)?.trim() ?? '';
      if (reqName.isNotEmpty) {
        targetApi =
            targetRequestList.where((r) => r.name == reqName).firstOrNull;
      }
      if (targetApi == null) {
        // 新建接口时校验必填项
        if (reqName.isEmpty) {
          return {
            'success': false,
            'error': '新建接口时 name 为必填参数（若更新已有接口请传入有效的 request_id）',
          };
        }
        if (arguments['url'] == null) {
          return {
            'success': false,
            'error': '新建接口时 url 为必填参数',
          };
        }
        isCreate = true;
        targetApi = ApiRequest(
          id: (reqIdArg != null && reqIdArg.isNotEmpty) ? reqIdArg : null,
          name: reqName,
          collectionId: targetCol.id,
          url: arguments['url'].toString(),
          method: HttpMethodExt.fromString(
            arguments['method']?.toString() ?? 'GET',
          ),
        );
      }
    }

    // 4. 智能局部更新（Patch 语义：仅覆盖本次显式传入的字段）
    targetApi.collectionId = targetCol.id;

    if (arguments['name'] != null &&
        arguments['name'].toString().trim().isNotEmpty) {
      targetApi.name = arguments['name'].toString().trim();
    }
    if (arguments['method'] != null) {
      targetApi.method =
          HttpMethodExt.fromString(arguments['method'].toString());
    }
    if (arguments['url'] != null) {
      targetApi.url = arguments['url'].toString();
    }
    if (arguments.containsKey('description') &&
        arguments['description'] != null) {
      targetApi.description = arguments['description'].toString();
    }
    if (arguments.containsKey('pre_request_script') &&
        arguments['pre_request_script'] != null) {
      targetApi.preRequestScript = arguments['pre_request_script'].toString();
    }
    if (arguments.containsKey('post_request_script') &&
        arguments['post_request_script'] != null) {
      targetApi.postRequestScript = arguments['post_request_script'].toString();
    }
    if (arguments.containsKey('headers') && arguments['headers'] != null) {
      targetApi.headers = _parseKeyValueItems(arguments['headers']);
    }
    if (arguments.containsKey('params') && arguments['params'] != null) {
      targetApi.params = _parseKeyValueItems(arguments['params']);
    }
    if (arguments.containsKey('raw_format') &&
        arguments['raw_format'] != null) {
      targetApi.rawFormat = arguments['raw_format'].toString();
    }
    if (arguments.containsKey('body_type') && arguments['body_type'] != null) {
      targetApi.bodyType = _parseBodyType(arguments['body_type'].toString());
    }
    if (arguments.containsKey('body') && arguments['body'] != null) {
      final bodyStr = arguments['body'].toString();
      targetApi.bodyContent = bodyStr;
      if (!arguments.containsKey('body_type') &&
          bodyStr.isNotEmpty &&
          targetApi.bodyType == BodyType.none) {
        targetApi.bodyType = BodyType.json;
      }
    }
    if (arguments.containsKey('form_data_fields') &&
        arguments['form_data_fields'] != null) {
      targetApi.formDataFields =
          _parseKeyValueItems(arguments['form_data_fields']);
      if (!arguments.containsKey('body_type') &&
          targetApi.formDataFields.isNotEmpty &&
          targetApi.bodyType == BodyType.none) {
        targetApi.bodyType = BodyType.formData;
      }
    }

    if (isCreate) {
      targetRequestList.add(targetApi);
    }

    onWorkspaceUpdated?.call(workspace);
    return {
      'success': true,
      'isCreated': isCreate,
      'requestId': targetApi.id,
      'name': targetApi.name,
      'method': targetApi.method.nameString,
      'url': targetApi.url,
      'bodyType': targetApi.bodyType.name,
      'collectionId': targetCol.id,
      'folderId': targetFolder?.id,
      'folderPath': resolvedFolderPath,
    };
  }

  // ===========================================================================
  // 5. manage_api_request (delete / move / duplicate)
  // ===========================================================================
  Map<String, dynamic> _handleManageApiRequest(Map<String, dynamic> arguments) {
    final action = (arguments['action'] as String? ?? '').trim();
    final singleId = (arguments['request_id'] as String?)?.trim();
    final batchIds = (arguments['request_ids'] as List<dynamic>?)
            ?.map((e) => e.toString().trim())
            .where((s) => s.isNotEmpty)
            .toList() ??
        [];
    final targetIds = <String>{
      if (singleId != null && singleId.isNotEmpty) singleId,
      ...batchIds,
    }.toList();

    if (targetIds.isEmpty) {
      return {'success': false, 'error': '请提供 request_id 或 request_ids'};
    }

    if (action == 'delete') {
      final deletedIds = <String>[];
      final notFoundIds = <String>[];
      for (final id in targetIds) {
        bool deleted = false;
        for (final col in workspace.collections) {
          if (col.deleteById(id)) {
            deleted = true;
            break;
          }
        }
        if (deleted) {
          deletedIds.add(id);
        } else {
          notFoundIds.add(id);
        }
      }
      if (deletedIds.isNotEmpty) {
        onWorkspaceUpdated?.call(workspace);
      }
      return {
        'success': deletedIds.isNotEmpty,
        'action': 'delete',
        'deletedCount': deletedIds.length,
        'deletedIds': deletedIds,
        if (notFoundIds.isNotEmpty) 'notFoundIds': notFoundIds,
        if (deletedIds.isEmpty) 'error': '未找到待删除的请求 ID',
      };
    }

    if (action == 'move') {
      final firstLoc = _findRequestLocationById(targetIds.first);
      if (firstLoc == null) {
        return {'success': false, 'error': '未找到请求 ID: ${targetIds.first}'};
      }

      final targetColId = (arguments['target_collection_id'] as String?)?.trim();
      final targetFolderId = (arguments['target_folder_id'] as String?)?.trim();
      final hasTargetPath = arguments.containsKey('target_folder_path');
      final targetFolderPath = _normalizeFolderPath(
        arguments['target_folder_path'] as String? ?? '',
      );

      ApiCollection targetCol = firstLoc.collection;
      if (targetColId != null && targetColId.isNotEmpty) {
        final col = workspace.collections
            .where((c) => c.id == targetColId)
            .firstOrNull;
        if (col == null) {
          return {'success': false, 'error': '未找到目标集合 ID: $targetColId'};
        }
        targetCol = col;
      }

      List<ApiRequest> destList = targetCol.requests;
      ApiFolder? destFolder;
      String finalPath = '';

      if (targetFolderId != null && targetFolderId.isNotEmpty) {
        final folderLoc = _findContainerLocationById(targetFolderId);
        if (folderLoc == null || folderLoc.isCollection) {
          return {'success': false, 'error': '未找到目标文件夹 ID: $targetFolderId'};
        }
        targetCol = folderLoc.collection;
        destFolder = folderLoc.container as ApiFolder;
        destList = destFolder.requests;
        finalPath = folderLoc.folderPath;
      } else if (hasTargetPath && targetFolderPath.isNotEmpty) {
        destFolder = _findOrCreateFolderByPath(targetCol, targetFolderPath);
        destList = destFolder.requests;
        finalPath = targetFolderPath;
      }

      final movedIds = <String>[];
      for (final id in targetIds) {
        final loc = _findRequestLocationById(id);
        if (loc == null) continue;
        loc.parentRequestList.removeWhere((r) => r.id == id);
        loc.request.collectionId = targetCol.id;
        if (!destList.any((r) => r.id == id)) {
          destList.add(loc.request);
        }
        movedIds.add(id);
      }

      onWorkspaceUpdated?.call(workspace);
      return {
        'success': true,
        'action': 'move',
        'movedIds': movedIds,
        'targetCollectionId': targetCol.id,
        'targetFolderId': destFolder?.id,
        'targetFolderPath': finalPath,
      };
    }

    if (action == 'duplicate') {
      final loc = _findRequestLocationById(targetIds.first);
      if (loc == null) {
        return {'success': false, 'error': '未找到请求 ID: ${targetIds.first}'};
      }

      final newNameArg = (arguments['new_name'] as String?)?.trim();
      final duplicated = loc.request.copyWith(
        id: const Uuid().v4(),
        name: (newNameArg != null && newNameArg.isNotEmpty)
            ? newNameArg
            : '${loc.request.name} - 副本',
      );

      final targetColId = (arguments['target_collection_id'] as String?)?.trim();
      final targetFolderId = (arguments['target_folder_id'] as String?)?.trim();
      final hasTargetPath = arguments.containsKey('target_folder_path');
      final targetFolderPath = _normalizeFolderPath(
        arguments['target_folder_path'] as String? ?? '',
      );

      ApiCollection destCol = loc.collection;
      List<ApiRequest> destList = loc.parentRequestList;
      ApiFolder? destFolder = loc.folder;
      String finalPath = loc.folderPath;

      if (targetColId != null && targetColId.isNotEmpty) {
        final col = workspace.collections
            .where((c) => c.id == targetColId)
            .firstOrNull;
        if (col == null) {
          return {'success': false, 'error': '未找到目标集合 ID: $targetColId'};
        }
        destCol = col;
        destList = destCol.requests;
        destFolder = null;
        finalPath = '';
      }

      if (targetFolderId != null && targetFolderId.isNotEmpty) {
        final folderLoc = _findContainerLocationById(targetFolderId);
        if (folderLoc == null || folderLoc.isCollection) {
          return {'success': false, 'error': '未找到目标文件夹 ID: $targetFolderId'};
        }
        destCol = folderLoc.collection;
        destFolder = folderLoc.container as ApiFolder;
        destList = destFolder.requests;
        finalPath = folderLoc.folderPath;
      } else if (hasTargetPath) {
        if (targetFolderPath.isNotEmpty) {
          destFolder = _findOrCreateFolderByPath(destCol, targetFolderPath);
          destList = destFolder.requests;
          finalPath = targetFolderPath;
        } else {
          destFolder = null;
          destList = destCol.requests;
          finalPath = '';
        }
      }

      duplicated.collectionId = destCol.id;
      destList.add(duplicated);
      onWorkspaceUpdated?.call(workspace);

      return {
        'success': true,
        'action': 'duplicate',
        'sourceRequestId': loc.request.id,
        'newRequestId': duplicated.id,
        'name': duplicated.name,
        'collectionId': destCol.id,
        'folderId': destFolder?.id,
        'folderPath': finalPath,
      };
    }

    return {'success': false, 'error': '未知的 manage_api_request action: $action'};
  }

  // ===========================================================================
  // 6. manage_containers (集合与多级目录管理 + 容器级公共配置)
  // ===========================================================================
  Map<String, dynamic> _handleManageContainers(Map<String, dynamic> arguments) {
    final action = (arguments['action'] as String? ?? '').trim();

    if (action == 'get_detail') {
      final loc = _resolveContainerLocation(arguments);
      if (loc == null) {
        return {'success': false, 'error': '未找到目标集合或文件夹'};
      }
      final c = loc.container;
      return {
        'success': true,
        'container': {
          'id': c.id,
          'name': c.name,
          'type': loc.isCollection ? 'collection' : 'folder',
          'collectionId': loc.collection.id,
          'folderPath': loc.folderPath,
          'description': c.description,
          'headers': c.headers.map((h) => h.toJson()).toList(),
          'variables': c.variables.map((v) => v.toJson()).toList(),
          'preRequestScript': c.preRequestScript,
          'postRequestScript': c.postRequestScript,
          'subFolders': c.folders
              .map((f) => {
                    'id': f.id,
                    'name': f.name,
                    'description': f.description,
                    'subFoldersCount': f.folders.length,
                    'requestsCount': f.requests.length,
                  })
              .toList(),
          'requests': c.requests
              .map((r) => {
                    'id': r.id,
                    'name': r.name,
                    'method': r.method.nameString,
                    'url': r.url,
                  })
              .toList(),
        },
      };
    }

    if (action == 'create_collection') {
      final name = (arguments['name'] as String? ?? '').trim();
      if (name.isEmpty) {
        return {'success': false, 'error': '创建集合时 name 为必填参数'};
      }
      final newCol = ApiCollection(
        id: (arguments['container_id'] as String?)?.trim().isNotEmpty == true
            ? (arguments['container_id'] as String).trim()
            : null,
        name: name,
        description: arguments['description']?.toString() ?? '',
        headers: arguments['headers'] != null
            ? _parseKeyValueItems(arguments['headers'])
            : [],
        variables: arguments['variables'] != null
            ? _parseVariableItems(arguments['variables'])
            : [],
        preRequestScript: arguments['pre_request_script']?.toString() ?? '',
        postRequestScript: arguments['post_request_script']?.toString() ?? '',
      );
      workspace.collections.add(newCol);
      onWorkspaceUpdated?.call(workspace);
      return {
        'success': true,
        'action': 'create_collection',
        'collectionId': newCol.id,
        'name': newCol.name,
      };
    }

    if (action == 'create_folder') {
      if (workspace.collections.isEmpty) {
        return {'success': false, 'error': '工作区尚无集合，请先创建集合'};
      }
      final parentId = (arguments['parent_id'] as String?)?.trim();
      final colId = (arguments['collection_id'] as String?)?.trim();
      final folderPathArg = _normalizeFolderPath(
        arguments['folder_path'] as String? ?? '',
      );
      final nameArg = (arguments['name'] as String? ?? '').trim();

      ApiCollection targetCol = workspace.collections.first;
      ApiContainer parentContainer = targetCol;
      String basePath = '';

      if (parentId != null && parentId.isNotEmpty) {
        final parentLoc = _findContainerLocationById(parentId);
        if (parentLoc == null) {
          return {'success': false, 'error': '未找到指定的 parent_id: $parentId'};
        }
        targetCol = parentLoc.collection;
        parentContainer = parentLoc.container;
        basePath = parentLoc.folderPath;
      } else if (colId != null && colId.isNotEmpty) {
        final col =
            workspace.collections.where((c) => c.id == colId).firstOrNull;
        if (col == null) {
          return {'success': false, 'error': '未找到指定的 collection_id: $colId'};
        }
        targetCol = col;
        parentContainer = col;
      }

      // 构建需要创建的相对路径段
      final pathToCreate = folderPathArg.isNotEmpty ? folderPathArg : nameArg;
      if (pathToCreate.isEmpty) {
        return {'success': false, 'error': '创建文件夹时请提供 name 或 folder_path'};
      }

      final segments = pathToCreate
          .split('/')
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList();
      ApiFolder? lastFolder;
      ApiContainer currentParent = parentContainer;
      String currentPath = basePath;

      for (int i = 0; i < segments.length; i++) {
        final seg = segments[i];
        final isLast = i == segments.length - 1;
        final existing =
            currentParent.folders.where((f) => f.name == seg).firstOrNull;
        if (existing != null) {
          lastFolder = existing;
        } else {
          final customId = isLast &&
                  (arguments['container_id'] as String?)?.trim().isNotEmpty ==
                      true
              ? (arguments['container_id'] as String).trim()
              : null;
          final created = ApiFolder(id: customId, name: seg);
          currentParent.folders.add(created);
          lastFolder = created;
        }
        currentParent = lastFolder;
        currentPath = currentPath.isEmpty ? seg : '$currentPath/$seg';
      }

      if (lastFolder != null) {
        _applyContainerPatch(lastFolder, arguments, allowRename: false);
      }

      onWorkspaceUpdated?.call(workspace);
      return {
        'success': true,
        'action': 'create_folder',
        'folderId': lastFolder!.id,
        'name': lastFolder.name,
        'collectionId': targetCol.id,
        'folderPath': currentPath,
      };
    }

    if (action == 'update') {
      final loc = _resolveContainerLocation(arguments);
      if (loc == null) {
        return {'success': false, 'error': '未找到待更新的目标集合或文件夹'};
      }
      _applyContainerPatch(loc.container, arguments, allowRename: true);
      onWorkspaceUpdated?.call(workspace);
      return {
        'success': true,
        'action': 'update',
        'containerId': loc.container.id,
        'name': loc.container.name,
        'type': loc.isCollection ? 'collection' : 'folder',
        'collectionId': loc.collection.id,
        'headersCount': loc.container.headers.length,
        'variablesCount': loc.container.variables.length,
        'hasPreRequestScript': loc.container.preRequestScript.trim().isNotEmpty,
        'hasPostRequestScript':
            loc.container.postRequestScript.trim().isNotEmpty,
      };
    }

    if (action == 'move_folder') {
      final loc = _resolveContainerLocation(arguments);
      if (loc == null || loc.isCollection) {
        return {'success': false, 'error': '请提供有效的文件夹 container_id 或 folder_path'};
      }
      final folderToMove = loc.container as ApiFolder;
      final parentId = (arguments['parent_id'] as String?)?.trim();
      final targetColId = (arguments['collection_id'] as String?)?.trim();

      late ApiContainer newParent;
      late ApiCollection newCol;

      if (parentId != null && parentId.isNotEmpty) {
        if (parentId == folderToMove.id ||
            folderToMove.findFolderById(parentId) != null) {
          return {'success': false, 'error': '不能将文件夹移动到其自身或子文件夹下'};
        }
        final destLoc = _findContainerLocationById(parentId);
        if (destLoc == null) {
          return {'success': false, 'error': '未找到目标父容器 ID: $parentId'};
        }
        newParent = destLoc.container;
        newCol = destLoc.collection;
      } else if (targetColId != null && targetColId.isNotEmpty) {
        final col = workspace.collections
            .where((c) => c.id == targetColId)
            .firstOrNull;
        if (col == null) {
          return {'success': false, 'error': '未找到目标集合 ID: $targetColId'};
        }
        newParent = col;
        newCol = col;
      } else {
        return {'success': false, 'error': 'move_folder 需要提供 parent_id 或 collection_id'};
      }

      loc.parentContainer?.folders.removeWhere((f) => f.id == folderToMove.id);
      if (!newParent.folders.any((f) => f.id == folderToMove.id)) {
        newParent.folders.add(folderToMove);
      }
      // 同步更新子孙请求的 collectionId
      for (final r in folderToMove.findAllRequests()) {
        r.collectionId = newCol.id;
      }

      onWorkspaceUpdated?.call(workspace);
      final updatedLoc = _findContainerLocationById(folderToMove.id);
      return {
        'success': true,
        'action': 'move_folder',
        'folderId': folderToMove.id,
        'collectionId': newCol.id,
        'folderPath': updatedLoc?.folderPath ?? folderToMove.name,
      };
    }

    if (action == 'delete') {
      final loc = _resolveContainerLocation(arguments);
      if (loc == null) {
        return {'success': false, 'error': '未找到待删除的集合或文件夹'};
      }
      if (loc.isCollection) {
        workspace.collections.removeWhere((c) => c.id == loc.container.id);
      } else {
        loc.collection.deleteById(loc.container.id);
      }
      onWorkspaceUpdated?.call(workspace);
      return {
        'success': true,
        'action': 'delete',
        'deletedId': loc.container.id,
        'deletedName': loc.container.name,
        'type': loc.isCollection ? 'collection' : 'folder',
      };
    }

    return {'success': false, 'error': '未知的 manage_containers action: $action'};
  }

  // ===========================================================================
  // 7. manage_environment_variables (环境 CRUD + 枚举变量 + 全局变量)
  // ===========================================================================
  Map<String, dynamic> _handleManageEnvironmentVariables(
    Map<String, dynamic> arguments,
  ) {
    final action = arguments['action'] as String? ?? 'list_environments';

    if (action == 'list_environments') {
      return {
        'success': true,
        'activeEnvironmentId': workspace.activeEnvironmentId,
        'environments': workspace.environments
            .map((e) => {
                  'id': e.id,
                  'name': e.name,
                  'baseUrl': e.baseUrl,
                  'description': e.description,
                  'variablesCount': e.variables.length,
                })
            .toList(),
        'globalVariablesCount': workspace.globalVariables.length,
      };
    }

    if (action == 'switch_active') {
      final envId = (arguments['environment_id'] as String?)?.trim() ?? '';
      if (envId.isNotEmpty &&
          !workspace.environments.any((e) => e.id == envId)) {
        return {'success': false, 'error': '未找到目标环境 ID: $envId'};
      }
      workspace.activeEnvironmentId = envId.isEmpty ? null : envId;
      onWorkspaceUpdated?.call(workspace);
      return {
        'success': true,
        'activeEnvironmentId': workspace.activeEnvironmentId,
        'activeEnvironmentName': workspace.activeEnvironment?.name,
      };
    }

    if (action == 'create_environment') {
      final name = (arguments['name'] as String? ?? '').trim();
      if (name.isEmpty) {
        return {'success': false, 'error': 'create_environment 时 name 为必填参数'};
      }
      final customId = (arguments['environment_id'] as String?)?.trim();
      final envId = (customId != null && customId.isNotEmpty)
          ? customId
          : 'env-${const Uuid().v4().substring(0, 8)}';
      final baseUrl = (arguments['base_url'] as String? ?? '').trim();
      final desc = arguments['description']?.toString() ?? '';
      final vars = arguments['variables'] != null
          ? _parseVariableItems(arguments['variables'])
          : <VariableItem>[];

      if (baseUrl.isNotEmpty && !vars.any((v) => v.key == 'baseUrl')) {
        vars.insert(
          0,
          VariableItem(
            key: 'baseUrl',
            value: baseUrl,
            isEnum: true,
            enumOptions: [EnumOption(name: '默认网关', value: baseUrl)],
            showInHeader: true,
          ),
        );
      }

      final newEnv = Environment(
        id: envId,
        name: name,
        baseUrl: baseUrl,
        description: desc,
        variables: vars,
      );
      workspace.environments.add(newEnv);
      if (arguments['set_active'] == true ||
          workspace.activeEnvironmentId == null) {
        workspace.activeEnvironmentId = newEnv.id;
      }
      onWorkspaceUpdated?.call(workspace);
      return {
        'success': true,
        'action': 'create_environment',
        'environment': newEnv.toJson(),
        'activeEnvironmentId': workspace.activeEnvironmentId,
      };
    }

    if (action == 'update_environment') {
      final targetEnv = _resolveTargetEnvironment(arguments);
      if (targetEnv == null) {
        return {'success': false, 'error': '未找到目标环境'};
      }
      if (arguments['name'] != null &&
          arguments['name'].toString().trim().isNotEmpty) {
        targetEnv.name = arguments['name'].toString().trim();
      }
      if (arguments.containsKey('description') &&
          arguments['description'] != null) {
        targetEnv.description = arguments['description'].toString();
      }
      if (arguments.containsKey('base_url') && arguments['base_url'] != null) {
        final newBaseUrl = arguments['base_url'].toString().trim();
        targetEnv.baseUrl = newBaseUrl;
        final baseVar = targetEnv.variables
            .where((v) => v.key == 'baseUrl')
            .firstOrNull;
        if (baseVar != null && newBaseUrl.isNotEmpty) {
          baseVar.value = newBaseUrl;
        }
      }
      if (arguments['variables'] != null) {
        final incoming = _parseVariableItems(arguments['variables']);
        for (final item in incoming) {
          _upsertVariableInList(targetEnv.variables, item);
        }
      }
      if (arguments['set_active'] == true) {
        workspace.activeEnvironmentId = targetEnv.id;
      }
      onWorkspaceUpdated?.call(workspace);
      return {
        'success': true,
        'action': 'update_environment',
        'environment': targetEnv.toJson(),
      };
    }

    if (action == 'delete_environment') {
      final envId = (arguments['environment_id'] as String? ?? '').trim();
      if (envId.isEmpty) {
        return {'success': false, 'error': 'delete_environment 需提供 environment_id'};
      }
      final beforeCount = workspace.environments.length;
      workspace.environments.removeWhere((e) => e.id == envId);
      if (workspace.environments.length == beforeCount) {
        return {'success': false, 'error': '未找到环境 ID: $envId'};
      }
      if (workspace.activeEnvironmentId == envId) {
        workspace.activeEnvironmentId = workspace.environments.isNotEmpty
            ? workspace.environments.first.id
            : null;
      }
      onWorkspaceUpdated?.call(workspace);
      return {
        'success': true,
        'action': 'delete_environment',
        'deletedEnvironmentId': envId,
        'activeEnvironmentId': workspace.activeEnvironmentId,
      };
    }

    if (action == 'get_variables') {
      final env = _resolveTargetEnvironment(arguments);
      return {
        'success': true,
        'environmentId': env?.id,
        'environmentName': env?.name ?? 'No Environment',
        'baseUrl': env?.baseUrl ?? '',
        'variables': env?.toMap() ?? {},
        'variableItems': env?.variables.map((v) => v.toJson()).toList() ?? [],
      };
    }

    if (action == 'set_variable') {
      final targetEnv = _resolveTargetEnvironment(arguments);
      if (targetEnv == null) {
        return {'success': false, 'error': '未找到目标环境'};
      }

      if (arguments['variables'] != null) {
        final incoming = _parseVariableItems(arguments['variables']);
        for (final item in incoming) {
          _upsertVariableInList(targetEnv.variables, item);
        }
        onWorkspaceUpdated?.call(workspace);
        return {
          'success': true,
          'environment': targetEnv.name,
          'updatedCount': incoming.length,
        };
      }

      final key = (arguments['key'] as String? ?? '').trim();
      if (key.isEmpty) {
        return {'success': false, 'error': 'set_variable 需要提供非空 key'};
      }
      final updatedItem =
          _applyVariablePatchInList(targetEnv.variables, key, arguments);
      onWorkspaceUpdated?.call(workspace);
      return {
        'success': true,
        'environment': targetEnv.name,
        'key': updatedItem.key,
        'value': updatedItem.value,
        'variable': updatedItem.toJson(),
      };
    }

    if (action == 'delete_variable') {
      final targetEnv = _resolveTargetEnvironment(arguments);
      if (targetEnv == null) {
        return {'success': false, 'error': '未找到目标环境'};
      }
      final key = (arguments['key'] as String? ?? '').trim();
      if (key.isEmpty) {
        return {'success': false, 'error': 'delete_variable 需要提供 key'};
      }
      final before = targetEnv.variables.length;
      targetEnv.variables.removeWhere((v) => v.key == key);
      final removed = before - targetEnv.variables.length;
      if (removed > 0) {
        onWorkspaceUpdated?.call(workspace);
      }
      return {
        'success': removed > 0,
        'environment': targetEnv.name,
        'deletedKey': key,
        if (removed == 0) 'error': '未找到变量: $key',
      };
    }

    if (action == 'get_global_variables') {
      final map = <String, String>{
        for (final v in workspace.globalVariables)
          if (v.isEnabled && v.key.isNotEmpty) v.key: v.value,
      };
      return {
        'success': true,
        'variables': map,
        'variableItems':
            workspace.globalVariables.map((v) => v.toJson()).toList(),
      };
    }

    if (action == 'set_global_variable') {
      if (arguments['variables'] != null) {
        final incoming = _parseVariableItems(arguments['variables']);
        for (final item in incoming) {
          _upsertVariableInList(workspace.globalVariables, item);
        }
        onWorkspaceUpdated?.call(workspace);
        return {
          'success': true,
          'updatedCount': incoming.length,
        };
      }

      final key = (arguments['key'] as String? ?? '').trim();
      if (key.isEmpty) {
        return {'success': false, 'error': 'set_global_variable 需要提供非空 key'};
      }
      final updatedItem =
          _applyVariablePatchInList(workspace.globalVariables, key, arguments);
      onWorkspaceUpdated?.call(workspace);
      return {
        'success': true,
        'key': updatedItem.key,
        'value': updatedItem.value,
        'variable': updatedItem.toJson(),
      };
    }

    if (action == 'delete_global_variable') {
      final key = (arguments['key'] as String? ?? '').trim();
      if (key.isEmpty) {
        return {'success': false, 'error': 'delete_global_variable 需要提供 key'};
      }
      final before = workspace.globalVariables.length;
      workspace.globalVariables.removeWhere((v) => v.key == key);
      final removed = before - workspace.globalVariables.length;
      if (removed > 0) {
        onWorkspaceUpdated?.call(workspace);
      }
      return {
        'success': removed > 0,
        'deletedKey': key,
        if (removed == 0) 'error': '未找到全局变量: $key',
      };
    }

    return {'success': false, 'error': '未知 action: $action'};
  }

  // ===========================================================================
  // 8. get_execution_history_logs
  // ===========================================================================
  Map<String, dynamic> _handleGetExecutionHistoryLogs(
    Map<String, dynamic> arguments,
  ) {
    final logType = (arguments['log_type'] as String? ?? 'all').trim();
    final reqIdFilter = (arguments['request_id'] as String?)?.trim();
    final rawLimit = arguments['limit'];
    final limit = (rawLimit is int
            ? rawLimit
            : int.tryParse(rawLimit?.toString() ?? '') ?? 10)
        .clamp(1, 200);
    final includeSnapshot = arguments['include_snapshot'] == true;

    final includeApiHistory = logType == 'all' || logType == 'api_history';
    final includeMcpAudit = logType == 'all' || logType == 'mcp_audit';

    final apiHistoryList = includeApiHistory
        ? workspace.apiHistory
            .where((h) =>
                reqIdFilter == null ||
                reqIdFilter.isEmpty ||
                h.requestId == reqIdFilter)
            .take(limit)
            .map((h) => {
                  'requestId': h.requestId,
                  'name': h.name,
                  'method': h.method.nameString,
                  'url': h.url,
                  'calledAt': h.calledAt.toIso8601String(),
                  'statusCode': h.statusCode,
                  'durationMs': h.durationMs,
                  if (includeSnapshot && h.requestSnapshot != null)
                    'requestSnapshot': h.requestSnapshot!.toJson(),
                })
            .toList()
        : <Map<String, dynamic>>[];

    final mcpAuditList = includeMcpAudit
        ? logs
            .take(limit)
            .map((l) => {
                  'time': l.time.toIso8601String(),
                  'toolName': l.toolName,
                  'params': l.params,
                  'status': l.status,
                  'summary': l.resultSummary,
                })
            .toList()
        : <Map<String, dynamic>>[];

    return {
      'success': true,
      'logType': logType,
      'limit': limit,
      if (includeApiHistory) 'apiHistory': apiHistoryList,
      if (includeMcpAudit) 'mcpLogs': mcpAuditList,
      // 保留向后兼容字段
      'recentLogs': mcpAuditList,
    };
  }

  // ===========================================================================
  // 内部定位与解析辅助方法
  // ===========================================================================

  String _normalizeFolderPath(String rawPath) {
    return rawPath
        .split('/')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .join('/');
  }

  _RequestLocation? _findRequestLocationById(String requestId) {
    for (final col in workspace.collections) {
      for (final req in col.requests) {
        if (req.id == requestId) {
          return _RequestLocation(
            collection: col,
            folder: null,
            folderPath: '',
            parentRequestList: col.requests,
            request: req,
          );
        }
      }
      final foundInFolder =
          _findRequestInFolders(col, col.folders, '', requestId);
      if (foundInFolder != null) {
        return foundInFolder;
      }
    }
    return null;
  }

  _RequestLocation? _findRequestInFolders(
    ApiCollection col,
    List<ApiFolder> folders,
    String parentPath,
    String requestId,
  ) {
    for (final folder in folders) {
      final currentPath =
          parentPath.isEmpty ? folder.name : '$parentPath/${folder.name}';
      for (final req in folder.requests) {
        if (req.id == requestId) {
          return _RequestLocation(
            collection: col,
            folder: folder,
            folderPath: currentPath,
            parentRequestList: folder.requests,
            request: req,
          );
        }
      }
      final sub =
          _findRequestInFolders(col, folder.folders, currentPath, requestId);
      if (sub != null) return sub;
    }
    return null;
  }

  _ContainerLocation? _findContainerLocationById(String containerId) {
    for (final col in workspace.collections) {
      if (col.id == containerId) {
        return _ContainerLocation(
          collection: col,
          container: col,
          isCollection: true,
          folderPath: '',
          parentContainer: null,
        );
      }
      final foundFolder =
          _findFolderLocationInList(col, col, col.folders, '', containerId);
      if (foundFolder != null) return foundFolder;
    }
    return null;
  }

  _ContainerLocation? _findFolderLocationInList(
    ApiCollection col,
    ApiContainer parent,
    List<ApiFolder> folders,
    String parentPath,
    String targetId,
  ) {
    for (final f in folders) {
      final currentPath = parentPath.isEmpty ? f.name : '$parentPath/${f.name}';
      if (f.id == targetId) {
        return _ContainerLocation(
          collection: col,
          container: f,
          isCollection: false,
          folderPath: currentPath,
          parentContainer: parent,
        );
      }
      final sub =
          _findFolderLocationInList(col, f, f.folders, currentPath, targetId);
      if (sub != null) return sub;
    }
    return null;
  }

  _ContainerLocation? _resolveContainerLocation(Map<String, dynamic> arguments) {
    final containerId = (arguments['container_id'] as String?)?.trim();
    if (containerId != null && containerId.isNotEmpty) {
      return _findContainerLocationById(containerId);
    }

    final colId = (arguments['collection_id'] as String?)?.trim();
    final folderPath = _normalizeFolderPath(
      arguments['folder_path'] as String? ?? '',
    );

    ApiCollection? targetCol;
    if (colId != null && colId.isNotEmpty) {
      targetCol =
          workspace.collections.where((c) => c.id == colId).firstOrNull;
      if (targetCol == null) return null;
    } else if (workspace.collections.isNotEmpty) {
      targetCol = workspace.collections.first;
    }

    if (targetCol == null) return null;
    if (folderPath.isEmpty) {
      return _ContainerLocation(
        collection: targetCol,
        container: targetCol,
        isCollection: true,
        folderPath: '',
        parentContainer: null,
      );
    }

    final segments = folderPath.split('/');
    ApiContainer currentParent = targetCol;
    ApiFolder? currentFolder;
    String builtPath = '';
    for (final seg in segments) {
      final next =
          currentParent.folders.where((f) => f.name == seg).firstOrNull;
      if (next == null) return null;
      currentFolder = next;
      builtPath = builtPath.isEmpty ? seg : '$builtPath/$seg';
      if (seg != segments.last) {
        currentParent = next;
      }
    }
    if (currentFolder == null) return null;
    return _ContainerLocation(
      collection: targetCol,
      container: currentFolder,
      isCollection: false,
      folderPath: builtPath,
      parentContainer: currentParent,
    );
  }

  ApiFolder _findOrCreateFolderByPath(
    ApiCollection collection,
    String folderPath,
  ) {
    final segments = _normalizeFolderPath(folderPath)
        .split('/')
        .where((s) => s.isNotEmpty)
        .toList();
    List<ApiFolder> currentFolders = collection.folders;
    ApiFolder? currentFolder;
    for (final seg in segments) {
      final existing = currentFolders.where((f) => f.name == seg).firstOrNull;
      if (existing != null) {
        currentFolder = existing;
      } else {
        final newFolder = ApiFolder(name: seg);
        currentFolders.add(newFolder);
        currentFolder = newFolder;
      }
      currentFolders = currentFolder.folders;
    }
    return currentFolder!;
  }

  void _applyContainerPatch(
    ApiContainer container,
    Map<String, dynamic> arguments, {
    required bool allowRename,
  }) {
    if (allowRename &&
        arguments['name'] != null &&
        arguments['name'].toString().trim().isNotEmpty) {
      container.name = arguments['name'].toString().trim();
    }
    if (arguments.containsKey('description') &&
        arguments['description'] != null) {
      container.description = arguments['description'].toString();
    }
    if (arguments.containsKey('headers') && arguments['headers'] != null) {
      container.headers = _parseKeyValueItems(arguments['headers']);
    }
    if (arguments.containsKey('variables') && arguments['variables'] != null) {
      container.variables = _parseVariableItems(arguments['variables']);
    }
    if (arguments.containsKey('pre_request_script') &&
        arguments['pre_request_script'] != null) {
      container.preRequestScript = arguments['pre_request_script'].toString();
    }
    if (arguments.containsKey('post_request_script') &&
        arguments['post_request_script'] != null) {
      container.postRequestScript = arguments['post_request_script'].toString();
    }
  }

  Environment? _resolveTargetEnvironment(Map<String, dynamic> arguments) {
    final envId = (arguments['environment_id'] as String?)?.trim();
    if (envId != null && envId.isNotEmpty) {
      return workspace.environments
          .cast<Environment?>()
          .firstWhere((e) => e?.id == envId, orElse: () => null);
    }
    return workspace.activeEnvironment;
  }

  BodyType _parseBodyType(String raw) {
    final lower = raw.trim().toLowerCase();
    switch (lower) {
      case 'none':
        return BodyType.none;
      case 'json':
        return BodyType.json;
      case 'formurlencoded':
      case 'x-www-form-urlencoded':
      case 'urlencoded':
        return BodyType.formUrlEncoded;
      case 'formdata':
      case 'form-data':
        return BodyType.formData;
      case 'raw':
        return BodyType.raw;
      default:
        return BodyType.json;
    }
  }

  List<KeyValueItem> _parseKeyValueItems(dynamic raw) {
    if (raw is Map) {
      return raw.entries
          .map((e) => KeyValueItem(
                key: e.key.toString(),
                value: e.value?.toString() ?? '',
              ))
          .toList();
    }
    if (raw is List) {
      return raw.whereType<Map<dynamic, dynamic>>().map((m) {
        final map = Map<String, dynamic>.from(m);
        return KeyValueItem.fromJson(map);
      }).toList();
    }
    return [];
  }

  List<VariableItem> _parseVariableItems(dynamic raw) {
    if (raw is Map) {
      return raw.entries
          .map((e) => VariableItem(
                key: e.key.toString(),
                value: e.value?.toString() ?? '',
              ))
          .toList();
    }
    if (raw is List) {
      return raw.whereType<Map<dynamic, dynamic>>().map((m) {
        final map = Map<String, dynamic>.from(m);
        return VariableItem.fromJson(map);
      }).toList();
    }
    return [];
  }

  void _upsertVariableInList(List<VariableItem> list, VariableItem incoming) {
    if (incoming.key.trim().isEmpty) return;
    final idx = list.indexWhere((v) => v.key == incoming.key);
    if (idx >= 0) {
      list[idx] = incoming;
    } else {
      list.add(incoming);
    }
  }

  VariableItem _applyVariablePatchInList(
    List<VariableItem> list,
    String key,
    Map<String, dynamic> arguments,
  ) {
    VariableItem? existing = list.where((v) => v.key == key).firstOrNull;
    final isNew = existing == null;
    existing ??= VariableItem(
      key: key,
      value: arguments['value']?.toString() ?? '',
    );

    if (arguments.containsKey('value') && arguments['value'] != null) {
      existing.value = arguments['value'].toString();
    }
    if (arguments['is_secret'] is bool) {
      existing.isSecret = arguments['is_secret'] as bool;
    }
    if (arguments['is_enabled'] is bool) {
      existing.isEnabled = arguments['is_enabled'] as bool;
    }
    if (arguments.containsKey('description') &&
        arguments['description'] != null) {
      existing.description = arguments['description'].toString();
    }
    if (arguments['is_enum'] is bool) {
      existing.isEnum = arguments['is_enum'] as bool;
    }
    if (arguments['enum_options'] is List) {
      existing.enumOptions = (arguments['enum_options'] as List)
          .map(EnumOption.fromJson)
          .toList();
      if (!arguments.containsKey('is_enum') &&
          existing.enumOptions.isNotEmpty) {
        existing.isEnum = true;
      }
    }
    if (arguments['show_in_header'] is bool) {
      existing.showInHeader = arguments['show_in_header'] as bool;
    }

    // 若启用了枚举且当前非空值不在候选项中，自动补充到候选项列表
    if (existing.isEnum &&
        existing.value.isNotEmpty &&
        !existing.enumOptions.any((o) => o.value == existing!.value)) {
      existing.enumOptions.insert(
        0,
        EnumOption(name: existing.value, value: existing.value),
      );
    }

    if (isNew) {
      list.add(existing);
    }
    return existing;
  }
}
