import 'dart:convert';

class TestAssertionResult {
  final String title;
  final bool passed;
  final String? error;

  TestAssertionResult({
    required this.title,
    required this.passed,
    this.error,
  });

  Map<String, dynamic> toJson() => {
        'title': title,
        'passed': passed,
        'error': error,
      };

  factory TestAssertionResult.fromJson(Map<String, dynamic> json) =>
      TestAssertionResult(
        title: json['title'] as String? ?? '',
        passed: json['passed'] as bool? ?? false,
        error: json['error'] as String?,
      );
}

class ApiResponse {
  final int statusCode;
  final String statusMessage;
  final Map<String, String> headers;
  final String body;
  final int durationMs;
  final int sizeBytes;
  final List<String> consoleLogs;
  final List<TestAssertionResult> testResults;
  final String? errorMessage;
  final DateTime timestamp;

  ApiResponse({
    required this.statusCode,
    required this.statusMessage,
    required this.headers,
    required this.body,
    required this.durationMs,
    required this.sizeBytes,
    List<String>? consoleLogs,
    List<TestAssertionResult>? testResults,
    this.errorMessage,
    DateTime? timestamp,
  })  : consoleLogs = consoleLogs ?? [],
        testResults = testResults ?? [],
        timestamp = timestamp ?? DateTime.now();

  bool get isSuccess => statusCode >= 200 && statusCode < 300;

  Map<String, dynamic> toJson() => {
        'statusCode': statusCode,
        'statusMessage': statusMessage,
        'headers': headers,
        'body': body,
        'durationMs': durationMs,
        'sizeBytes': sizeBytes,
        'consoleLogs': consoleLogs,
        'testResults': testResults.map((e) => e.toJson()).toList(),
        'errorMessage': errorMessage,
        'timestamp': timestamp.toIso8601String(),
      };

  factory ApiResponse.error({
    required String error,
    int durationMs = 0,
    List<String>? consoleLogs,
  }) {
    return ApiResponse(
      statusCode: 0,
      statusMessage: 'Client Error',
      headers: {},
      body: '',
      durationMs: durationMs,
      sizeBytes: 0,
      consoleLogs: consoleLogs,
      errorMessage: error,
    );
  }

  /// 格式化 Pretty JSON（惰性单次计算并缓存，避免 UI 重绘时重复解析大 JSON）
  late final String prettyBody = _formatPrettyBody();

  String _formatPrettyBody() {
    if (body.trim().isEmpty) return '';
    try {
      final decoded = json.decode(body);
      return const JsonEncoder.withIndent('  ').convert(decoded);
    } catch (_) {
      return body;
    }
  }
}
