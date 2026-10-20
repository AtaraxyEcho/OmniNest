/// 通知偏好设置模型。
class NotificationPreferences {
  const NotificationPreferences({
    this.enabled = true,
    this.types = const {},
    this.quietHours = const QuietHours(),
    this.sound = true,
    this.showPreview = true,
    this.foregroundBanner = true,
    this.emailNotification = false,
  });

  factory NotificationPreferences.fromJson(Map<String, dynamic> json) {
    final typesRaw = json['types'] as Map<String, dynamic>? ?? {};
    final types = typesRaw.map(
      (key, value) => MapEntry(key, value as bool? ?? true),
    );
    return NotificationPreferences(
      enabled: json['enabled'] as bool? ?? true,
      types: types,
      quietHours:
          json['quietHours'] is Map<String, dynamic>
              ? QuietHours.fromJson(json['quietHours'] as Map<String, dynamic>)
              : const QuietHours(),
      sound: json['sound'] as bool? ?? true,
      showPreview: json['showPreview'] as bool? ?? true,
      foregroundBanner: json['foregroundBanner'] as bool? ?? true,
      emailNotification: json['emailNotification'] as bool? ?? false,
    );
  }

  final bool enabled;
  final Map<String, bool> types;
  final QuietHours quietHours;
  final bool sound;
  final bool showPreview;

  /// 前台横幅开关：与提示音、预览一样属服务端偏好，本地快照仅作首帧缓存。
  final bool foregroundBanner;
  final bool emailNotification;

  Map<String, dynamic> toJson() {
    return {
      'enabled': enabled,
      'types': types,
      'quietHours': quietHours.toJson(),
      'sound': sound,
      'showPreview': showPreview,
      'foregroundBanner': foregroundBanner,
      'emailNotification': emailNotification,
    };
  }

  NotificationPreferences copyWith({
    bool? enabled,
    Map<String, bool>? types,
    QuietHours? quietHours,
    bool? sound,
    bool? showPreview,
    bool? foregroundBanner,
    bool? emailNotification,
  }) {
    return NotificationPreferences(
      enabled: enabled ?? this.enabled,
      types: types ?? this.types,
      quietHours: quietHours ?? this.quietHours,
      sound: sound ?? this.sound,
      showPreview: showPreview ?? this.showPreview,
      foregroundBanner: foregroundBanner ?? this.foregroundBanner,
      emailNotification: emailNotification ?? this.emailNotification,
    );
  }

  /// 获取指定类型是否启用（未配置默认 true）。
  bool isTypeEnabled(String typeCode) {
    return types[typeCode] ?? true;
  }

  /// 该类型的实时通知是否允许弹前台横幅：总开关、横幅开关、类型开关任一
  /// 关闭即不弹，免打扰时段内同样静默（横幅与提示音一起跳过）。
  bool presentsBannerFor(String typeCode, {required DateTime at}) {
    if (!enabled || !foregroundBanner) {
      return false;
    }
    if (!isTypeEnabled(typeCode)) {
      return false;
    }
    return !isQuietAt(at);
  }

  /// 免打扰时段判定：HH:mm 按本地墙钟比较，起始晚于结束时视为跨零点。
  /// 起止相等或格式非法视为未生效，避免整点被当成全天免打扰。
  bool isQuietAt(DateTime at) {
    if (!quietHours.enabled) {
      return false;
    }
    final start = _parseMinutesOfDay(quietHours.start);
    final end = _parseMinutesOfDay(quietHours.end);
    if (start == null || end == null || start == end) {
      return false;
    }
    final minutes = at.hour * 60 + at.minute;
    if (start < end) {
      return minutes >= start && minutes < end;
    }
    return minutes >= start || minutes < end;
  }
}

int? _parseMinutesOfDay(String value) {
  final parts = value.split(':');
  if (parts.length != 2) {
    return null;
  }
  final hour = int.tryParse(parts[0].trim());
  final minute = int.tryParse(parts[1].trim());
  if (hour == null || minute == null || hour < 0 || hour > 23) {
    return null;
  }
  if (minute < 0 || minute > 59) {
    return null;
  }
  return hour * 60 + minute;
}

/// 免打扰时段配置。
class QuietHours {
  const QuietHours({
    this.enabled = false,
    this.start = '22:00',
    this.end = '08:00',
  });

  factory QuietHours.fromJson(Map<String, dynamic> json) {
    return QuietHours(
      enabled: json['enabled'] as bool? ?? false,
      start: json['start']?.toString() ?? '22:00',
      end: json['end']?.toString() ?? '08:00',
    );
  }

  final bool enabled;
  final String start;
  final String end;

  Map<String, dynamic> toJson() {
    return {'enabled': enabled, 'start': start, 'end': end};
  }

  QuietHours copyWith({bool? enabled, String? start, String? end}) {
    return QuietHours(
      enabled: enabled ?? this.enabled,
      start: start ?? this.start,
      end: end ?? this.end,
    );
  }
}
