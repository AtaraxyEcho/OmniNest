import 'package:flutter/material.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/core/errors/error_message.dart';
import 'package:toastification/toastification.dart';

/// 透出挂载 Wrapper 所需的类型，消费方只需导入本门面。
export 'package:toastification/toastification.dart' show ToastificationWrapper;

/// 全局瞬时反馈分级。
enum OmniFeedbackSeverity { info, success, warning, error }

/// 反馈条固定宽度。holder 为 tightFor 定宽约束，取 352 兼容 360dp 手机，
/// 桌面端观感亦可接受；低于 360dp 的屏幕接受两侧少量裁切。
const double _kFeedbackWidth = 352;

/// 同屏最多同时存留的反馈条数量，超出时移除最旧一条。
const int _kFeedbackLimit = 3;

final ToastificationConfig omniFeedbackToastConfig = ToastificationConfig(
  alignment: AlignmentDirectional.topCenter,
  itemWidth: _kFeedbackWidth,
  maxToastLimit: _kFeedbackLimit,
  animationDuration: const Duration(milliseconds: 300),
  maxTitleLines: 3,
  maxDescriptionLines: 2,
  // 顶部锚定，键盘弹出不应把提示条推走。
  applyMediaQueryViewInsets: false,
);

const Duration _infoAutoClose = Duration(seconds: 2);
const Duration _errorAutoClose = Duration(seconds: 4);
const Duration _actionAutoClose = Duration(seconds: 6);

/// 活动反馈注册表：key = severity|message|actionLabel。
/// 依赖插入顺序维护「最旧」语义，展示前先剔除已自然消失的条目。
final Map<String, ToastificationItem> _activeFeedback = {};

ToastificationType _toastType(OmniFeedbackSeverity severity) =>
    switch (severity) {
      OmniFeedbackSeverity.info => ToastificationType.info,
      OmniFeedbackSeverity.success => ToastificationType.success,
      OmniFeedbackSeverity.warning => ToastificationType.warning,
      OmniFeedbackSeverity.error => ToastificationType.error,
    };

Duration _resolveAutoClose(
  OmniFeedbackSeverity severity,
  bool hasAction,
  Duration? override,
) {
  if (override != null) {
    return override;
  }
  if (hasAction) {
    return _actionAutoClose;
  }
  return severity == OmniFeedbackSeverity.error
      ? _errorAutoClose
      : _infoAutoClose;
}

void _pruneStaleFeedback() {
  _activeFeedback.removeWhere(
    (key, item) => toastification.findToastificationItem(item.id) == null,
  );
}

/// 全局瞬时反馈入口：顶部居中、限宽、分级配色、同文案合并重置计时。
///
/// [actionLabel] 与 [onAction] 成对提供时在文案下方渲染动作按钮（如撤销、
/// 查看通知），并延长停留时间。[duration] 仅在调用方有明确节奏诉求时覆盖
/// 默认分级策略。跨异步边界调用由本入口统一校验 [context.mounted]。
void showOmniFeedback(
  BuildContext context,
  String message, {
  OmniFeedbackSeverity severity = OmniFeedbackSeverity.info,
  String? actionLabel,
  VoidCallback? onAction,
  Duration? duration,
}) {
  if (!context.mounted) {
    return;
  }
  final trimmed = message.trim();
  if (trimmed.isEmpty) {
    return;
  }
  _pruneStaleFeedback();
  final key = '$severity|$trimmed|$actionLabel';
  final existing = _activeFeedback.remove(key);
  if (existing != null) {
    toastification.dismiss(existing, showRemoveAnimation: false);
  }
  while (_activeFeedback.length >= _kFeedbackLimit) {
    final oldestKey = _activeFeedback.keys.first;
    final oldest = _activeFeedback.remove(oldestKey);
    if (oldest != null) {
      toastification.dismiss(oldest, showRemoveAnimation: false);
    }
  }
  final hasAction = actionLabel != null && actionLabel.isNotEmpty;
  ToastificationItem? item;
  final foreground = Theme.of(context).colorScheme.primary;
  item = toastification.show(
    context: context,
    alignment: Alignment.topCenter,
    type: _toastType(severity),
    style: ToastificationStyle.flat,
    autoCloseDuration: _resolveAutoClose(severity, hasAction, duration),
    title: Semantics(liveRegion: true, child: Text(trimmed)),
    description:
        hasAction
            ? Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton(
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  minimumSize: const Size(0, 32),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  foregroundColor: foreground,
                ),
                onPressed: () {
                  final resolved = item;
                  if (resolved != null) {
                    toastification.dismiss(resolved);
                  }
                  onAction?.call();
                },
                child: Text(
                  actionLabel,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
              ),
            )
            : null,
    showProgressBar: false,
    closeOnClick: true,
    dragToClose: true,
    pauseOnHover: true,
    applyBlurEffect: false,
  );
  _activeFeedback[key] = item;
}

/// 异常反馈：走统一错误映射链（错误码本地化 + 后端 message 回退），
/// 以 error 级展示。任何 [Object] 异常均可直接传入。
void showOmniError(BuildContext context, Object error) {
  if (!context.mounted) {
    return;
  }
  final l10n = AppLocalizations.of(context);
  final userFacing = describeUserFacingError(error, l10n: l10n);
  showOmniFeedback(
    context,
    userFacing.message.isEmpty
        ? (l10n.errorOperationFailed)
        : userFacing.message,
    severity: OmniFeedbackSeverity.error,
  );
}
