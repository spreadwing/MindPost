import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;
import '../models/workspace.dart';
import '../models/api_collection.dart';
import '../models/api_request.dart';
import '../models/s3_sync_config.dart';
import '../models/workbench_tab.dart';

class StorageService {
  final Directory? _customDir;

  StorageService({this._customDir});

  Future<String> _getWorkspaceDirPath() async {
    return _getWorkspaceDirPathSync();
  }

  String _getWorkspaceDirPathSync() {
    final customDir = _customDir;
    if (customDir != null) {
      return customDir.path;
    }
    // 优先检查本地当前运行目录下的 .mindpost
    final currentDirMindpost =
        Directory(p.join(Directory.current.path, '.mindpost'));
    if (currentDirMindpost.existsSync()) {
      return Directory.current.path;
    }
    final userProfile =
        Platform.environment['USERPROFILE'] ?? Platform.environment['HOME'];
    if (userProfile != null && userProfile.isNotEmpty) {
      return p.join(userProfile, 'Documents', 'MindPost');
    }
    return Directory.current.path;
  }

  Future<void> _migrateLegacyIfNeeded(Directory mindpostDir) async {
    if (await mindpostDir.exists()) return;
    final userProfile =
        Platform.environment['USERPROFILE'] ?? Platform.environment['HOME'];
    if (userProfile == null || userProfile.isEmpty) return;
    final legacyDir =
        Directory(p.join(userProfile, 'Documents', 'PostMCP', '.postmcp'));
    if (await legacyDir.exists()) {
      await mindpostDir.create(recursive: true);
      await for (final entity in legacyDir.list()) {
        if (entity is File) {
          final targetPath = p.join(mindpostDir.path, p.basename(entity.path));
          await entity.copy(targetPath);
        }
      }
    }
  }

  /// 加载工作区配置（若无则创建默认 Demo 工作区）
  Future<Workspace> loadWorkspace() async {
    try {
      final baseDirPath = await _getWorkspaceDirPath();
      final mindpostDir = Directory(p.join(baseDirPath, '.mindpost'));
      await _migrateLegacyIfNeeded(mindpostDir);
      final workspaceFile = File(p.join(mindpostDir.path, 'workspace.json'));
      final s3ConfigFile = File(p.join(mindpostDir.path, 's3_config.json'));

      S3SyncConfig? localS3Config;
      if (await s3ConfigFile.exists()) {
        try {
          final s3Raw = await s3ConfigFile.readAsString();
          localS3Config =
              S3SyncConfig.fromJson(json.decode(s3Raw) as Map<String, dynamic>);
        } catch (_) {}
      }

      if (await workspaceFile.exists()) {
        final content = await workspaceFile.readAsString();
        final jsonMap = json.decode(content) as Map<String, dynamic>;
        final ws = Workspace.fromJson(jsonMap);
        if (localS3Config != null && localS3Config.isConfigured) {
          ws.s3Config = localS3Config;
        }
        return ws;
      }
    } catch (_) {
      // 容错降级
    }

    final demo = Workspace.createDemo();
    await saveWorkspace(demo);
    return demo;
  }

  /// 保存工作区配置到本地文件
  Future<void> saveWorkspace(Workspace workspace) async {
    try {
      final baseDirPath = await _getWorkspaceDirPath();
      final mindpostDir = Directory(p.join(baseDirPath, '.mindpost'));
      if (!await mindpostDir.exists()) {
        await mindpostDir.create(recursive: true);
      }

      final workspaceFile = File(p.join(mindpostDir.path, 'workspace.json'));
      const encoder = JsonEncoder.withIndent('  ');
      await workspaceFile.writeAsString(encoder.convert(workspace.toJson()));

      final s3ConfigFile = File(p.join(mindpostDir.path, 's3_config.json'));
      await s3ConfigFile
          .writeAsString(encoder.convert(workspace.s3Config.toJson()));
    } catch (_) {
      // 写入失败静默防护
    }
  }

  /// 加载工作台 UI 状态（打开的标签页、激活索引、边侧节点展开集合）
  Future<WorkbenchState?> loadWorkbenchState() async {
    try {
      final baseDirPath = await _getWorkspaceDirPath();
      final stateFile =
          File(p.join(baseDirPath, '.mindpost', 'workbench_state.json'));
      if (await stateFile.exists()) {
        final content = await stateFile.readAsString();
        final jsonMap = json.decode(content) as Map<String, dynamic>;
        return WorkbenchState.fromJson(jsonMap);
      }
    } catch (_) {
      // 读取失败静默降级
    }
    return null;
  }

  /// 保存工作台 UI 状态到本地
  Future<void> saveWorkbenchState(WorkbenchState state) async {
    saveWorkbenchStateSync(state);
  }

  /// 同步保存工作台 UI 状态到本地（确保在进程退出前物理刷盘完成）
  void saveWorkbenchStateSync(WorkbenchState state) {
    try {
      final baseDirPath = _getWorkspaceDirPathSync();
      final mindpostDir = Directory(p.join(baseDirPath, '.mindpost'));
      if (!mindpostDir.existsSync()) {
        mindpostDir.createSync(recursive: true);
      }

      final stateFile =
          File(p.join(mindpostDir.path, 'workbench_state.json'));
      const encoder = JsonEncoder.withIndent('  ');
      stateFile.writeAsStringSync(encoder.convert(state.toJson()), flush: true);
    } catch (_) {
      // 写入失败静默防护
    }
  }

  /// 导出为 Postman Collection v2.1 格式 JSON
  static String exportPostmanCollection(ApiCollection collection) {
    final item = collection.requests.map((r) {
      return {
        'name': r.name,
        'request': {
          'method': r.method.nameString,
          'header': r.headers
              .where((h) => h.isEnabled)
              .map((h) => {'key': h.key, 'value': h.value})
              .toList(),
          'url': {
            'raw': r.url,
          },
          'body': r.bodyType == BodyType.json
              ? {
                  'mode': 'raw',
                  'raw': r.bodyContent,
                  'options': {
                    'raw': {'language': 'json'}
                  }
                }
              : null,
          'description': r.description,
        },
      };
    }).toList();

    final postmanJson = {
      'info': {
        'name': collection.name,
        'description': collection.description,
        'schema':
            'https://schema.getpostman.com/json/collection/v2.1.0/collection.json',
      },
      'item': item,
    };

    return const JsonEncoder.withIndent('  ').convert(postmanJson);
  }
}
