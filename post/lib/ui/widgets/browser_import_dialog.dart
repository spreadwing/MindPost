import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../models/api_request.dart';
import 'status_badge.dart';

class ParsedBrowserRequest {
  final HttpMethod method;
  final String url;
  final List<KeyValueItem> params;
  final List<KeyValueItem> headers;
  final BodyType bodyType;
  final String rawFormat;
  final String bodyContent;
  final List<KeyValueItem> formDataFields;
  final String suggestedName;
  final bool isValid;

  ParsedBrowserRequest({
    required this.method,
    required this.url,
    required this.params,
    required this.headers,
    required this.bodyType,
    required this.rawFormat,
    required this.bodyContent,
    required this.formDataFields,
    required this.suggestedName,
    this.isValid = true,
  });

  factory ParsedBrowserRequest.empty() {
    return ParsedBrowserRequest(
      method: HttpMethod.get,
      url: '',
      params: [],
      headers: [],
      bodyType: BodyType.none,
      rawFormat: 'json',
      bodyContent: '',
      formDataFields: [],
      suggestedName: '',
      isValid: false,
    );
  }
}

/// 解析从浏览器开发者工具复制的请求（支持 cURL bash / cURL cmd / fetch / PowerShell / Raw HTTP）
class BrowserRequestParser {
  static ParsedBrowserRequest parse(String rawInput) {
    final trimmed = rawInput.trim();
    if (trimmed.isEmpty) {
      return ParsedBrowserRequest.empty();
    }

    if (_looksLikeFetch(trimmed)) {
      return _parseFetch(trimmed);
    }
    if (_looksLikePowerShell(trimmed)) {
      return _parsePowerShell(trimmed);
    }
    if (_looksLikeCurl(trimmed)) {
      return _parseCurl(trimmed);
    }
    if (_looksLikeRawHttp(trimmed)) {
      return _parseRawHttp(trimmed);
    }
    // 兜底：若直接粘贴了 URL
    return _finalizeParsed(
      methodStr: 'GET',
      fullUrl: trimmed.split(RegExp(r'\s+')).first,
      headers: [],
      rawBody: '',
      formFields: [],
      isMultipart: false,
    );
  }

  static bool _looksLikeCurl(String text) {
    final lower = text.toLowerCase();
    return lower.startsWith('curl ') ||
        lower.startsWith('curl.exe ') ||
        lower.startsWith('curl\t') ||
        lower.startsWith('curl\r') ||
        lower.startsWith('curl\n') ||
        lower.startsWith('curl.exe\t') ||
        lower.startsWith('curl.exe\r') ||
        lower.startsWith('curl.exe\n');
  }

  static bool _looksLikeFetch(String text) {
    return RegExp(r'^\s*(await\s+)?fetch\s*\(', multiLine: true)
        .hasMatch(text);
  }

  static bool _looksLikePowerShell(String text) {
    final lower = text.toLowerCase();
    return lower.contains('invoke-webrequest') ||
        lower.contains('invoke-restmethod') ||
        lower.startsWith('iwr ') ||
        lower.startsWith('irm ');
  }

  static bool _looksLikeRawHttp(String text) {
    return RegExp(
            r'^(GET|POST|PUT|DELETE|PATCH|HEAD|OPTIONS)\s+\S+\s+HTTP/\d',
            caseSensitive: false)
        .hasMatch(text);
  }

  /// 脱去首尾成对的引号（单引号或双引号）
  static String _unquote(String str) {
    var s = str.trim();
    while (s.length >= 2 &&
        ((s.startsWith('"') && s.endsWith('"')) ||
            (s.startsWith("'") && s.endsWith("'")))) {
      s = s.substring(1, s.length - 1).trim();
    }
    return s;
  }

  /// 预处理并规范化 Windows CMD 下导出的 cURL 命令（例如 Chrome "Copy as cURL (cmd)"）
  static String _normalizeCmdCurl(String input) {
    var s = input;
    // 1. 合并 CMD 行尾续行符 (包含前后空格)
    s = s.replaceAll(RegExp(r'\s*\^\s*\r?\n\s*'), ' ');

    // 2. 还原 cURL 在 CMD 双引号内的转义引号变体 (如 ^\^" 或 \^" 或 ^\") -> \"
    s = s.replaceAll(r'^\^"', r'\"');
    s = s.replaceAll(r'\^"', r'\"');
    s = s.replaceAll(r'^\"', r'\"');

    // 3. 还原 Chrome 对 % 的转义 (^%^ 或 ^%) -> %
    s = s.replaceAll(r'^%^', '%');
    s = s.replaceAll(r'^%', '%');

    // 4. 保护真正转义的 caret (^^)
    s = s.replaceAll('^^', '\u0000');

    // 5. 将参数边界及独立的 ^" 还原为标准双引号 "
    s = s.replaceAll('^"', '"');

    // 6. 还原被 ^ 转义的 CMD 特殊字符 (如 ^{ ^} ^[ ^] ^( ^) ^& ^| ^< ^> ^= ^;)
    s = s.replaceAllMapped(RegExp(r'\^(.)'), (m) => m.group(1)!);

    // 7. 恢复 ^^
    s = s.replaceAll('\u0000', '^');

    return s;
  }

  /// 解析浏览器 Copy as cURL (bash) 或 Copy as cURL (cmd)
  static ParsedBrowserRequest _parseCurl(String input) {
    String normalized = input;
    // 检测是否为 Windows CMD 格式
    final isCmdFormat = RegExp(r'\^\s*\r?\n').hasMatch(normalized) ||
        normalized.contains('^"') ||
        normalized.contains('^{') ||
        normalized.contains(r'^\^"') ||
        normalized.contains(r'\^"') ||
        normalized.contains('^%');

    if (isCmdFormat) {
      normalized = _normalizeCmdCurl(normalized);
    } else {
      // 合并 Bash 续行符 \\\r?\n 与 PowerShell `\r?\n
      normalized = normalized
          .replaceAll(RegExp(r'\\\s*\r?\n\s*'), ' ')
          .replaceAll(RegExp(r'`\s*\r?\n\s*'), ' ');
    }

    final tokens = _tokenizeShell(normalized);
    if (tokens.isEmpty) return ParsedBrowserRequest.empty();

    String? methodStr;
    String fullUrl = '';
    final headers = <KeyValueItem>[];
    final bodyParts = <String>[];
    final formFields = <KeyValueItem>[];
    bool isMultipart = false;

    int i = 0;
    if (tokens.first.toLowerCase() == 'curl' ||
        tokens.first.toLowerCase() == 'curl.exe') {
      i = 1;
    }

    while (i < tokens.length) {
      final token = tokens[i];

      // 请求方式 -X / --request
      if ((token == '-X' || token == '--request') && i + 1 < tokens.length) {
        methodStr = _unquote(tokens[++i]).toUpperCase();
      } else if (token.startsWith('--request=')) {
        methodStr = _unquote(token.substring(10)).toUpperCase();
      } else if (token.startsWith('-X') && token.length > 2) {
        methodStr = _unquote(token.substring(2)).toUpperCase();
      }
      // 请求头 -H / --header
      else if ((token == '-H' || token == '--header') &&
          i + 1 < tokens.length) {
        final rawHeader = _unquote(tokens[++i]);
        final colonIdx = rawHeader.indexOf(':');
        if (colonIdx > 0) {
          final k = _unquote(rawHeader.substring(0, colonIdx).trim());
          final v = _unquote(rawHeader.substring(colonIdx + 1).trim());
          if (k.isNotEmpty) {
            headers.add(KeyValueItem(key: k, value: v));
          }
        }
      } else if (token.startsWith('--header=')) {
        final rawHeader = _unquote(token.substring(9));
        final colonIdx = rawHeader.indexOf(':');
        if (colonIdx > 0) {
          final k = _unquote(rawHeader.substring(0, colonIdx).trim());
          final v = _unquote(rawHeader.substring(colonIdx + 1).trim());
          if (k.isNotEmpty) {
            headers.add(KeyValueItem(key: k, value: v));
          }
        }
      } else if (token.startsWith('-H') && token.length > 2) {
        final rawHeader = _unquote(token.substring(2));
        final colonIdx = rawHeader.indexOf(':');
        if (colonIdx > 0) {
          final k = _unquote(rawHeader.substring(0, colonIdx).trim());
          final v = _unquote(rawHeader.substring(colonIdx + 1).trim());
          if (k.isNotEmpty) {
            headers.add(KeyValueItem(key: k, value: v));
          }
        }
      }
      // Cookie -b / --cookie
      else if ((token == '-b' || token == '--cookie') &&
          i + 1 < tokens.length) {
        final cookieVal = _unquote(tokens[++i]);
        if (cookieVal.isNotEmpty) {
          headers.add(KeyValueItem(key: 'Cookie', value: cookieVal));
        }
      } else if (token.startsWith('--cookie=')) {
        final cookieVal = _unquote(token.substring(9));
        if (cookieVal.isNotEmpty) {
          headers.add(KeyValueItem(key: 'Cookie', value: cookieVal));
        }
      } else if (token.startsWith('-b') &&
          token.length > 2 &&
          !token.startsWith('--')) {
        final cookieVal = _unquote(token.substring(2));
        if (cookieVal.isNotEmpty) {
          headers.add(KeyValueItem(key: 'Cookie', value: cookieVal));
        }
      }
      // User-Agent -A / --user-agent
      else if ((token == '-A' || token == '--user-agent') &&
          i + 1 < tokens.length) {
        final uaVal = _unquote(tokens[++i]);
        if (uaVal.isNotEmpty) {
          headers.add(KeyValueItem(key: 'User-Agent', value: uaVal));
        }
      } else if (token.startsWith('--user-agent=')) {
        final uaVal = _unquote(token.substring(13));
        if (uaVal.isNotEmpty) {
          headers.add(KeyValueItem(key: 'User-Agent', value: uaVal));
        }
      } else if (token.startsWith('-A') && token.length > 2) {
        final uaVal = _unquote(token.substring(2));
        if (uaVal.isNotEmpty) {
          headers.add(KeyValueItem(key: 'User-Agent', value: uaVal));
        }
      }
      // Basic 认证 -u / --user
      else if ((token == '-u' || token == '--user') && i + 1 < tokens.length) {
        final userPass = _unquote(tokens[++i]);
        if (userPass.isNotEmpty &&
            !headers.any((h) => h.key.toLowerCase() == 'authorization')) {
          final auth = base64Encode(utf8.encode(userPass));
          headers.add(KeyValueItem(key: 'Authorization', value: 'Basic $auth'));
        }
      } else if (token.startsWith('--user=')) {
        final userPass = _unquote(token.substring(7));
        if (userPass.isNotEmpty &&
            !headers.any((h) => h.key.toLowerCase() == 'authorization')) {
          final auth = base64Encode(utf8.encode(userPass));
          headers.add(KeyValueItem(key: 'Authorization', value: 'Basic $auth'));
        }
      } else if (token.startsWith('-u') &&
          token.length > 2 &&
          !token.startsWith('--')) {
        final userPass = _unquote(token.substring(2));
        if (userPass.isNotEmpty &&
            !headers.any((h) => h.key.toLowerCase() == 'authorization')) {
          final auth = base64Encode(utf8.encode(userPass));
          headers.add(KeyValueItem(key: 'Authorization', value: 'Basic $auth'));
        }
      }
      // Body 数据 -d / --data / --data-raw 等
      else if ((token == '-d' ||
              token == '--data' ||
              token == '--data-raw' ||
              token == '--data-binary' ||
              token == '--data-ascii' ||
              token == '--data-urlencode') &&
          i + 1 < tokens.length) {
        bodyParts.add(tokens[++i]);
      } else if (token.startsWith('--data=') ||
          token.startsWith('--data-raw=') ||
          token.startsWith('--data-binary=') ||
          token.startsWith('--data-ascii=') ||
          token.startsWith('--data-urlencode=')) {
        final eqIdx = token.indexOf('=');
        bodyParts.add(token.substring(eqIdx + 1));
      } else if (token.startsWith('-d') &&
          token.length > 2 &&
          !token.startsWith('--')) {
        bodyParts.add(token.substring(2));
      }
      // Multipart 表单 -F / --form
      else if ((token == '-F' || token == '--form') &&
          i + 1 < tokens.length) {
        isMultipart = true;
        final formStr = _unquote(tokens[++i]);
        final eqIdx = formStr.indexOf('=');
        if (eqIdx > 0) {
          final k = _unquote(formStr.substring(0, eqIdx).trim());
          final v = _unquote(formStr.substring(eqIdx + 1).trim());
          formFields.add(KeyValueItem(key: k, value: v));
        }
      } else if (token.startsWith('--form=')) {
        isMultipart = true;
        final formStr = _unquote(token.substring(7));
        final eqIdx = formStr.indexOf('=');
        if (eqIdx > 0) {
          final k = _unquote(formStr.substring(0, eqIdx).trim());
          final v = _unquote(formStr.substring(eqIdx + 1).trim());
          formFields.add(KeyValueItem(key: k, value: v));
        }
      }
      // 目标 URL --url
      else if (token == '--url' && i + 1 < tokens.length) {
        fullUrl = _unquote(tokens[++i]);
      } else if (token.startsWith('--url=')) {
        fullUrl = _unquote(token.substring(6));
      }
      // 无前缀位置参数作为 URL
      else if (!token.startsWith('-')) {
        if (fullUrl.isEmpty &&
            (token.startsWith('http://') ||
                token.startsWith('https://') ||
                token.startsWith('/'))) {
          fullUrl = _unquote(token);
        } else if (fullUrl.isEmpty) {
          fullUrl = _unquote(token);
        }
      }
      i++;
    }

    final rawBody = bodyParts.join('&');
    final effectiveMethod = methodStr ??
        ((rawBody.isNotEmpty || isMultipart) ? 'POST' : 'GET');

    return _finalizeParsed(
      methodStr: effectiveMethod,
      fullUrl: fullUrl,
      headers: headers,
      rawBody: rawBody,
      formFields: formFields,
      isMultipart: isMultipart,
    );
  }

  /// Shell 命令行分词器（支持单引号、双引号、ANSI-C 引用 $'...' 及反斜杠转义）
  static List<String> _tokenizeShell(String input) {
    final tokens = <String>[];
    final current = StringBuffer();
    bool inSingleQuote = false;
    bool inDoubleQuote = false;
    bool inAnsiQuote = false;
    bool hasTokenContent = false;

    int i = 0;
    while (i < input.length) {
      final ch = input[i];

      // ANSI-C 引用: $'...'
      if (!inSingleQuote &&
          !inDoubleQuote &&
          !inAnsiQuote &&
          ch == r'$' &&
          i + 1 < input.length &&
          input[i + 1] == "'") {
        inAnsiQuote = true;
        hasTokenContent = true;
        i += 2;
        continue;
      }

      if (inAnsiQuote) {
        if (ch == r'\' && i + 1 < input.length) {
          final next = input[i + 1];
          if (next == 'n') {
            current.write('\n');
          } else if (next == 'r') {
            current.write('\r');
          } else if (next == 't') {
            current.write('\t');
          } else {
            current.write(next);
          }
          i += 2;
          continue;
        } else if (ch == "'") {
          inAnsiQuote = false;
          i++;
          continue;
        } else {
          current.write(ch);
          i++;
          continue;
        }
      }

      // 单引号区域
      if (inSingleQuote) {
        if (ch == "'") {
          // 处理 bash '\'' 模式
          if (i + 3 < input.length &&
              input.substring(i, i + 4) == r"'\''") {
            current.write("'");
            i += 4;
            continue;
          }
          inSingleQuote = false;
        } else {
          current.write(ch);
        }
        i++;
        continue;
      }

      // 双引号区域
      if (inDoubleQuote) {
        if (ch == r'\' && i + 1 < input.length) {
          final next = input[i + 1];
          if (next == '"' || next == r'\' || next == r'$' || next == '`') {
            current.write(next);
            i += 2;
            continue;
          }
        }
        if (ch == '"') {
          inDoubleQuote = false;
        } else {
          current.write(ch);
        }
        i++;
        continue;
      }

      // 非引号区域
      if (ch == "'") {
        inSingleQuote = true;
        hasTokenContent = true;
      } else if (ch == '"') {
        inDoubleQuote = true;
        hasTokenContent = true;
      } else if (ch == r'\' && i + 1 < input.length) {
        // 非引号区域的反斜杠转义（如 escaped space \ ）
        current.write(input[i + 1]);
        hasTokenContent = true;
        i += 2;
        continue;
      } else if (ch == ' ' || ch == '\t' || ch == '\r' || ch == '\n') {
        if (hasTokenContent || current.isNotEmpty) {
          tokens.add(current.toString());
          current.clear();
          hasTokenContent = false;
        }
      } else {
        current.write(ch);
        hasTokenContent = true;
      }
      i++;
    }

    if (hasTokenContent || current.isNotEmpty) {
      tokens.add(current.toString());
    }
    return tokens;
  }

  /// 解析浏览器 Copy as fetch / Copy as Node.js fetch
  static ParsedBrowserRequest _parseFetch(String input) {
    final urlMatch =
        RegExp(r'fetch\s*\(\s*(["\x27`])(.*?)\1', dotAll: true).firstMatch(input);
    final fullUrl = urlMatch?.group(2)?.trim() ?? '';

    String methodStr = 'GET';
    final headers = <KeyValueItem>[];
    String rawBody = '';

    // 尝试提取第二个参数 JSON 对象
    if (urlMatch != null) {
      final afterUrl = input.substring(urlMatch.end);
      final braceStart = afterUrl.indexOf('{');
      final braceEnd = afterUrl.lastIndexOf('}');
      if (braceStart >= 0 && braceEnd > braceStart) {
        final objText = afterUrl.substring(braceStart, braceEnd + 1);
        try {
          final decoded = json.decode(objText) as Map<String, dynamic>;
          if (decoded['method'] != null) {
            methodStr = decoded['method'].toString().toUpperCase();
          }
          if (decoded['headers'] is Map) {
            (decoded['headers'] as Map).forEach((k, v) {
              if (k != null && v != null) {
                headers.add(
                    KeyValueItem(key: k.toString(), value: v.toString()));
              }
            });
          }
          if (decoded['body'] != null) {
            rawBody = decoded['body'].toString();
          }
        } catch (_) {
          // 降级正则提取
          final mMatch = RegExp(r'"?method"?\s*:\s*["\x27](\w+)["\x27]',
                  caseSensitive: false)
              .firstMatch(objText);
          if (mMatch != null) {
            methodStr = mMatch.group(1)!.toUpperCase();
          }
        }
      }
    }

    return _finalizeParsed(
      methodStr: methodStr,
      fullUrl: fullUrl,
      headers: headers,
      rawBody: rawBody,
      formFields: [],
      isMultipart: false,
    );
  }

  /// 解析浏览器 Copy as PowerShell
  static ParsedBrowserRequest _parsePowerShell(String input) {
    final normalized = input.replaceAll(RegExp(r'`\s*\r?\n\s*'), ' ');
    String fullUrl = '';
    final uriMatch =
        RegExp(r'-Uri\s+(["\x27])(.*?)\1', caseSensitive: false)
            .firstMatch(normalized);
    if (uriMatch != null) {
      fullUrl = uriMatch.group(2) ?? '';
    }

    String methodStr = 'GET';
    final methodMatch =
        RegExp(r'-Method\s+(["\x27]?)(\w+)\1', caseSensitive: false)
            .firstMatch(normalized);
    if (methodMatch != null) {
      methodStr = methodMatch.group(2)!.toUpperCase();
    }

    final headers = <KeyValueItem>[];
    final headersBlockMatch =
        RegExp(r'-Headers\s+@\{([\s\S]*?)\}', caseSensitive: false)
            .firstMatch(normalized);
    if (headersBlockMatch != null) {
      final block = headersBlockMatch.group(1) ?? '';
      final kvRegex = RegExp(r'["\x27]([^"\x27]+)["\x27]\s*=\s*["\x27]([^"\x27]*)["\x27]');
      for (final m in kvRegex.allMatches(block)) {
        headers.add(KeyValueItem(key: m.group(1)!, value: m.group(2)!));
      }
    }

    final ctMatch =
        RegExp(r'-ContentType\s+(["\x27])(.*?)\1', caseSensitive: false)
            .firstMatch(normalized);
    if (ctMatch != null &&
        !headers.any((h) => h.key.toLowerCase() == 'content-type')) {
      headers.add(
          KeyValueItem(key: 'Content-Type', value: ctMatch.group(2) ?? ''));
    }

    String rawBody = '';
    final bodyMatch =
        RegExp(r'-Body\s+(["\x27])([\s\S]*?)\1(?=\s+-|\s*$)', caseSensitive: false)
            .firstMatch(normalized);
    if (bodyMatch != null) {
      rawBody = (bodyMatch.group(2) ?? '').replaceAll('`"', '"');
      if (methodMatch == null && rawBody.isNotEmpty) {
        methodStr = 'POST';
      }
    }

    return _finalizeParsed(
      methodStr: methodStr,
      fullUrl: fullUrl,
      headers: headers,
      rawBody: rawBody,
      formFields: [],
      isMultipart: false,
    );
  }

  /// 解析 Raw HTTP 报文
  static ParsedBrowserRequest _parseRawHttp(String input) {
    final lines = input.split(RegExp(r'\r?\n'));
    final firstLine = lines.first.trim();
    final parts = firstLine.split(RegExp(r'\s+'));
    final methodStr = parts.isNotEmpty ? parts[0].toUpperCase() : 'GET';
    String pathOrUrl = parts.length > 1 ? parts[1] : '';

    final headers = <KeyValueItem>[];
    String? hostHeader;
    int bodyStartIdx = lines.length;

    for (int i = 1; i < lines.length; i++) {
      final line = lines[i];
      if (line.trim().isEmpty) {
        bodyStartIdx = i + 1;
        break;
      }
      final colonIdx = line.indexOf(':');
      if (colonIdx > 0) {
        final k = line.substring(0, colonIdx).trim();
        final v = line.substring(colonIdx + 1).trim();
        if (k.toLowerCase() == 'host') {
          hostHeader = v;
        }
        headers.add(KeyValueItem(key: k, value: v));
      }
    }

    if (!pathOrUrl.startsWith('http://') &&
        !pathOrUrl.startsWith('https://') &&
        hostHeader != null &&
        hostHeader.isNotEmpty) {
      pathOrUrl = 'http://$hostHeader$pathOrUrl';
    }

    final rawBody = bodyStartIdx < lines.length
        ? lines.sublist(bodyStartIdx).join('\n').trim()
        : '';

    return _finalizeParsed(
      methodStr: methodStr,
      fullUrl: pathOrUrl,
      headers: headers,
      rawBody: rawBody,
      formFields: [],
      isMultipart: false,
    );
  }

  static ParsedBrowserRequest _finalizeParsed({
    required String methodStr,
    required String fullUrl,
    required List<KeyValueItem> headers,
    required String rawBody,
    required List<KeyValueItem> formFields,
    required bool isMultipart,
  }) {
    // 拆分 URL 与 Query 参数
    String cleanUrl = _unquote(fullUrl.trim());
    final params = <KeyValueItem>[];
    final qIdx = cleanUrl.indexOf('?');
    if (qIdx >= 0) {
      final queryStr = cleanUrl.substring(qIdx + 1);
      cleanUrl = cleanUrl.substring(0, qIdx);
      for (final seg in queryStr.split('&')) {
        if (seg.trim().isEmpty) continue;
        final eqIdx = seg.indexOf('=');
        final k = eqIdx >= 0 ? seg.substring(0, eqIdx) : seg;
        final v = eqIdx >= 0 ? seg.substring(eqIdx + 1) : '';
        if (k.isNotEmpty) {
          String decodedK = _unquote(k);
          String decodedV = _unquote(v);
          try {
            decodedK = Uri.decodeQueryComponent(decodedK);
            decodedV = Uri.decodeQueryComponent(decodedV);
          } catch (_) {}
          params.add(KeyValueItem(key: decodedK, value: decodedV));
        }
      }
    }

    // 推断默认接口名称
    String suggestedName = '导入接口';
    if (cleanUrl.isNotEmpty) {
      final uri = Uri.tryParse(cleanUrl);
      final segments = (uri?.pathSegments ?? cleanUrl.split('/'))
          .where((s) => s.trim().isNotEmpty)
          .toList();
      if (segments.isNotEmpty) {
        var rawName = segments.last;
        final qPos = rawName.indexOf('?');
        if (qPos >= 0) rawName = rawName.substring(0, qPos);
        final hPos = rawName.indexOf('#');
        if (hPos >= 0) rawName = rawName.substring(0, hPos);
        final cleanedName = _unquote(rawName.trim());
        if (cleanedName.isNotEmpty) {
          suggestedName = cleanedName;
        }
      }
    }

    // 推断 BodyType 与美化 JSON
    BodyType bodyType = BodyType.none;
    String rawFormat = 'json';
    String finalBodyContent = rawBody;
    final finalFormFields = List<KeyValueItem>.from(formFields);

    String contentType = '';
    for (final h in headers) {
      if (h.key.toLowerCase() == 'content-type') {
        contentType = h.value.toLowerCase();
        break;
      }
    }

    if (isMultipart) {
      bodyType = BodyType.formData;
    } else if (rawBody.trim().isNotEmpty) {
      final candidateBody = rawBody.trim();
      bool jsonSuccess = false;

      // 1. 尝试直接解析为 JSON
      try {
        var decoded = json.decode(candidateBody);
        // 如果是已被包裹的 JSON 字符串（如 "{\"a\": 1}"），尝试二次解码
        if (decoded is String) {
          try {
            final innerDecoded = json.decode(decoded);
            if (innerDecoded is Map || innerDecoded is List) {
              decoded = innerDecoded;
            }
          } catch (_) {}
        }
        if (decoded is Map || decoded is List) {
          bodyType = BodyType.json;
          rawFormat = 'json';
          finalBodyContent =
              const JsonEncoder.withIndent('  ').convert(decoded);
          jsonSuccess = true;
        } else {
          bodyType = BodyType.raw;
          rawFormat = 'text';
          finalBodyContent = decoded.toString();
          jsonSuccess = true;
        }
      } catch (_) {}

      // 2. 若直接解析失败且两端有引号，脱去两端引号再试一次
      if (!jsonSuccess &&
          ((candidateBody.startsWith('"') && candidateBody.endsWith('"')) ||
              (candidateBody.startsWith("'") && candidateBody.endsWith("'")))) {
        final stripped = _unquote(candidateBody);
        try {
          var decoded = json.decode(stripped);
          if (decoded is String) {
            try {
              final innerDecoded = json.decode(decoded);
              if (innerDecoded is Map || innerDecoded is List) {
                decoded = innerDecoded;
              }
            } catch (_) {}
          }
          if (decoded is Map || decoded is List) {
            bodyType = BodyType.json;
            rawFormat = 'json';
            finalBodyContent =
                const JsonEncoder.withIndent('  ').convert(decoded);
            jsonSuccess = true;
          }
        } catch (_) {}
      }

      // 3. 非 JSON 格式的回退解析
      if (!jsonSuccess) {
        if (contentType.contains('application/x-www-form-urlencoded')) {
          bodyType = BodyType.formUrlEncoded;
          for (final seg in candidateBody.split('&')) {
            if (seg.trim().isEmpty) continue;
            final eqIdx = seg.indexOf('=');
            final k = eqIdx >= 0 ? seg.substring(0, eqIdx) : seg;
            final v = eqIdx >= 0 ? seg.substring(eqIdx + 1) : '';
            if (k.isNotEmpty) {
              String dk = _unquote(k);
              String dv = _unquote(v);
              try {
                dk = Uri.decodeQueryComponent(dk);
                dv = Uri.decodeQueryComponent(dv);
              } catch (_) {}
              finalFormFields.add(KeyValueItem(key: dk, value: dv));
            }
          }
        } else if (contentType.contains('xml')) {
          bodyType = BodyType.raw;
          rawFormat = 'xml';
        } else if (contentType.contains('html')) {
          bodyType = BodyType.raw;
          rawFormat = 'html';
        } else if (contentType.contains('javascript')) {
          bodyType = BodyType.raw;
          rawFormat = 'javascript';
        } else {
          bodyType = BodyType.raw;
          rawFormat = 'text';
        }
      }
    }

    return ParsedBrowserRequest(
      method: HttpMethodExt.fromString(methodStr),
      url: cleanUrl,
      params: params,
      headers: headers,
      bodyType: bodyType,
      rawFormat: rawFormat,
      bodyContent: finalBodyContent,
      formDataFields: finalFormFields,
      suggestedName: suggestedName,
      isValid: cleanUrl.isNotEmpty ||
          headers.isNotEmpty ||
          finalBodyContent.isNotEmpty ||
          finalFormFields.isNotEmpty,
    );
  }
}

/// 从浏览器复制的请求导入弹窗
class BrowserImportDialog extends StatefulWidget {
  final String folderName;
  final String? collectionId;

  const BrowserImportDialog({
    super.key,
    required this.folderName,
    this.collectionId,
  });

  @override
  State<BrowserImportDialog> createState() => _BrowserImportDialogState();
}

class _BrowserImportDialogState extends State<BrowserImportDialog> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _rawInputController = TextEditingController();

  bool _importUrl = true;
  bool _importHeaders = true;
  bool _importBody = true;
  bool _userEditedName = false;

  ParsedBrowserRequest _parsed = ParsedBrowserRequest.empty();

  void _onRawInputChanged(String text) {
    final parsed = BrowserRequestParser.parse(text);
    setState(() {
      _parsed = parsed;
      if (!_userEditedName && parsed.suggestedName.isNotEmpty) {
        _nameController.text = parsed.suggestedName;
      }
    });
  }

  Future<void> _pasteFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text ?? '';
    if (text.trim().isNotEmpty) {
      _rawInputController.text = text;
      _onRawInputChanged(text);
    }
  }

  void _confirmImport() {
    final finalName = _nameController.text.trim().isNotEmpty
        ? _nameController.text.trim()
        : (_parsed.suggestedName.isNotEmpty ? _parsed.suggestedName : '导入接口');

    final req = ApiRequest(
      name: finalName,
      collectionId: widget.collectionId ?? '',
      method: _importUrl ? _parsed.method : HttpMethod.get,
      url: _importUrl ? _parsed.url : '',
      params: _importUrl ? _parsed.params : [],
      headers: _importHeaders ? _parsed.headers : [],
      bodyType: _importBody ? _parsed.bodyType : BodyType.none,
      rawFormat: _importBody ? _parsed.rawFormat : 'json',
      bodyContent: _importBody ? _parsed.bodyContent : '',
      formDataFields: _importBody ? _parsed.formDataFields : [],
    );

    Navigator.of(context).pop(req);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _rawInputController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: Container(
        width: 640,
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 标题栏
            Row(
              children: [
                const Icon(Icons.input_rounded,
                    color: Color(0xFF2563EB), size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '从浏览器请求导入 · ${widget.folderName}',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF0F172A),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded, size: 18),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const Divider(height: 16),

            // 1. 导入接口名称输入
            Row(
              children: [
                const SizedBox(
                  width: 72,
                  child: Text(
                    '接口名称',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF334155),
                    ),
                  ),
                ),
                Expanded(
                  child: TextField(
                    controller: _nameController,
                    style: const TextStyle(fontSize: 13),
                    decoration: const InputDecoration(
                      hintText: '输入接口名称，粘贴请求后会自动提取默认名称',
                      isDense: true,
                      contentPadding:
                          EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (val) {
                      _userEditedName = val.trim().isNotEmpty;
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // 2. 选择需要导入的部分：URL / Header / Request Body
            Row(
              children: [
                const SizedBox(
                  width: 72,
                  child: Text(
                    '导入内容',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF334155),
                    ),
                  ),
                ),
                _buildOptionCheckbox(
                  label: 'URL',
                  value: _importUrl,
                  onChanged: (val) => setState(() => _importUrl = val),
                ),
                const SizedBox(width: 16),
                _buildOptionCheckbox(
                  label: 'Header',
                  value: _importHeaders,
                  onChanged: (val) => setState(() => _importHeaders = val),
                ),
                const SizedBox(width: 16),
                _buildOptionCheckbox(
                  label: 'Request Body',
                  value: _importBody,
                  onChanged: (val) => setState(() => _importBody = val),
                ),
                const Spacer(),
                TextButton.icon(
                  style: TextButton.styleFrom(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  onPressed: _pasteFromClipboard,
                  icon: const Icon(Icons.content_paste_rounded, size: 15),
                  label: const Text('粘贴剪贴板',
                      style: TextStyle(fontSize: 12)),
                ),
              ],
            ),
            const SizedBox(height: 10),

            // 3. 浏览器请求文本输入区
            Container(
              height: 210,
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: const Color(0xFFCBD5E1)),
              ),
              child: TextField(
                controller: _rawInputController,
                maxLines: null,
                expands: true,
                textAlignVertical: TextAlignVertical.top,
                style: const TextStyle(
                  fontSize: 12,
                  fontFamily: 'Consolas',
                  height: 1.45,
                  color: Color(0xFF0F172A),
                ),
                decoration: const InputDecoration(
                  hintText:
                      '在此粘贴浏览器开发者工具 Network 中复制的请求内容\n支持 Copy as cURL bash、Copy as cURL cmd、Copy as fetch、Copy as PowerShell 或原始 HTTP 报文',
                  hintStyle: TextStyle(
                    fontSize: 12,
                    color: Color(0xFF94A3B8),
                    height: 1.5,
                  ),
                  filled: false,
                  contentPadding: EdgeInsets.all(12),
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                ),
                onChanged: _onRawInputChanged,
              ),
            ),
            const SizedBox(height: 10),

            // 4. 实时解析结果预览条
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: _parsed.isValid
                    ? const Color(0xFFEFF6FF).withValues(alpha: 0.6)
                    : const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: _parsed.isValid
                      ? const Color(0xFFBFDBFE)
                      : const Color(0xFFE2E8F0),
                ),
              ),
              child: !_parsed.isValid
                  ? const Text(
                      '等待粘贴浏览器请求文本...',
                      style: TextStyle(fontSize: 11.5, color: Color(0xFF94A3B8)),
                    )
                  : Row(
                      children: [
                        HttpMethodBadge(method: _parsed.method, fontSize: 10),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _importUrl
                                ? (_parsed.url.isEmpty ? '无 URL' : _parsed.url)
                                : '不导入 URL',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 11.5,
                              fontFamily: 'Consolas',
                              color: _importUrl
                                  ? const Color(0xFF1E293B)
                                  : const Color(0xFF94A3B8),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        _buildPreviewTag(
                          text: 'Params ${_importUrl ? _parsed.params.length : 0}',
                          active: _importUrl && _parsed.params.isNotEmpty,
                        ),
                        const SizedBox(width: 6),
                        _buildPreviewTag(
                          text:
                              'Header ${_importHeaders ? _parsed.headers.length : 0}',
                          active: _importHeaders && _parsed.headers.isNotEmpty,
                        ),
                        const SizedBox(width: 6),
                        _buildPreviewTag(
                          text: _importBody && _parsed.bodyType != BodyType.none
                              ? 'Body ${_parsed.bodyType.name.toUpperCase()}'
                              : '无 Body',
                          active:
                              _importBody && _parsed.bodyType != BodyType.none,
                        ),
                      ],
                    ),
            ),
            const SizedBox(height: 16),

            // 5. 底部按钮
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('取消'),
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2563EB),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 18, vertical: 10),
                  ),
                  onPressed: _rawInputController.text.trim().isEmpty &&
                          _nameController.text.trim().isEmpty
                      ? null
                      : _confirmImport,
                  icon: const Icon(Icons.check_rounded, size: 16),
                  label:
                      const Text('确定导入', style: TextStyle(fontSize: 12.5)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOptionCheckbox({
    required String label,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(4),
      onTap: () => onChanged(!value),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 18,
              height: 18,
              child: Checkbox(
                value: value,
                activeColor: const Color(0xFF2563EB),
                onChanged: (v) => onChanged(v ?? true),
              ),
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: value ? FontWeight.w600 : FontWeight.normal,
                color: value
                    ? const Color(0xFF0F172A)
                    : const Color(0xFF64748B),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPreviewTag({required String text, required bool active}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: active ? const Color(0xFFDBEAFE) : const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w600,
          color: active ? const Color(0xFF1D4ED8) : const Color(0xFF94A3B8),
        ),
      ),
    );
  }
}
