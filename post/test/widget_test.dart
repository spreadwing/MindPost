import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postmcp/engine/variable_resolver.dart';
import 'package:postmcp/models/workspace.dart';
import 'package:postmcp/main.dart';

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
  });

  testWidgets('PostMcpApp 初始加载态烟雾测试', (WidgetTester tester) async {
    await tester.pumpWidget(const PostMcpApp());
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });
}
