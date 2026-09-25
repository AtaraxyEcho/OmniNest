import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:omninest/app/theme/app_typography.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:omninest/features/photos/application/photo_controller.dart';
import 'package:omninest/features/photos/domain/photo.dart';
import 'package:omninest/features/photos/domain/photo_share_link.dart';
import 'package:omninest/features/photos/platform/photo_share_channel.dart';
import 'package:omninest/features/photos/presentation/widgets/frame_dialogs.dart';
import 'package:omninest/features/photos/presentation/widgets/photo_share_dialog.dart';
import 'package:omninest/features/photos/presentation/widgets/photo_panel_host.dart';
import 'package:omninest/features/photos/presentation/widgets/photo_thumb_image.dart';
import 'package:omninest/core/log/dev_log.dart';
import 'package:omninest/core/utils/clipboard_writer.dart';
import 'package:omninest/app/theme/severity_colors.dart';
import 'package:omninest/app/theme/feature/photos_chrome_colors.dart';

part 'photo_share_panel_builders.dart';
part 'photo_share_panel_rows.dart';

/// 照片分享侧栏：SHARE 眉题 + 预览卡 + LINK 复制 + 分享渠道宫格 + OPTIONS 开关。
///
/// 打开时撤销该照片旧有效链并新建；链接创建后自动复制。渠道按平台取用：
/// 移动端「微信」按钮走 [photoShareChannel] 系统分享（不可用降级复制），
/// 桌面/Web 展示二维码扫码进手机；复制全平台可用。
class PhotoSharePanel extends ConsumerStatefulWidget {
  const PhotoSharePanel({
    required this.visible,
    required this.photo,
    this.onDone,
    super.key,
  });

  final bool visible;
  final PhotoItem photo;

  /// 用户点击 Done 或关闭侧栏时回调，由宿主收敛 visible 状态。
  final VoidCallback? onDone;

  @override
  ConsumerState<PhotoSharePanel> createState() => _PhotoSharePanelState();
}

class _PhotoSharePanelState extends ConsumerState<PhotoSharePanel> {
  bool _creating = false;
  String? _error;
  bool _copied = false;
  bool _includeLocation = true;
  bool _originalQuality = true;

  /// 分享设置：有效期档位（1d/7d/30d/never）与访问密码。
  /// 变更只置脏，不再自动重建链接——由用户点击创建/更新链接时生效。
  String _expiryOption = '30d';
  String? _password;
  Timer? _copyResetTimer;

  /// 两条规范槽位（按链接的 expiresAt 区分）：永久与限时。
  /// 各自独立存在，创建某槽不撤销另一槽；空值表示该槽尚未创建。
  PhotoShareLink? _permanentShare;
  PhotoShareLink? _timedShare;
  String? _permanentUrl;
  String? _timedUrl;

  /// 设置已变更、尚未应用到链接。
  bool _settingsDirty = false;

  @override
  void initState() {
    super.initState();
    if (widget.visible) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          unawaited(_loadShareState());
        }
      });
    }
  }

  @override
  void didUpdateWidget(PhotoSharePanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.visible && !oldWidget.visible) {
      unawaited(_loadShareState());
    }
    if (widget.photo.id != oldWidget.photo.id) {
      _permanentShare = null;
      _timedShare = null;
      _permanentUrl = null;
      _timedUrl = null;
      _settingsDirty = false;
      _error = null;
      _copied = false;
      if (widget.visible) {
        unawaited(_loadShareState());
      }
    }
  }

  @override
  void dispose() {
    _copyResetTimer?.cancel();
    super.dispose();
  }

  /// 打开/切换照片时加载分享状态。
  ///
  /// 打开面板不创建链接：已有仍有效的链接按槽位复用展示（令牌由后端解密
  /// 回传，可长期复制同一地址），空槽由用户显式点击创建。
  Future<void> _loadShareState() async {
    final photoId = widget.photo.id;
    setState(() {
      _creating = false;
      _error = null;
    });
    List<PhotoShareLink> shares;
    try {
      shares = await ref
          .read(photoCenterControllerProvider.notifier)
          .listPhotoShares(photoId);
    } on Exception {
      if (!mounted || photoId != widget.photo.id) return;
      setState(
        () => _error = AppLocalizations.of(context).photosShareLinkFailed,
      );
      return;
    }
    if (!mounted || photoId != widget.photo.id) return;
    final permanent = _pickReusableShare(shares, permanent: true);
    final timed = _pickReusableShare(shares, permanent: false);
    setState(() {
      _settingsDirty = false;
      _permanentShare = permanent;
      _timedShare = timed;
      _permanentUrl = null;
      _timedUrl = null;
    });
    final permanentUrl =
        permanent == null ? null : await _buildShareUrl(permanent.token);
    if (!mounted || photoId != widget.photo.id) return;
    final timedUrl = timed == null ? null : await _buildShareUrl(timed.token);
    if (!mounted || photoId != widget.photo.id) return;
    setState(() {
      _permanentUrl = permanentUrl;
      _timedUrl = timedUrl;
    });
  }

  /// 从列表中挑选某槽位可复用的链接：未过期、未耗尽且带明文令牌的最新一条。
  ///
  /// 槽位按链接是否设置过期时间区分：永久槽对应 expiresAt 为空。
  PhotoShareLink? _pickReusableShare(
    List<PhotoShareLink> shares, {
    required bool permanent,
  }) {
    for (final share in shares) {
      if (share.isExpired || share.isExhausted) {
        continue;
      }
      if ((share.expiresAt == null) != permanent) {
        continue;
      }
      // 后端未回传令牌（历史链接）时无法展示地址，视为不可复用。
      if (share.token.isEmpty) {
        continue;
      }
      return share;
    }
    return null;
  }

  /// 创建或更新指定槽位的链接。
  ///
  /// 只在用户显式点击时触发；仅替换同一槽位的既有链接，另一槽位不受影响，
  /// 因此不需要"清空全部"即可维持一永久一限时两条链接。
  Future<void> _createOrReplaceSlot({required bool permanent}) async {
    final photoId = widget.photo.id;
    setState(() {
      _creating = true;
      _error = null;
    });
    try {
      final controller = ref.read(photoCenterControllerProvider.notifier);
      final existing = permanent ? _permanentShare : _timedShare;
      if (existing != null) {
        await controller.revokeAlbumShare(existing.id);
      }
      final link = await controller.createPhotoShare(
        photoId,
        password: _password,
        expiresAt: permanent ? null : resolveShareExpiry(_expiryOption),
        includeLocation: _includeLocation,
        originalQuality: _originalQuality,
      );
      if (!mounted || photoId != widget.photo.id) return;
      final shareUrl = await _buildShareUrl(link.token);
      if (!mounted || photoId != widget.photo.id) return;
      setState(() {
        if (permanent) {
          _permanentShare = link;
          _permanentUrl = shareUrl;
        } else {
          _timedShare = link;
          _timedUrl = shareUrl;
        }
        _settingsDirty = false;
        _creating = false;
      });
    } on Exception catch (error) {
      if (!mounted) return;
      setState(() {
        _creating = false;
        _error = describeShareError(error);
      });
    }
  }

  /// 删除指定槽位的链接（撤销后该槽回到未创建态）。
  Future<void> _removeSlot({required bool permanent}) async {
    final photoId = widget.photo.id;
    final existing = permanent ? _permanentShare : _timedShare;
    if (existing == null) {
      return;
    }
    setState(() => _creating = true);
    try {
      await ref
          .read(photoCenterControllerProvider.notifier)
          .revokeAlbumShare(existing.id);
    } on Exception catch (error) {
      if (!mounted) return;
      setState(() {
        _creating = false;
        _error = describeShareError(error);
      });
      return;
    }
    if (!mounted || photoId != widget.photo.id) return;
    setState(() {
      if (permanent) {
        _permanentShare = null;
        _permanentUrl = null;
      } else {
        _timedShare = null;
        _timedUrl = null;
      }
      _creating = false;
    });
  }

  /// 渠道分享/二维码使用的地址：优先限时槽，其次永久槽。
  String? get _activeUrl => _timedUrl ?? _permanentUrl;

  Future<void> _copyToClipboard({String? url}) async {
    final target = url ?? _activeUrl;
    if (target == null || target.isEmpty) return;
    final copied = await copyTextToClipboard(target);
    if (!mounted) return;
    if (!copied) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context).clipboardCopyFailed),
        ),
      );
      return;
    }
    setState(() => _copied = true);
    _copyResetTimer?.cancel();
    _copyResetTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) {
        setState(() => _copied = false);
      }
    });
  }

  /// 开关密码：只修改设置并置脏，由用户点击创建/更新链接时生效。
  Future<void> _togglePassword(bool enable, AppLocalizations l10n) async {
    if (!enable) {
      if (_password == null) return;
      setState(() {
        _password = null;
        _settingsDirty = true;
      });
      return;
    }
    final password = await showFramePromptDialog(
      context,
      title: l10n.photosSharePasswordOption,
      hint: l10n.photosSharePasswordHint,
      obscureText: true,
      confirmLabel: l10n.coreConfirm,
    );
    if (!mounted || password == null || password.isEmpty) return;
    setState(() {
      _password = password;
      _settingsDirty = true;
    });
  }

  String describeShareError(Object error) {
    return AppLocalizations.of(context).photosShareLinkFailed;
  }

  /// 分享页为独立静态页（share.html，原生 JS 调公开 API），
  /// 不依赖 Flutter SPA 部署；链接用路径形态携带令牌，避免地址栏暴露查询参数。
  /// 指向 API 地址会命中受保护接口返回 401。
  /// 单照分享链接为 SPA hash 路由（/shared/photos/item/:token），基址取
  /// 服务器下发的对外 Web 地址；未配置时回退浏览器地址或 API origin
  ///（仅本机可用）。旧路径形态 /share/{token} 仅开发期后端托管页可用，
  /// 生产 nginx 与 SPA 路由均无该路径，已废弃。
  Future<String> _buildShareUrl(String token) async {
    final webBase = await ref.read(webShareBaseUrlResolverProvider).resolve();
    return '$webBase/#/shared/photos/item/$token';
  }

  /// 将状态变更封装为回调，供扩展中的构建方法触发重建。
  void _update(VoidCallback fn) {
    setState(fn);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final preferZh = Localizations.localeOf(context).languageCode == 'zh';
    final location = widget.photo.locationDisplay(preferZh: preferZh);
    return PhotoPanelHost(
      visible: widget.visible,
      onClose: () => widget.onDone?.call(),
      child: Container(
        decoration: photoPanelContainerDecoration(context),
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            padding:
                MediaQuery.sizeOf(context).width < photoPanelCompactBreakpoint
                    ? const EdgeInsets.fromLTRB(24, 20, 24, 24)
                    : const EdgeInsets.fromLTRB(24, 64, 24, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.photosShareEyebrow,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.30),
                    fontSize: AppTypography.labelSmall,
                    letterSpacing: 0.14,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  widget.photo.title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: AppTypography.titleLarge,
                    fontWeight: FontWeight.w300,
                  ),
                ),
                const SizedBox(height: 28),
                _buildPreviewCard(location),
                const SizedBox(height: 24),
                _buildLinkSection(l10n),
                const SizedBox(height: 24),
                _buildShareToGrid(l10n),
                const SizedBox(height: 24),
                _buildOptions(l10n, location),
                const SizedBox(height: 32),
                SizedBox(
                  width: double.infinity,
                  child: TextButton(
                    onPressed: widget.onDone,
                    style: TextButton.styleFrom(
                      backgroundColor: Colors.white.withValues(alpha: 0.10),
                      foregroundColor: Colors.white.withValues(alpha: 0.90),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(
                          color: Colors.white.withValues(alpha: 0.10),
                        ),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    child: Text(
                      l10n.photosShareDone,
                      style: const TextStyle(
                        fontSize: AppTypography.bodyMedium,
                        letterSpacing: 0.04,
                        fontWeight: FontWeight.w300,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _openManageDialog() async {
    final controller = ref.read(photoCenterControllerProvider.notifier);
    List<PhotoShareLink> shares = [];
    try {
      shares = await controller.listPhotoShares(widget.photo.id);
    } on Exception {
      // 管理入口加载失败时按空列表打开，可在对话框内重试撤销等操作
    }
    if (!mounted) return;
    final result = await showPhotoShareDialog(
      context,
      title: AppLocalizations.of(context).photosSharePhoto,
      shares: shares,
      onRevoke:
          (shareId) => ref
              .read(photoCenterControllerProvider.notifier)
              .revokeAlbumShare(shareId),
      onRevokeAll:
          () => ref
              .read(photoCenterControllerProvider.notifier)
              .revokeAllPhotoShares(widget.photo.id),
    );
    if (!mounted) return;
    if (result == null) {
      // 对话框内可能已撤销/清空链接：重新加载槽位状态。
      await _loadShareState();
      return;
    }
    // 在管理对话框里新建了链接（密码留空 = 显式创建无密码链接）：
    // 按"限时"语义创建并归入限时槽，刷新面板显示。
    final (password, expiryOption) = result;
    try {
      final link = await ref
          .read(photoCenterControllerProvider.notifier)
          .createPhotoShare(
            widget.photo.id,
            password: password.isEmpty ? null : password,
            expiresAt: resolveShareExpiry(expiryOption),
            includeLocation: _includeLocation,
            originalQuality: _originalQuality,
          );
      if (!mounted) return;
      final shareUrl = await _buildShareUrl(link.token);
      if (!mounted) return;
      setState(() {
        _timedShare = link;
        _timedUrl = shareUrl;
        _error = null;
      });
      await _copyToClipboard(url: shareUrl);
    } on Exception {
      if (!mounted) return;
      setState(() {
        _error = AppLocalizations.of(context).photosShareLinkFailed;
      });
    }
  }

  Future<void> _shareViaSystem(AppLocalizations l10n) async {
    final url = _activeUrl;
    if (url == null || url.isEmpty) {
      return;
    }
    final result = await photoShareChannel.shareLink(
      title: widget.photo.title,
      url: url,
    );
    if (!mounted) {
      return;
    }
    switch (result) {
      case PhotoShareChannelSuccess():
        return;
      case PhotoShareChannelUnsupported(:final reason):
        devLog('系统分享不可用，降级复制链接：$reason');
        await _copyToClipboard();
        if (!mounted) {
          return;
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.photosShareWeChatCopiedFallback)),
        );
      case PhotoShareChannelFailure(:final message):
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  void _showQrCode(AppLocalizations l10n) {
    final url = _activeUrl;
    if (!mounted) {
      return;
    }
    showDialog<void>(
      context: context,
      builder:
          (dialogContext) => AlertDialog(
            title: Text(l10n.photosShareToQr),
            content:
                url == null || url.isEmpty
                    ? Text(l10n.photosShareLinkFailed)
                    // 固定宽度：QrImageView 内部 LayoutBuilder 不支持
                    // AlertDialog 的固有尺寸测量。
                    : SizedBox(
                      width: 260,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(12),
                            color: Colors.white,
                            child: QrImageView(data: url, size: 192),
                          ),
                          const SizedBox(height: 12),
                          SelectableText(
                            url,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.55),
                              fontSize: AppTypography.bodySmall,
                            ),
                          ),
                        ],
                      ),
                    ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: Text(l10n.coreConfirm),
              ),
            ],
          ),
    );
  }
}
