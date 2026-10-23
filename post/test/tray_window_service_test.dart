import 'package:flutter_test/flutter_test.dart';
import 'package:mindpost/models/workspace.dart';
import 'package:mindpost/services/tray_window_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('系统托盘与最小化设置测试', () {
    test('Workspace 默认开启关闭缩小到托盘选项', () {
      final ws = Workspace(name: '测试工作区');
      expect(ws.minimizeToTrayOnClose, isTrue);

      final demoWs = Workspace.createDemo();
      expect(demoWs.minimizeToTrayOnClose, isTrue);
    });

    test('Workspace 序列化与反序列化保留 minimizeToTrayOnClose 状态', () {
      final ws = Workspace(
        name: '自定义工作区',
        minimizeToTrayOnClose: false,
      );

      final json = ws.toJson();
      expect(json['minimizeToTrayOnClose'], isFalse);

      final restored = Workspace.fromJson(json);
      expect(restored.minimizeToTrayOnClose, isFalse);

      // 缺失字段时默认回退为 true
      final defaultJson = {'name': '缺失字段工作区'};
      final fallbackWs = Workspace.fromJson(defaultJson);
      expect(fallbackWs.minimizeToTrayOnClose, isTrue);
    });

    test('TrayWindowService 接口与回调行为验证', () async {
      final service = TrayWindowService.instance;
      expect(service, isNotNull);

      bool callbackInvoked = false;
      await service.init(
        shouldMinimizeToTray: () => true,
        onMinimizedToTray: () {
          callbackInvoked = true;
        },
      );

      expect(service.shouldMinimizeToTray?.call(), isTrue);

      // 模拟触发 onWindowClose
      service.onWindowClose();
      // 等待异步完成
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(callbackInvoked, isTrue);
    });
  });
}
