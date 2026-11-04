import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mindpost/models/api_request.dart';
import 'package:mindpost/models/workspace.dart';
import 'package:mindpost/services/http_client_service.dart';
import 'package:mindpost/ui/widgets/status_badge.dart';

void main() {
  group('HttpClientService 长请求保持连接测试', () {
    test('HttpClientService 实例化及默认 Keep-Alive 长连接请求头自动补全', () async {
      final service = HttpClientService();
      final workspace = Workspace(name: '测试工作区');
      final req = ApiRequest(
        name: '测试请求',
        url: 'http://127.0.0.1:9999/dummy-test-endpoint',
        method: HttpMethod.get,
      );

      // 执行时目标无法连通会抛出连接错误，但我们可捕获返回并验证执行流程
      final result = await service.executeRequest(
        request: req,
        workspace: workspace,
      );

      expect(result.resolvedHeaders['Connection'], equals('keep-alive'));
      expect(result.resolvedHeaders['Keep-Alive'], equals('timeout=3600, max=1000'));
    });

    test('当用户显式指定 Connection 头时保留用户设置', () async {
      final service = HttpClientService();
      final workspace = Workspace(name: '测试工作区');
      final req = ApiRequest(
        name: '自定义短连接请求',
        url: 'http://127.0.0.1:9999/dummy-test-endpoint',
        method: HttpMethod.get,
        headers: [
          KeyValueItem(key: 'Connection', value: 'close'),
        ],
      );

      final result = await service.executeRequest(
        request: req,
        workspace: workspace,
      );

      expect(result.resolvedHeaders['Connection'], equals('close'));
    });
  });

  group('RequestPendingBadge 状态徽章渲染测试', () {
    testWidgets('渲染正在请求中状态徽章', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: RequestPendingBadge(label: '正在请求...'),
          ),
        ),
      );

      expect(find.text('正在请求...'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });
  });
}
