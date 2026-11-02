import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:mindpost/models/api_collection.dart';
import 'package:mindpost/models/api_folder.dart';
import 'package:mindpost/models/api_request.dart';
import 'package:mindpost/models/workbench_tab.dart';
import 'package:mindpost/models/workspace.dart';
import 'package:mindpost/services/storage_service.dart';

void main() {
  test('WorkbenchState 持久化及工作区请求跨层级定位测试', () async {
    final tempDir = await Directory.systemTemp.createTemp('mindpost_wb_test_');
    final storage = StorageService(customDir: tempDir);

    final req1 = ApiRequest(name: '获取用户信息', url: '/user/info');
    final req2 = ApiRequest(name: '提交订单', url: '/order/submit');
    final subFolder = ApiFolder(name: '订单子模块', requests: [req2]);
    final rootFolder = ApiFolder(name: '业务模块', folders: [subFolder]);
    final col = ApiCollection(
      name: '生产服务',
      requests: [req1],
      folders: [rootFolder],
    );
    final ws = Workspace(name: '测试工作区', collections: [col]);

    expect(ws.findRequestById(req1.id), isNotNull);
    expect(ws.findRequestById(req2.id), isNotNull);
    expect(ws.findContainerById(subFolder.id, isCollection: false), isNotNull);
    expect(ws.findContainerById(col.id, isCollection: true), isNotNull);

    // 保存工作台状态
    final state = WorkbenchState(
      openTabs: [
        WorkbenchTabState(id: req1.id, type: 'request'),
        WorkbenchTabState(id: req2.id, type: 'request'),
        WorkbenchTabState(id: subFolder.id, type: 'container', isCollection: false),
      ],
      activeTabIndex: 1,
      expandedNodeIds: [col.id, rootFolder.id, subFolder.id],
    );

    storage.saveWorkbenchStateSync(state);

    final loaded = await storage.loadWorkbenchState();
    expect(loaded, isNotNull);
    expect(loaded!.openTabs.length, 3);
    expect(loaded.activeTabIndex, 1);
    expect(loaded.expandedNodeIds, contains(subFolder.id));

    // 验证根据保存状态能否正确恢复 WorkbenchTab
    final restoredTabs = <WorkbenchTab>[];
    for (final ts in loaded.openTabs) {
      if (ts.type == 'request') {
        final r = ws.findRequestById(ts.id);
        if (r != null) restoredTabs.add(WorkbenchTab.request(r));
      } else {
        final c = ws.findContainerById(ts.id, isCollection: ts.isCollection);
        if (c != null) {
          restoredTabs.add(WorkbenchTab.container(c, isCollection: ts.isCollection));
        }
      }
    }

    expect(restoredTabs.length, 3);
    expect(restoredTabs[0].id, req1.id);
    expect(restoredTabs[1].id, req2.id);
    expect(restoredTabs[2].id, subFolder.id);

    await tempDir.delete(recursive: true);
  });
}
