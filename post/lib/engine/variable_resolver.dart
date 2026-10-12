import 'dart:math';
import 'package:uuid/uuid.dart';
import '../models/api_collection.dart';
import '../models/workspace.dart';

class VariableResolver {
  /// 构建合并后的级联变量表 (Global -> Environment -> Collection -> Request)
  static Map<String, String> buildVariableMap({
    required Workspace workspace,
    ApiCollection? collection,
    Map<String, String>? requestVariables,
  }) {
    final map = <String, String>{};

    // 1. 全局变量
    for (final v in workspace.globalVariables) {
      if (v.isEnabled && v.key.isNotEmpty) {
        map[v.key] = v.value;
      }
    }

    // 2. 当前激活环境中的变量
    final activeEnv = workspace.activeEnvironment;
    if (activeEnv != null) {
      if (activeEnv.baseUrl.isNotEmpty) {
        map['baseUrl'] = activeEnv.baseUrl;
      }
      for (final v in activeEnv.variables) {
        if (v.isEnabled && v.key.isNotEmpty) {
          map[v.key] = v.value;
        }
      }
    }

    // 3. 集合级变量
    if (collection != null) {
      for (final v in collection.variables) {
        if (v.isEnabled && v.key.isNotEmpty) {
          map[v.key] = v.value;
        }
      }
    }

    // 4. 请求级局部变量
    if (requestVariables != null) {
      map.addAll(requestVariables);
    }

    return map;
  }

  /// 解析字符串中的占位符 {{varName}} 与动态内置变量
  static String interpolate(String text, Map<String, String> variables) {
    if (text.isEmpty) return text;

    final regex = RegExp(r'\{\{\s*([a-zA-Z0-9_\-\.\$]+)\s*\}\}');
    return text.replaceAllMapped(regex, (match) {
      final key = match.group(1) ?? '';

      // 处理系统内置动态占位符
      if (key == r'$timestamp') {
        return (DateTime.now().millisecondsSinceEpoch ~/ 1000).toString();
      }
      if (key == r'$timestamp_ms') {
        return DateTime.now().millisecondsSinceEpoch.toString();
      }
      if (key == r'$uuid' || key == r'$guid') {
        return const Uuid().v4();
      }
      if (key == r'$randomInt') {
        return (Random().nextInt(9000) + 1000).toString();
      }

      // 从级联变量表中查找
      if (variables.containsKey(key)) {
        return variables[key]!;
      }

      // 没匹配到则保持原样
      return match.group(0)!;
    });
  }

  /// 解析最终请求的完整 URL
  /// 兼容隐式相对路径自动补齐与显式占位符替换
  static String resolveUrl({
    required String rawUrl,
    required Map<String, String> variables,
    String? currentBaseUrl,
  }) {
    var trimmed = rawUrl.trim();
    if (trimmed.isEmpty) return '';

    // 1. 先进行变量插值替换（例如替换 {{baseUrl}}）
    var interpolated = interpolate(trimmed, variables);

    // 2. 检查是否已经是完整的协议地址 (http:// 或 https://)
    final uri = Uri.tryParse(interpolated);
    if (uri != null && (uri.scheme == 'http' || uri.scheme == 'https')) {
      return interpolated;
    }

    // 3. 隐式 Base URL 自动拼接处理
    final baseUrl = currentBaseUrl ?? variables['baseUrl'];
    if (baseUrl != null && baseUrl.isNotEmpty) {
      final cleanBase = baseUrl.endsWith('/')
          ? baseUrl.substring(0, baseUrl.length - 1)
          : baseUrl;
      final cleanPath =
          interpolated.startsWith('/') ? interpolated : '/$interpolated';
      return '$cleanBase$cleanPath';
    }

    return interpolated;
  }
}
