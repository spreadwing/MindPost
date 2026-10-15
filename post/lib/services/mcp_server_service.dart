import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';
import 'package:uuid/uuid.dart';
import '../models/workspace.dart';
import '../models/api_request.dart';
import '../models/environment.dart';
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
            'version': '1.0.0',
            'toolsCount': 5,
            'activeEnvironment': workspace.activeEnvironment?.name ?? 'None',
          }),
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      });

      // 2. GET /sse: 标准 MCP SSE 长连接端点
      router.get('/sse', (Request request) {
        final sessionId = const Uuid().v4();
        final controller = StreamController<String>.broadcast();
        _sseSessions[sessionId] = controller;

        final stream = controller.stream.map((msg) => 'data: $msg\n\n');

        // 告知 Client 发送消息的目标 URL
        Timer.run(() {
          controller.add(json.encode({
            'event': 'endpoint',
            'data': '/messages?sessionId=$sessionId',
          }));
        });

        return Response.ok(
          stream,
          headers: {
            'content-type': 'text/event-stream',
            'cache-control': 'no-cache',
            'connection': 'keep-alive',
          },
        );
      });

      // 3. POST /messages: 处理 MCP 客户端请求
      router.post('/messages', (Request request) async {
        final bodyStr = await request.readAsString();
        final jsonBody = json.decode(bodyStr);
        final responsePayload = await _handleJsonRpc(jsonBody);

        return Response.ok(
          json.encode(responsePayload),
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      });

      // 4. POST /mcp: 直连 JSON-RPC 端点（用于 Agent 或工具快速调用）
      router.post('/mcp', (Request request) async {
        final bodyStr = await request.readAsString();
        final jsonBody = json.decode(bodyStr);
        final responsePayload = await _handleJsonRpc(jsonBody);

        return Response.ok(
          json.encode(responsePayload),
          headers: {'content-type': 'application/json; charset=utf-8'},
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
              'resources': {},
            },
            'serverInfo': {
              'name': 'mindpost-workbench',
              'version': '1.0.0',
            },
          },
        };

      case 'notifications/initialized':
        return {'jsonrpc': '2.0', 'id': id, 'result': {}};

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
        final toolResult = await _executeMcpTool(toolName, arguments);

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

  /// 暴露的标准 MCP Tools 定义列表
  List<Map<String, dynamic>> _getMcpToolsDefinitions() {
    return [
      {
        'name': 'list_collections_and_apis',
        'description':
            '获取 MindPost 桌面客户端中所有接口集合、文件夹及 API 请求列表（包含请求 ID、名称、方法和 URL 模板）。供 AI Agent 快速检索当前项目接口。',
        'inputSchema': {
          'type': 'object',
          'properties': {
            'collection_id': {
              'type': 'string',
              'description': '可选：指定特定集合 ID 过滤，不传则返回全部集合',
            },
          },
        },
      },
      {
        'name': 'get_api_detail',
        'description': '根据请求 ID 获取接口完整定义，包含 Headers、Params、Body、前置脚本和后置断言。',
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
            '调度客户端引擎执行 API 请求。支持按已有 request_id 执行，也支持临时覆盖 Method、URL、Headers、Body。将自动执行前置脚本并完成环境变量替换。',
        'inputSchema': {
          'type': 'object',
          'properties': {
            'request_id': {
              'type': 'string',
              'description': '已有请求的 ID（可选）',
            },
            'method': {
              'type': 'string',
              'enum': ['GET', 'POST', 'PUT', 'DELETE', 'PATCH', 'HEAD'],
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
            'body': {
              'type': 'string',
              'description': '请求体内容（字符串格式，如 JSON 文本）',
            },
            'environment_id': {
              'type': 'string',
              'description': '执行绑定的环境 ID（不传则使用当前激活环境）',
            },
          },
        },
      },
      {
        'name': 'manage_environment_variables',
        'description':
            '查看环境变量列表、切换当前激活环境，或动态修改特定环境下的变量值（例如登录成功后将返回的 Token 回填入环境变量）。',
        'inputSchema': {
          'type': 'object',
          'properties': {
            'action': {
              'type': 'string',
              'enum': ['list_environments', 'switch_active', 'set_variable', 'get_variables'],
              'description': '执行动作类型',
            },
            'environment_id': {
              'type': 'string',
              'description': '目标环境 ID',
            },
            'key': {
              'type': 'string',
              'description': '变量名（set_variable 时必填）',
            },
            'value': {
              'type': 'string',
              'description': '变量值（set_variable 时必填）',
            },
          },
          'required': ['action'],
        },
      },
      {
        'name': 'get_execution_history_logs',
        'description': '查询最近由客户端或 AI Agent 执行的接口调试历史记录和前置脚本执行日志。',
        'inputSchema': {
          'type': 'object',
          'properties': {
            'limit': {
              'type': 'integer',
              'description': '最多返回的历史条数，默认 10',
            },
          },
        },
      },
    ];
  }

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
          final targetCollectionId = arguments['collection_id'] as String?;
          final collections = workspace.collections.where((c) {
            return targetCollectionId == null || c.id == targetCollectionId;
          }).map((c) {
            return {
              'id': c.id,
              'name': c.name,
              'description': c.description,
              'foldersCount': c.folders.length,
              'requests': c.findAllRequests().map((r) => {
                    'id': r.id,
                    'name': r.name,
                    'method': r.method.nameString,
                    'url': r.url,
                  }).toList(),
            };
          }).toList();
          result = {'success': true, 'collections': collections};
          break;

        case 'get_api_detail':
          final requestId = arguments['request_id'] as String? ?? '';
          ApiRequest? foundRequest;
          for (final c in workspace.collections) {
            final r = c.findRequestById(requestId);
            if (r != null) {
              foundRequest = r;
              break;
            }
          }
          if (foundRequest == null) {
            result = {'success': false, 'error': '未找到 ID 为 $requestId 的请求'};
          } else {
            result = {'success': true, 'request': foundRequest.toJson()};
          }
          break;

        case 'execute_api_request':
          final requestId = arguments['request_id'] as String?;
          ApiRequest? targetRequest;

          if (requestId != null && requestId.isNotEmpty) {
            for (final c in workspace.collections) {
              final r = c.findRequestById(requestId);
              if (r != null) {
                targetRequest = r.copyWith();
                break;
              }
            }
          }

          targetRequest ??= ApiRequest(name: 'Agent 临时执行请求');

          if (arguments.containsKey('method')) {
            targetRequest.method =
                HttpMethodExt.fromString(arguments['method'].toString());
          }
          if (arguments.containsKey('url')) {
            targetRequest.url = arguments['url'].toString();
          }
          if (arguments.containsKey('body')) {
            targetRequest.bodyType = BodyType.json;
            targetRequest.bodyContent = arguments['body'].toString();
          }
          if (arguments['headers'] is Map) {
            final extraHeaders = (arguments['headers'] as Map).entries.map(
                  (e) => KeyValueItem(key: e.key.toString(), value: e.value.toString()),
                );
            targetRequest.headers = [...targetRequest.headers, ...extraHeaders];
          }

          final calledTime = DateTime.now();
          workspace.recordApiCall(targetRequest, calledAt: calledTime);
          onWorkspaceUpdated?.call(workspace);

          final execRes = await httpClientService.executeRequest(
            request: targetRequest,
            workspace: workspace,
          );

          workspace.recordApiCall(
            targetRequest,
            statusCode: execRes.response.statusCode,
            durationMs: execRes.response.durationMs,
            calledAt: calledTime,
          );

          // 若前置/后置脚本更新了环境变量，同步回写
          if (execRes.updatedEnvironmentVariables.isNotEmpty &&
              workspace.activeEnvironment != null) {
            final env = workspace.activeEnvironment!;
            for (final entry in execRes.updatedEnvironmentVariables.entries) {
              final existing = env.variables.cast<VariableItem?>().firstWhere(
                    (v) => v?.key == entry.key,
                    orElse: () => null,
                  );
              if (existing != null) {
                existing.value = entry.value;
              } else {
                env.variables.add(VariableItem(key: entry.key, value: entry.value));
              }
            }
          }
          onWorkspaceUpdated?.call(workspace);

          result = {
            'success': true,
            'resolvedUrl': execRes.resolvedUrl,
            'statusCode': execRes.response.statusCode,
            'statusMessage': execRes.response.statusMessage,
            'durationMs': execRes.response.durationMs,
            'responseHeaders': execRes.response.headers,
            'responseBody': execRes.response.body,
            'consoleLogs': execRes.response.consoleLogs,
            'testResults': execRes.response.testResults.map((t) => t.toJson()).toList(),
          };
          break;

        case 'manage_environment_variables':
          final action = arguments['action'] as String? ?? 'list_environments';
          if (action == 'list_environments') {
            result = {
              'success': true,
              'activeEnvironmentId': workspace.activeEnvironmentId,
              'environments': workspace.environments.map((e) => {
                    'id': e.id,
                    'name': e.name,
                    'baseUrl': e.baseUrl,
                    'variablesCount': e.variables.length,
                  }).toList(),
            };
          } else if (action == 'switch_active') {
            final envId = arguments['environment_id'] as String? ?? '';
            workspace.activeEnvironmentId = envId;
            onWorkspaceUpdated?.call(workspace);
            result = {'success': true, 'activeEnvironmentId': envId};
          } else if (action == 'set_variable') {
            final key = arguments['key'] as String? ?? '';
            final value = arguments['value'] as String? ?? '';
            final envId = arguments['environment_id'] as String? ??
                workspace.activeEnvironmentId;
            final targetEnv = workspace.environments.cast<Environment?>().firstWhere(
                  (e) => e?.id == envId,
                  orElse: () => workspace.activeEnvironment,
                );

            if (targetEnv == null) {
              result = {'success': false, 'error': '未找到目标环境'};
            } else {
              final existing = targetEnv.variables.cast<VariableItem?>().firstWhere(
                    (v) => v?.key == key,
                    orElse: () => null,
                  );
              if (existing != null) {
                existing.value = value;
              } else {
                targetEnv.variables.add(VariableItem(key: key, value: value));
              }
              onWorkspaceUpdated?.call(workspace);
              result = {
                'success': true,
                'environment': targetEnv.name,
                'key': key,
                'value': value,
              };
            }
          } else if (action == 'get_variables') {
            final env = workspace.activeEnvironment;
            result = {
              'success': true,
              'environmentName': env?.name ?? 'No Environment',
              'baseUrl': env?.baseUrl ?? '',
              'variables': env?.toMap() ?? {},
            };
          } else {
            result = {'success': false, 'error': '未知 action: $action'};
          }
          break;

        case 'get_execution_history_logs':
          result = {
            'success': true,
            'recentLogs': logs.take(10).map((l) => {
                  'time': l.time.toIso8601String(),
                  'toolName': l.toolName,
                  'status': l.status,
                  'summary': l.resultSummary,
                }).toList(),
          };
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
}
