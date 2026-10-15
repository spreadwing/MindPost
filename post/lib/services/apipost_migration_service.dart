import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;
import '../models/api_collection.dart';
import '../models/api_folder.dart';
import '../models/api_request.dart';
import '../models/environment.dart';

class ApipostMigrationResult {
  final List<ApiCollection> collections;
  final int projectCount;
  final int folderCount;
  final int apiCount;

  ApipostMigrationResult({
    required this.collections,
    required this.projectCount,
    required this.folderCount,
    required this.apiCount,
  });
}

/// 通过 Apipost 单机版 MCP 协议/桥接服务将接口与目录全量迁移至当前项目
class ApipostMigrationService {
  static String get defaultMcpConfigPath {
    final appData = Platform.environment['APPDATA'];
    if (appData != null && appData.isNotEmpty) {
      return p.join(
        appData,
        'Apipost单机版',
        'offline-data-local',
        'settings',
        'mcp_config.json',
      );
    }
    return r'C:\Users\zy\AppData\Roaming\Apipost单机版\offline-data-local\settings\mcp_config.json';
  }

  /// 调用 Apipost 本地 MCP Bridge
  static Future<Map<String, dynamic>> _callBridge({
    required int port,
    required String token,
    required String method,
    required Map<String, dynamic> params,
  }) async {
    final socket = await Socket.connect(
      '127.0.0.1',
      port,
      timeout: const Duration(seconds: 15),
    );

    final completer = Completer<Map<String, dynamic>>();
    final buffer = StringBuffer();

    late StreamSubscription<String> sub;
    sub = utf8.decoder.bind(socket).listen(
      (chunk) {
        buffer.write(chunk);
        final current = buffer.toString();
        final newlineIdx = current.indexOf('\n');
        if (newlineIdx >= 0 && !completer.isCompleted) {
          final line = current.substring(0, newlineIdx);
          try {
            final decoded = json.decode(line) as Map<String, dynamic>;
            if (decoded['error'] != null) {
              completer.completeError(Exception(decoded['error'].toString()));
            } else {
              completer.complete(decoded);
            }
          } catch (e) {
            completer.completeError(e);
          } finally {
            sub.cancel();
            socket.destroy();
          }
        }
      },
      onError: (Object err) {
        if (!completer.isCompleted) {
          completer.completeError(err);
        }
        socket.destroy();
      },
      onDone: () {
        if (!completer.isCompleted) {
          final remaining = buffer.toString().trim();
          if (remaining.isNotEmpty) {
            try {
              final decoded = json.decode(remaining) as Map<String, dynamic>;
              completer.complete(decoded);
              return;
            } catch (_) {}
          }
          completer.completeError(Exception('Apipost MCP 连接提前关闭'));
        }
      },
      cancelOnError: true,
    );

    final payload = json.encode({
      'token': token,
      'method': method,
      'params': params,
    });
    socket.write('$payload\n');

    return completer.future.timeout(
      const Duration(seconds: 30),
      onTimeout: () {
        socket.destroy();
        throw Exception('Apipost MCP 请求超时: $method');
      },
    );
  }

  /// 从 Apipost MCP 执行全量项目目录与接口迁移
  static Future<ApipostMigrationResult> migrateFromMcp({
    String? configPath,
    void Function(int completed, int total, String itemName)? onProgress,
  }) async {
    final cfgFile = File(configPath ?? defaultMcpConfigPath);
    if (!await cfgFile.exists()) {
      throw Exception('未找到 Apipost MCP 配置文件: ${cfgFile.path}');
    }

    final cfgMap =
        json.decode(await cfgFile.readAsString()) as Map<String, dynamic>;
    final enabled = cfgMap['enabled'] == true;
    final port = cfgMap['port'] as int?;
    final token = cfgMap['token'] as String?;

    if (!enabled || port == null || token == null || token.isEmpty) {
      throw Exception('Apipost MCP 未启用或配置不完整，请确认 Apipost 单机版已开启 MCP');
    }

    // 1. 获取已授权项目列表
    final projectsRes = await _callBridge(
      port: port,
      token: token,
      method: 'apipost_list_projects',
      params: {},
    );
    final projects = (projectsRes['projects'] as List<dynamic>?)
            ?.whereType<Map<String, dynamic>>()
            .toList() ??
        [];

    if (projects.isEmpty) {
      throw Exception('Apipost MCP 中没有已授权的项目');
    }

    final migratedCollections = <ApiCollection>[];
    int totalFoldersCount = 0;
    int totalApisCount = 0;

    for (final proj in projects) {
      final projectId = proj['project_id']?.toString() ?? '';
      final projectName = proj['name']?.toString() ?? 'Apipost 项目';
      if (projectId.isEmpty) continue;

      // 2. 获取该项目下的所有目录与接口清单
      final listRes = await _callBridge(
        port: port,
        token: token,
        method: 'apipost_list_apis',
        params: {'project_id': projectId},
      );
      final rawItems = (listRes['apis'] as List<dynamic>?)
              ?.whereType<Map<String, dynamic>>()
              .toList() ??
          [];

      // 按 sort 字段升序排序
      rawItems.sort((a, b) {
        final sa = (a['sort'] as num?)?.toInt() ?? 0;
        final sb = (b['sort'] as num?)?.toInt() ?? 0;
        return sa.compareTo(sb);
      });

      // 3. 批量拉取每个节点的完整详情
      final detailMap = <String, Map<String, dynamic>>{};
      int completed = 0;
      const batchSize = 8;

      for (int i = 0; i < rawItems.length; i += batchSize) {
        final end =
            (i + batchSize < rawItems.length) ? i + batchSize : rawItems.length;
        final batch = rawItems.sublist(i, end);

        await Future.wait(batch.map((item) async {
          final targetId = item['target_id']?.toString() ?? '';
          final itemName = item['name']?.toString() ?? '';
          if (targetId.isEmpty) return;
          try {
            final detailRes = await _callBridge(
              port: port,
              token: token,
              method: 'apipost_get_api_detail',
              params: {
                'project_id': projectId,
                'target_id': targetId,
              },
            );
            final apiObj = detailRes['api'];
            if (apiObj is Map<String, dynamic>) {
              detailMap[targetId] = apiObj;
            }
          } catch (_) {
            // 若单个详情失败，降级使用列表基础信息
            detailMap[targetId] = item;
          } finally {
            completed++;
            onProgress?.call(completed, rawItems.length, itemName);
          }
        }));
      }

      // 4. 先梳理所有 folder 节点与 api 节点
      final folderSummaries = rawItems
          .where((item) => item['target_type']?.toString() == 'folder')
          .toList();
      final apiSummaries = rawItems
          .where((item) => item['target_type']?.toString() == 'api')
          .toList();

      totalFoldersCount += folderSummaries.length;
      totalApisCount += apiSummaries.length;

      final folderIdSet =
          folderSummaries.map((f) => f['target_id'].toString()).toSet();

      // 判断哪些 folder 是顶层目录 (parent_id == '0' 或父节点不在 folderIdSet 中)
      final topFolderIds = <String>{};
      final topCollectionsById = <String, ApiCollection>{};
      final subFoldersById = <String, ApiFolder>{};

      for (final fSum in folderSummaries) {
        final fid = fSum['target_id']?.toString() ?? '';
        final parentId = fSum['parent_id']?.toString() ?? '0';
        final detail = detailMap[fid] ?? fSum;
        final reqBlock = detail['request'] as Map<String, dynamic>?;

        final headers = _parseKeyValueList(reqBlock?['header']?['parameter']);
        final preScript = _parseTasksScript(reqBlock?['pre_tasks'] as List?);
        final postScript = _parseTasksScript(reqBlock?['post_tasks'] as List?);
        final desc = detail['description']?.toString() ?? '';
        final fname = detail['name']?.toString() ??
            fSum['name']?.toString() ??
            '未命名目录';

        if (parentId == '0' || !folderIdSet.contains(parentId)) {
          topFolderIds.add(fid);
          final col = ApiCollection(
            id: fid,
            name: fname,
            description: desc,
            headers: headers,
            variables: <VariableItem>[],
            preRequestScript: preScript,
            postRequestScript: postScript,
          );
          topCollectionsById[fid] = col;
          migratedCollections.add(col);
        } else {
          subFoldersById[fid] = ApiFolder(
            id: fid,
            name: fname,
            description: desc,
            headers: headers,
            variables: <VariableItem>[],
            preRequestScript: preScript,
            postRequestScript: postScript,
          );
        }
      }

      // 挂载子目录层级关系
      for (final fSum in folderSummaries) {
        final fid = fSum['target_id']?.toString() ?? '';
        if (topFolderIds.contains(fid)) continue;

        final parentId = fSum['parent_id']?.toString() ?? '0';
        final folderObj = subFoldersById[fid];
        if (folderObj == null) continue;

        if (topCollectionsById.containsKey(parentId)) {
          topCollectionsById[parentId]!.folders.add(folderObj);
        } else if (subFoldersById.containsKey(parentId)) {
          subFoldersById[parentId]!.folders.add(folderObj);
        }
      }

      // 若存在直接挂在根目录 (parent_id == '0') 的孤立接口，准备一个项目级默认目录
      ApiCollection? rootFallbackCollection;

      // 挂载所有 API 请求节点
      for (final aSum in apiSummaries) {
        final aid = aSum['target_id']?.toString() ?? '';
        final parentId = aSum['parent_id']?.toString() ?? '0';
        final detail = detailMap[aid] ?? aSum;

        final apiReq = _convertApipostDetailToRequest(aid, aSum, detail);

        if (topCollectionsById.containsKey(parentId)) {
          topCollectionsById[parentId]!.requests.add(apiReq);
        } else if (subFoldersById.containsKey(parentId)) {
          subFoldersById[parentId]!.requests.add(apiReq);
        } else {
          rootFallbackCollection ??= ApiCollection(
            id: 'col_$projectId',
            name: projectName,
          );
          rootFallbackCollection.requests.add(apiReq);
        }
      }

      if (rootFallbackCollection != null) {
        migratedCollections.add(rootFallbackCollection);
      }
    }

    return ApipostMigrationResult(
      collections: migratedCollections,
      projectCount: projects.length,
      folderCount: totalFoldersCount,
      apiCount: totalApisCount,
    );
  }

  static ApiRequest _convertApipostDetailToRequest(
    String targetId,
    Map<String, dynamic> summary,
    Map<String, dynamic> detail,
  ) {
    final name = detail['name']?.toString() ??
        summary['name']?.toString() ??
        '未命名接口';
    final methodStr = detail['method']?.toString() ??
        summary['method']?.toString() ??
        'GET';
    final rawUrl =
        detail['url']?.toString() ?? summary['url']?.toString() ?? '';
    final description = detail['description']?.toString() ?? '';

    final reqBlock = detail['request'] as Map<String, dynamic>?;
    final headers = _parseKeyValueList(reqBlock?['header']?['parameter']);
    final params = _parseKeyValueList(reqBlock?['query']?['parameter']);
    final preScript = _parseTasksScript(reqBlock?['pre_tasks'] as List?);
    final postScript = _parseTasksScript(reqBlock?['post_tasks'] as List?);

    // 清理 URL 中已存在于 params 列表的冗余查询串，避免发送时参数重复拼接
    String cleanUrl = rawUrl;
    final qIndex = rawUrl.indexOf('?');
    if (qIndex >= 0 && params.isNotEmpty) {
      cleanUrl = rawUrl.substring(0, qIndex);
      final queryPart = rawUrl.substring(qIndex + 1);
      for (final seg in queryPart.split('&')) {
        if (seg.trim().isEmpty) continue;
        final eqIdx = seg.indexOf('=');
        final k = eqIdx >= 0 ? seg.substring(0, eqIdx) : seg;
        final v = eqIdx >= 0 ? seg.substring(eqIdx + 1) : '';
        if (k.isNotEmpty && !params.any((p) => p.key == k)) {
          params.add(KeyValueItem(
            key: Uri.decodeQueryComponent(k),
            value: Uri.decodeQueryComponent(v),
          ));
        }
      }
    }

    // 解析 Body
    final bodyBlock = reqBlock?['body'] as Map<String, dynamic>?;
    final mode = (bodyBlock?['mode']?.toString() ?? 'none').toLowerCase();
    final rawBody = bodyBlock?['raw']?.toString() ?? '';
    final bodyParams = bodyBlock?['parameter'] as List<dynamic>?;

    BodyType bodyType = BodyType.none;
    String rawFormat = 'json';
    List<KeyValueItem> formDataFields = [];

    if (mode == 'json') {
      bodyType = BodyType.json;
      rawFormat = 'json';
    } else if (mode == 'urlencoded' || mode == 'x-www-form-urlencoded') {
      bodyType = BodyType.formUrlEncoded;
      formDataFields = _parseFormDataList(bodyParams);
    } else if (mode == 'form-data' || mode == 'formdata') {
      bodyType = BodyType.formData;
      formDataFields = _parseFormDataList(bodyParams);
    } else if (mode == 'xml') {
      bodyType = BodyType.raw;
      rawFormat = 'xml';
    } else if (mode == 'html') {
      bodyType = BodyType.raw;
      rawFormat = 'html';
    } else if (mode == 'javascript' || mode == 'js') {
      bodyType = BodyType.raw;
      rawFormat = 'javascript';
    } else if (mode == 'text' || mode == 'plain' || mode == 'raw') {
      bodyType = BodyType.raw;
      rawFormat = 'text';
    } else {
      bodyType = BodyType.none;
    }

    return ApiRequest(
      id: targetId,
      name: name,
      method: HttpMethodExt.fromString(methodStr),
      url: cleanUrl,
      headers: headers,
      params: params,
      bodyType: bodyType,
      rawFormat: rawFormat,
      bodyContent: rawBody,
      formDataFields: formDataFields,
      preRequestScript: preScript,
      postRequestScript: postScript,
      description: description,
    );
  }

  static List<KeyValueItem> _parseKeyValueList(dynamic rawList) {
    if (rawList is! List) return [];
    final result = <KeyValueItem>[];
    for (final item in rawList) {
      if (item is Map<String, dynamic>) {
        final key = item['key']?.toString().trim() ?? '';
        if (key.isEmpty) continue;
        final val = item['value']?.toString() ?? '';
        final checked = item['is_checked'];
        final isEnabled = checked == null ? true : (checked == 1);
        final desc = item['description']?.toString() ?? '';
        result.add(KeyValueItem(
          key: key,
          value: val,
          isEnabled: isEnabled,
          description: desc,
        ));
      }
    }
    return result;
  }

  static List<KeyValueItem> _parseFormDataList(dynamic rawList) {
    if (rawList is! List) return [];
    final result = <KeyValueItem>[];
    for (final item in rawList) {
      if (item is Map<String, dynamic>) {
        final key = item['key']?.toString().trim() ?? '';
        if (key.isEmpty) continue;
        final val = item['value']?.toString() ?? '';
        final checked = item['is_checked'];
        final isEnabled = checked == null ? true : (checked == 1);
        final fieldType =
            (item['field_type']?.toString() ?? 'text').toLowerCase();
        result.add(KeyValueItem(
          key: key,
          value: val,
          type: fieldType == 'file' ? 'file' : 'text',
          isEnabled: isEnabled,
        ));
      }
    }
    return result;
  }

  static String _parseTasksScript(List<dynamic>? tasks) {
    if (tasks == null || tasks.isEmpty) return '';
    final scripts = <String>[];
    for (final t in tasks) {
      if (t is Map<String, dynamic>) {
        final enabled = t['enabled'] ?? 1;
        final data = t['data']?.toString().trim() ?? '';
        if (enabled == 1 && data.isNotEmpty) {
          scripts.add(data);
        }
      }
    }
    return scripts.join('\n\n');
  }
}
