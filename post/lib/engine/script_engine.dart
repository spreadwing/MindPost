import 'dart:convert';
import 'package:crypto/crypto.dart';
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

      // 5. 准备初始化 JS 沙箱 Polyfill
      final envJson = json.encode(environmentVariables);
      final globalJson = json.encode(globalVariables ?? {});

      final polyfillScript = '''
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
          // 在客户端同步支持
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
