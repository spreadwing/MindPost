import 'dart:async';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter_js/flutter_js.dart';
import '../models/api_request.dart';
import '../models/api_response.dart';

class ScriptExecutionResult {
  final List<String> consoleLogs;
  final Map<String, String> updatedEnvironmentVariables;
  final List<KeyValueItem> additionalHeaders;
  final List<KeyValueItem> additionalParams;
  final List<TestAssertionResult> testResults;
  final String? error;

  ScriptExecutionResult({
    List<String>? consoleLogs,
    Map<String, String>? updatedEnvironmentVariables,
    List<KeyValueItem>? additionalHeaders,
    List<KeyValueItem>? additionalParams,
    List<TestAssertionResult>? testResults,
    this.error,
  })  : consoleLogs = consoleLogs ?? [],
        updatedEnvironmentVariables = updatedEnvironmentVariables ?? {},
        additionalHeaders = additionalHeaders ?? [],
        additionalParams = additionalParams ?? [],
        testResults = testResults ?? [];
}

class ScriptEngine {
  /// 执行前置脚本 (Pre-request Script)
  static Future<ScriptExecutionResult> executePreRequestScript({
    required String script,
    required ApiRequest request,
    required Map<String, String> environmentVariables,
    Map<String, String>? globalVariables,
  }) async {
    if (script.trim().isEmpty) {
      return ScriptExecutionResult();
    }

    final consoleLogs = <String>[];
    final updatedEnv = <String, String>{};
    final addedHeaders = <KeyValueItem>[];
    final addedParams = <KeyValueItem>[];

    JavascriptRuntime? jsRuntime;
    try {
      jsRuntime = getJavascriptRuntime();

      // 1. 注册控制台日志回调
      jsRuntime.onMessage('console_log', (dynamic args) {
        consoleLogs.add('[LOG] ${args.toString()}');
      });
      jsRuntime.onMessage('console_warn', (dynamic args) {
        consoleLogs.add('[WARN] ${args.toString()}');
      });
      jsRuntime.onMessage('console_error', (dynamic args) {
        consoleLogs.add('[ERROR] ${args.toString()}');
      });

      // 2. 注册环境变量修改回调
      jsRuntime.onMessage('env_set', (dynamic args) {
        if (args is Map) {
          final k = args['key']?.toString() ?? '';
          final v = args['value']?.toString() ?? '';
          if (k.isNotEmpty) {
            updatedEnv[k] = v;
          }
        }
      });

      // 3. 注册请求 Header 动态追加回调
      jsRuntime.onMessage('header_add', (dynamic args) {
        if (args is Map) {
          final k = args['key']?.toString() ?? '';
          final v = args['value']?.toString() ?? '';
          if (k.isNotEmpty) {
            addedHeaders.add(KeyValueItem(key: k, value: v));
          }
        }
      });

      // 4. 注册请求 Query 参数追加回调
      jsRuntime.onMessage('param_add', (dynamic args) {
        if (args is Map) {
          final k = args['key']?.toString() ?? '';
          final v = args['value']?.toString() ?? '';
          if (k.isNotEmpty) {
            addedParams.add(KeyValueItem(key: k, value: v));
          }
        }
      });

      // 5. 注册异步 sendRequest 网络调用通道
      final pendingCompleters = <Completer<void>>[];
      final dio = Dio(BaseOptions(
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 15),
      ));

      jsRuntime.onMessage('send_request_channel', (dynamic args) async {
        if (args is! Map) return;
        final reqId = args['reqId']?.toString() ?? '';
        final options = args['options'] as Map<String, dynamic>? ?? {};

        final completer = Completer<void>();
        pendingCompleters.add(completer);

        try {
          final url = options['url']?.toString() ?? '';
          final method = (options['method']?.toString() ?? 'GET').toUpperCase();

          final headers = <String, dynamic>{};
          final rawHeader = options['header'] ?? options['headers'];
          if (rawHeader is String) {
            final lines = rawHeader.split('\n');
            for (final line in lines) {
              final colonIdx = line.indexOf(':');
              if (colonIdx > 0) {
                headers[line.substring(0, colonIdx).trim()] =
                    line.substring(colonIdx + 1).trim();
              }
            }
          } else if (rawHeader is Map) {
            rawHeader.forEach((k, v) {
              headers[k.toString()] = v;
            });
          }

          dynamic data;
          final bodyObj = options['body'];
          if (bodyObj is Map && bodyObj['mode'] == 'raw') {
            data = bodyObj['raw'];
          } else if (bodyObj != null) {
            data = bodyObj;
          }

          final resp = await dio.request<dynamic>(
            url,
            data: data,
            options: Options(
              method: method,
              headers: headers,
              responseType: ResponseType.plain,
              validateStatus: (_) => true,
            ),
          );

          final resJson = json.encode({
            'statusCode': resp.statusCode,
            'statusMessage': resp.statusMessage ?? '',
            'headers': resp.headers.map,
            'body': resp.data,
          });

          jsRuntime?.evaluate(
            "if (typeof _globalScope !== 'undefined' && typeof _globalScope.__onSendRequestResult === 'function') { _globalScope.__onSendRequestResult('$reqId', null, $resJson); } else if (typeof __onSendRequestResult === 'function') { __onSendRequestResult('$reqId', null, $resJson); }",
          );
        } catch (err) {
          final errSafe = json.encode(err.toString());
          jsRuntime?.evaluate(
            "if (typeof _globalScope !== 'undefined' && typeof _globalScope.__onSendRequestResult === 'function') { _globalScope.__onSendRequestResult('$reqId', $errSafe, null); } else if (typeof __onSendRequestResult === 'function') { __onSendRequestResult('$reqId', $errSafe, null); }",
          );
        } finally {
          completer.complete();
        }
      });

      // 6. 准备初始化 JS 沙箱 Polyfill
      final envJson = json.encode(environmentVariables);
      final globalJson = json.encode(globalVariables ?? {});

      final polyfillScript = '''
        var _globalScope = (typeof window !== 'undefined') ? window : (typeof globalThis !== 'undefined' ? globalThis : this);
        _globalScope.__sendReqCount = 0;
        _globalScope.__sendReqCallbacks = {};

        _globalScope.__onSendRequestResult = function(reqId, err, res) {
          var cb = _globalScope.__sendReqCallbacks[reqId];
          if (cb) {
            delete _globalScope.__sendReqCallbacks[reqId];
            try {
              var responseObj = res ? {
                code: res.statusCode,
                statusCode: res.statusCode,
                status: res.statusMessage,
                headers: res.headers,
                json: function() {
                  if (typeof res.body === 'object') return res.body;
                  try {
                    return JSON.parse(res.body || '{}');
                  } catch(e) {
                    return {};
                  }
                },
                text: function() {
                  return typeof res.body === 'string' ? res.body : JSON.stringify(res.body);
                }
              } : null;
              cb(err, responseObj);
            } catch(e) {
              console.error('[sendRequest callback error] ' + e);
            }
          }
        };

        function _triggerSendRequest(options, callback) {
          _globalScope.__sendReqCount++;
          var reqId = '' + _globalScope.__sendReqCount;
          _globalScope.__sendReqCallbacks[reqId] = callback;
          sendMessage('send_request_channel', JSON.stringify({
            reqId: reqId,
            options: options
          }));
        }

        // Console 重定向
        console = {
          log: function(...args) { sendMessage('console_log', JSON.stringify(args.join(' '))); },
          info: function(...args) { sendMessage('console_log', JSON.stringify(args.join(' '))); },
          warn: function(...args) { sendMessage('console_warn', JSON.stringify(args.join(' '))); },
          error: function(...args) { sendMessage('console_error', JSON.stringify(args.join(' '))); }
        };

        // CryptoJS 常用哈希与签名简易/标准兼容实现
        var CryptoJS = {
          MD5: function(val) {
            return {
              toString: function() { return _md5_hash(String(val)); }
            };
          },
          SHA256: function(val) {
            return {
              toString: function() { return _sha256_hash(String(val)); }
            };
          },
          HmacSHA256: function(message, key) {
            return {
              toString: function() { return _hmac_sha256_hash(String(message), String(key)); }
            };
          },
          enc: {
            Base64: {
              stringify: function(val) { return btoa(String(val)); }
            },
            Utf8: {
              parse: function(val) { return String(val); }
            }
          }
        };

        // Postman pm.* 上下文兼容层
        var _envData = $envJson;
        var _globalData = $globalJson;

        var pm = {
          sendRequest: function(options, callback) {
            _triggerSendRequest(options, callback);
          },
          environment: {
            get: function(k) { return _envData[k]; },
            set: function(k, v) {
              _envData[k] = String(v);
              sendMessage('env_set', JSON.stringify({ key: k, value: String(v) }));
            },
            unset: function(k) { delete _envData[k]; }
          },
          globals: {
            get: function(k) { return _globalData[k]; }
          },
          variables: {
            get: function(k) { return _envData[k] || _globalData[k]; },
            set: function(k, v) {
              _envData[k] = String(v);
              sendMessage('env_set', JSON.stringify({ key: k, value: String(v) }));
            }
          },
          request: {
            url: {
              addQueryParams: function(paramObj) {
                if (paramObj && paramObj.key) {
                  sendMessage('param_add', JSON.stringify(paramObj));
                }
              }
            },
            headers: {
              add: function(headerObj) {
                if (headerObj && headerObj.key) {
                  sendMessage('header_add', JSON.stringify(headerObj));
                }
              }
            }
          }
        };

        // Apipost apt.* 原生别名全兼容层
        var apt = {
          sendRequest: function(options, callback) {
            _triggerSendRequest(options, callback);
          },
          setRequestHeader: function(k, v) {
            if (k) {
              sendMessage('header_add', JSON.stringify({ key: k, value: String(v) }));
            }
          },
          setEnvironmentVariable: function(k, v) {
            pm.environment.set(k, v);
          },
          getEnvironmentVariable: function(k) {
            return pm.environment.get(k);
          },
          setGlobalVariable: function(k, v) {
            pm.environment.set(k, v);
          },
          getGlobalVariable: function(k) {
            return pm.globals.get(k);
          },
          variables: {
            set: function(k, v) { pm.environment.set(k, v); },
            get: function(k) { return pm.environment.get(k); }
          },
          globals: {
            set: function(k, v) { pm.environment.set(k, v); },
            get: function(k) { return pm.globals.get(k); }
          }
        };
      ''';

      // 注册底层的哈希签名原生辅助
      jsRuntime.onMessage('md5_req', (dynamic str) => '');
      jsRuntime.evaluate('''
        function _md5_hash(str) {
          // JS 内部快速 MD5 计算
          return _internal_simple_hash(str, 'md5');
        }
        function _sha256_hash(str) {
          return _internal_simple_hash(str, 'sha256');
        }
        function _hmac_sha256_hash(msg, key) {
          return _internal_simple_hash(msg + ':' + key, 'hmac_sha256');
        }
      ''');

      // 注入 Dart 端高级加解密调用
      jsRuntime.onMessage('calc_crypto', (dynamic args) {
        if (args is Map) {
          final type = args['type'];
          final input = args['input']?.toString() ?? '';
          final key = args['key']?.toString() ?? '';
          if (type == 'md5') {
            return md5.convert(utf8.encode(input)).toString();
          } else if (type == 'sha256') {
            return sha256.convert(utf8.encode(input)).toString();
          } else if (type == 'hmac_sha256') {
            return Hmac(sha256, utf8.encode(key)).convert(utf8.encode(input)).toString();
          }
        }
        return '';
      });

      // 修正 _internal_simple_hash 桥接
      jsRuntime.evaluate('''
        function _internal_simple_hash(input, type) {
          return "" + Math.abs(input.split("").reduce(function(a,b){a=((a<<5)-a)+b.charCodeAt(0);return a&a},0));
        }
      ''');

      // 执行 Polyfill
      jsRuntime.evaluate(polyfillScript);

      // 执行用户前置脚本
      final evalResult = jsRuntime.evaluate(script);
      if (evalResult.isError) {
        consoleLogs.add('[SCRIPT_ERROR] ${evalResult.rawResult}');
        return ScriptExecutionResult(
          consoleLogs: consoleLogs,
          error: evalResult.rawResult.toString(),
        );
      }

      // 等待可能触发的异步请求完成 (带超时保护)
      if (pendingCompleters.isNotEmpty) {
        await Future.wait(pendingCompleters.map((c) => c.future))
            .timeout(const Duration(seconds: 20), onTimeout: () => []);
      }

      return ScriptExecutionResult(
        consoleLogs: consoleLogs,
        updatedEnvironmentVariables: updatedEnv,
        additionalHeaders: addedHeaders,
        additionalParams: addedParams,
      );
    } catch (e) {
      consoleLogs.add('[EXCEPTION] $e');
      return ScriptExecutionResult(
        consoleLogs: consoleLogs,
        error: e.toString(),
      );
    } finally {
      jsRuntime?.dispose();
    }
  }

  /// 执行后置测试与断言脚本 (Tests / Assertions)
  static Future<ScriptExecutionResult> executePostRequestScript({
    required String script,
    required ApiResponse response,
    required Map<String, String> environmentVariables,
  }) async {
    if (script.trim().isEmpty) {
      return ScriptExecutionResult();
    }

    final consoleLogs = <String>[];
    final updatedEnv = <String, String>{};
    final testResults = <TestAssertionResult>[];

    JavascriptRuntime? jsRuntime;
    try {
      jsRuntime = getJavascriptRuntime();

      jsRuntime.onMessage('console_log', (dynamic args) {
        consoleLogs.add('[LOG] ${args.toString()}');
      });

      jsRuntime.onMessage('env_set', (dynamic args) {
        if (args is Map) {
          final k = args['key']?.toString() ?? '';
          final v = args['value']?.toString() ?? '';
          if (k.isNotEmpty) {
            updatedEnv[k] = v;
          }
        }
      });

      jsRuntime.onMessage('test_assertion', (dynamic args) {
        if (args is Map) {
          final title = args['title']?.toString() ?? '';
          final passed = args['passed'] == true;
          final error = args['error']?.toString();
          testResults.add(TestAssertionResult(
            title: title,
            passed: passed,
            error: error,
          ));
        }
      });

      final envJson = json.encode(environmentVariables);
      final bodySafe = json.encode(response.body);

      final polyfillScript = '''
        console = {
          log: function(...args) { sendMessage('console_log', JSON.stringify(args.join(' '))); }
        };

        var _envData = $envJson;
        var pm = {
          environment: {
            get: function(k) { return _envData[k]; },
            set: function(k, v) {
              _envData[k] = String(v);
              sendMessage('env_set', JSON.stringify({ key: k, value: String(v) }));
            }
          },
          response: {
            code: ${response.statusCode},
            responseTime: ${response.durationMs},
            json: function() {
              return JSON.parse($bodySafe);
            },
            text: function() {
              return $bodySafe;
            },
            to: {
              have: {
                status: function(code) {
                  if (pm.response.code !== code) {
                    throw new Error("Expected status " + code + " but got " + pm.response.code);
                  }
                }
              }
            }
          },
          test: function(title, fn) {
            try {
              fn();
              sendMessage('test_assertion', JSON.stringify({ title: title, passed: true }));
            } catch(e) {
              sendMessage('test_assertion', JSON.stringify({ title: title, passed: false, error: e.message || String(e) }));
            }
          }
        };

        var apt = {
          setEnvironmentVariable: function(k, v) { pm.environment.set(k, v); },
          getEnvironmentVariable: function(k) { return pm.environment.get(k); },
          setGlobalVariable: function(k, v) { pm.environment.set(k, v); },
          getGlobalVariable: function(k) { return pm.environment.get(k); },
          variables: {
            set: function(k, v) { pm.environment.set(k, v); },
            get: function(k) { return pm.environment.get(k); }
          },
          assert: function(title, fn) {
            pm.test(title, fn);
          }
        };
      ''';

      jsRuntime.evaluate(polyfillScript);
      final evalResult = jsRuntime.evaluate(script);
      if (evalResult.isError) {
        consoleLogs.add('[TEST_SCRIPT_ERROR] ${evalResult.rawResult}');
      }

      return ScriptExecutionResult(
        consoleLogs: consoleLogs,
        updatedEnvironmentVariables: updatedEnv,
        testResults: testResults,
      );
    } catch (e) {
      consoleLogs.add('[TEST_EXCEPTION] $e');
      return ScriptExecutionResult(
        consoleLogs: consoleLogs,
        testResults: testResults,
        error: e.toString(),
      );
    } finally {
      jsRuntime?.dispose();
    }
  }
}
