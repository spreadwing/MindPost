class S3SyncConfig {
  String endpoint;
  String region;
  String bucket;
  String accessKeyId;
  String secretAccessKey;
  String objectKey;
  bool forcePathStyle;
  bool autoSyncOnSave;
  String? lastSyncTime;

  S3SyncConfig({
    this.endpoint = '',
    this.region = 'us-east-1',
    this.bucket = '',
    this.accessKeyId = '',
    this.secretAccessKey = '',
    this.objectKey = 'mindpost/workspace.json',
    this.forcePathStyle = true,
    this.autoSyncOnSave = false,
    this.lastSyncTime,
  });

  bool get isConfigured =>
      endpoint.trim().isNotEmpty &&
      bucket.trim().isNotEmpty &&
      accessKeyId.trim().isNotEmpty &&
      secretAccessKey.trim().isNotEmpty &&
      objectKey.trim().isNotEmpty;

  S3SyncConfig copyWith({
    String? endpoint,
    String? region,
    String? bucket,
    String? accessKeyId,
    String? secretAccessKey,
    String? objectKey,
    bool? forcePathStyle,
    bool? autoSyncOnSave,
    String? lastSyncTime,
  }) {
    return S3SyncConfig(
      endpoint: endpoint ?? this.endpoint,
      region: region ?? this.region,
      bucket: bucket ?? this.bucket,
      accessKeyId: accessKeyId ?? this.accessKeyId,
      secretAccessKey: secretAccessKey ?? this.secretAccessKey,
      objectKey: objectKey ?? this.objectKey,
      forcePathStyle: forcePathStyle ?? this.forcePathStyle,
      autoSyncOnSave: autoSyncOnSave ?? this.autoSyncOnSave,
      lastSyncTime: lastSyncTime ?? this.lastSyncTime,
    );
  }

  Map<String, dynamic> toJson() => {
        'endpoint': endpoint,
        'region': region,
        'bucket': bucket,
        'accessKeyId': accessKeyId,
        'secretAccessKey': secretAccessKey,
        'objectKey': objectKey,
        'forcePathStyle': forcePathStyle,
        'autoSyncOnSave': autoSyncOnSave,
        'lastSyncTime': lastSyncTime,
      };

  factory S3SyncConfig.fromJson(Map<String, dynamic> json) {
    return S3SyncConfig(
      endpoint: json['endpoint'] as String? ?? '',
      region: (json['region'] as String?)?.trim().isNotEmpty == true
          ? json['region'] as String
          : 'us-east-1',
      bucket: json['bucket'] as String? ?? '',
      accessKeyId: json['accessKeyId'] as String? ?? '',
      secretAccessKey: json['secretAccessKey'] as String? ?? '',
      objectKey: (json['objectKey'] as String?)?.trim().isNotEmpty == true
          ? json['objectKey'] as String
          : 'mindpost/workspace.json',
      forcePathStyle: json['forcePathStyle'] as bool? ?? true,
      autoSyncOnSave: json['autoSyncOnSave'] as bool? ?? false,
      lastSyncTime: json['lastSyncTime'] as String?,
    );
  }
}
