import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:omninest/app/theme/app_typography.dart';
import 'package:omninest/core/widgets/workstation_dialog.dart';
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
import 'package:omninest/core/feedback/omni_feedback.dart';

part 'photo_share_panel_builders.dart';
part 'photo_share_panel_rows.dart';

/// 照片分享侧栏：分享眉题 + 预览卡 + 链接 + 分享渠道 + 链接设置。
///
/// 面板只编辑一条链接，地址在链接存续期间保持不变：改有效期、密码或可见范围
/// 走 PATCH 原地写回，不再"撤销 + 重建"，否则已经发出去的地址会当场失效。
/// 尚未创建链接时，设置只作为创建参数暂存。渠道按平台取用：移动端「微信」按钮
/// 走 [photoShareChannel] 系统分享（不可用降级复制），桌面/Web 展示二维码扫码
/// 进手机；复制全平台可用。
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

  /// 分享设置：有效期档位（1d/7d/30d/never）与待写入的访问密码。
  /// 已有链接时改动即时写回；尚未创建链接时只作为创建参数暂存。
  String _expiryOption = '30d';

  /// 待写入的明文口令，只在"还没有链接、等待创建"时留存；写回成功后立即清空。
  String? _password;

  /// 链接是否受口令保护。口令只存哈希、读不回明文，界面因此只能显示状态，
  /// 不能把"未知"当成"未设置"。
  bool _passwordProtected = false;

  Timer? _copyResetTimer;

  /// 面板编辑的唯一链接及其地址。
  ///
  /// 后端允许同一照片存在多条链接，但"有效期"必须是这根链接的属性而不是
  /// 切换编辑对象——否则改一次档位就换一条 URL，等于让已经发出去的地址失效。
  /// 其余链接只在"管理已有链接"里呈现与撤销。
  PhotoShareLink? _share;
  String? _shareUrl;

  /// 设置改动正在写回后端，期间禁用设置控件避免并发覆盖。
  bool _saving = false;

  /// 除当前编辑对象外仍有效的链接数，用于提示用户去管理入口查看。
  int _otherShareCount = 0;

  /// 创建或写回进行中：期间所有可提交入口统一禁用。
  bool get _busy => _creating || _saving;

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
      _resetState();
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

  /// 切换照片时丢弃上一张照片的编辑对象与暂存设置。
  ///
  /// 由 didUpdateWidget 调用，处于 build 阶段，不得触发 setState。
  void _resetState() {
    _share = null;
    _shareUrl = null;
    _password = null;
    _passwordProtected = false;
    _otherShareCount = 0;
    _expiryOption = '30d';
    _includeLocation = true;
    _originalQuality = true;
    _error = null;
    _copied = false;
  }

  /// 打开/切换照片时加载分享状态。
  ///
  /// 打开面板不创建链接：已有仍有效的链接直接复用展示（令牌由后端解密回传，
  /// 可长期复制同一地址），没有链接时由用户点击创建。
  Future<void> _loadShareState() async {
    final photoId = widget.photo.id;
    setState(() {
      _creating = false;
      _saving = false;
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
    final live =
        shares
            .where((share) => !share.isExpired && !share.isExhausted)
            .toList();
    final share = _pickEditableShare(live);
    setState(() {
      _share = share;
      _shareUrl = null;
      _otherShareCount = share == null ? live.length : live.length - 1;
      if (share != null) {
        _password = null;
        _passwordProtected = share.passwordProtected;
        _expiryOption = _expiryOptionFor(share.expiresAt);
        _includeLocation = share.includeLocation;
        _originalQuality = share.originalQuality;
      }
    });
    final token = share?.token;
    if (token == null || token.isEmpty) return;
    final shareUrl = await _buildShareUrl(token);
    if (!mounted || photoId != widget.photo.id) return;
    setState(() => _shareUrl = shareUrl);
  }

  /// 从仍有效的链接里挑面板编辑对象：带明文令牌的最新一条。
  ///
  /// 后端未回传令牌的历史链接无法展示地址，不作为编辑对象，只计入"另有"。
  PhotoShareLink? _pickEditableShare(List<PhotoShareLink> live) {
    PhotoShareLink? newest;
    for (final share in live) {
      if (share.token.isEmpty) continue;
      final created = share.createdAt;
      final newestCreated = newest?.createdAt;
      if (newest == null ||
          (created != null &&
              newestCreated != null &&
              created.isAfter(newestCreated))) {
        newest = share;
      }
    }
    return newest;
  }

  /// 由链接的过期时刻反推档位，把已有链接映射回有效期选择器。
  ///
  /// 档位是相对时长、落库是绝对时刻，只能按剩余时长归到最近的一档；
  /// 改档时会写入新的绝对时刻，因此不会累积跨档歧义。
  String _expiryOptionFor(DateTime? expiresAt) {
    if (expiresAt == null) return 'never';
    final remaining = expiresAt.difference(DateTime.now());
    if (remaining <= const Duration(days: 1)) return '1d';
    if (remaining <= const Duration(days: 7)) return '7d';
    return '30d';
  }

  /// 按当前设置创建链接。已有链接时设置改动直接写回，不进入此方法。
  Future<void> _createShare() async {
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
            includeLocation: _includeLocation,
            originalQuality: _originalQuality,
          );
      if (!mounted || photoId != widget.photo.id) return;
      final shareUrl = await _buildShareUrl(link.token);
      if (!mounted || photoId != widget.photo.id) return;
      setState(() {
        _share = link;
        _shareUrl = shareUrl;
        _password = null;
        _passwordProtected = link.passwordProtected;
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

  /// 把当前设置原地写回已有链接：令牌不变，已发出的地址改完仍可用。
  ///
  /// `password` 只在用户本次改了口令时传值（空串表示清除），其余情况传 null
  /// 保持原密码——服务端只存哈希，回读不到明文，跟着全量提交会抹掉提取码。
  /// 访问次数上限面板不编辑，按链接现值回填，避免被"整体替换"清零。
  /// 写回失败时把设置回滚到服务端状态，否则界面会显示一个并未生效的档位。
  Future<void> _applySettings({String? password}) async {
    final share = _share;
    if (share == null) return;
    final photoId = widget.photo.id;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final link = await ref
          .read(photoCenterControllerProvider.notifier)
          .updatePhotoShare(
            share.id,
            password: password,
            expiresAt: resolveShareExpiry(_expiryOption),
            maxAccessCount: share.maxAccessCount,
            includeLocation: _includeLocation,
            originalQuality: _originalQuality,
          );
      if (!mounted || photoId != widget.photo.id) return;
      setState(() {
        _share = link;
        _password = null;
        _passwordProtected = link.passwordProtected;
        _saving = false;
      });
    } on Exception catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = describeUpdateError(error);
        _syncSettingsFromShare();
      });
    }
  }

  void _syncSettingsFromShare() {
    final share = _share;
    if (share == null) return;
    _expiryOption = _expiryOptionFor(share.expiresAt);
    _includeLocation = share.includeLocation;
    _originalQuality = share.originalQuality;
    _password = null;
    _passwordProtected = share.passwordProtected;
  }

  /// 撤销当前链接。撤销后重新加载：另一条仍有效的链接会顶上编辑位。
  Future<void> _removeShare() async {
    final share = _share;
    if (share == null) return;
    final photoId = widget.photo.id;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref
          .read(photoCenterControllerProvider.notifier)
          .revokeAlbumShare(share.id);
    } on Exception catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = describeUpdateError(error);
      });
      return;
    }
    if (!mounted || photoId != widget.photo.id) return;
    await _loadShareState();
  }

  Future<void> _copyToClipboard({String? url}) async {
    final target = url ?? _shareUrl;
    if (target == null || target.isEmpty) return;
    final copied = await copyTextToClipboard(target);
    if (!mounted) return;
    if (!copied) {
      showOmniFeedback(
        context,
        AppLocalizations.of(context).clipboardCopyFailed,
        severity: OmniFeedbackSeverity.error,
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

  /// 口令开关：已有链接时立即写回（关闭提交空串表示清除），
  /// 还没有链接时只暂存待创建的值。
  Future<void> _togglePassword(bool enable, AppLocalizations l10n) async {
    if (!enable) {
      if (!_passwordProtected) return;
      if (_share == null) {
        setState(() {
          _password = null;
          _passwordProtected = false;
        });
        return;
      }
      await _applySettings(password: '');
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
    if (_share == null) {
      setState(() {
        _password = password;
        _passwordProtected = true;
      });
      return;
    }
    await _applySettings(password: password);
  }

  String describeShareError(Object error) {
    return AppLocalizations.of(context).photosShareLinkFailed;
  }

  /// 原地写回/撤销失败的文案：不能复用"创建失败"，否则用户以为链接没建成，
  /// 实际是设置没生效、旧地址仍然可用。
  String describeUpdateError(Object error) {
    return AppLocalizations.of(context).photosShareUpdateFailed;
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
                _buildSettings(l10n, location),
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
      // 对话框内可能已撤销或清空链接：重新加载，编辑位由剩余链接顶上。
      await _loadShareState();
      return;
    }
    // 在管理对话框里新建了链接（密码留空 = 显式创建无密码链接）：
    // 创建后重新加载，新链接按"最新一条"接管编辑位并自动复制地址。
    final (password, expiryOption) = result;
    setState(() {
      _creating = true;
      _error = null;
    });
    try {
      await ref
          .read(photoCenterControllerProvider.notifier)
          .createPhotoShare(
            widget.photo.id,
            password: password.isEmpty ? null : password,
            expiresAt: resolveShareExpiry(expiryOption),
            includeLocation: _includeLocation,
            originalQuality: _originalQuality,
          );
    } on Exception {
      if (!mounted) return;
      setState(() {
        _creating = false;
        _error = AppLocalizations.of(context).photosShareLinkFailed;
      });
      return;
    }
    if (!mounted) return;
    await _loadShareState();
    await _copyToClipboard();
  }

  Future<void> _shareViaSystem(AppLocalizations l10n) async {
    final url = _shareUrl;
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
        showOmniFeedback(
          context,
          l10n.photosShareWeChatCopiedFallback,
          severity: OmniFeedbackSeverity.success,
        );
      case PhotoShareChannelFailure(:final message):
        showOmniFeedback(context, message);
    }
  }

  void _showQrCode(AppLocalizations l10n) {
    final url = _shareUrl;
    if (!mounted) {
      return;
    }
    showWorkstationDialog<void>(
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
