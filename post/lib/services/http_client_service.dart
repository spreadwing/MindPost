import 'dart:convert';
import 'package:dio/dio.dart';
import '../models/api_request.dart';
import '../models/api_response.dart';
import '../models/workspace.dart';
import '../models/api_collection.dart';
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
            connectTimeout: const Duration(seconds: 15),
            receiveTimeout: const Duration(seconds: 30),
            validateStatus: (status) => true, // 允许所有状态码（包括 4xx/5xx）正常返回供调试
            responseType: ResponseType.plain,
          ),
        );

  /// 执行完整的请求生命周期流水线
  Future<ExecutionResult> executeRequest({
    required ApiRequest request,
    required Workspace workspace,
    ApiCollection? collection,
    CancelToken? cancelToken,
  }) async {
    final startTime = DateTime.now();
    final allConsoleLogs = <String>[];

    // 1. 构建初始级联变量表
    final envVars = VariableResolver.buildVariableMap(
      workspace: workspace,
      collection: collection,
    );
    final globalVars = {
      for (final g in workspace.globalVariables)
        if (g.isEnabled) g.key: g.value
    };

    // 2. 执行前置脚本 (Pre-request Script)
    Map<String, String> updatedEnv = {};
    List<KeyValueItem> extraHeaders = [];
    List<KeyValueItem> extraParams = [];

    if (request.preRequestScript.trim().isNotEmpty) {
      final scriptResult = await ScriptEngine.executePreRequestScript(
        script: request.preRequestScript,
        request: request,
        environmentVariables: envVars,
        globalVariables: globalVars,
      );
      allConsoleLogs.addAll(scriptResult.consoleLogs);
      updatedEnv = scriptResult.updatedEnvironmentVariables;
      extraHeaders = scriptResult.additionalHeaders;
      extraParams = scriptResult.additionalParams;

      // 实时将脚本修改的变量合并入本次请求的临时变量上下文
      envVars.addAll(updatedEnv);
    }

    // 3. 解析最终 URL
    final activeBaseUrl = workspace.activeEnvironment?.baseUrl;
    final finalUrl = VariableResolver.resolveUrl(
      rawUrl: request.url,
      variables: envVars,
      currentBaseUrl: activeBaseUrl,
    );

    // 4. 解析 Query Parameters
    final queryParams = <String, dynamic>{};
    for (final p in [...request.params, ...extraParams]) {
      if (p.isEnabled && p.key.isNotEmpty) {
        queryParams[VariableResolver.interpolate(p.key, envVars)] =
            VariableResolver.interpolate(p.value, envVars);
      }
    }

    // 5. 解析 Headers
    final headers = <String, dynamic>{};
    for (final h in [...request.headers, ...extraHeaders]) {
      if (h.isEnabled && h.key.isNotEmpty) {
        headers[VariableResolver.interpolate(h.key, envVars)] =
            VariableResolver.interpolate(h.value, envVars);
      }
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
        if (request.bodyType == BodyType.json &&
            !headers.containsKey('Content-Type') &&
            !headers.containsKey('content-type')) {
          headers['Content-Type'] = 'application/json';
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
            map[VariableResolver.interpolate(f.key, envVars)] =
                VariableResolver.interpolate(f.value, envVars);
          }
        }
        bodyData = FormData.fromMap(map);
        finalResolvedBody = json.encode(map);
        break;
    }

    // 7. 发送 HTTP 请求
    ApiResponse apiResponse;
    try {
      final response = await _dio.request(
        finalUrl,
        data: bodyData,
        queryParameters: queryParams.isNotEmpty ? queryParams : null,
        options: Options(
          method: request.method.nameString,
          headers: headers,
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

      // 8. 执行后置测试与断言脚本 (Tests / Assertions)
      List<TestAssertionResult> testResults = [];
      if (request.postRequestScript.trim().isNotEmpty) {
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
        testResults = postResult.testResults;
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
      final errorMsg = e.message ?? e.toString();
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
}
