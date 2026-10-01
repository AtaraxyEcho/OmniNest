class NotificationDto {
  const NotificationDto({
    required this.id,
    required this.type,
    required this.title,
    this.message,
    required this.read,
    required this.createdAt,
    this.metadata = const <String, dynamic>{},
  });

  factory NotificationDto.fromJson(Map<String, dynamic> json) {
    return NotificationDto(
      id: json['id']?.toString() ?? '',
      type: json['type']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      message: json['message']?.toString(),
      read: json['read'] as bool? ?? false,
      createdAt: _parseDateTime(json['createdAt']),
      metadata:
          json['metadata'] is Map<String, dynamic>
              ? json['metadata'] as Map<String, dynamic>
              : const <String, dynamic>{},
    );
  }

  final String id;
  final String type;
  final String? title;
  final String? message;
  final bool read;
  final DateTime createdAt;

  /// 业务元数据（taskId、shareId 等服务端跳转上下文）。
  final Map<String, dynamic> metadata;

  NotificationDto copyWith({bool? read}) {
    return NotificationDto(
      id: id,
      type: type,
      title: title,
      message: message,
      read: read ?? this.read,
      createdAt: createdAt,
      metadata: metadata,
    );
  }

  static DateTime _parseDateTime(dynamic value) {
    final raw = value?.toString() ?? '';
    final parsed = DateTime.tryParse(raw);
    if (parsed != null) return parsed.toLocal();
    final normalized = raw.replaceFirst(' ', 'T');
    final fallback = DateTime.tryParse(normalized);
    return fallback?.toLocal() ?? DateTime.now();
  }
}
