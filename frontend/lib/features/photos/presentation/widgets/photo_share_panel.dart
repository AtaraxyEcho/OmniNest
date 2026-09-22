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

  Widget _buildPreviewCard(String? location) {
    final cover = widget.photo.coverUrl;
    // 预览卡仅 130 高、宽度受面板约束：按实际显示宽度解码，
    // 避免小尺寸卡片触发全分辨率封面解码。
    final size = MediaQuery.sizeOf(context);
    final cardWidth =
        size.width < photoPanelCompactBreakpoint
            ? size.width
            : photoInfoPanelWidth;
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        height: 130,
        width: double.infinity,
        child: Stack(
          fit: StackFit.expand,
          children: [
            ColoredBox(color: Colors.white.withValues(alpha: 0.05)),
            if (cover != null && cover.isNotEmpty)
              CachedNetworkImage(
                imageUrl: cover,
                cacheKey: widget.photo.coverCacheKey,
                memCacheWidth: thumbnailDecodeWidth(
                  cardWidth,
                  MediaQuery.devicePixelRatioOf(context),
                ),
                fit: BoxFit.cover,
                fadeInDuration: Duration.zero,
                errorWidget: (context, url, error) => const SizedBox.shrink(),
              ),
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment(0, -0.4),
                  colors: [
                    Colors.black.withValues(alpha: 0.5),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
            if (location != null)
              Positioned(
                left: 12,
                bottom: 8,
                child: Text(
                  location,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.60),
                    fontSize: AppTypography.labelSmall,
                    letterSpacing: 0.05,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildLinkSection(AppLocalizations l10n) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.photosShareLinkEyebrow,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.30),
            fontSize: AppTypography.labelSmall,
            letterSpacing: 0.10,
          ),
        ),
        const SizedBox(height: 8),
        // 两条规范槽位：永久与限时。各自独立创建/删除，互不撤销。
        _buildSlotRow(
          l10n,
          permanent: true,
          label: l10n.photosShareSlotPermanent,
          share: _permanentShare,
          url: _permanentUrl,
        ),
        const SizedBox(height: 8),
        _buildSlotRow(
          l10n,
          permanent: false,
          label: l10n.photosShareSlotTimed,
          share: _timedShare,
          url: _timedUrl,
        ),
        if (_error != null) ...[
          const SizedBox(height: 8),
          Text(
            _error!,
            style: TextStyle(
              color: Theme.of(context).colorScheme.error,
              fontSize: AppTypography.labelSmall,
            ),
          ),
        ],
        const SizedBox(height: 8),
        TextButton(
          onPressed: _openManageDialog,
          child: Text(
            l10n.photosShareManage,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.40),
              fontSize: AppTypography.labelSmall,
            ),
          ),
        ),
      ],
    );
  }

  /// 单个槽位行：有链接时展示地址与复制/删除，无链接时提供显式创建入口。
  Widget _buildSlotRow(
    AppLocalizations l10n, {
    required bool permanent,
    required String label,
    required PhotoShareLink? share,
    required String? url,
  }) {
    final copied = _copied && url != null && url == _activeUrl;
    final hasLink = share != null && url != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.45),
            fontSize: AppTypography.labelSmall,
            letterSpacing: 0.04,
          ),
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.08),
                  ),
                ),
                child: Text(
                  url ?? l10n.photosShareSlotEmpty,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.50),
                    fontSize: AppTypography.bodySmall,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            if (hasLink) ...[
              TextButton(
                onPressed:
                    _creating
                        ? null
                        : () => unawaited(_copyToClipboard(url: url)),
                style: TextButton.styleFrom(
                  backgroundColor:
                      copied
                          ? const Color(0x264ADE80)
                          : Colors.white.withValues(alpha: 0.10),
                  foregroundColor:
                      copied
                          ? const Color(0xFF4ADE80)
                          : Colors.white.withValues(alpha: 0.80),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                    side: BorderSide(
                      color:
                          copied
                              ? const Color(0x4D4ADE80)
                              : Colors.white.withValues(alpha: 0.10),
                    ),
                  ),
                  minimumSize: const Size(56, 36),
                ),
                child: Text(
                  copied ? l10n.photosShareCopied : l10n.photosShareCopy,
                  style: const TextStyle(
                    fontSize: AppTypography.bodySmall,
                    letterSpacing: 0.04,
                  ),
                ),
              ),
              IconButton(
                tooltip: l10n.coreDelete,
                onPressed:
                    _creating
                        ? null
                        : () => unawaited(_removeSlot(permanent: permanent)),
                icon: Icon(
                  Icons.delete_outline,
                  size: 18,
                  color: Colors.white.withValues(alpha: 0.45),
                ),
              ),
            ] else
              TextButton(
                onPressed:
                    _creating
                        ? null
                        : () => unawaited(
                          _createOrReplaceSlot(permanent: permanent),
                        ),
                style: TextButton.styleFrom(
                  backgroundColor: Colors.white.withValues(alpha: 0.10),
                  foregroundColor: Colors.white.withValues(alpha: 0.80),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                    side: BorderSide(
                      color: Colors.white.withValues(alpha: 0.10),
                    ),
                  ),
                  minimumSize: const Size(56, 36),
                ),
                child: Text(
                  permanent
                      ? l10n.photosShareSlotCreatePermanent
                      : l10n.photosShareSlotCreateTimed,
                  style: const TextStyle(
                    fontSize: AppTypography.bodySmall,
                    letterSpacing: 0.04,
                  ),
                ),
              ),
          ],
        ),
        // 设置（密码/有效期/隐私）变更后按当前设置重建该槽链接。
        if (hasLink && _settingsDirty)
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed:
                  _creating
                      ? null
                      : () =>
                          unawaited(_createOrReplaceSlot(permanent: permanent)),
              child: Text(
                l10n.photosShareLinkUpdate,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.60),
                  fontSize: AppTypography.labelSmall,
                ),
              ),
            ),
          ),
      ],
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

  Widget _buildShareToGrid(AppLocalizations l10n) {
    // 移动端：系统分享入口（可选微信）+ 复制；桌面/Web：二维码 + 复制。
    final showSystemShare = photoShareChannel.supportsSystemShare;
    final targets = <(Color, IconData, String, VoidCallback)>[
      if (showSystemShare)
        (
          const Color(0xFF07C160),
          Icons.chat_bubble_rounded,
          l10n.photosShareToWeChat,
          () => unawaited(_shareViaSystem(l10n)),
        ),
      (
        const Color(0xFF007AFF),
        Icons.link_rounded,
        l10n.photosShareCopy,
        () => unawaited(_copyToClipboard()),
      ),
      if (!showSystemShare)
        (
          const Color(0xFF8E8E93),
          Icons.qr_code_2_rounded,
          l10n.photosShareToQr,
          () => _showQrCode(l10n),
        ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.photosShareToEyebrow,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.30),
            fontSize: AppTypography.labelSmall,
            letterSpacing: 0.10,
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            for (var i = 0; i < targets.length; i++) ...[
              if (i > 0) const SizedBox(width: 8),
              Expanded(
                child: _buildShareTarget(
                  targets[i].$1,
                  targets[i].$2,
                  targets[i].$3,
                  targets[i].$4,
                  enabled: _activeUrl != null,
                ),
              ),
            ],
          ],
        ),
      ],
    );
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

  Widget _buildShareTarget(
    Color color,
    IconData icon,
    String label,
    VoidCallback onTap, {
    required bool enabled,
  }) {
    return Tooltip(
      message: label,
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
          ),
          child: Column(
            children: [
              Icon(
                icon,
                size: 20,
                color: enabled ? color : color.withValues(alpha: 0.35),
              ),
              const SizedBox(height: 8),
              Text(
                label,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.40),
                  fontSize: AppTypography.labelSmall,
                  letterSpacing: 0.04,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildOptions(AppLocalizations l10n, String? location) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.photosShareOptionsEyebrow,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.30),
            fontSize: AppTypography.labelSmall,
            letterSpacing: 0.10,
          ),
        ),
        const SizedBox(height: 12),
        _ShareSelectRow(
          label: l10n.photosShareExpiryOption,
          value: _expiryOption,
          onSelected: (value) {
            if (value == _expiryOption) return;
            setState(() {
              _expiryOption = value;
              _settingsDirty = true;
            });
          },
        ),
        const SizedBox(height: 8),
        _ShareToggleRow(
          label: l10n.photosSharePasswordOption,
          sublabel:
              _password != null
                  ? l10n.photosSharePasswordOn
                  : l10n.photosSharePasswordNone,
          value: _password != null,
          onChanged: (on) => unawaited(_togglePassword(on, l10n)),
        ),
        const SizedBox(height: 8),
        _ShareToggleRow(
          label: l10n.photosShareOptionLocation,
          sublabel: location ?? '—',
          value: _includeLocation,
          onChanged: (v) {
            if (v == _includeLocation) return;
            setState(() {
              _includeLocation = v;
              _settingsDirty = true;
            });
          },
        ),
        const SizedBox(height: 8),
        _ShareToggleRow(
          label: l10n.photosShareOptionOriginal,
          sublabel: l10n.photosShareOptionOriginalFull,
          value: _originalQuality,
          onChanged: (v) {
            if (v == _originalQuality) return;
            setState(() {
              _originalQuality = v;
              _settingsDirty = true;
            });
          },
        ),
      ],
    );
  }
}

/// OPTIONS 选择行：整行下拉，右侧显示当前档位。
class _ShareSelectRow extends StatelessWidget {
  const _ShareSelectRow({
    required this.label,
    required this.value,
    required this.onSelected,
  });

  final String label;
  final String value;
  final ValueChanged<String> onSelected;

  List<(String, String)> _entries(AppLocalizations l10n) {
    return [
      ('1d', l10n.photosShareExpiry1d),
      ('7d', l10n.photosShareExpiry7d),
      ('30d', l10n.photosShareExpiry30d),
      ('never', l10n.photosShareExpiryNever),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final entries = _entries(l10n);
    final current = entries.firstWhere(
      (entry) => entry.$1 == value,
      orElse: () => entries.first,
    );
    return PopupMenuButton<String>(
      onSelected: onSelected,
      tooltip: '',
      color: const Color(0xFF1C1C1C),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.white.withValues(alpha: 0.10)),
      ),
      itemBuilder:
          (context) => [
            for (final entry in entries)
              PopupMenuItem(
                value: entry.$1,
                height: 40,
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        entry.$2,
                        style: TextStyle(
                          color:
                              entry.$1 == value
                                  ? const Color(0xFF4ADE80)
                                  : Colors.white.withValues(alpha: 0.80),
                          fontSize: AppTypography.bodyMedium,
                        ),
                      ),
                    ),
                    if (entry.$1 == value)
                      const Icon(
                        Icons.check_rounded,
                        size: 16,
                        color: Color(0xFF4ADE80),
                      ),
                  ],
                ),
              ),
          ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.75),
                  fontSize: AppTypography.bodySmall,
                ),
              ),
            ),
            Text(
              current.$2,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.45),
                fontSize: AppTypography.labelSmall,
              ),
            ),
            const SizedBox(width: 4),
            Icon(
              Icons.expand_more_rounded,
              size: 16,
              color: Colors.white.withValues(alpha: 0.40),
            ),
          ],
        ),
      ),
    );
  }
}

/// OPTIONS 开关行：iOS 胶囊 36×22，开态绿色。
class _ShareToggleRow extends StatelessWidget {
  const _ShareToggleRow({
    required this.label,
    required this.sublabel,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final String sublabel;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => onChanged(!value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.75),
                      fontSize: AppTypography.bodySmall,
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    sublabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.30),
                      fontSize: AppTypography.labelSmall,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            GestureDetector(
              onTap: () => onChanged(!value),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                width: 36,
                height: 22,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(999),
                  color:
                      value
                          ? const Color(0xB34ADE80)
                          : Colors.white.withValues(alpha: 0.15),
                ),
                child: AnimatedAlign(
                  duration: const Duration(milliseconds: 250),
                  curve: Curves.easeOutCubic,
                  alignment:
                      value ? Alignment.centerRight : Alignment.centerLeft,
                  child: Container(
                    width: 18,
                    height: 18,
                    margin: const EdgeInsets.all(2),
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(color: Color(0x66000000), blurRadius: 3),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
