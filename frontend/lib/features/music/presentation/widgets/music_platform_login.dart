import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/app_typography.dart';
import 'package:omninest/app/theme/feature/music_colors.dart';
import 'package:omninest/features/music/application/music_controller.dart';
import 'package:omninest/features/music/application/music_platform_library_controller.dart';
import 'package:omninest/features/music/domain/music_models.dart';
import 'package:omninest/features/music/presentation/widgets/music_glass_panel.dart';
import 'package:omninest/core/errors/error_message.dart';

/// 平台登录底部弹出面板
///
/// - 网易云：QR 扫码登录
/// - QQ 音乐：Cookie 手动注入
class PlatformLoginSheet extends ConsumerWidget {
  const PlatformLoginSheet({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const PlatformLoginSheet(),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.musicColors;
    final state = ref.watch(musicCenterControllerProvider).asData?.value;
    return DraggableScrollableSheet(
      initialChildSize: 0.65,
      minChildSize: 0.4,
      maxChildSize: 0.85,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            border: Border(
              top: BorderSide(color: colors.outline.withValues(alpha: 0.15)),
            ),
          ),
          child: Column(
            children: [
              // 拖拽条
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: colors.outline.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
              ),
              // 标题
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
                child: Row(
                  children: [
                    Icon(Icons.cloud_outlined, color: colors.primary, size: 22),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        AppLocalizations.of(context).musicPlatformLoginTitle,
                        style: TextStyle(
                          color: colors.onSurface,
                          fontSize: AppTypography.titleLarge,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: Icon(
                        Icons.close_rounded,
                        color: colors.onSurfaceVariant,
                        size: 20,
                      ),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ),
              Divider(height: 1, color: colors.outline.withValues(alpha: 0.10)),
              // 内容
              Expanded(
                child: ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
                  children: [
                    _NeteaseLoginSection(userInfo: state?.neteaseUserInfo),
                    const SizedBox(height: 20),
                    _QqMusicLoginSection(userInfo: state?.qqUserInfo),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ─── 网易云登录区域 ────────────────────────────────────────

class _NeteaseLoginSection extends ConsumerStatefulWidget {
  const _NeteaseLoginSection({required this.userInfo});

  final PlatformUserInfo? userInfo;

  @override
  ConsumerState<_NeteaseLoginSection> createState() =>
      _NeteaseLoginSectionState();
}

class _NeteaseLoginSectionState extends ConsumerState<_NeteaseLoginSection> {
  bool _loadingQr = false;

  Future<void> _startQrLogin() async {
    final musicController = ref.read(musicCenterControllerProvider.notifier);
    setState(() => _loadingQr = true);
    try {
      final session = await musicController.neteaseQrLogin();
      if (!mounted) return;
      setState(() => _loadingQr = false);
      final status = await showDialog<QrLoginStatus>(
        context: context,
        barrierDismissible: false,
        builder: (_) => _QrLoginDialog(session: session),
      );
      if (!mounted || status?.status != 'confirmed') {
        return;
      }
      // 后台刷新账号与曲库，避免扫码确认后同步全量拉取造成数秒卡顿。
      unawaited(_refreshPlatformData(musicController));
    } on Exception catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _loadingQr = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppLocalizations.of(
              context,
            ).musicSaveFailed(describeUserFacingError(error).message),
          ),
        ),
      );
    }
  }

  Future<void> _refreshPlatformData(dynamic musicController) async {
    try {
      await musicController.loadPlatformInfo();
    } on Object {
      // 账号资料刷新失败不阻塞曲库刷新。
    }
    if (!mounted) {
      return;
    }
    ref.invalidate(musicPlatformLibraryProvider);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.musicColors;
    final user = widget.userInfo;
    return _PlatformCard(
      icon: Icons.cloud_circle_outlined,
      iconColor: const Color(0xFFEC4141),
      title: AppLocalizations.of(context).musicPlatformNeteaseName,
      child:
          user != null
              ? _LoggedInInfo(
                user: user,
                accentColor: const Color(0xFFEC4141),
                onLogout:
                    () => ref
                        .read(musicCenterControllerProvider.notifier)
                        .platformLogout('netease'),
              )
              : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    AppLocalizations.of(context).musicPlatformNeteaseQrHint,
                    style: TextStyle(
                      color: colors.onSurfaceVariant,
                      fontSize: AppTypography.bodyMedium,
                    ),
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFEC4141),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      onPressed: _loadingQr ? null : _startQrLogin,
                      icon:
                          _loadingQr
                              ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                              : const Icon(Icons.qr_code_rounded, size: 18),
                      label: Text(
                        _loadingQr
                            ? AppLocalizations.of(
                              context,
                            ).musicPlatformQrGenerating
                            : AppLocalizations.of(
                              context,
                            ).musicPlatformQrAction,
                        style: const TextStyle(
                          fontSize: AppTypography.bodyLarge,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
    );
  }
}

// ─── QQ音乐登录区域 ────────────────────────────────────────

class _QqMusicLoginSection extends ConsumerStatefulWidget {
  const _QqMusicLoginSection({required this.userInfo});

  final PlatformUserInfo? userInfo;

  @override
  ConsumerState<_QqMusicLoginSection> createState() =>
      _QqMusicLoginSectionState();
}

class _QqMusicLoginSectionState extends ConsumerState<_QqMusicLoginSection> {
  final _cookieController = TextEditingController();
  bool _verifying = false;
  String? _error;

  @override
  void dispose() {
    _cookieController.dispose();
    super.dispose();
  }

  Future<void> _verifyAndSave() async {
    final l10n = AppLocalizations.of(context);
    final cookie = _cookieController.text.trim();
    if (cookie.isEmpty) {
      setState(() => _error = l10n.musicPlatformQqCookieRequired);
      return;
    }
    setState(() {
      _verifying = true;
      _error = null;
    });
    final musicController = ref.read(musicCenterControllerProvider.notifier);
    try {
      await musicController.applyQqCookie(cookie);
      if (!mounted) {
        return;
      }
      _cookieController.clear();
    } on Exception catch (e) {
      if (!mounted) {
        return;
      }
      setState(() => _error = l10n.musicPlatformQqVerifyFailed(e.toString()));
    } finally {
      if (mounted) setState(() => _verifying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.musicColors;
    final user = widget.userInfo;
    return _PlatformCard(
      icon: Icons.headphones_outlined,
      iconColor: const Color(0xFF31C27C),
      title: AppLocalizations.of(context).musicPlatformQqName,
      child:
          user != null
              ? _LoggedInInfo(
                user: user,
                accentColor: const Color(0xFF31C27C),
                onLogout:
                    () => ref
                        .read(musicCenterControllerProvider.notifier)
                        .platformLogout('qq'),
              )
              : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    AppLocalizations.of(context).musicPlatformQqCookieHint,
                    style: TextStyle(
                      color: colors.onSurfaceVariant,
                      fontSize: AppTypography.bodyMedium,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    AppLocalizations.of(context).musicPlatformQqCookieKeyHint,
                    style: TextStyle(
                      color: colors.onSurfaceVariant.withValues(alpha: 0.65),
                      fontSize: AppTypography.labelSmall,
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: _cookieController,
                    maxLines: 3,
                    style: TextStyle(
                      color: colors.onSurface,
                      fontSize: AppTypography.bodyMedium,
                      fontFamily: AppTypography.monoFamily,
                      fontFamilyFallback: AppTypography.monoFamilyFallback,
                    ),
                    decoration: InputDecoration(
                      hintText:
                          AppLocalizations.of(
                            context,
                          ).musicPlatformQqCookiePlaceholder,
                      hintStyle: TextStyle(
                        color: colors.onSurfaceVariant.withValues(alpha: 0.5),
                      ),
                      filled: true,
                      fillColor: colors.surfaceContainerHigh.withValues(
                        alpha: 0.5,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(
                          color: colors.outline.withValues(alpha: 0.2),
                        ),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(
                          color: colors.outline.withValues(alpha: 0.2),
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(
                          color: const Color(0xFF31C27C).withValues(alpha: 0.5),
                        ),
                      ),
                      contentPadding: const EdgeInsets.all(12),
                    ),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      _error!,
                      style: TextStyle(
                        color: colors.danger,
                        fontSize: AppTypography.bodySmall,
                      ),
                    ),
                  ],
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF31C27C),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      onPressed: _verifying ? null : _verifyAndSave,
                      icon:
                          _verifying
                              ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                              : const Icon(Icons.check_rounded, size: 18),
                      label: Text(
                        _verifying
                            ? AppLocalizations.of(
                              context,
                            ).musicPlatformQqVerifying
                            : AppLocalizations.of(
                              context,
                            ).musicPlatformQqVerifyAction,
                        style: const TextStyle(
                          fontSize: AppTypography.bodyLarge,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
    );
  }
}

// ─── 通用组件 ──────────────────────────────────────────────

/// 平台卡片容器
class _PlatformCard extends StatelessWidget {
  const _PlatformCard({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.child,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = context.musicColors;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: colors.surfaceContainer.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(colors.cardBorderRadius),
        border: Border.all(color: colors.outline.withValues(alpha: 0.15)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: iconColor, size: 18),
              ),
              const SizedBox(width: 12),
              Text(
                title,
                style: TextStyle(
                  color: colors.onSurface,
                  fontSize: AppTypography.titleMedium,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }
}

/// 已登录用户信息
class _LoggedInInfo extends StatelessWidget {
  const _LoggedInInfo({
    required this.user,
    required this.accentColor,
    required this.onLogout,
  });

  final PlatformUserInfo user;
  final Color accentColor;
  final VoidCallback onLogout;

  @override
  Widget build(BuildContext context) {
    final colors = context.musicColors;
    return Row(
      children: [
        // 头像
        CircleAvatar(
          radius: 22,
          backgroundColor: accentColor.withValues(alpha: 0.15),
          backgroundImage:
              user.avatarUrl.isNotEmpty ? NetworkImage(user.avatarUrl) : null,
          child:
              user.avatarUrl.isEmpty
                  ? Icon(Icons.person_rounded, color: accentColor, size: 22)
                  : null,
        ),
        const SizedBox(width: 14),
        // 昵称 + VIP
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Flexible(
                    child: Text(
                      user.nickname.isEmpty
                          ? AppLocalizations.of(
                            context,
                          ).musicPlatformAnonymousUser
                          : user.nickname,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: colors.onSurface,
                        fontSize: AppTypography.titleMedium,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  if (user.vip) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: accentColor.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        AppLocalizations.of(context).musicPlatformVipBadge,
                        style: TextStyle(
                          color: accentColor,
                          fontSize: AppTypography.labelSmall,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 2),
              Text(
                AppLocalizations.of(context).musicPlatformUserId(user.userId),
                style: TextStyle(
                  color: colors.onSurfaceVariant.withValues(alpha: 0.6),
                  fontSize: AppTypography.bodySmall,
                ),
              ),
            ],
          ),
        ),
        // 登出按钮
        TextButton(
          style: TextButton.styleFrom(
            foregroundColor: colors.danger,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          ),
          onPressed: onLogout,
          child: Text(
            AppLocalizations.of(context).musicPlatformLogout,
            style: TextStyle(
              fontSize: AppTypography.bodyMedium,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}

// ─── QR 登录对话框 ─────────────────────────────────────────

class _QrLoginDialog extends ConsumerStatefulWidget {
  const _QrLoginDialog({required this.session});

  final QrLoginSession session;

  @override
  ConsumerState<_QrLoginDialog> createState() => _QrLoginDialogState();
}

class _QrLoginDialogState extends ConsumerState<_QrLoginDialog> {
  static const _maximumPollingDuration = Duration(minutes: 3);
  static const _maximumConsecutiveFailures = 5;
  late final MusicCenterController _musicController;
  _QrLoginDisplayStatus _displayStatus = _QrLoginDisplayStatus.waiting;
  String? _unknownStatus;
  bool _cancelled = false;
  bool _completed = false;
  bool _loopActive = false;
  int _consecutiveFailures = 0;

  @override
  void initState() {
    super.initState();
    _musicController = ref.read(musicCenterControllerProvider.notifier);
    unawaited(_runPolling());
  }

  @override
  void dispose() {
    _cancelled = true;
    super.dispose();
  }

  Future<void> _runPolling() async {
    if (_loopActive || _cancelled || _completed) {
      return;
    }
    _loopActive = true;
    final startedAt = DateTime.now();
    try {
      while (mounted && !_cancelled && !_completed) {
        if (DateTime.now().difference(startedAt) >= _maximumPollingDuration) {
          setState(() {
            _displayStatus = _QrLoginDisplayStatus.expired;
          });
          return;
        }
        try {
          final status = await _musicController.checkNeteaseQrLogin(
            widget.session.loginKey,
          );
          if (!mounted || _cancelled || _completed) {
            return;
          }
          _consecutiveFailures = 0;
          switch (status.status) {
            case 'pending':
              setState(() => _displayStatus = _QrLoginDisplayStatus.waiting);
            case 'scanned':
              setState(() => _displayStatus = _QrLoginDisplayStatus.scanned);
            case 'confirmed':
              _completed = true;
              Navigator.of(context).pop(status);
              return;
            case 'expired':
              setState(() => _displayStatus = _QrLoginDisplayStatus.expired);
              return;
            default:
              setState(() {
                _displayStatus = _QrLoginDisplayStatus.unknown;
                _unknownStatus = status.status;
              });
          }
        } on Object {
          if (!mounted || _cancelled) {
            return;
          }
          _consecutiveFailures++;
          setState(() => _displayStatus = _QrLoginDisplayStatus.error);
          if (_consecutiveFailures >= _maximumConsecutiveFailures) {
            return;
          }
        }
        final seconds = switch (_consecutiveFailures) {
          0 => 2,
          1 => 3,
          2 => 6,
          _ => 12,
        };
        await Future<void>.delayed(Duration(seconds: seconds));
      }
    } finally {
      _loopActive = false;
    }
  }

  void _retryPolling() {
    if (_loopActive || _completed) {
      return;
    }
    setState(() {
      _consecutiveFailures = 0;
      _displayStatus = _QrLoginDisplayStatus.waiting;
    });
    unawaited(_runPolling());
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.musicColors;
    final l10n = AppLocalizations.of(context);
    final statusText = switch (_displayStatus) {
      _QrLoginDisplayStatus.waiting => l10n.musicQrWaiting,
      _QrLoginDisplayStatus.scanned => l10n.musicQrScanned,
      _QrLoginDisplayStatus.expired => l10n.musicQrExpired,
      _QrLoginDisplayStatus.error => l10n.musicQrStatusFailed,
      _QrLoginDisplayStatus.unknown => l10n.musicQrUnknownStatus(
        _unknownStatus ?? '',
      ),
    };
    final showProgress =
        _displayStatus == _QrLoginDisplayStatus.waiting ||
        _displayStatus == _QrLoginDisplayStatus.scanned;
    return Dialog(
      backgroundColor: Colors.transparent,
      child: MusicGlassPanel(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              l10n.musicQrLoginTitle,
              style: TextStyle(
                color: colors.onSurface,
                fontSize: AppTypography.titleLarge,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              l10n.musicQrLoginInstruction,
              style: TextStyle(
                color: colors.onSurfaceVariant,
                fontSize: AppTypography.bodyMedium,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            // QR 码
            Container(
              width: 200,
              height: 200,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
              ),
              child: _buildQrContent(),
            ),
            const SizedBox(height: 20),
            // 状态文本
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (showProgress)
                  SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: colors.primary,
                    ),
                  ),
                if (showProgress) const SizedBox(width: 8),
                Text(
                  statusText,
                  style: TextStyle(
                    color:
                        _displayStatus == _QrLoginDisplayStatus.expired ||
                                _displayStatus == _QrLoginDisplayStatus.error
                            ? colors.danger
                            : colors.onSurfaceVariant,
                    fontSize: AppTypography.bodyMedium,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (_displayStatus == _QrLoginDisplayStatus.error)
                  TextButton.icon(
                    onPressed: _retryPolling,
                    icon: const Icon(Icons.refresh_rounded),
                    label: Text(l10n.musicQrRetry),
                  ),
                if (_displayStatus == _QrLoginDisplayStatus.expired)
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text(
                      l10n.readerClose,
                      style: TextStyle(color: colors.onSurfaceVariant),
                    ),
                  )
                else
                  TextButton(
                    onPressed: () {
                      _cancelled = true;
                      Navigator.of(context).pop();
                    },
                    child: Text(
                      l10n.adminCancel,
                      style: TextStyle(color: colors.onSurfaceVariant),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQrContent() {
    final qrImage = widget.session.qrImageBase64;
    if (qrImage == null || qrImage.isEmpty) {
      return const Center(
        child: Icon(Icons.qr_code_rounded, size: 64, color: Colors.grey),
      );
    }
    try {
      // 处理 data:image/png;base64,... 格式
      final base64Str =
          qrImage.contains(',') ? qrImage.split(',').last : qrImage;
      final bytes = base64Decode(base64Str);
      return ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Image.memory(bytes, fit: BoxFit.contain),
      );
    } on Exception catch (_) {
      return const Center(
        child: Icon(Icons.broken_image_rounded, size: 48, color: Colors.grey),
      );
    }
  }
}

enum _QrLoginDisplayStatus { waiting, scanned, expired, error, unknown }
