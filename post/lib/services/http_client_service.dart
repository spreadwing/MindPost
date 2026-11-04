import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:path/path.dart' as p;
import '../models/api_request.dart';
import '../models/api_response.dart';
import '../models/workspace.dart';
import '../models/api_collection.dart';
import '../models/api_container.dart';
import '../engine/variable_resolver.dart';
import '../engine/script_engine.dart';

class ExecutionResult {
  final ApiResponse response;
  final String resolvedUrl;
  final Map<String, String> resolvedHeaders;
  final String resolvedBody;
  final Map<String, String> updatedEnvironmentVariables;

  ExecutionResult({
    required this.response,
    required this.resolvedUrl,
    required this.resolvedHeaders,
    required this.resolvedBody,
    required this.updatedEnvironmentVariables,
  });
}

class HttpClientService {
  final Dio _dio;

  HttpClientService()
      : _dio = Dio(
          BaseOptions(
            connectTimeout: const Duration(minutes: 10),
            receiveTimeout: null, // 关键：null 代表无超时限制，长请求保持与接口连接不断开
            sendTimeout: null,    // 不限发送数据超时
            validateStatus: (status) => true, // 允许所有状态码（包括 4xx/5xx）正常返回供调试
            responseType: ResponseType.plain,
            persistentConnection: true, // HTTP 保持长连接
          ),
        ) {
    // 显式替换底层的 httpClientAdapter，注入长连接与高并发连接池配置
    _dio.httpClientAdapter = IOHttpClientAdapter(
      createHttpClient: () {
        final client = HttpClient();
        client.idleTimeout = const Duration(hours: 2); // 延长空闲长连接保活时间至 2 小时
        client.connectionTimeout = const Duration(minutes: 10);
        client.maxConnectionsPerHost = 100; // 提高单域名最大长连接并发与连接池复用上限
        client.autoUncompress = true;
        client.badCertificateCallback = (cert, host, port) => true; // 允许测试环境自签名证书
        return client;
      },
    );
  }

  /// 执行完整的请求生命周期流水线（支持父级集合与目录级联继承）
  Future<ExecutionResult> executeRequest({
    required ApiRequest request,
    required Workspace workspace,
    ApiCollection? collection,
    CancelToken? cancelToken,
  }) async {
    final startTime = DateTime.now();
    final allConsoleLogs = <String>[];

    // 0. 查找目标请求所属的父容器链 (Root Collection -> 各级 Folder)
    List<ApiContainer> parentChain = [];
    if (collection != null) {
      parentChain = collection.findParentChainForRequest(request.id);
    } else {
      for (final col in workspace.collections) {
        if (col.findRequestById(request.id) != null) {
          parentChain = col.findParentChainForRequest(request.id);
          break;
        }
      }
    }

    // 1. 构建初始级联变量表 (Global -> Environment -> Containers Chain -> Request)
    final envVars = VariableResolver.buildVariableMap(
      workspace: workspace,
      collection: collection,
      parentContainers: parentChain,
    );
    final globalVars = {
      for (final g in workspace.globalVariables)
        if (g.isEnabled) g.key: g.value
    };

    // 2. 依次执行父容器链与请求自身的前置脚本 (Pre-request Script)
    final updatedEnv = <String, String>{};
    final extraHeaders = <KeyValueItem>[];
    final extraParams = <KeyValueItem>[];

    // 2.1 自顶向下执行父容器链（集合/目录）前置脚本
    for (final container in parentChain) {
      final cScript = container.preRequestScript;
      if (cScript.trim().isNotEmpty) {
        allConsoleLogs.add('[PRE-SCRIPT] 执行容器【${container.name}】前置脚本');
        final scriptResult = await ScriptEngine.executePreRequestScript(
          script: cScript,
          request: request,
          environmentVariables: envVars,
          globalVariables: globalVars,
        );
        allConsoleLogs.addAll(scriptResult.consoleLogs);
        updatedEnv.addAll(scriptResult.updatedEnvironmentVariables);
        extraHeaders.addAll(scriptResult.additionalHeaders);
        extraParams.addAll(scriptResult.additionalParams);
        envVars.addAll(scriptResult.updatedEnvironmentVariables);
      }
    }

    // 2.2 执行当前请求自身的前置脚本
    if (request.preRequestScript.trim().isNotEmpty) {
      allConsoleLogs.add('[PRE-SCRIPT] 执行请求【${request.name}】前置脚本');
      final scriptResult = await ScriptEngine.executePreRequestScript(
        script: request.preRequestScript,
        request: request,
        environmentVariables: envVars,
        globalVariables: globalVars,
      );
      allConsoleLogs.addAll(scriptResult.consoleLogs);
      updatedEnv.addAll(scriptResult.updatedEnvironmentVariables);
      extraHeaders.addAll(scriptResult.additionalHeaders);
      extraParams.addAll(scriptResult.additionalParams);
      envVars.addAll(scriptResult.updatedEnvironmentVariables);
    }

    // 3. 解析最终 URL
    final activeBaseUrl = workspace.activeEnvironment?.baseUrl;
    String finalUrl = VariableResolver.resolveUrl(
      rawUrl: request.url,
      variables: envVars,
      currentBaseUrl: activeBaseUrl,
    );

    // 4. 解析 Query Parameters（若 URL 已带查询串且与 Params 列表同时存在，自动合并去重）
    final queryParams = <String, dynamic>{};
    final qMarkIdx = finalUrl.indexOf('?');
    if (qMarkIdx >= 0) {
      final rawQuery = finalUrl.substring(qMarkIdx + 1);
      finalUrl = finalUrl.substring(0, qMarkIdx);
      for (final seg in rawQuery.split('&')) {
        if (seg.trim().isEmpty) continue;
        final eqIdx = seg.indexOf('=');
        final k = eqIdx >= 0 ? seg.substring(0, eqIdx) : seg;
        final v = eqIdx >= 0 ? seg.substring(eqIdx + 1) : '';
        if (k.isNotEmpty) {
          queryParams[Uri.decodeQueryComponent(k)] =
              Uri.decodeQueryComponent(v);
        }
      }
    }
    for (final p in [...request.params, ...extraParams]) {
      if (p.isEnabled && p.key.isNotEmpty) {
        queryParams[VariableResolver.interpolate(p.key, envVars)] =
            VariableResolver.interpolate(p.value, envVars);
      }
    }

    // 5. 级联继承父容器公共 Headers，随后由请求自身 Headers 覆盖
    final inheritedHeaders = <String, KeyValueItem>{};
    for (final container in parentChain) {
      for (final h in container.headers) {
        if (h.isEnabled && h.key.isNotEmpty) {
          inheritedHeaders[h.key] = h;
        }
      }
    }
    // 请求自身 Headers 覆盖父级同名 Header
    for (final h in [...request.headers, ...extraHeaders]) {
      if (h.isEnabled && h.key.isNotEmpty) {
        inheritedHeaders[h.key] = h;
      }
    }

    final headers = <String, dynamic>{};
    for (final h in inheritedHeaders.values) {
      headers[VariableResolver.interpolate(h.key, envVars)] =
          VariableResolver.interpolate(h.value, envVars);
    }

    // 默认保持持久长连接 Keep-Alive 请求头（若用户未显式覆盖 Connection / Keep-Alive 头）
    if (!headers.keys.any((k) => k.toLowerCase() == 'connection')) {
      headers['Connection'] = 'keep-alive';
    }
    if (!headers.keys.any((k) => k.toLowerCase() == 'keep-alive')) {
      headers['Keep-Alive'] = 'timeout=3600, max=1000';
    }

    // 6. 解析 Request Body
    dynamic bodyData;
    String finalResolvedBody = '';

    switch (request.bodyType) {
      case BodyType.none:
        bodyData = null;
        break;
      case BodyType.json:
      case BodyType.raw:
        finalResolvedBody =
            VariableResolver.interpolate(request.bodyContent, envVars);
        bodyData = finalResolvedBody;
        if (!headers.containsKey('Content-Type') &&
            !headers.containsKey('content-type')) {
          switch (request.rawFormat.toLowerCase()) {
            case 'xml':
              headers['Content-Type'] = 'application/xml';
              break;
            case 'html':
              headers['Content-Type'] = 'text/html';
              break;
            case 'javascript':
              headers['Content-Type'] = 'application/javascript';
              break;
            case 'text':
              headers['Content-Type'] = 'text/plain';
              break;
            case 'json':
            default:
              headers['Content-Type'] = 'application/json';
              break;
          }
        }
        break;
      case BodyType.formUrlEncoded:
        final map = <String, String>{};
        for (final f in request.formDataFields) {
          if (f.isEnabled && f.key.isNotEmpty) {
            map[VariableResolver.interpolate(f.key, envVars)] =
                VariableResolver.interpolate(f.value, envVars);
          }
        }
        bodyData = map;
        finalResolvedBody = json.encode(map);
        headers['Content-Type'] = 'application/x-www-form-urlencoded';
        break;
      case BodyType.formData:
        final map = <String, dynamic>{};
        for (final f in request.formDataFields) {
          if (f.isEnabled && f.key.isNotEmpty) {
            final fieldKey = VariableResolver.interpolate(f.key, envVars);
            final fieldVal = VariableResolver.interpolate(f.value, envVars);

            if (f.type == 'file' && fieldVal.isNotEmpty) {
              final file = File(fieldVal);
              if (await file.exists()) {
                map[fieldKey] = await MultipartFile.fromFile(
                  fieldVal,
                  filename: p.basename(fieldVal),
                );
              } else {
                map[fieldKey] = fieldVal;
              }
            } else {
              map[fieldKey] = fieldVal;
            }
          }
        }
        bodyData = FormData.fromMap(map);
        finalResolvedBody = json.encode({
          for (final entry in map.entries)
            entry.key: entry.value is MultipartFile
                ? '[File: ${(entry.value as MultipartFile).filename}]'
                : entry.value
        });
        break;
    }

    // 7. 发送 HTTP 请求
    ApiResponse apiResponse;
    try {
      final response = await _dio.request<dynamic>(
        finalUrl,
        data: bodyData,
        queryParameters: queryParams.isNotEmpty ? queryParams : null,
        options: Options(
          method: request.method.nameString,
          headers: headers,
          persistentConnection: true, // 启用长连接
          receiveTimeout: null,       // 长请求不限制接收超时，保持接口连接不断开
          sendTimeout: null,          // 不限制发送数据超时
        ),
        cancelToken: cancelToken,
      );

      final durationMs =
          DateTime.now().difference(startTime).inMilliseconds;
      final responseHeaders = <String, String>{};
      response.headers.forEach((k, v) {
        responseHeaders[k] = v.join(', ');
      });

      final bodyStr = response.data?.toString() ?? '';
      final sizeBytes = utf8.encode(bodyStr).length;

      // 8. 依次执行父容器链与请求自身后置测试与断言脚本 (Tests / Assertions)
      final testResults = <TestAssertionResult>[];

      // 8.1 自顶向下执行父容器测试脚本
      for (final container in parentChain) {
        final cPostScript = container.postRequestScript;
        if (cPostScript.trim().isNotEmpty) {
          allConsoleLogs.add('[TESTS] 执行容器【${container.name}】后置断言');
          final postResult = await ScriptEngine.executePostRequestScript(
            script: cPostScript,
            response: ApiResponse(
              statusCode: response.statusCode ?? 200,
              statusMessage: response.statusMessage ?? 'OK',
              headers: responseHeaders,
              body: bodyStr,
              durationMs: durationMs,
              sizeBytes: sizeBytes,
            ),
            environmentVariables: envVars,
          );
          allConsoleLogs.addAll(postResult.consoleLogs);
          testResults.addAll(postResult.testResults);
          updatedEnv.addAll(postResult.updatedEnvironmentVariables);
        }
      }

      // 8.2 执行当前请求自身后置测试脚本
      if (request.postRequestScript.trim().isNotEmpty) {
        allConsoleLogs.add('[TESTS] 执行请求【${request.name}】后置断言');
        final postResult = await ScriptEngine.executePostRequestScript(
          script: request.postRequestScript,
          response: ApiResponse(
            statusCode: response.statusCode ?? 200,
            statusMessage: response.statusMessage ?? 'OK',
            headers: responseHeaders,
            body: bodyStr,
            durationMs: durationMs,
            sizeBytes: sizeBytes,
          ),
          environmentVariables: envVars,
        );
        allConsoleLogs.addAll(postResult.consoleLogs);
        testResults.addAll(postResult.testResults);
        updatedEnv.addAll(postResult.updatedEnvironmentVariables);
      }

      apiResponse = ApiResponse(
        statusCode: response.statusCode ?? 200,
        statusMessage: response.statusMessage ?? 'OK',
        headers: responseHeaders,
        body: bodyStr,
        durationMs: durationMs,
        sizeBytes: sizeBytes,
        consoleLogs: allConsoleLogs,
        testResults: testResults,
      );
    } on DioException catch (e) {
      final durationMs =
          DateTime.now().difference(startTime).inMilliseconds;
      String errorMsg = e.message ?? e.toString();
      if (e.type == DioExceptionType.cancel) {
        errorMsg = '请求已被用户取消';
      } else if (e.type == DioExceptionType.connectionTimeout) {
        errorMsg = '连接超时 (Connection Timeout)，无法连接到目标服务器';
      } else if (e.type == DioExceptionType.sendTimeout) {
        errorMsg = '发送数据超时 (Send Timeout)';
      } else if (e.type == DioExceptionType.receiveTimeout) {
        errorMsg = '响应接收超时 (Receive Timeout)';
      } else if (e.type == DioExceptionType.connectionError) {
        errorMsg = '长请求连接断开或网络异常 (Connection Error): $errorMsg';
      }
      allConsoleLogs.add('[NETWORK_ERROR] $errorMsg');

      apiResponse = ApiResponse.error(
        error: errorMsg,
        durationMs: durationMs,
        consoleLogs: allConsoleLogs,
      );
    } catch (e) {
      final durationMs =
          DateTime.now().difference(startTime).inMilliseconds;
      allConsoleLogs.add('[UNKNOWN_ERROR] $e');

      apiResponse = ApiResponse.error(
        error: e.toString(),
        durationMs: durationMs,
        consoleLogs: allConsoleLogs,
      );
    }

    return ExecutionResult(
      response: apiResponse,
      resolvedUrl: finalUrl,
      resolvedHeaders: headers.map((k, v) => MapEntry(k, v.toString())),
      resolvedBody: finalResolvedBody,
      updatedEnvironmentVariables: updatedEnv,
    );
  }

  /// 释放底层 HTTP 连接池资源
  void dispose() {
    _dio.close(force: true);
  }
}
