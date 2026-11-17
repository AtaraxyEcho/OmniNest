part of 'file_browser_page.dart';

/// 托管态我的分享：原型 `.feature-list`——计数眉标 + 发丝线行 + 状态丸。
///
/// 稿子的 file-shared 页签是 Links/People，本项目后端只有分享链接与其派生状态，
/// 因此不照抄页签，只给有效/已过期/已撤销的真实计数与逐条状态；编辑与撤销在
/// 点开的分享面板内完成。分区宿主自带纵向滚动（下发无界高约束），所以本组件
/// 只出非滚动内容，不用 Expanded 也不在横排取 stretch。
class _HostedSharesPage extends StatelessWidget {
  const _HostedSharesPage({
    required this.l10n,
    required this.shares,
    required this.loadedCount,
    required this.totalCount,
    required this.onLoadNext,
    required this.onOpen,
  });

  final AppLocalizations l10n;
  final List<FileShareLink> shares;
  final int loadedCount;
  final int totalCount;
  final VoidCallback onLoadNext;
  final void Function(FileShareLink share) onOpen;

  static MobileStatusTone _toneOf(String state) {
    return switch (state) {
      'REVOKED' => MobileStatusTone.danger,
      'EXPIRED' => MobileStatusTone.warning,
      _ => MobileStatusTone.calm,
    };
  }

  String _stateLabel(String state) {
    return switch (state) {
      'REVOKED' => l10n.filesShareRevoked,
      'EXPIRED' => l10n.filesShareExpired,
      _ => l10n.filesShareActive,
    };
  }

  String get _summaryText {
    int countOf(String state) =>
        shares.where((share) => _derivedShareState(share) == state).length;
    return '${l10n.filesMyShares} · '
        '${l10n.filesShareActive} ${countOf('ACTIVE')} · '
        '${l10n.filesShareExpired} ${countOf('EXPIRED')} · '
        '${l10n.filesShareRevoked} ${countOf('REVOKED')}';
  }

  String _expiryLabel(BuildContext context, FileShareLink share) {
    final expiresAt = share.expiresAt;
    if (expiresAt == null) {
      return l10n.filesSharePermanent;
    }
    return DateFormat(
      'yyyy-MM-dd',
      Localizations.localeOf(context).toString(),
    ).format(expiresAt);
  }

  @override
  Widget build(BuildContext context) {
    final hasMore = loadedCount < totalCount;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _HostedSectionMetaRow(
          text: _summaryText,
          action:
              hasMore
                  ? _HostedPillAction(
                    icon: Icons.expand_more_rounded,
                    label: l10n.filesUploadQueueLoadMore(
                      '$loadedCount',
                      '$totalCount',
                    ),
                    onTap: onLoadNext,
                  )
                  : null,
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
          child:
              shares.isEmpty
                  ? EnvEmptyState(
                    icon: OmniIcons.share,
                    title: l10n.filesSharesEmptyTitle,
                    message: l10n.filesSharesEmptyMessage,
                  )
                  : Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final share in shares)
                        _HostedInfoRow(
                          icon: Icons.link_rounded,
                          title: share.resourceName,
                          subtitle: _expiryLabel(context, share),
                          trailing: MobileStatusPill(
                            label: _stateLabel(_derivedShareState(share)),
                            tone: _toneOf(_derivedShareState(share)),
                          ),
                          onTap: () => onOpen(share),
                        ),
                    ],
                  ),
        ),
      ],
    );
  }
}
