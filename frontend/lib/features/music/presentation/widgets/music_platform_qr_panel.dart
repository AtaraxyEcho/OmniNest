import 'dart:async';
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/app_typography.dart';
import 'package:omninest/app/theme/feature/music_colors.dart';
import 'package:omninest/features/music/application/music_platform_qr_session_controller.dart';
import 'package:omninest/features/music/presentation/widgets/music_platform_login_controls.dart';

/// 账号窗口内的内联二维码登录面板（浅色模式按样例渲染取景框与遮罩）。
///
/// 纯展示组件：不持有轮询或网络调用，状态与命令都来自
/// [platformQrSessionProvider]（application 层）。面板自持的唯一资源是
/// 激光扫描线动画控制器，随面板销毁释放，并在系统减少动态效果时停用。
///
/// 默认只展示"扫码登录"入口：二维码需请求平台会话才能生成，属于有成本的
/// 外部调用，且一次会话只有 5 分钟有效期，进入窗口就自动拉取会浪费会话时长。
class MusicPlatformQrPanel extends ConsumerStatefulWidget {
  const MusicPlatformQrPanel({super.key});

  /// 二维码展示边长：兼顾笔记本屏幕可视高度与手机端识别率。
  static const double qrSize = 176;

  /// "扫码登录"入口按钮的测试键。
  @visibleForTesting
  static const startButtonKey = Key('platformQrStartButton');

  /// 二维码容器的测试键。
  @visibleForTesting
  static const qrContainerKey = Key('platformQrContainer');

  @override
  ConsumerState<MusicPlatformQrPanel> createState() =>
      _MusicPlatformQrPanelState();
}

class _MusicPlatformQrPanelState extends ConsumerState<MusicPlatformQrPanel>
    with SingleTickerProviderStateMixin {
  /// 提前保存 notifier：`dispose()` 中禁止通过 `ref` 查找 Provider。
  late final PlatformQrSessionController _sessionNotifier;

  /// 激光扫描线动画：仅在"等待扫码"时运行（样例 `laser-scan 2.8s`）。
  late final AnimationController _laserController;

  @override
  void initState() {
    super.initState();
    _sessionNotifier = ref.read(platformQrSessionProvider.notifier);
    _laserController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2800),
    );
  }

  @override
  void dispose() {
    _laserController.dispose();
    // 停止轮询但保留会话状态：重新打开面板可继续扫同一张二维码。
    _sessionNotifier.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final session = ref.watch(platformQrSessionProvider);
    _syncLaser(session.status);
    final hasQr =
        session.loginKey != null &&
        session.status != PlatformQrDisplayStatus.idle;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.musicPlatformNeteaseQrHint,
          style: TextStyle(
            color: context.musicColors.onSurfaceVariant,
            fontSize: AppTypography.bodyMedium,
          ),
        ),
        const SizedBox(height: kMusicPlatformFieldGap),
        if (!hasQr) ...[
          _QrEntry(session: session, onStart: () => _sessionNotifier.start()),
        ] else ...[
          Center(child: _QrFrame(session: session, laser: _laserController)),
          const SizedBox(height: kMusicPlatformBlockGap),
          if (session.status == PlatformQrDisplayStatus.starting ||
              session.status == PlatformQrDisplayStatus.unknown)
            _QrStatusLine(session: session),
          if (session.status == PlatformQrDisplayStatus.waiting)
            _QrWaitingHint(),
        ],
      ],
    );
  }

  /// 激光线只在等待扫码时往复运动；系统减少动态效果时保持静止。
  void _syncLaser(PlatformQrDisplayStatus status) {
    final shouldAnimate =
        status == PlatformQrDisplayStatus.waiting &&
        !MediaQuery.disableAnimationsOf(context);
    if (shouldAnimate) {
      if (!_laserController.isAnimating) {
        _laserController.repeat();
      }
      return;
    }
    if (_laserController.isAnimating) {
      _laserController.stop();
    }
  }
}

/// 未申请会话时的入口：只有用户点击后才发起会话申请。
class _QrEntry extends StatelessWidget {
  const _QrEntry({required this.session, required this.onStart});

  final PlatformQrSessionState session;
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    final colors = context.musicColors;
    final l10n = AppLocalizations.of(context);
    final starting = session.status == PlatformQrDisplayStatus.starting;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
          decoration: BoxDecoration(
            color: colors.fieldFill,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: colors.fieldBorder),
          ),
          child: Column(
            children: [
              Icon(
                Icons.qr_code_scanner_rounded,
                size: 40,
                color: colors.onSurfaceVariant,
              ),
              const SizedBox(height: kMusicPlatformFieldGap),
              Text(
                l10n.musicQrLoginInstruction,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: colors.onSurfaceVariant,
                  fontSize: AppTypography.bodyMedium,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: kMusicPlatformBlockGap),
        MusicPlatformPrimaryButton(
          key: MusicPlatformQrPanel.startButtonKey,
          color: const Color(0xFFEC4141),
          icon: Icons.qr_code_rounded,
          label: l10n.musicPlatformQrAction,
          busy: starting,
          onPressed: starting ? null : onStart,
        ),
        if (session.failureMessage != null) ...[
          const SizedBox(height: kMusicPlatformFieldGap),
          Text(
            session.failureMessage!,
            style: TextStyle(
              color: colors.danger,
              fontSize: AppTypography.bodySmall,
            ),
          ),
        ],
      ],
    );
  }
}

/// 取景框：内衬二维码白卡，四角有瞄准括号，等待态运行激光扫描线，
/// 已扫码 / 过期 / 失败时整面覆盖状态遮罩（样例 `qr-confirmed-state` 与
/// `qr-mask`）。
class _QrFrame extends StatelessWidget {
  const _QrFrame({required this.session, required this.laser});

  final PlatformQrSessionState session;
  final AnimationController laser;

  static const double _framePadding = 14;

  @override
  Widget build(BuildContext context) {
    final colors = context.musicColors;
    final isLight = Theme.of(context).brightness == Brightness.light;
    final overlay = _frameOverlay(context);
    return Container(
      key: MusicPlatformQrPanel.qrContainerKey,
      padding: const EdgeInsets.all(_framePadding),
      decoration: BoxDecoration(
        // 浅色取实色浅灰（样例 neutral-50）：在白色磨砂抽屉上形成"凹槽"层级；
        // 深色沿用模块色阶。
        color: isLight ? const Color(0xFFF7F8F9) : colors.fieldFill,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.fieldBorder),
      ),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          _QrImage(session: session),
          ..._buildBrackets(context),
          // 激光扫描线：等待扫码时由上至下往复（样例 `animate-laser`）。
          if (session.status == PlatformQrDisplayStatus.waiting)
            Positioned.fill(
              child: AnimatedBuilder(
                animation: laser,
                builder: (context, _) {
                  return Padding(
                    padding: EdgeInsets.only(
                      top:
                          _framePadding +
                          laser.value * (MusicPlatformQrPanel.qrSize - 16),
                      left: 10,
                      right: 10,
                    ),
                    child: Align(
                      alignment: Alignment.topCenter,
                      child: Container(
                        height: 2,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: <Color>[
                              (isLight ? Colors.black : Colors.white)
                                  .withValues(alpha: 0),
                              (isLight ? Colors.black87 : Colors.white)
                                  .withValues(alpha: 0.85),
                              (isLight ? Colors.black : Colors.white)
                                  .withValues(alpha: 0),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          if (overlay != null) overlay,
        ],
      ),
    );
  }

  /// 已扫码 / 过期 / 失败态的面覆盖遮罩；其余状态返回 null。
  Widget? _frameOverlay(BuildContext context) {
    final colors = context.musicColors;
    final l10n = AppLocalizations.of(context);
    final isLight = Theme.of(context).brightness == Brightness.light;
    final status = session.status;
    final (IconData icon, String message, bool failed) = switch (status) {
      PlatformQrDisplayStatus.scanned => (
        Icons.phonelink_ring_rounded,
        l10n.musicQrScanned,
        false,
      ),
      PlatformQrDisplayStatus.expired => (
        Icons.hourglass_disabled_rounded,
        l10n.musicQrExpired,
        true,
      ),
      PlatformQrDisplayStatus.error => (
        Icons.wifi_off_rounded,
        session.failureMessage ?? l10n.musicQrStatusFailed,
        true,
      ),
      _ => (Icons.info_outline_rounded, '', false),
    };
    if (status != PlatformQrDisplayStatus.scanned &&
        status != PlatformQrDisplayStatus.expired &&
        status != PlatformQrDisplayStatus.error) {
      return null;
    }
    final contentColor = colors.onSurface;
    return Positioned.fill(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: BackdropFilter(
          filter:
              isLight
                  ? ImageFilter.blur(sigmaX: 6, sigmaY: 6)
                  : ImageFilter.blur(sigmaX: 4, sigmaY: 4),
          child: Container(
            color:
                isLight
                    ? Colors.white.withValues(alpha: 0.95)
                    : Colors.black.withValues(alpha: 0.72),
            alignment: Alignment.center,
            padding: const EdgeInsets.all(12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color:
                        isLight
                            ? Colors.black.withValues(alpha: 0.05)
                            : Colors.white.withValues(alpha: 0.1),
                  ),
                  child: Icon(
                    icon,
                    size: 22,
                    color:
                        failed
                            ? colors.danger
                            : contentColor.withValues(alpha: 0.9),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: contentColor,
                    fontSize: AppTypography.bodySmall,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (session.canRegenerate) ...[
                  const SizedBox(height: 10),
                  _QrOverlayRefreshButton(session: session),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 四角瞄准括号（样例 `w-4 h-4 border-t-2 border-l-2`）。
  List<Widget> _buildBrackets(BuildContext context) {
    final colors = context.musicColors;
    final color = colors.onSurface.withValues(alpha: 0.85);
    final borderSide = BorderSide(color: color, width: 2);
    return <Widget>[
      Positioned(
        left: 0,
        top: 0,
        child: _bracket(width: 16, height: 16, topLeft: borderSide),
      ),
      Positioned(
        right: 0,
        top: 0,
        child: _bracket(width: 16, height: 16, topRight: borderSide),
      ),
      Positioned(
        left: 0,
        bottom: 0,
        child: _bracket(width: 16, height: 16, bottomLeft: borderSide),
      ),
      Positioned(
        right: 0,
        bottom: 0,
        child: _bracket(width: 16, height: 16, bottomRight: borderSide),
      ),
    ];
  }

  Widget _bracket({
    required double width,
    required double height,
    BorderSide? topLeft,
    BorderSide? topRight,
    BorderSide? bottomLeft,
    BorderSide? bottomRight,
  }) {
    return SizedBox(
      width: width,
      height: height,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(
            top: topLeft ?? BorderSide.none,
            right: topRight ?? BorderSide.none,
            bottom: bottomLeft ?? BorderSide.none,
            left: bottomRight ?? BorderSide.none,
          ),
          borderRadius: BorderRadius.only(
            topLeft: topLeft != null ? const Radius.circular(4) : Radius.zero,
            topRight: topRight != null ? const Radius.circular(4) : Radius.zero,
            bottomLeft:
                bottomLeft != null ? const Radius.circular(4) : Radius.zero,
            bottomRight:
                bottomRight != null ? const Radius.circular(4) : Radius.zero,
          ),
        ),
      ),
    );
  }
}

/// 已过期 / 失败遮罩内的就地刷新按钮（样例 `点击刷新`）。
class _QrOverlayRefreshButton extends ConsumerWidget {
  const _QrOverlayRefreshButton({required this.session});

  final PlatformQrSessionState session;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final colors = context.musicColors;
    final isLight = Theme.of(context).brightness == Brightness.light;
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap:
          session.regenerating
              ? null
              : () => unawaited(
                ref.read(platformQrSessionProvider.notifier).regenerate(),
              ),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(999),
          color:
              isLight
                  ? Colors.black.withValues(alpha: 0.05)
                  : Colors.white.withValues(alpha: 0.1),
          border: Border.all(color: colors.fieldBorder.withValues(alpha: 0.8)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            session.regenerating
                ? SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: colors.onSurfaceVariant,
                  ),
                )
                : Icon(
                  Icons.refresh_rounded,
                  size: 13,
                  color: colors.onSurfaceVariant,
                ),
            const SizedBox(width: 5),
            Text(
              l10n.musicQrRegenerate,
              style: TextStyle(
                color: colors.onSurfaceVariant,
                fontSize: AppTypography.bodySmall,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 等待扫码时的提示行：呼吸圆点 + 指引文案（样例 `animate-ping` 行）。
class _QrWaitingHint extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final colors = context.musicColors;
    final l10n = AppLocalizations.of(context);
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: colors.onSurface.withValues(alpha: 0.7),
          ),
        ),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            l10n.musicQrLoginInstruction,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: colors.onSurfaceVariant,
              fontSize: AppTypography.bodySmall,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}

/// 申请中 / 未知状态行：只随状态变化重建，不触碰二维码区。
class _QrStatusLine extends StatelessWidget {
  const _QrStatusLine({required this.session});

  final PlatformQrSessionState session;

  @override
  Widget build(BuildContext context) {
    final colors = context.musicColors;
    final l10n = AppLocalizations.of(context);
    final statusText = switch (session.status) {
      PlatformQrDisplayStatus.starting => l10n.musicPlatformQrPreparing,
      PlatformQrDisplayStatus.unknown => l10n.musicQrUnknownStatus(
        session.unknownStatus ?? '',
      ),
      _ => '',
    };
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (session.busy) ...[
          SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: colors.primary,
            ),
          ),
          const SizedBox(width: 8),
        ],
        Flexible(
          child: Text(
            statusText,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: colors.onSurfaceVariant,
              fontSize: AppTypography.bodyMedium,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}

/// 二维码位图：只在会话换码时重新解析。
///
/// `gaplessPlayback` 保证换码期间旧图保留到新图就绪，避免出现一帧白屏闪烁。
class _QrImage extends StatelessWidget {
  const _QrImage({required this.session});

  final PlatformQrSessionState session;

  @override
  Widget build(BuildContext context) {
    final bytes = session.qrBytes;
    final base = SizedBox(
      width: MusicPlatformQrPanel.qrSize,
      height: MusicPlatformQrPanel.qrSize,
      child: Container(
        color: Colors.white,
        alignment: Alignment.center,
        child:
            bytes == null || bytes.isEmpty
                ? const Icon(
                  Icons.qr_code_rounded,
                  size: 56,
                  color: Colors.grey,
                )
                : Image.memory(
                  bytes,
                  fit: BoxFit.contain,
                  gaplessPlayback: true,
                  key: ValueKey<String>(session.loginKey ?? ''),
                ),
      ),
    );
    return ClipRRect(borderRadius: BorderRadius.circular(12), child: base);
  }
}
