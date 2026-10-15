import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import '../models/s3_sync_config.dart';
import '../models/workspace.dart';

class S3SyncResult {
  final bool success;
  final String message;
  final Workspace? workspace;
  final String? syncTime;

  S3SyncResult({
    required this.success,
    required this.message,
    this.workspace,
    this.syncTime,
  });
}

/// 基于 AWS Signature V4 标准协议的 S3 同步服务
/// 兼容 AWS S3、MinIO、阿里云 OSS、腾讯云 COS、Cloudflare R2 等对象存储
class S3SyncService {
  static String formatNow() {
    return DateFormat('yyyy-MM-dd HH:mm:ss').format(DateTime.now());
  }

  /// 测试 S3 连接与凭证有效性
  static Future<S3SyncResult> testConnection(S3SyncConfig config) async {
    final validationError = _validateConfig(config);
    if (validationError != null) {
      return S3SyncResult(success: false, message: validationError);
    }

    try {
      final response = await _sendSignedRequest(
        method: 'HEAD',
        config: config,
        payloadBytes: Uint8List(0),
      );

      if (response.statusCode == 200) {
        return S3SyncResult(
          success: true,
          message: '连接成功，远端已存在同步数据文件',
        );
      } else if (response.statusCode == 404) {
        return S3SyncResult(
          success: true,
          message: '连接与鉴权成功，远端将在首次上传时创建同步文件',
        );
      } else {
        final errDetail = _extractS3ErrorMessage(response);
        return S3SyncResult(
          success: false,
          message: 'S3 响应异常 HTTP ${response.statusCode}: $errDetail',
        );
      }
    } catch (e) {
      return S3SyncResult(
        success: false,
        message: '连接失败: $e',
      );
    }
  }

  /// 将本地工作区数据上传同步至 S3
  static Future<S3SyncResult> uploadWorkspace(
    S3SyncConfig config,
    Workspace workspace,
  ) async {
    final validationError = _validateConfig(config);
    if (validationError != null) {
      return S3SyncResult(success: false, message: validationError);
    }

    try {
      final syncTime = formatNow();
      workspace.s3Config.lastSyncTime = syncTime;

      final jsonMap = Map<String, dynamic>.from(workspace.toJson());
      final jsonString = const JsonEncoder.withIndent('  ').convert(jsonMap);
      final payloadBytes = Uint8List.fromList(utf8.encode(jsonString));

      final response = await _sendSignedRequest(
        method: 'PUT',
        config: config,
        payloadBytes: payloadBytes,
        contentType: 'application/json; charset=utf-8',
      );

      if (response.statusCode == 200 ||
          response.statusCode == 201 ||
          response.statusCode == 204) {
        final colCount = workspace.collections.length;
        final apiCount = workspace.collections.fold<int>(
          0,
          (sum, c) => sum + c.findAllRequests().length,
        );
        return S3SyncResult(
          success: true,
          syncTime: syncTime,
          message: '已同步至 S3 · $colCount 个目录、$apiCount 个接口',
        );
      } else {
        final errDetail = _extractS3ErrorMessage(response);
        return S3SyncResult(
          success: false,
          message: '上传失败 HTTP ${response.statusCode}: $errDetail',
        );
      }
    } catch (e) {
      return S3SyncResult(
        success: false,
        message: '上传异常: $e',
      );
    }
  }

  /// 从 S3 下载拉取工作区数据
  static Future<S3SyncResult> downloadWorkspace(S3SyncConfig config) async {
    final validationError = _validateConfig(config);
    if (validationError != null) {
      return S3SyncResult(success: false, message: validationError);
    }

    try {
      final response = await _sendSignedRequest(
        method: 'GET',
        config: config,
        payloadBytes: Uint8List(0),
      );

      if (response.statusCode == 200) {
        final bodyText = utf8.decode(response.bodyBytes);
        final decoded = json.decode(bodyText);
        if (decoded is! Map<String, dynamic>) {
          return S3SyncResult(
            success: false,
            message: '远端文件格式无效，不是合法的工作区 JSON 对象',
          );
        }

        final syncTime = formatNow();
        final remoteWorkspace = Workspace.fromJson(decoded);
        // 保留当前本地 S3 连接配置并更新同步时间
        remoteWorkspace.s3Config = config.copyWith(lastSyncTime: syncTime);

        final colCount = remoteWorkspace.collections.length;
        final apiCount = remoteWorkspace.collections.fold<int>(
          0,
          (sum, c) => sum + c.findAllRequests().length,
        );

        return S3SyncResult(
          success: true,
          workspace: remoteWorkspace,
          syncTime: syncTime,
          message: '已从 S3 拉取成功 · $colCount 个目录、$apiCount 个接口',
        );
      } else if (response.statusCode == 404) {
        return S3SyncResult(
          success: false,
          message: '远端 S3 尚未找到该同步文件，请先执行上传同步',
        );
      } else {
        final errDetail = _extractS3ErrorMessage(response);
        return S3SyncResult(
          success: false,
          message: '拉取失败 HTTP ${response.statusCode}: $errDetail',
        );
      }
    } catch (e) {
      return S3SyncResult(
        success: false,
        message: '拉取异常: $e',
      );
    }
  }

  static String? _validateConfig(S3SyncConfig config) {
    if (config.endpoint.trim().isEmpty) {
      return '请填写 S3 Endpoint 地址';
    }
    if (config.bucket.trim().isEmpty) {
      return '请填写 Bucket 名称';
    }
    if (config.accessKeyId.trim().isEmpty) {
      return '请填写 Access Key ID';
    }
    if (config.secretAccessKey.trim().isEmpty) {
      return '请填写 Secret Access Key';
    }
    if (config.objectKey.trim().isEmpty) {
      return '请填写同步文件路径 Object Key';
    }
    return null;
  }

  /// 构建并发送带 AWS Signature Version 4 签名的 HTTP 请求
  static Future<http.Response> _sendSignedRequest({
    required String method,
    required S3SyncConfig config,
    required Uint8List payloadBytes,
    String? contentType,
  }) async {
    String rawEndpoint = config.endpoint.trim();
    if (!rawEndpoint.startsWith('http://') &&
        !rawEndpoint.startsWith('https://')) {
      rawEndpoint = 'https://$rawEndpoint';
    }

    final parsedEndpoint = Uri.parse(rawEndpoint);
    final scheme = parsedEndpoint.scheme;
    final cleanBucket =
        config.bucket.trim().replaceAll(RegExp(r'^/+|/+$'), '');
    final cleanObjectKey =
        config.objectKey.trim().replaceAll(RegExp(r'^/+'), '');
    final region =
        config.region.trim().isEmpty ? 'us-east-1' : config.region.trim();

    late String host;
    late String rawPath;

    final endpointBasePath =
        parsedEndpoint.path.replaceAll(RegExp(r'^/+|/+$'), '');

    if (config.forcePathStyle) {
      host = parsedEndpoint.host;
      final segments = <String>[
        if (endpointBasePath.isNotEmpty) endpointBasePath,
        cleanBucket,
        cleanObjectKey,
      ];
      rawPath = '/${segments.join('/')}';
    } else {
      if (parsedEndpoint.host.startsWith('$cleanBucket.')) {
        host = parsedEndpoint.host;
      } else {
        host = '$cleanBucket.${parsedEndpoint.host}';
      }
      final segments = <String>[
        if (endpointBasePath.isNotEmpty) endpointBasePath,
        cleanObjectKey,
      ];
      rawPath = '/${segments.join('/')}';
    }

    final hasCustomPort = parsedEndpoint.hasPort &&
        !((scheme == 'http' && parsedEndpoint.port == 80) ||
            (scheme == 'https' && parsedEndpoint.port == 443));
    final hostHeader =
        hasCustomPort ? '$host:${parsedEndpoint.port}' : host;

    final canonicalUri = _uriEncodePath(rawPath);
    final requestUri = Uri.parse('$scheme://$hostHeader$canonicalUri');

    final nowUtc = DateTime.now().toUtc();
    final amzDate = DateFormat("yyyyMMdd'T'HHmmss'Z'").format(nowUtc);
    final dateStamp = DateFormat('yyyyMMdd').format(nowUtc);

    final payloadHash = sha256.convert(payloadBytes).toString();

    final canonicalHeadersMap = <String, String>{
      'host': hostHeader,
      'x-amz-content-sha256': payloadHash,
      'x-amz-date': amzDate,
    };
    if (contentType != null && contentType.isNotEmpty) {
      canonicalHeadersMap['content-type'] = contentType;
    }

    final sortedHeaderKeys = canonicalHeadersMap.keys.toList()..sort();
    final canonicalHeaders = sortedHeaderKeys
        .map((k) => '$k:${canonicalHeadersMap[k]!.trim()}\n')
        .join();
    final signedHeaders = sortedHeaderKeys.join(';');

    final canonicalRequest = [
      method.toUpperCase(),
      canonicalUri,
      '', // canonicalQueryString
      canonicalHeaders,
      signedHeaders,
      payloadHash,
    ].join('\n');

    final credentialScope = '$dateStamp/$region/s3/aws4_request';
    final stringToSign = [
      'AWS4-HMAC-SHA256',
      amzDate,
      credentialScope,
      sha256.convert(utf8.encode(canonicalRequest)).toString(),
    ].join('\n');

    final signingKey = _deriveSigningKey(
      config.secretAccessKey.trim(),
      dateStamp,
      region,
      's3',
    );
    final signature =
        Hmac(sha256, signingKey).convert(utf8.encode(stringToSign)).toString();

    final authorizationHeader =
        'AWS4-HMAC-SHA256 Credential=${config.accessKeyId.trim()}/$credentialScope, '
        'SignedHeaders=$signedHeaders, '
        'Signature=$signature';

    final requestHeaders = <String, String>{
      'Host': hostHeader,
      'x-amz-date': amzDate,
      'x-amz-content-sha256': payloadHash,
      'Authorization': authorizationHeader,
      if (contentType != null && contentType.isNotEmpty)
        'Content-Type': contentType,
    };

    final client = http.Client();
    try {
      final request = http.Request(method.toUpperCase(), requestUri);
      request.headers.addAll(requestHeaders);
      if (payloadBytes.isNotEmpty) {
        request.bodyBytes = payloadBytes;
      }
      final streamed =
          await client.send(request).timeout(const Duration(seconds: 20));
      return await http.Response.fromStream(streamed);
    } finally {
      client.close();
    }
  }

  static List<int> _deriveSigningKey(
    String secretKey,
    String dateStamp,
    String regionName,
    String serviceName,
  ) {
    final kSecret = utf8.encode('AWS4$secretKey');
    final kDate = Hmac(sha256, kSecret).convert(utf8.encode(dateStamp)).bytes;
    final kRegion = Hmac(sha256, kDate).convert(utf8.encode(regionName)).bytes;
    final kService =
        Hmac(sha256, kRegion).convert(utf8.encode(serviceName)).bytes;
    final kSigning =
        Hmac(sha256, kService).convert(utf8.encode('aws4_request')).bytes;
    return kSigning;
  }

  /// AWS SigV4 标准 URI Path 编码
  static String _uriEncodePath(String path) {
    final bytes = utf8.encode(path);
    final sb = StringBuffer();
    for (final b in bytes) {
      if ((b >= 0x41 && b <= 0x5A) || // A-Z
          (b >= 0x61 && b <= 0x7A) || // a-z
          (b >= 0x30 && b <= 0x39) || // 0-9
          b == 0x2D || // -
          b == 0x5F || // _
          b == 0x2E || // .
          b == 0x7E || // ~
          b == 0x2F) {
        // /
        sb.writeCharCode(b);
      } else {
        sb.write('%');
        sb.write(b.toRadixString(16).toUpperCase().padLeft(2, '0'));
      }
    }
    return sb.toString();
  }

  static String _extractS3ErrorMessage(http.Response response) {
    try {
      final body = utf8.decode(response.bodyBytes);
      final codeMatch = RegExp(r'<Code>(.*?)</Code>').firstMatch(body);
      final msgMatch = RegExp(r'<Message>(.*?)</Message>').firstMatch(body);
      if (codeMatch != null || msgMatch != null) {
        final code = codeMatch?.group(1) ?? '';
        final msg = msgMatch?.group(1) ?? '';
        return [if (code.isNotEmpty) code, if (msg.isNotEmpty) msg].join(' - ');
      }
      if (body.trim().isNotEmpty && body.length < 200) {
        return body.trim();
      }
    } catch (_) {}
    return response.reasonPhrase ?? '未知错误';
  }
}
