part of 'photo_share_panel.dart';

/// 分享面板的分区 UI 构建方法。
extension _PhotoSharePanelBuilders on _PhotoSharePanelState {
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
                          ? SeverityColors.goodSoft
                          : Colors.white.withValues(alpha: 0.10),
                  foregroundColor:
                      copied
                          ? SeverityColors.good
                          : Colors.white.withValues(alpha: 0.80),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                    side: BorderSide(
                      color:
                          copied
                              ? SeverityColors.goodMuted
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

  Widget _buildShareToGrid(AppLocalizations l10n) {
    // 移动端：系统分享入口（可选微信）+ 复制；桌面/Web：二维码 + 复制。
    final showSystemShare = photoShareChannel.supportsSystemShare;
    final targets = <(Color, IconData, String, VoidCallback)>[
      if (showSystemShare)
        (
          ShareBrandColors.wechat,
          Icons.chat_bubble_rounded,
          l10n.photosShareToWeChat,
          () => unawaited(_shareViaSystem(l10n)),
        ),
      (
        ShareBrandColors.systemBlue,
        Icons.link_rounded,
        l10n.photosShareCopy,
        () => unawaited(_copyToClipboard()),
      ),
      if (!showSystemShare)
        (
          ShareBrandColors.systemGray,
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
            _update(() {
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
            _update(() {
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
            _update(() {
              _originalQuality = v;
              _settingsDirty = true;
            });
          },
        ),
      ],
    );
  }
}
