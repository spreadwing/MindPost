import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:mindpost/models/workspace.dart';
import 'package:mindpost/services/http_client_service.dart';
import 'package:mindpost/services/mcp_server_service.dart';

void main() {
  group('McpServerService 8大核心 MCP 工具全生命周期测试', () {
    late Workspace workspace;
    late HttpClientService httpClientService;
    late McpServerService mcpService;
    int workspaceUpdateCount = 0;

    setUp(() {
      workspace = Workspace.createDemo();
      httpClientService = HttpClientService();
      workspaceUpdateCount = 0;
      mcpService = McpServerService(
        httpClientService: httpClientService,
        workspace: workspace,
        onWorkspaceUpdated: (ws) {
          workspace = ws;
          workspaceUpdateCount++;
        },
      );
    });

    tearDown(() {
      httpClientService.dispose();
    });

    test('暴露 8 个标准 MCP 工具定义', () {
      final tools = mcpService.toolDefinitions;
      expect(tools.length, equals(8));
      final names = tools.map((t) => t['name']).toList();
      expect(
        names,
        containsAll([
          'list_collections_and_apis',
          'get_api_detail',
          'execute_api_request',
          'upsert_api_request',
          'manage_api_request',
          'manage_containers',
          'manage_environment_variables',
          'get_execution_history_logs',
        ]),
      );
    });

    test('1. list_collections_and_apis: 返回递归目录树及 folderPath，支持 keyword/method/folder_path 过滤', () async {
      final allRes = await mcpService.executeToolDirectly(
        'list_collections_and_apis',
        {},
      );
      expect(allRes['success'], isTrue);
      final collections = allRes['collections'] as List;
      expect(collections.length, 1);

      final firstCol = collections.first as Map<String, dynamic>;
      expect(firstCol['folders'], isA<List<dynamic>>());
      expect((firstCol['folders'] as List).length, 1);

      final authFolder = (firstCol['folders'] as List).first as Map<String, dynamic>;
      expect(authFolder['name'], '用户认证模块');
      expect(authFolder['path'], '用户认证模块');
      expect((authFolder['requests'] as List).length, 1);

      // 按 keyword 过滤
      final kwRes = await mcpService.executeToolDirectly(
        'list_collections_and_apis',
        {'keyword': '订单'},
      );
      final kwReqs = (kwRes['collections'] as List).first['requests'] as List;
      expect(kwReqs.length, 1);
      expect(kwReqs.first['name'], '创建订单');

      // 按 folder_path 过滤
      final pathRes = await mcpService.executeToolDirectly(
        'list_collections_and_apis',
        {'folder_path': '用户认证模块'},
      );
      final pathReqs = (pathRes['collections'] as List).first['requests'] as List;
      expect(pathReqs.length, 1);
      expect(pathReqs.first['id'], 'req-get-user');
      expect(pathReqs.first['folderPath'], '用户认证模块');
    });

    test('2. get_api_detail: 返回完整接口定义、所属目录路径及父容器链继承上下文', () async {
      final res = await mcpService.executeToolDirectly(
        'get_api_detail',
        {'request_id': 'req-get-user'},
      );
      expect(res['success'], isTrue);
      expect(res['collectionId'], 'col-demo');
      expect(res['folderId'], 'folder-auth');
      expect(res['folderPath'], '用户认证模块');

      final parentChain = res['parentChain'] as List;
      expect(parentChain.length, 2);

      final inherited = res['inheritedContext'] as Map<String, dynamic>;
      final inheritedHeaders = inherited['inheritedHeaders'] as List;
      final headerKeys = inheritedHeaders.map((h) => h['key']).toSet();
      expect(headerKeys, containsAll(['X-Global-App', 'X-Module']));
      expect((inherited['parentPreRequestScripts'] as List).length, 2);
    });

    test('3. upsert_api_request: 支持新建接口、按 request_id 局部更新 (Patch)、重命名及跨目录迁移', () async {
      // 3.1 新建带多级目录、前置脚本、FormData 的接口
      final createRes = await mcpService.executeToolDirectly(
        'upsert_api_request',
        {
          'folder_path': '订单模块/支付子模块',
          'name': '发起支付',
          'method': 'POST',
          'url': '{{baseUrl}}/pay/create',
          'headers': {'X-Pay-Channel': 'WeChat'},
          'params': {'version': '2.0'},
          'body_type': 'formData',
          'form_data_fields': [
            {'key': 'orderNo', 'value': 'ORD_1001', 'type': 'text'},
          ],
          'pre_request_script': 'console.log("pre-pay");',
          'post_request_script': 'console.log("post-pay");',
          'description': '微信支付下单接口',
        },
      );
      expect(createRes['success'], isTrue);
      expect(createRes['isCreated'], isTrue);
      expect(createRes['folderPath'], '订单模块/支付子模块');
      final createdId = createRes['requestId'] as String;

      // 3.2 按 request_id 局部更新（仅修改名称与 URL，验证未传的脚本/Headers/FormData 保留）
      final patchRes = await mcpService.executeToolDirectly(
        'upsert_api_request',
        {
          'request_id': createdId,
          'name': '发起聚合支付V2',
          'url': '{{baseUrl}}/pay/v2/create',
          'folder_path': '订单模块/聚合支付',
        },
      );
      expect(patchRes['success'], isTrue);
      expect(patchRes['isCreated'], isFalse);
      expect(patchRes['name'], '发起聚合支付V2');
      expect(patchRes['folderPath'], '订单模块/聚合支付');

      final detailRes = await mcpService.executeToolDirectly(
        'get_api_detail',
        {'request_id': createdId},
      );
      final reqJson = detailRes['request'] as Map<String, dynamic>;
      expect(reqJson['name'], '发起聚合支付V2');
      expect(reqJson['url'], '{{baseUrl}}/pay/v2/create');
      expect(reqJson['preRequestScript'], 'console.log("pre-pay");');
      expect(reqJson['postRequestScript'], 'console.log("post-pay");');
      expect(reqJson['bodyType'], 'formData');
      expect((reqJson['headers'] as List).first['key'], 'X-Pay-Channel');
      expect(detailRes['folderPath'], '订单模块/聚合支付');
      expect(workspaceUpdateCount, greaterThanOrEqualTo(2));
    });

    test('4. manage_api_request: 支持 duplicate 复制、move 移动目录与 delete 删除接口', () async {
      // 复制
      final dupRes = await mcpService.executeToolDirectly(
        'manage_api_request',
        {
          'action': 'duplicate',
          'request_id': 'req-get-user',
          'new_name': '获取用户数据-拷贝',
        },
      );
      expect(dupRes['success'], isTrue);
      final newId = dupRes['newRequestId'] as String;
      expect(dupRes['folderPath'], '用户认证模块');

      // 移动到集合根目录
      final moveRes = await mcpService.executeToolDirectly(
        'manage_api_request',
        {
          'action': 'move',
          'request_id': newId,
          'target_folder_path': '/',
        },
      );
      expect(moveRes['success'], isTrue);
      expect(moveRes['targetFolderPath'], '');

      final movedDetail = await mcpService.executeToolDirectly(
        'get_api_detail',
        {'request_id': newId},
      );
      expect(movedDetail['folderPath'], '');

      // 删除
      final delRes = await mcpService.executeToolDirectly(
        'manage_api_request',
        {
          'action': 'delete',
          'request_id': newId,
        },
      );
      expect(delRes['success'], isTrue);
      expect(delRes['deletedCount'], 1);
      expect(workspace.findRequestById(newId), isNull);
    });

    test('5. manage_containers: 集合与多级文件夹 CRUD 及容器级公共配置（Headers/变量/前后置脚本）', () async {
      // 创建新集合并配置公共 Headers 与变量
      final colRes = await mcpService.executeToolDirectly(
        'manage_containers',
        {
          'action': 'create_collection',
          'name': 'ERP 核心服务',
          'description': 'ERP 接口集合',
          'headers': {'X-ERP-Tenant': 'Geely'},
          'variables': {'servicePrefix': '/erp/v1'},
          'pre_request_script': 'console.log("col pre");',
        },
      );
      expect(colRes['success'], isTrue);
      final colId = colRes['collectionId'] as String;

      // 在新集合下递归创建多级目录并设置目录公共配置
      final folderRes = await mcpService.executeToolDirectly(
        'manage_containers',
        {
          'action': 'create_folder',
          'collection_id': colId,
          'folder_path': '财务中心/结算单',
          'description': '结算单相关接口',
          'headers': [
            {'key': 'X-Finance-Role', 'value': 'Auditor', 'isEnabled': true}
          ],
          'variables': [
            {'key': 'currency', 'value': 'CNY', 'isEnabled': true}
          ],
          'post_request_script': 'pm.test("ok", function(){});',
        },
      );
      expect(folderRes['success'], isTrue);
      final folderId = folderRes['folderId'] as String;
      expect(folderRes['folderPath'], '财务中心/结算单');

      // 查询容器详情
      final detailRes = await mcpService.executeToolDirectly(
        'manage_containers',
        {
          'action': 'get_detail',
          'container_id': folderId,
        },
      );
      expect(detailRes['success'], isTrue);
      final containerMap = detailRes['container'] as Map<String, dynamic>;
      expect(containerMap['name'], '结算单');
      expect((containerMap['headers'] as List).first['key'], 'X-Finance-Role');
      expect((containerMap['variables'] as List).first['key'], 'currency');

      // 更新容器公共配置（Patch）
      final updateRes = await mcpService.executeToolDirectly(
        'manage_containers',
        {
          'action': 'update',
          'container_id': folderId,
          'name': '月度结算单',
          'pre_request_script': 'console.log("folder pre updated");',
        },
      );
      expect(updateRes['success'], isTrue);
      expect(updateRes['name'], '月度结算单');
      expect(updateRes['hasPreRequestScript'], isTrue);
      expect(updateRes['hasPostRequestScript'], isTrue);

      // 删除文件夹与集合
      final delFolderRes = await mcpService.executeToolDirectly(
        'manage_containers',
        {'action': 'delete', 'container_id': folderId},
      );
      expect(delFolderRes['success'], isTrue);

      final delColRes = await mcpService.executeToolDirectly(
        'manage_containers',
        {'action': 'delete', 'container_id': colId},
      );
      expect(delColRes['success'], isTrue);
    });

    test('6. manage_environment_variables: 环境增删改、枚举变量配置与全局变量 CRUD', () async {
      // 创建新环境
      final createEnvRes = await mcpService.executeToolDirectly(
        'manage_environment_variables',
        {
          'action': 'create_environment',
          'name': 'Staging 预发环境',
          'base_url': 'https://staging.example.com',
          'description': '预发联调环境',
          'set_active': false,
        },
      );
      expect(createEnvRes['success'], isTrue);
      final stagingEnvId =
          (createEnvRes['environment'] as Map<String, dynamic>)['id'] as String;
      // 未设置 set_active: true，因此当前激活环境仍为 env-dev
      expect(workspace.activeEnvironmentId, 'env-dev');

      // 在 Staging 环境中设置带枚举候选项的变量
      final setVarRes = await mcpService.executeToolDirectly(
        'manage_environment_variables',
        {
          'action': 'set_variable',
          'environment_id': stagingEnvId,
          'key': 'clusterNode',
          'value': 'node-hz-1',
          'is_enum': true,
          'show_in_header': true,
          'enum_options': [
            {'name': '杭州节点1', 'value': 'node-hz-1'},
            {'name': '上海节点2', 'value': 'node-sh-2'},
          ],
        },
      );
      expect(setVarRes['success'], isTrue);
      final varJson = setVarRes['variable'] as Map<String, dynamic>;
      expect(varJson['isEnum'], isTrue);
      expect(varJson['showInHeader'], isTrue);
      expect((varJson['enumOptions'] as List).length, 2);

      // 删除环境变量
      final delVarRes = await mcpService.executeToolDirectly(
        'manage_environment_variables',
        {
          'action': 'delete_variable',
          'environment_id': stagingEnvId,
          'key': 'clusterNode',
        },
      );
      expect(delVarRes['success'], isTrue);

      // 全局变量设置、读取与删除
      await mcpService.executeToolDirectly(
        'manage_environment_variables',
        {
          'action': 'set_global_variable',
          'key': 'globalTraceId',
          'value': 'TRACE_999',
          'description': '全局追踪标识',
        },
      );
      final globalRes = await mcpService.executeToolDirectly(
        'manage_environment_variables',
        {'action': 'get_global_variables'},
      );
      expect((globalRes['variables'] as Map)['globalTraceId'], 'TRACE_999');

      final delGlobalRes = await mcpService.executeToolDirectly(
        'manage_environment_variables',
        {
          'action': 'delete_global_variable',
          'key': 'globalTraceId',
        },
      );
      expect(delGlobalRes['success'], isTrue);

      // 删除环境
      final delEnvRes = await mcpService.executeToolDirectly(
        'manage_environment_variables',
        {
          'action': 'delete_environment',
          'environment_id': stagingEnvId,
        },
      );
      expect(delEnvRes['success'], isTrue);
    });

    test('7. execute_api_request & get_execution_history_logs: 支持临时绑定 environment_id 执行并记录真实 API 历史与审计日志', () async {
      // 启动一个本地临时 Mock HTTP Server 验证端到端请求执行与环境绑定
      final mockServer = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final mockPort = mockServer.port;
      mockServer.listen((HttpRequest req) async {
        req.response.statusCode = 200;
        req.response.headers.contentType = ContentType.json;
        req.response.write(json.encode({
          'path': req.uri.path,
          'query': req.uri.queryParameters,
          'envToken': req.headers.value('x-env-token'),
        }));
        await req.response.close();
      });

      try {
        // 将 env-test 的 baseUrl 指向本地 Mock Server，并设置特有 token
        final testEnv =
            workspace.environments.firstWhere((e) => e.id == 'env-test');
        testEnv.baseUrl = 'http://127.0.0.1:$mockPort';
        testEnv.variables
            .firstWhere((v) => v.key == 'baseUrl')
            .value = 'http://127.0.0.1:$mockPort';

        // 当前工作区激活的是 env-dev，但我们通过 environment_id 临时指定 env-test 执行
        final execRes = await mcpService.executeToolDirectly(
          'execute_api_request',
          {
            'url': '/check-env',
            'method': 'GET',
            'environment_id': 'env-test',
            'headers': {'X-Env-Token': '{{apiKey}}'},
            'params': {'from': 'mcp'},
          },
        );

        expect(execRes['success'], isTrue);
        expect(execRes['statusCode'], 200);
        expect(execRes['environmentId'], 'env-test');
        // UI 的激活环境保持 env-dev 未被篡改
        expect(workspace.activeEnvironmentId, 'env-dev');

        final bodyMap =
            json.decode(execRes['responseBody'] as String) as Map<String, dynamic>;
        expect(bodyMap['path'], '/check-env');
        expect((bodyMap['query'] as Map)['from'], 'mcp');
        // 验证使用了 env-test 的 apiKey ('test_token_886') 而非 env-dev 的 ('dev_secret_key_998')
        expect(bodyMap['envToken'], 'test_token_886');

        // 验证 get_execution_history_logs 同时返回真实 apiHistory 与 mcpLogs
        final historyRes = await mcpService.executeToolDirectly(
          'get_execution_history_logs',
          {'log_type': 'all', 'limit': 5},
        );
        expect(historyRes['success'], isTrue);
        final apiHistory = historyRes['apiHistory'] as List;
        final mcpLogs = historyRes['mcpLogs'] as List;
        expect(apiHistory, isNotEmpty);
        expect(apiHistory.first['url'], '/check-env');
        expect(apiHistory.first['statusCode'], 200);
        expect(mcpLogs, isNotEmpty);
      } finally {
        await mockServer.close(force: true);
      }
    });
  });
}
