/// 服务端同步事件作用域。
enum RealtimeScope {
  tasks,
  files,
  photos,
  video,
  music,
  reader,
  preferences,
  notifications,
  admin;

  /// 将服务端大写作用域解析为客户端枚举。
  static RealtimeScope parse(String value) {
    return RealtimeScope.values.firstWhere(
      (scope) => scope.name.toUpperCase() == value.toUpperCase(),
      orElse: () => throw FormatException('未知同步作用域: $value'),
    );
  }
}

/// 服务端同步事件动作。
enum RealtimeAction {
  created,
  updated,
  deleted,
  restored,
  progress,
  completed,
  failed,
  invalidated,
  permissionChanged;

  /// 将服务端动作解析为客户端枚举。
  static RealtimeAction parse(String value) {
    final normalized = value.toUpperCase();
    return RealtimeAction.values.firstWhere(
      (action) => _wireName(action) == normalized,
      orElse: () => throw FormatException('未知同步动作: $value'),
    );
  }

  static String _wireName(RealtimeAction action) {
    return switch (action) {
      RealtimeAction.permissionChanged => 'PERMISSION_CHANGED',
      _ => action.name.toUpperCase(),
    };
  }
}

/// 单条服务端同步事件。
class RealtimeSyncEvent {
  const RealtimeSyncEvent({
    required this.schemaVersion,
    required this.eventId,
    required this.sequenceNo,
    required this.scope,
    required this.resourceType,
    required this.action,
    required this.hints,
    required this.occurredAt,
    this.resourceId,
    this.resourceVersion,
  });

  factory RealtimeSyncEvent.fromJson(Map<String, dynamic> json) {
    final hintsValue = json['hints'];
    return RealtimeSyncEvent(
      schemaVersion: (json['schemaVersion'] as num?)?.toInt() ?? 0,
      eventId: json['eventId']?.toString() ?? '',
      sequenceNo: (json['sequenceNo'] as num?)?.toInt() ?? 0,
      scope: RealtimeScope.parse(json['scope']?.toString() ?? ''),
      resourceType: json['resourceType']?.toString() ?? '',
      resourceId: json['resourceId']?.toString(),
      action: RealtimeAction.parse(json['action']?.toString() ?? ''),
      resourceVersion: (json['resourceVersion'] as num?)?.toInt(),
      hints:
          hintsValue is Map
              ? Map<String, dynamic>.from(hintsValue)
              : const <String, dynamic>{},
      occurredAt: DateTime.parse(json['occurredAt']?.toString() ?? '').toUtc(),
    );
  }

  final int schemaVersion;
  final String eventId;
  final int sequenceNo;
  final RealtimeScope scope;
  final String resourceType;
  final String? resourceId;
  final RealtimeAction action;
  final int? resourceVersion;
  final Map<String, dynamic> hints;
  final DateTime occurredAt;
}

/// 同步初始化高水位。
class RealtimeBootstrap {
  const RealtimeBootstrap({
    required this.schemaVersion,
    required this.latestCursor,
    required this.retentionFloor,
    required this.serverTime,
  });

  factory RealtimeBootstrap.fromJson(Map<String, dynamic> json) {
    return RealtimeBootstrap(
      schemaVersion: (json['schemaVersion'] as num?)?.toInt() ?? 0,
      latestCursor: (json['latestCursor'] as num?)?.toInt() ?? 0,
      retentionFloor: (json['retentionFloor'] as num?)?.toInt() ?? 0,
      serverTime: DateTime.parse(json['serverTime']?.toString() ?? '').toUtc(),
    );
  }

  final int schemaVersion;
  final int latestCursor;
  final int retentionFloor;
  final DateTime serverTime;
}

/// 服务端增量事件页。
class RealtimeEventPage {
  const RealtimeEventPage({
    required this.items,
    required this.nextCursor,
    required this.latestCursor,
    required this.hasMore,
    required this.resetRequired,
  });

  factory RealtimeEventPage.fromJson(Map<String, dynamic> json) {
    final rawItems = json['items'] as List<dynamic>? ?? const [];
    return RealtimeEventPage(
      items: rawItems
          .map(
            (item) => RealtimeSyncEvent.fromJson(
              Map<String, dynamic>.from(item as Map),
            ),
          )
          .toList(growable: false),
      nextCursor: (json['nextCursor'] as num?)?.toInt() ?? 0,
      latestCursor: (json['latestCursor'] as num?)?.toInt() ?? 0,
      hasMore: json['hasMore'] == true,
      resetRequired: json['resetRequired'] == true,
    );
  }

  final List<RealtimeSyncEvent> items;
  final int nextCursor;
  final int latestCursor;
  final bool hasMore;
  final bool resetRequired;
}

/// 服务端同步高水位。
class RealtimeHead {
  const RealtimeHead({
    required this.schemaVersion,
    required this.latestCursor,
    required this.retentionFloor,
  });

  factory RealtimeHead.fromJson(Map<String, dynamic> json) {
    return RealtimeHead(
      schemaVersion: (json['schemaVersion'] as num?)?.toInt() ?? 0,
      latestCursor: (json['latestCursor'] as num?)?.toInt() ?? 0,
      retentionFloor: (json['retentionFloor'] as num?)?.toInt() ?? 0,
    );
  }

  final int schemaVersion;
  final int latestCursor;
  final int retentionFloor;
}

/// 业务模块待处理的失效记录。
class RealtimeInvalidation {
  const RealtimeInvalidation({
    required this.key,
    required this.scope,
    required this.resourceType,
    required this.revision,
    required this.createdAt,
    this.resourceId,
  });

  final String key;
  final RealtimeScope scope;
  final String resourceType;
  final String? resourceId;
  final int revision;
  final DateTime createdAt;
}

/// 实时同步协调器状态。
enum RealtimePhase {
  signedOut,
  connecting,
  subscribed,
  catchingUp,
  healthy,
  degraded,
  reconnecting,
}
