/// 通知类型配置模型。
class NotificationTypeConfig {
  const NotificationTypeConfig({
    required this.typeCode,
    required this.label,
    this.description,
    this.icon,
    this.color,
    this.sortOrder = 0,
    this.enabled = true,
  });

  factory NotificationTypeConfig.fromJson(Map<String, dynamic> json) {
    return NotificationTypeConfig(
      typeCode: json['typeCode']?.toString() ?? '',
      label: json['label']?.toString() ?? '',
      description: json['description']?.toString(),
      icon: json['icon']?.toString(),
      color: json['color']?.toString(),
      sortOrder: (json['sortOrder'] as num?)?.toInt() ?? 0,
      enabled: json['enabled'] as bool? ?? true,
    );
  }

  final String typeCode;
  final String label;
  final String? description;
  final String? icon;
  final String? color;
  final int sortOrder;
  final bool enabled;

  /// 硬编码默认类型列表，API 失败时降级使用。
  static const List<NotificationTypeConfig> fallbackTypes = [
    NotificationTypeConfig(
      typeCode: 'TASK_COMPLETED',
      label: '任务完成',
      description: '异步任务执行成功',
      icon: 'check_circle_rounded',
      color: '#34D399',
      sortOrder: 1,
    ),
    NotificationTypeConfig(
      typeCode: 'TASK_FAILED',
      label: '任务失败',
      description: '异步任务执行失败',
      icon: 'error_rounded',
      color: '#F87171',
      sortOrder: 2,
    ),
    NotificationTypeConfig(
      typeCode: 'SHARE_ACCESS',
      label: '分享访问',
      description: '有人访问了你的分享链接',
      icon: 'share_rounded',
      color: '#60A5FA',
      sortOrder: 3,
    ),
    NotificationTypeConfig(
      typeCode: 'SYSTEM_MESSAGE',
      label: '系统消息',
      description: '系统级通知',
      icon: 'info_rounded',
      color: '#C3C0FF',
      sortOrder: 4,
    ),
    NotificationTypeConfig(
      typeCode: 'MEDIA_SCRAPED',
      label: '元数据刮削',
      description: '媒体元数据刮削完成',
      icon: 'auto_awesome_rounded',
      color: '#A78BFA',
      sortOrder: 5,
    ),
    NotificationTypeConfig(
      typeCode: 'SHARE_ACCESSED',
      label: '分享被访问',
      description: '有人访问了你的分享链接',
      icon: 'visibility_rounded',
      color: '#60A5FA',
      sortOrder: 6,
    ),
    NotificationTypeConfig(
      typeCode: 'QUOTA_WARNING',
      label: '存储预警',
      description: '存储空间使用率超过 80%',
      icon: 'storage_rounded',
      color: '#FBBF24',
      sortOrder: 7,
    ),
    NotificationTypeConfig(
      typeCode: 'NEW_DEVICE_LOGIN',
      label: '新设备登录',
      description: '检测到新设备登录',
      icon: 'phone_android_rounded',
      color: '#34D399',
      sortOrder: 8,
    ),
    NotificationTypeConfig(
      typeCode: 'PASSWORD_CHANGED',
      label: '密码已修改',
      description: '账户密码已成功修改',
      icon: 'lock_rounded',
      color: '#F59E0B',
      sortOrder: 9,
    ),
    NotificationTypeConfig(
      typeCode: 'SECURITY_THREAT',
      label: '安全威胁',
      description: '检测到可疑的文件上传行为',
      icon: 'gpp_maybe_rounded',
      color: '#EF4444',
      sortOrder: 10,
    ),
    NotificationTypeConfig(
      typeCode: 'SECURITY_SCAN_FAILED',
      label: '安全扫描失败',
      description: '文件未能通过安全扫描，已被隔离',
      icon: 'gpp_bad_rounded',
      color: '#F97316',
      sortOrder: 11,
    ),
  ];
}
