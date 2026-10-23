import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mindpost/models/workspace.dart';
import 'package:mindpost/ui/folder_theme_config.dart';

void main() {
  group('FolderThemeConfig 单元与组件测试', () {
    test('默认配置应为柔和科技蓝与双色调 (Duotone)', () {
      final config = FolderThemeConfig.standard();
      expect(config.colorPreset.id, equals('blue'));
      expect(config.colorPreset.primaryColor, equals(const Color(0xFF3B82F6)));
      expect(config.iconStyle, equals(FolderIconStyle.duotone));
    });

    test('6 种预设配色方案正常解析', () {
      expect(FolderColorPreset.presets.length, equals(6));

      final blue = FolderColorPreset.fromId('blue');
      expect(blue.primaryColor, equals(const Color(0xFF3B82F6)));

      final amber = FolderColorPreset.fromId('amber');
      expect(amber.primaryColor, equals(const Color(0xFFF59E0B)));

      final slate = FolderColorPreset.fromId('slate');
      expect(slate.primaryColor, equals(const Color(0xFF64748B)));

      final emerald = FolderColorPreset.fromId('emerald');
      expect(emerald.primaryColor, equals(const Color(0xFF10B981)));

      final purple = FolderColorPreset.fromId('purple');
      expect(purple.primaryColor, equals(const Color(0xFF8B5CF6)));

      final system = FolderColorPreset.fromId('system');
      expect(system.isSystem, isTrue);
    });

    test('Workspace 序列化与反序列化持久化字段', () {
      final ws = Workspace(
        name: '测试工作区',
        folderColorTheme: 'emerald',
        folderIconStyle: 'outlined',
      );

      final json = ws.toJson();
      expect(json['folderColorTheme'], equals('emerald'));
      expect(json['folderIconStyle'], equals('outlined'));

      final restored = Workspace.fromJson(json);
      expect(restored.folderColorTheme, equals('emerald'));
      expect(restored.folderIconStyle, equals('outlined'));
    });

    testWidgets('FolderThemeIcon 双色调 (Duotone) 使用双层 Stack 渲染',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: FolderThemeIcon(
              isExpanded: false,
              size: 20,
              config: FolderThemeConfig(
                colorPreset: FolderColorPreset(
                  id: 'blue',
                  name: '柔和科技蓝',
                  primaryColor: Color(0xFF3B82F6),
                  duotoneOpacity: 0.15,
                ),
                iconStyle: FolderIconStyle.duotone,
              ),
            ),
          ),
        ),
      );

      expect(find.byType(Stack), findsOneWidget);
      expect(find.byIcon(Icons.folder_rounded), findsOneWidget);
      expect(find.byIcon(Icons.folder_outlined), findsOneWidget);
    });

    testWidgets('FolderThemeIcon 纯线性 (Outlined) 渲染', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: FolderThemeIcon(
              isExpanded: true,
              size: 18,
              config: FolderThemeConfig(
                colorPreset: FolderColorPreset(
                  id: 'purple',
                  name: '优雅幻影紫',
                  primaryColor: Color(0xFF8B5CF6),
                  duotoneOpacity: 0.15,
                ),
                iconStyle: FolderIconStyle.outlined,
              ),
            ),
          ),
        ),
      );

      expect(find.byType(Stack), findsNothing);
      expect(find.byIcon(Icons.folder_open_outlined), findsOneWidget);
    });

    testWidgets('FolderThemeIcon 经典实心 (Filled) 渲染', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: FolderThemeIcon(
              isExpanded: false,
              size: 16,
              config: FolderThemeConfig(
                colorPreset: FolderColorPreset(
                  id: 'amber',
                  name: '经典琥珀橙',
                  primaryColor: Color(0xFFF59E0B),
                  duotoneOpacity: 0.18,
                ),
                iconStyle: FolderIconStyle.filled,
              ),
            ),
          ),
        ),
      );

      expect(find.byType(Stack), findsNothing);
      expect(find.byIcon(Icons.folder_rounded), findsOneWidget);
    });
  });
}
