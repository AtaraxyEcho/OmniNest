import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:omninest/app/theme/app_typography.dart';
import 'package:omninest/features/photos/application/photo_controller.dart';
import 'package:omninest/features/photos/domain/photo.dart';
import 'package:omninest/features/photos/domain/photo_share_link.dart';
import 'package:omninest/features/photos/presentation/widgets/frame_dialogs.dart';
import 'package:omninest/features/photos/presentation/widgets/photo_share_dialog.dart';
import 'package:omninest/features/photos/presentation/widgets/photo_panel_host.dart';

/// 照片分享侧栏：SHARE 眉题 + 预览卡 + LINK 复制 + 分享渠道宫格 + OPTIONS 开关。
///
/// 打开时优先复用该照片已有的最新分享链接，不存在则创建（默认 30 天有效、无密码）；
/// 链接创建后自动复制到剪贴板。渠道宫格与 OPTIONS 为展示占位，尚未接通系统分享。
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
  String? _shareUrl;
  bool _creating = false;
  String? _error;
  bool _copied = false;
  bool _includeLocation = true;
  bool _originalQuality = true;

  /// 分享设置：有效期档位（1d/7d/30d/never）与访问密码；变更即重建链接。
  String _expiryOption = '30d';
  String? _password;
  Timer? _copyResetTimer;
  String? _loadedForPhotoId;

  @override
  void initState() {
    super.initState();
    if (widget.visible) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          unawaited(_ensureShareLink());
        }
      });
    }
  }

  @override
  void didUpdateWidget(PhotoSharePanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.visible && !oldWidget.visible) {
      unawaited(_ensureShareLink());
    }
    if (widget.photo.id != oldWidget.photo.id) {
      _shareUrl = null;
      _loadedForPhotoId = null;
      _error = null;
      _copied = false;
      if (widget.visible) {
        unawaited(_ensureShareLink());
      }
    }
  }

  @override
  void dispose() {
    _copyResetTimer?.cancel();
    super.dispose();
  }

  /// 创建分享链接。后端只存 token 哈希、列表接口不回明文（仅创建时返回一次），
  /// 因此不做"复用已有链接"——每次打开面板创建新链接，旧链接经"管理"撤销。
  Future<void> _ensureShareLink() async {
    final photoId = widget.photo.id;
    if (_creating || (_loadedForPhotoId == photoId && _shareUrl != null)) {
      return;
    }
    setState(() {
      _creating = true;
      _error = null;
    });
    try {
      final controller = ref.read(photoCenterControllerProvider.notifier);
      final link = await controller.createPhotoShare(
        photoId,
        password: _password,
        expiresAt: resolveShareExpiry(_expiryOption),
      );
      if (!mounted || photoId != widget.photo.id) return;
      setState(() {
        _shareUrl = _buildShareUrl(link.token);
        _loadedForPhotoId = photoId;
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

  Future<void> _copyToClipboard() async {
    final url = _shareUrl;
    if (url == null || url.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: url));
    if (!mounted) return;
    setState(() => _copied = true);
    _copyResetTimer?.cancel();
    _copyResetTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) {
        setState(() => _copied = false);
      }
    });
  }

  /// 按当前有效期/密码设置重建链接并复制；用户在 OPTIONS 变更设置时触发。
  Future<void> _recreateLink() async {
    final photoId = widget.photo.id;
    setState(() {
      _creating = true;
      _error = null;
    });
    try {
      final link = await ref
          .read(photoCenterControllerProvider.notifier)
          .createPhotoShare(
            photoId,
            password: _password,
            expiresAt: resolveShareExpiry(_expiryOption),
          );
      if (!mounted || photoId != widget.photo.id) return;
      setState(() {
        _shareUrl = _buildShareUrl(link.token);
        _creating = false;
      });
    } on Exception {
      if (!mounted) return;
      setState(() {
        _creating = false;
        _error = AppLocalizations.of(context).photosShareLinkFailed;
      });
    }
  }

  Future<void> _togglePassword(bool enable, AppLocalizations l10n) async {
    if (!enable) {
      if (_password == null) return;
      _password = null;
      await _recreateLink();
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
    _password = password;
    await _recreateLink();
  }

  String describeShareError(Object error) {
    return AppLocalizations.of(context).photosShareLinkFailed;
  }

  /// 分享页为独立静态页（share.html，原生 JS 调公开 API），
  /// 不依赖 Flutter SPA 部署；链接用路径形态携带令牌，避免地址栏暴露查询参数。
  /// 指向 API 地址会命中受保护接口返回 401。
  String _buildShareUrl(String token) {
    final webBase = ref.read(appEnvironmentProvider).effectiveWebBaseUrl;
    return '$webBase/share/$token';
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
    );
  }

  Widget _buildPreviewCard(String? location) {
    final cover = widget.photo.coverUrl;
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
    final copied = _copied;
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
                  _error ?? (_creating || _shareUrl == null ? '…' : _shareUrl!),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color:
                        _error != null
                            ? Theme.of(context).colorScheme.error
                            : Colors.white.withValues(alpha: 0.50),
                    fontSize: AppTypography.bodySmall,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            TextButton(
              onPressed:
                  (_creating || _shareUrl == null || _error != null)
                      ? null
                      : () => unawaited(_copyToClipboard()),
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
                minimumSize: const Size(60, 36),
              ),
              child: Text(
                copied ? l10n.photosShareCopied : l10n.photosShareCopy,
                style: const TextStyle(
                  fontSize: AppTypography.bodySmall,
                  letterSpacing: 0.04,
                ),
              ),
            ),
          ],
        ),
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
    );
    if (result != null && mounted) {
      // 在管理对话框里新建了带密码/有效期的链接后，刷新面板链接显示。
      final (password, expiryOption) = result;
      if (password.isNotEmpty) {
        try {
          final link = await ref
              .read(photoCenterControllerProvider.notifier)
              .createPhotoShare(
                widget.photo.id,
                password: password,
                expiresAt: resolveShareExpiry(expiryOption),
              );
          if (!mounted) return;
          setState(() {
            _shareUrl = _buildShareUrl(link.token);
            _error = null;
          });
          unawaited(_copyToClipboard());
        } on Exception {
          if (!mounted) return;
          setState(() {
            _error = AppLocalizations.of(context).photosShareLinkFailed;
          });
        }
      }
    }
  }

  Widget _buildShareToGrid(AppLocalizations l10n) {
    final targets = <(Color, IconData, String)>[
      (
        const Color(0xFF34C759),
        Icons.chat_bubble_rounded,
        l10n.photosShareToMessages,
      ),
      (
        const Color(0xFF007AFF),
        Icons.mail_outline_rounded,
        l10n.photosShareToMail,
      ),
      (
        const Color(0xFFE1306C),
        Icons.camera_alt_outlined,
        l10n.photosShareToInstagram,
      ),
      (
        const Color(0xFF8E8E93),
        Icons.more_horiz_rounded,
        l10n.photosShareToMore,
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
              Expanded(child: _buildShareTarget(targets[i])),
            ],
          ],
        ),
      ],
    );
  }

  Widget _buildShareTarget((Color, IconData, String) target) {
    final (color, icon, label) = target;
    return Tooltip(
      message: label,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
        ),
        child: Column(
          children: [
            Icon(icon, size: 20, color: color),
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
            setState(() => _expiryOption = value);
            unawaited(_recreateLink());
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
          onChanged: (v) => setState(() => _includeLocation = v),
        ),
        const SizedBox(height: 8),
        _ShareToggleRow(
          label: l10n.photosShareOptionOriginal,
          sublabel: 'Full resolution',
          value: _originalQuality,
          onChanged: (v) => setState(() => _originalQuality = v),
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
