import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mindpost/models/workspace.dart';
import 'package:mindpost/ui/widgets/help_dialog.dart';

void main() {
  group('HelpDialog 帮助中心弹窗组件测试', () {
    late Workspace workspace;
    late bool workspaceChanged;

    setUp(() {
      workspace = Workspace.createDemo();
      workspace.doubleClickToCloseTab = true;
      workspace.showUrlPreviewBar = true;
      workspaceChanged = false;
    });

    testWidgets('HelpDialog 渲染并展示 6 个核心导航分类', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: HelpDialog(
              workspace: workspace,
              onWorkspaceChanged: () {
                workspaceChanged = true;
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 验证左侧分类导航
      expect(find.text('帮助中心'), findsOneWidget);
      expect(find.text('交互与快捷键'), findsAtLeastNWidgets(1));
      expect(find.text('快速上手指南'), findsOneWidget);
      expect(find.text('变量与内置函数'), findsOneWidget);
      expect(find.text('AI 助手与 MCP'), findsOneWidget);
      expect(find.text('S3 云端多端同步'), findsOneWidget);
      expect(find.text('关于 MindPost'), findsOneWidget);

      // 验证默认选中的是「交互与快捷键」
      expect(find.text('鼠标与标签页交互配置'), findsOneWidget);
      expect(find.text('双击标签页关闭'), findsOneWidget);
      expect(find.text('显示解析后请求目标栏'), findsOneWidget);
      expect(find.text('常用全局快捷键速查'), findsOneWidget);
    });

    testWidgets('切换开关能正确更新 Workspace 并触发回调', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: HelpDialog(
              workspace: workspace,
              onWorkspaceChanged: () {
                workspaceChanged = true;
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 找到 Switch 并点击
      final switches = find.byType(Switch);
      expect(switches, findsNWidgets(2));

      // 点击第一个 Switch (双击标签页关闭)
      await tester.tap(switches.first);
      await tester.pumpAndSettle();

      expect(workspace.doubleClickToCloseTab, isFalse);
      expect(workspaceChanged, isTrue);

      // 点击第二个 Switch (显示解析后请求目标栏)
      workspaceChanged = false;
      await tester.tap(switches.last);
      await tester.pumpAndSettle();

      expect(workspace.showUrlPreviewBar, isFalse);
      expect(workspaceChanged, isTrue);
    });

    testWidgets('切换至其他分类页签能正确渲染对应内容', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: HelpDialog(
              workspace: workspace,
              onWorkspaceChanged: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 切换到快速上手指南
      await tester.tap(find.text('快速上手指南'));
      await tester.pumpAndSettle();
      expect(find.text('欢迎使用 MindPost'), findsOneWidget);
      expect(find.text('1. 接口与集合组织架构'), findsOneWidget);

      // 切换到变量与内置函数
      await tester.tap(find.text('变量与内置函数'));
      await tester.pumpAndSettle();
      expect(find.text('双大括号插值语法'), findsOneWidget);
      expect(find.text('系统内置动态变量'), findsOneWidget);

      // 切换到 AI 助手与 MCP
      await tester.tap(find.text('AI 助手与 MCP'));
      await tester.pumpAndSettle();
      expect(find.text('AI 智能助手 (Copilot)'), findsOneWidget);
      expect(find.text('内置标准 MCP (Model Context Protocol) 协议'), findsOneWidget);

      // 切换到 S3 云端多端同步
      await tester.tap(find.text('S3 云端多端同步'));
      await tester.pumpAndSettle();
      expect(find.text('为什么采用 S3 协议进行云端同步？'), findsOneWidget);

      // 切换到关于 MindPost
      await tester.tap(find.text('关于 MindPost'));
      await tester.pumpAndSettle();
      expect(find.text('MindPost Desktop'), findsOneWidget);
      expect(find.text('设计理念与核心优势'), findsOneWidget);
    });
  });
}
