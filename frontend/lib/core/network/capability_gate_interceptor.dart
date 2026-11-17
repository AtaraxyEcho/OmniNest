import 'package:dio/dio.dart';
import 'package:omninest/core/errors/capability_skipped_error.dart';
import 'package:omninest/core/log/dev_log.dart';

/// 写请求能力门控策略。
///
/// - [autoSkip]：系统自动写回（进度 / 历史 / 队列 / 定位 / 偏好同步），
///   无对应权限时不发网络，静默跳过。
/// - [strict]：用户主动写（收藏 / 书签 / 删历史 / 通知等），无权限时由
///   API 层预检抛 `AppException(FORBIDDEN)`，拦截器不做软放行。
enum CapabilityWritePolicy { autoSkip, strict }

/// 在 `RequestOptions.extra` 中传递请求级写策略的键。
const String capabilityPolicyKey = 'omninest.capabilityPolicy';

/// 本人活动写权限码（进度 / 历史 / 队列 / 收藏 / 书签 / 通知已读）。
const String activityWritePermission = 'activity:write';

/// 本人偏好写权限码。
const String preferenceWritePermission = 'preference:write';

/// 能力门控拦截器：双策略模型。
///
/// - 命中 autoSkip 规则（显式标记，或未标记但路径命中自动写回表）且缺少
///   对应权限时，不发网络，reject 携带 [CapabilitySkippedError] 的
///   DioException，由各 autoSkip API 方法统一 catch 后转为本地值或 no-op。
/// - strict 请求一律放行，由 API 预检与后端 `@PreAuthorize` 兜底。
/// - 写请求未显式标记策略且命中 autoSkip 规则表时按 autoSkip 处理，
///   防止自动写回调用点漏标导致 403 回归。
class CapabilityGateInterceptor extends Interceptor {
  CapabilityGateInterceptor({required Set<String> Function() readPermissions})
    : _readPermissions = readPermissions;

  final Set<String> Function() _readPermissions;

  /// 自动写回路径表：路径 → 所需权限。
  ///
  /// 用户主动写（收藏 / 书签 / 批注 / 笔记 / 书架 / 删历史 / 通知）不在
  /// 此表，一律 strict。锚定 `/…(/|$)` 或 `$`，避免子串误伤无关路径。
  static final List<AutoSkipRule> _autoSkipRules = <AutoSkipRule>[
    AutoSkipRule(RegExp(r'/progress$'), activityWritePermission),
    AutoSkipRule(RegExp(r'/position$'), activityWritePermission),
    AutoSkipRule(RegExp(r'/playback-queue$'), activityWritePermission),
    AutoSkipRule(RegExp(r'/play-history(/|$)'), activityWritePermission),
    AutoSkipRule(RegExp(r'/sessions$'), activityWritePermission),
    AutoSkipRule(RegExp(r'/weather/location$'), activityWritePermission),
    AutoSkipRule(RegExp(r'/preferences/'), preferenceWritePermission),
  ];

  static final List<String> _writeMethods = <String>[
    'POST',
    'PUT',
    'PATCH',
    'DELETE',
  ];

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    final method = options.method.toUpperCase();
    if (!_writeMethods.contains(method)) {
      handler.next(options);
      return;
    }
    final rule = _matchAutoSkipRule(options.path);
    if (rule == null || !_isAutoSkip(options)) {
      // 非 autoSkip 路径或显式 strict：放行，由 API 预检与后端兜底。
      handler.next(options);
      return;
    }
    if (_readPermissions().contains(rule.permission)) {
      handler.next(options);
      return;
    }
    devLog('跳过无 ${rule.permission} 的自动写回: ${options.method} ${options.path}');
    handler.reject(
      DioException(
        requestOptions: options,
        type: DioExceptionType.unknown,
        error: CapabilitySkippedError(rule.permission),
      ),
    );
  }

  /// 命中自动写回表的写请求默认 autoSkip（防漏标回归 403）；
  /// 显式标记为 [CapabilityWritePolicy.strict] 时优先放行。
  bool _isAutoSkip(RequestOptions options) {
    final marked = options.extra[capabilityPolicyKey];
    if (marked is CapabilityWritePolicy) {
      return marked == CapabilityWritePolicy.autoSkip;
    }
    return true;
  }

  static AutoSkipRule? _matchAutoSkipRule(String path) {
    for (final rule in _autoSkipRules) {
      if (rule.pattern.hasMatch(path)) {
        return rule;
      }
    }
    return null;
  }
}

/// 自动写回规则：路径模式与所需权限的配对。
class AutoSkipRule {
  const AutoSkipRule(this.pattern, this.permission);

  final RegExp pattern;
  final String permission;
}
