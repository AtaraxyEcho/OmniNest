part of 'admin_operations_pages.dart';

/// 操作审计详情弹窗（元数据 + 变更快照 + 原始 payload），
/// 自 admin_operations_logs_center 拆出。

class _AuditDetailDialog extends StatelessWidget {
  const _AuditDetailDialog({required this.item});

  final AdminAuditLog item;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final hasChangeSnapshot =
        item.payload.containsKey('oldValue') &&
        item.payload.containsKey('newValue');
    return WorkstationDialogFrame(
      title: l10n.adminAuditDetailTitle,
      headerLabel: item.action,
      width: 620,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _DetailKeyValueRow(
            label: l10n.adminAuditFieldAction,
            value: adminAuditActionLabel(l10n, item.action),
          ),
          _DetailKeyValueRow(
            label: l10n.adminAuditFieldTime,
            value: item.createdAt,
            mono: true,
          ),
          _DetailKeyValueRow(
            label: l10n.adminAuditFieldActor,
            value: item.actorUserId ?? '-',
          ),
          _DetailKeyValueRow(
            label: l10n.adminAuditFieldIp,
            value: item.ipAddress,
            mono: true,
          ),
          _DetailKeyValueRow(
            label: l10n.adminResourceType,
            value: item.resourceType,
          ),
          if (hasChangeSnapshot) ...[
            const SizedBox(height: 6),
            WorkstationDialogSectionLabel(l10n.adminAuditChangeSnapshot),
            const SizedBox(height: 10),
            // 弹窗 body 处于无界高度滚动区内，不能用 stretch 拉齐子高，
            // 两侧块以等宽 Expanded 顶对齐即可。
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: _SnapshotValueBlock(
                    label: l10n.adminAuditOldValue,
                    text: _formatPayloadValue(item.payload['oldValue']),
                    tone: _SnapshotTone.oldValue,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _SnapshotValueBlock(
                    label: l10n.adminAuditNewValue,
                    text: _formatPayloadValue(item.payload['newValue']),
                    tone: _SnapshotTone.newValue,
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 6),
          WorkstationDialogSectionLabel(l10n.adminAuditPayload),
          const SizedBox(height: 10),
          if (item.payload.isEmpty)
            Text(
              l10n.adminAuditPayloadEmpty,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            )
          else
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerLow,
                border: Border.all(color: scheme.outlineVariant),
              ),
              child: Text(
                _prettyPayloadJson(item.payload),
                style: TextStyle(
                  fontFamily: AppTypography.monoFamily,
                  fontFamilyFallback: AppTypography.monoFamilyFallback,
                  fontSize: AppTypography.bodySmall,
                  height: 16 / 12,
                  color: scheme.onSurface,
                ),
              ),
            ),
        ],
      ),
      actions: [
        TextButton(
          autofocus: true,
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.coreClose),
        ),
      ],
    );
  }
}
