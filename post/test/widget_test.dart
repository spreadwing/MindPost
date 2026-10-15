import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mindpost/engine/variable_resolver.dart';
import 'package:mindpost/models/workspace.dart';
import 'package:mindpost/models/api_collection.dart';
import 'package:mindpost/models/api_folder.dart';
import 'package:mindpost/models/api_request.dart';
import 'package:mindpost/models/environment.dart';
import 'package:mindpost/models/workbench_tab.dart';
import 'package:mindpost/ui/widgets/json_syntax_highlighter.dart';
import 'package:mindpost/main.dart';

void main() {
  group('VariableResolver 单元测试', () {
    test('正确解析级联变量与动态占位符', () {
      final workspace = Workspace.createDemo();
      final variables = VariableResolver.buildVariableMap(workspace: workspace);

      expect(variables['apiKey'], isNotNull);
      expect(variables['baseUrl'], 'https://httpbin.org');

      final interpolated = VariableResolver.interpolate(
        'User_{{apiKey}}_{{\$timestamp}}',
        variables,
      );

      expect(interpolated.contains('dev_secret_key_998'), isTrue);
      expect(interpolated.contains(r'$timestamp'), isFalse);
    });

    test('正确处理相对路径隐式 Base URL 拼接与显式占位符', () {
      final variables = {'baseUrl': 'https://httpbin.org'};

      // 相对路径自动拼接
      final url1 = VariableResolver.resolveUrl(
        rawUrl: '/get?id=1',
        variables: variables,
        currentBaseUrl: 'https://httpbin.org',
      );
      expect(url1, 'https://httpbin.org/get?id=1');

      // 显式模板占位符解析
      final url2 = VariableResolver.resolveUrl(
        rawUrl: '{{baseUrl}}/post',
        variables: variables,
      );
      expect(url2, 'https://httpbin.org/post');

      // 完整绝对路径保持不变
      final url3 = VariableResolver.resolveUrl(
        rawUrl: 'https://api.github.com/users',
        variables: variables,
      );
      expect(url3, 'https://api.github.com/users');
    });
    test('多层级文件夹变量链继承与优先级覆盖', () {
      final col = ApiCollection(
        name: '根集合',
        variables: [VariableItem(key: 'token', value: 'col_token'), VariableItem(key: 'env', value: 'test')],
      );
      final subFolder = ApiFolder(
        name: '子目录',
        variables: [VariableItem(key: 'token', value: 'folder_token')],
      );
      final req = ApiRequest(name: '测试API');
      subFolder.requests.add(req);
      col.folders.add(subFolder);

      final ws = Workspace(name: '测试空间', collections: [col]);

      final chain = col.findParentChainForRequest(req.id);
      expect(chain.length, 2);
      expect(chain[0].name, '根集合');
      expect(chain[1].name, '子目录');

      final variables = VariableResolver.buildVariableMap(
        workspace: ws,
        parentContainers: chain,
      );
      // 子目录的变量覆盖根集合
      expect(variables['token'], 'folder_token');
      // 根集合的独有变量依然继承保留
      expect(variables['env'], 'test');
    });
  });

  group('ApiFolder 树形结构与递归操作测试', () {
    test('支持多层级嵌套查找与全部请求搜集', () {
      final col = ApiCollection(name: '电商服务');
      final level1 = ApiFolder(name: '订单域');
      final level2 = ApiFolder(name: '退款模块');
      final req1 = ApiRequest(name: '发起退款');
      final req2 = ApiRequest(name: '退款审核');

      level2.requests.add(req1);
      level1.folders.add(level2);
      level1.requests.add(req2);
      col.folders.add(level1);

      expect(col.findAllRequests().length, 2);
      expect(col.findRequestById(req1.id)?.name, '发起退款');
      expect(col.findRequestById(req2.id)?.name, '退款审核');

      final parentChain = col.findParentChainForRequest(req1.id);
      expect(parentChain.length, 3);
      expect(parentChain.map((c) => c.name).toList(), ['电商服务', '订单域', '退款模块']);

      // 测试递归删除
      final deleted = col.deleteById(req1.id);
      expect(deleted, isTrue);
      expect(col.findAllRequests().length, 1);
      expect(col.findRequestById(req1.id), isNull);
    });
  });

  group('WorkbenchTab 与 JsonSyntaxHighlightController 单元测试', () {
    test('WorkbenchTab 模型创建与状态管理', () {
      final req = ApiRequest(name: '测试请求');
      final reqTab = WorkbenchTab.request(req);
      expect(reqTab.type, TabType.request);
      expect(reqTab.id, req.id);
      expect(reqTab.title, '测试请求');

      final col = ApiCollection(name: '微服务集合');
      final colTab = WorkbenchTab.container(col, isCollection: true);
      expect(colTab.type, TabType.container);
      expect(colTab.isCollection, isTrue);
      expect(colTab.title, '微服务集合');
    });

    test('JsonSyntaxHighlightController 构造与文本 Span 高亮分词', () {
      final controller = JsonSyntaxHighlightController(
        text: '{"status": 200, "success": true, "data": null}',
      );
      expect(controller.text.isNotEmpty, isTrue);
    });
  });

  testWidgets('MindPostApp 初始渲染烟雾测试', (WidgetTester tester) async {
    await tester.pumpWidget(const MindPostApp());
    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
