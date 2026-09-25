import 'package:omninest/features/admin/domain/admin_operations.dart';

/// 将监控组件 JSON 解析为领域模型。
///
/// `detail` 值在边界统一为字符串，领域层不持有 `Map<String, dynamic>`。
AdminMonitoringComponent parseAdminMonitoringComponent(
  Map<String, dynamic> json,
) {
  return AdminMonitoringComponent(
    name: json['name']?.toString() ?? '',
    status: json['status']?.toString() ?? 'UNKNOWN',
    detail: _stringMap(json['detail']),
  );
}

/// 将监控组件列表 JSON 解析为领域模型列表。
List<AdminMonitoringComponent> parseAdminMonitoringComponents(Object? value) {
  if (value is! List) {
    return const [];
  }
  return value
      .whereType<Map<String, dynamic>>()
      .map(parseAdminMonitoringComponent)
      .toList();
}

Map<String, String> _stringMap(Object? value) {
  if (value is! Map) {
    return const {};
  }
  return value.map(
    (key, value) => MapEntry(key.toString(), value?.toString() ?? ''),
  );
}
