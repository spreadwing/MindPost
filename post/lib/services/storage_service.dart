import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../models/workspace.dart';
import '../models/api_collection.dart';
import '../models/api_request.dart';

class StorageService {
  final Directory? _customDir;

  StorageService({this._customDir});

  Future<String> _getWorkspaceDirPath() async {
    final customDir = _customDir;
    if (customDir != null) {
      return customDir.path;
    }
    // 优先检查本地当前运行目录下的 .postmcp
    final currentDirPostmcp = Directory(p.join(Directory.current.path, '.postmcp'));
    if (await currentDirPostmcp.exists()) {
      return Directory.current.path;
    }
    final docDir = await getApplicationDocumentsDirectory();
    return p.join(docDir.path, 'PostMCP');
  }

  /// 加载工作区配置（若无则创建默认 Demo 工作区）
  Future<Workspace> loadWorkspace() async {
    try {
      final baseDirPath = await _getWorkspaceDirPath();
      final postmcpDir = Directory(p.join(baseDirPath, '.postmcp'));
      final workspaceFile = File(p.join(postmcpDir.path, 'workspace.json'));

      if (await workspaceFile.exists()) {
        final content = await workspaceFile.readAsString();
        final jsonMap = json.decode(content) as Map<String, dynamic>;
        return Workspace.fromJson(jsonMap);
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
      final postmcpDir = Directory(p.join(baseDirPath, '.postmcp'));
      if (!await postmcpDir.exists()) {
        await postmcpDir.create(recursive: true);
      }

      final workspaceFile = File(p.join(postmcpDir.path, 'workspace.json'));
      const encoder = JsonEncoder.withIndent('  ');
      await workspaceFile.writeAsString(encoder.convert(workspace.toJson()));
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
