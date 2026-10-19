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
        _buildLinkField(l10n),
        _buildSummaryRow(l10n),
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
        // 第二条及以后的链接只在摘要里计数，管理入口负责列出与撤销：
        // 面板始终只编辑一条，避免同一件事出现第二个编辑对象。
        if (_otherShareCount > 0) ...[
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: TextButton.icon(
              onPressed: _busy ? null : _openManageDialog,
              icon: Icon(
                Icons.tune_rounded,
                size: 16,
                color: Colors.white.withValues(alpha: 0.55),
              ),
              label: Text(
                l10n.photosShareManage,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.55),
                  fontSize: AppTypography.labelSmall,
                  letterSpacing: 0.04,
                ),
              ),
              style: TextButton.styleFrom(
                minimumSize: const Size(0, 36),
                padding: const EdgeInsets.symmetric(horizontal: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                  side: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }

  /// 链接字段：地址在左、动作作为框内后缀，中间一条分隔线。
  ///
  /// 动作贴着它操作的对象，且"有链接/未创建"两态共用同一高度，面板上下
  /// 各区块因此不会在创建前后跳动。
  Widget _buildLinkField(AppLocalizations l10n) {
    final url = _shareUrl;
    final hasLink = _share != null && url != null;
    final copied = _copied && hasLink;
    return Container(
      height: 40,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text(
                url ?? l10n.photosShareNoLinkYet,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color:
                      hasLink
                          ? Colors.white.withValues(alpha: 0.70)
                          : Colors.white.withValues(alpha: 0.32),
                  fontSize: AppTypography.bodySmall,
                ),
              ),
            ),
          ),
          if (hasLink)
            Container(
              width: 1,
              height: 40,
              color: Colors.white.withValues(alpha: 0.08),
            ),
          TextButton(
            onPressed:
                _busy
                    ? null
                    : () => unawaited(
                      hasLink ? _copyToClipboard(url: url) : _createShare(),
                    ),
            style: TextButton.styleFrom(
              backgroundColor:
                  copied
                      ? SeverityColors.goodSoft
                      : Colors.white.withValues(alpha: 0.06),
              foregroundColor:
                  copied
                      ? SeverityColors.good
                      : Colors.white.withValues(alpha: 0.78),
              shape: const RoundedRectangleBorder(
                borderRadius: BorderRadius.zero,
              ),
              minimumSize: const Size(64, 40),
              padding: const EdgeInsets.symmetric(horizontal: 12),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: Text(
              hasLink
                  ? (copied ? l10n.photosShareCopied : l10n.photosShareCopy)
                  : (_creating
                      ? l10n.photosShareCreating
                      : l10n.photosCreateLink),
              style: const TextStyle(
                fontSize: AppTypography.bodySmall,
                letterSpacing: 0.04,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 链接状态摘要行：有效期 · 提取码 · 访问量（还有其他链接时附计数），
  /// 右端放撤销。摘要让"这条链接现在是什么状态"不必打开管理就能读到。
  Widget _buildSummaryRow(AppLocalizations l10n) {
    final share = _share;
    if (share == null) {
      return const SizedBox.shrink();
    }
    final segments = <String>[
      _expirySummary(l10n, share),
      if (_passwordProtected) l10n.photosShareSummaryPassword,
      l10n.photosShareAccessCount(share.accessCount),
      if (_otherShareCount > 0)
        l10n.photosShareOtherLinksHint(_otherShareCount),
    ];
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              segments.join(' · '),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.40),
                fontSize: AppTypography.labelSmall,
              ),
            ),
          ),
          TextButton(
            onPressed: _busy ? null : () => unawaited(_removeShare()),
            style: TextButton.styleFrom(
              foregroundColor: Colors.white.withValues(alpha: 0.40),
              minimumSize: const Size(0, 20),
              padding: const EdgeInsets.symmetric(horizontal: 4),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: Text(
              l10n.coreDelete,
              style: const TextStyle(
                fontSize: AppTypography.labelSmall,
                letterSpacing: 0.04,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 有效期摘要文案，与"管理已有链接"对话框保持同一措辞。
  String _expirySummary(AppLocalizations l10n, PhotoShareLink share) {
    if (share.isExpired) {
      return l10n.photosShareLinkExpired;
    }
    final expiresAt = share.expiresAt;
    if (expiresAt == null) {
      return l10n.photosShareLinkNoExpiry;
    }
    final month = expiresAt.month.toString().padLeft(2, '0');
    final day = expiresAt.day.toString().padLeft(2, '0');
    return l10n.photosShareLinkExpiresOn('${expiresAt.year}-$month-$day');
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
                  enabled: _shareUrl != null,
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

  /// 链接设置：任一改动都即时写回已有链接，尚未创建时作为创建参数暂存。
  Widget _buildSettings(AppLocalizations l10n, String? location) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.photosShareSettingsEyebrow,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.30),
            fontSize: AppTypography.labelSmall,
            letterSpacing: 0.10,
          ),
        ),
        const SizedBox(height: 12),
        _ShareExpiryChips(
          value: _expiryOption,
          enabled: !_busy,
          onSelected: (value) {
            if (value == _expiryOption) return;
            _update(() => _expiryOption = value);
            unawaited(_applySettings());
          },
        ),
        const SizedBox(height: 8),
        _ShareToggleRow(
          label: l10n.photosSharePasswordOption,
          sublabel:
              _passwordProtected
                  ? l10n.photosSharePasswordOn
                  : l10n.photosSharePasswordNone,
          value: _passwordProtected,
          enabled: !_busy,
          onChanged: (on) => unawaited(_togglePassword(on, l10n)),
        ),
        const SizedBox(height: 8),
        _ShareToggleRow(
          label: l10n.photosShareOptionLocation,
          sublabel: location ?? '—',
          value: _includeLocation,
          enabled: !_busy,
          onChanged: (v) {
            if (v == _includeLocation) return;
            _update(() => _includeLocation = v);
            unawaited(_applySettings());
          },
        ),
        const SizedBox(height: 8),
        _ShareToggleRow(
          label: l10n.photosShareOptionOriginal,
          sublabel: l10n.photosShareOptionOriginalFull,
          value: _originalQuality,
          enabled: !_busy,
          onChanged: (v) {
            if (v == _originalQuality) return;
            _update(() => _originalQuality = v);
            unawaited(_applySettings());
          },
        ),
      ],
    );
  }
}
