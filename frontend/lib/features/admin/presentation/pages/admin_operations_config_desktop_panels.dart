part of 'admin_operations_pages.dart';

/// 配置控制台的历史与复核：从主面板拆出，避免单文件越过 800 行闸门。
extension _DesktopConfigPanels on _DesktopConfigPanelState {
  Widget _historyCard(AppLocalizations l10n, DesktopSkin skin) {
    final totalPages =
        (_history.length / _DesktopConfigPanelState._historyPageSize).ceil();
    final page = totalPages == 0 ? 0 : _historyPage.clamp(0, totalPages - 1);
    final items =
        _history
            .skip(page * _DesktopConfigPanelState._historyPageSize)
            .take(_DesktopConfigPanelState._historyPageSize)
            .toList();
    return AdminCard(
      title: l10n.desktopConfigHistory,
      count: _history.length,
      subtitle: l10n.desktopConfigHistoryScope,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_history.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Text(
                l10n.desktopConfigHistoryEmpty,
                style: DesktopType.dense(skin.text3),
              ),
            )
          else ...[
            for (final change in items)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Container(
                  padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
                  decoration: BoxDecoration(
                    color: skin.panel,
                    borderRadius: BorderRadius.circular(DesktopMetrics.radius),
                    border: Border.all(color: skin.line),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              change.label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: DesktopType.denseStrong(skin.text),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '${change.key} · '
                              '${DateFormat.Hms().format(change.at)}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: DesktopType.caption(skin.text3),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        change.display(change.from),
                        style: DesktopType.dense(
                          const Color(0xFFE57A74),
                        ).copyWith(
                          decoration: TextDecoration.lineThrough,
                          decorationColor: const Color(0xFFE57A74),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        child: Icon(
                          DesktopIcons.chevron,
                          size: 13,
                          color: skin.text3,
                        ),
                      ),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 180),
                        child: Text(
                          change.display(change.to),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: DesktopType.dense(
                            const Color(0xFF7FCF9F),
                          ).copyWith(fontWeight: FontWeight.w600),
                        ),
                      ),
                      const SizedBox(width: 10),
                      DesktopButton(
                        label: l10n.adminRollback,
                        variant: DesktopButtonVariant.ghost,
                        tooltip:
                            change.rollbackAvailable
                                ? null
                                : l10n.desktopConfigSecretRollbackUnavailable,
                        onPressed:
                            _rollingBack || !change.rollbackAvailable
                                ? null
                                : () => _rollback(change),
                      ),
                    ],
                  ),
                ),
              ),
            AdminPager(
              page: page,
              totalPages: totalPages,
              summary: l10n.desktopConfigHistoryTotal(_history.length),
              onPageChanged: (next) => _rebuild(() => _historyPage = next),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _review(List<AdminConfigEntry> items) async {
    final l10n = AppLocalizations.of(context);
    final skin = DesktopSkin.of(context);
    final changes = items.where(_isDirty).toList();
    if (changes.isEmpty) {
      return;
    }
    final confirmed = await showDesktopDialog<bool>(
      context,
      builder:
          (dialogContext) => DesktopDialog(
            title: l10n.desktopConfigReviewTitle(changes.length),
            eyebrow: l10n.desktopConfigReview,
            lead: Icon(DesktopIcons.settings, size: 20, color: skin.text2),
            width: 640,
            content: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  l10n.desktopConfigReviewHint,
                  style: DesktopType.caption(skin.text3),
                ),
                const SizedBox(height: 12),
                for (final entry in changes)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Container(
                      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
                      decoration: BoxDecoration(
                        color: skin.panel,
                        borderRadius: BorderRadius.circular(
                          DesktopMetrics.radius,
                        ),
                        border: Border.all(color: skin.line),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _configTitle(l10n, entry),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: DesktopType.denseStrong(skin.text),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  entry.key,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: DesktopType.caption(skin.text3),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          Text(
                            _display(entry, entry.value),
                            style: DesktopType.dense(
                              const Color(0xFFE57A74),
                            ).copyWith(
                              decoration: TextDecoration.lineThrough,
                              decorationColor: const Color(0xFFE57A74),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 6),
                            child: Icon(
                              DesktopIcons.chevron,
                              size: 13,
                              color: skin.text3,
                            ),
                          ),
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 190),
                            child: Text(
                              _display(entry, _draft[entry.key] ?? ''),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: DesktopType.dense(
                                const Color(0xFF7FCF9F),
                              ).copyWith(fontWeight: FontWeight.w600),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
            actions: [
              DesktopButton(
                label: l10n.adminCancel,
                variant: DesktopButtonVariant.ghost,
                onPressed: () => closeDesktopModal(dialogContext, false),
              ),
              DesktopButton(
                label: l10n.desktopConfigSaveChanges,
                variant: DesktopButtonVariant.primary,
                onPressed: () => closeDesktopModal(dialogContext, true),
              ),
            ],
          ),
    );
    if (confirmed != true || !mounted) {
      return;
    }
    await _save(changes);
  }
}
