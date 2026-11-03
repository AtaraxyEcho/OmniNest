part of 'share_link_sheet.dart';

/// 分享面板的只读概览与编辑两段。
///
/// 扩展成员不算 State 实例成员，改状态一律走 _updateState，不直接调 setState。
extension _ShareLinkSheetSections on _ShareLinkSheetState {
  Widget _buildShareInfo(FileShareLink share) {
    final l10n = AppLocalizations.of(context);
    final hosted = !widget.embedded && MobileShellScope.isHosted(context);
    // 基址解析完成前先占位（复制按钮同时禁用）。
    final baseUrl = _shareBaseUrl;
    // 早期分享没落令牌密文，地址已不可回显：此时不给复制入口，
    // 否则复制出去的是打不开的链接（分享码为空拼出的 /s/ 地址必然 404）。
    final shareUrl =
        baseUrl == null || share.shareCode.isEmpty
            ? null
            : '$baseUrl/#/s/${share.shareCode}';
    final hasPassword = share.generatedPassword != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: Theme.of(
              context,
            ).colorScheme.primary.withValues(alpha: 0.06),
            // 移动壳层按原型卡片语言取 r15，工位形态保持直角。
            borderRadius: BorderRadius.circular(hosted ? 15 : 0),
            border: Border.all(
              color: Theme.of(
                context,
              ).colorScheme.outlineVariant.withValues(alpha: 0.3),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      shareUrl ??
                          (share.shareCode.isEmpty
                              ? l10n.filesShareLinkUnrecoverable
                              : '…'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: AppTypography.bodySmall,
                        fontFamily: AppTypography.monoFamily,
                        fontFamilyFallback: AppTypography.monoFamilyFallback,
                      ),
                    ),
                  ),
                  Tooltip(
                    message: l10n.filesShareCopyLink,
                    child: Semantics(
                      button: true,
                      label: l10n.filesShareCopyLink,
                      child: InkWell(
                        onTap:
                            shareUrl == null
                                ? null
                                : () => _copyToClipboard(shareUrl),
                        borderRadius: BorderRadius.zero,
                        child: Padding(
                          padding: const EdgeInsets.all(4),
                          child: Icon(
                            Icons.copy,
                            size: 16,
                            color: context.filesColors.primary,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              if (hasPassword) ...[
                const SizedBox(height: 6),
                Row(
                  children: [
                    Icon(
                      Icons.key,
                      size: 13,
                      color: context.filesColors.onSurface,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      l10n.filesSharePasswordLabel(share.generatedPassword!),
                      style: TextStyle(
                        fontSize: AppTypography.bodySmall,
                        fontFamily: AppTypography.monoFamily,
                        fontFamilyFallback: AppTypography.monoFamilyFallback,
                        fontWeight: FontWeight.w600,
                        color: context.filesColors.onSurface,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Tooltip(
                      message: l10n.filesShareCopyPassword,
                      child: Semantics(
                        button: true,
                        label: l10n.filesShareCopyPassword,
                        child: InkWell(
                          onTap:
                              () => _copyToClipboard(share.generatedPassword!),
                          borderRadius: BorderRadius.zero,
                          child: Padding(
                            padding: const EdgeInsets.all(3),
                            child: Icon(
                              Icons.copy,
                              size: 13,
                              color: context.filesColors.onSurface,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 6),
              Row(
                children: [
                  _buildStatusChip(
                    _statusText(share.status),
                    isActive: share.status.toUpperCase() == 'ACTIVE',
                    hosted: hosted,
                  ),
                  if (share.maxAccessCount != null) ...[
                    const SizedBox(width: 8),
                    Text(
                      '${share.accessCount}/${share.maxAccessCount}',
                      style: TextStyle(
                        fontSize: AppTypography.labelSmall,
                        color: context.filesColors.onSurfaceVariant,
                      ),
                    ),
                  ],
                  if (share.expiresAt != null) ...[
                    const SizedBox(width: 8),
                    Icon(
                      Icons.schedule,
                      size: 12,
                      color: context.filesColors.onSurfaceVariant,
                    ),
                    const SizedBox(width: 2),
                    Text(
                      _formatCompactDate(share.expiresAt!),
                      style: TextStyle(
                        fontSize: AppTypography.labelSmall,
                        color: context.filesColors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
        // 纯复制链接与链接行右侧复制 icon 完全重复，已删；
        // 仅保留“含密码复制”（组合了提取码，功能独立）。
        if (hasPassword && shareUrl != null) ...[
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              _buildCapsuleButton(
                l10n.filesCopyLinkWithPassword,
                Icons.copy,
                // 按钮承诺"含密码"，只复制链接会把提取码丢在剪贴板外。
                () => _copyToClipboard(
                  '$shareUrl\n${l10n.filesSharePasswordLabel(share.generatedPassword!)}',
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  /// 已建分享的设置编辑区：只改有效期、访问次数上限与密码，令牌与地址不变。
  Widget _buildEditSection(
    FileShareLink share,
    AsyncValue<FileShareLink?> shareState,
  ) {
    final l10n = AppLocalizations.of(context);
    final busy = shareState.isLoading;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 16),
        Container(height: 1, color: context.filesColors.outlineVariant),
        const SizedBox(height: 14),
        Text(
          l10n.filesShareEditSettings,
          style: TextStyle(
            fontSize: AppTypography.bodyMedium,
            fontWeight: FontWeight.w600,
            color: context.filesColors.onSurface,
          ),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _maxAccessController,
          keyboardType: TextInputType.number,
          enabled: !busy,
          decoration: InputDecoration(
            labelText: l10n.filesMaxAccessCount,
            hintText: l10n.filesNoLimit,
            isDense: true,
            border: const OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 8),
        ListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          title: Text(l10n.filesExpiryTime),
          subtitle: Text(
            _expiresAt != null
                ? _formatDateTime(_expiresAt!)
                : l10n.filesNeverExpire,
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_expiresAt != null)
                IconButton(
                  tooltip: l10n.coreClear,
                  icon: const Icon(Icons.clear, size: 18),
                  onPressed:
                      busy ? null : () => _updateState(() => _expiresAt = null),
                ),
              IconButton(
                tooltip: l10n.coreChooseDate,
                icon: const Icon(Icons.calendar_today, size: 18),
                onPressed: busy ? null : _pickExpiryDate,
              ),
            ],
          ),
        ),
        TextField(
          controller: _passwordController,
          enabled: !busy,
          obscureText: true,
          decoration: InputDecoration(
            labelText: l10n.profileChangePassword,
            hintText: l10n.filesSharePasswordKeepHint,
            isDense: true,
            border: const OutlineInputBorder(),
          ),
        ),
        CheckboxListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          value: _clearPasswordRequested,
          onChanged:
              busy
                  ? null
                  : (value) => _updateState(
                    () => _clearPasswordRequested = value ?? false,
                  ),
          title: Text(l10n.filesSharePasswordClear),
        ),
        if (shareState.hasError) ...[
          const SizedBox(height: 6),
          Text(
            shareState.hasError
                ? describeUserFacingError(
                  shareState.error!,
                  l10n: AppLocalizations.of(context),
                ).message
                : '',
            style: TextStyle(
              fontSize: AppTypography.bodySmall,
              color: context.filesColors.error,
            ),
          ),
        ],
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: busy ? null : () => unawaited(_saveShareSettings(share)),
            icon: const Icon(Icons.check, size: 18),
            label: Text(l10n.filesShareSaveSettings),
          ),
        ),
      ],
    );
  }
}
