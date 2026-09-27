/// 能力门控跳过信号：仅 autoSkip 漏网路径使用。
///
/// 由 [CapabilityGateInterceptor] 在自动写回缺少对应权限时随
/// `DioException(error: ...)` 携带抛出；各 autoSkip API 方法必须在内部
/// catch 并转为本地值或 no-op，禁止冒泡到调用方——离线重放队列
/// （reader / music 同步队列）遇到异常会重试后滞留，违背静默跳过目标。
class CapabilitySkippedError implements Exception {
  const CapabilitySkippedError(this.permission);

  /// 缺失的权限码，仅用于日志定位，不进入用户可见文案。
  final String permission;

  @override
  String toString() => 'CapabilitySkippedError($permission)';
}
