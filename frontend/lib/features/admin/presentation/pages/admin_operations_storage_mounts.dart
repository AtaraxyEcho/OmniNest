part of 'admin_operations_pages.dart';

/// 可信挂载区：挂载卡 + 约定目录槽位 + 扫描/自动入库开关。
/// 自 admin_operations_storage.dart 拆出，控制单文件规模。

class _AdminTrustedMountsSection extends ConsumerStatefulWidget {
  const _AdminTrustedMountsSection({
    required this.mounts,
    required this.canManage,
  });

  final List<AdminTrustedMount> mounts;
  final bool canManage;

  @override
  ConsumerState<_AdminTrustedMountsSection> createState() =>
      _AdminTrustedMountsSectionState();
}

class _AdminTrustedMountsSectionState
    extends ConsumerState<_AdminTrustedMountsSection> {
  String? _busyMountKey;
  String? _scanningMountKey;

  Future<void> _provision(
    AdminTrustedMount mount, {
    required bool enabled,
    required bool autoImport,
  }) async {
    if (_busyMountKey != null) {
      return;
    }
    final l10n = AppLocalizations.of(context);
    final wasEnabled =
        _resolveMountLibraryState(
          mountKey: mount.mountKey,
          locations:
              ref.read(videoStorageLocationsProvider).asData?.value ?? const [],
          sources:
              ref.read(videoLibrarySourcesProvider).asData?.value ?? const [],
        ).enabled;
    setState(() => _busyMountKey = mount.mountKey);
    try {
      await ref
          .read(videoLibrarySourceActionsProvider)
          .provisionMountLibrary(
            mountKey: mount.mountKey,
            enabled: enabled,
            autoImport: autoImport,
          );
      if (!mounted) {
        return;
      }
      ref.read(adminOperationsActionsProvider).scheduleStorageRelatedRefresh();
      if (enabled && !wasEnabled) {
        showOmniFeedback(
          context,
          l10n.adminMountLibraryProvisionSuccess,
          severity: OmniFeedbackSeverity.success,
        );
      }
    } on Exception catch (error) {
      if (!mounted) {
        return;
      }
      showOmniFeedback(
        context,
        '${l10n.adminMountLibraryProvisionFailed}: '
        '${describeUserFacingError(error, l10n: l10n).message}',
        severity: OmniFeedbackSeverity.error,
      );
    } finally {
      if (mounted) {
        setState(() => _busyMountKey = null);
      }
    }
  }

  Future<void> _scanAll(
    AdminTrustedMount mount,
    _MountLibraryState state,
  ) async {
    if (_scanningMountKey != null || state.sourceIds.isEmpty) {
      return;
    }
    final l10n = AppLocalizations.of(context);
    setState(() => _scanningMountKey = mount.mountKey);
    try {
      final result = await ref
          .read(videoLibrarySourceActionsProvider)
          .scanAll(state.sourceIds);
      if (!mounted) {
        return;
      }
      if (result.failed == 0) {
        showOmniFeedback(
          context,
          l10n.adminMountLibraryScanAllSuccess(result.success),
          severity: OmniFeedbackSeverity.success,
        );
      } else {
        final lastError =
            result.lastError == null
                ? ''
                : ' · ${describeUserFacingError(Exception(result.lastError), l10n: l10n).message}';
        showOmniFeedback(
          context,
          '${l10n.adminMountLibraryScanAllPartial(result.success, result.failed)}$lastError',
          severity: OmniFeedbackSeverity.warning,
        );
      }
    } finally {
      if (mounted) {
        setState(() => _scanningMountKey = null);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final locations =
        ref.watch(videoStorageLocationsProvider).asData?.value ??
        const <VideoStorageLocation>[];
    final sources =
        ref.watch(videoLibrarySourcesProvider).asData?.value ??
        const <VideoLibrarySource>[];
    return AdminTableSection(
      title: l10n.adminTrustedMountsTitle,
      subtitle: l10n.adminTrustedMountsSubtitle,
      children: [
        if (widget.mounts.isEmpty)
          _EmptyText(l10n.adminTrustedMountsEmpty)
        else
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Column(
              children: [
                for (final mount in widget.mounts)
                  _MountLibraryCard(
                    mount: mount,
                    state: _resolveMountLibraryState(
                      mountKey: mount.mountKey,
                      locations: locations,
                      sources: sources,
                    ),
                    canManage: widget.canManage,
                    busy: _busyMountKey == mount.mountKey,
                    onEnableChanged:
                        widget.canManage
                            ? (value) => _provision(
                              mount,
                              enabled: value,
                              autoImport:
                                  _resolveMountLibraryState(
                                    mountKey: mount.mountKey,
                                    locations: locations,
                                    sources: sources,
                                  ).autoImport,
                            )
                            : null,
                    onAutoImportChanged:
                        widget.canManage
                            ? (value) => _provision(
                              mount,
                              enabled: true,
                              autoImport: value,
                            )
                            : null,
                    scanning: _scanningMountKey == mount.mountKey,
                    onScanAll:
                        () => _scanAll(
                          mount,
                          _resolveMountLibraryState(
                            mountKey: mount.mountKey,
                            locations: locations,
                            sources: sources,
                          ),
                        ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

class _MountLibraryCard extends StatelessWidget {
  const _MountLibraryCard({
    required this.mount,
    required this.state,
    required this.canManage,
    required this.busy,
    required this.onEnableChanged,
    required this.onAutoImportChanged,
    required this.scanning,
    required this.onScanAll,
  });

  final AdminTrustedMount mount;
  final _MountLibraryState state;
  final bool canManage;
  final bool busy;
  final ValueChanged<bool>? onEnableChanged;
  final ValueChanged<bool>? onAutoImportChanged;
  final bool scanning;
  final VoidCallback? onScanAll;

  String _statusLabel(AppLocalizations l10n) {
    if (state.isPartial) {
      return l10n.adminMountLibraryStatusPartial;
    }
    return state.enabled
        ? l10n.adminMountLibraryStatusOn
        : l10n.adminMountLibraryStatusOff;
  }

  AdminTagTone _statusTone() {
    if (state.isPartial) {
      return AdminTagTone.warning;
    }
    return state.enabled ? AdminTagTone.success : AdminTagTone.neutral;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final canToggle = canManage && mount.available && !busy;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(16, 14, 8, 6),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                Icons.dns_outlined,
                size: 20,
                color:
                    mount.available
                        ? context.adminColors.success
                        : context.adminColors.tertiary,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  mount.mountKey,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              AdminStatusTag(
                label: healthStatusLabel(
                  l10n,
                  mount.available ? 'AVAILABLE' : 'UNAVAILABLE',
                ),
                tone:
                    mount.available
                        ? AdminTagTone.success
                        : AdminTagTone.warning,
              ),
              const SizedBox(width: 8),
              AdminStatusTag(label: _statusLabel(l10n), tone: _statusTone()),
              if (busy) ...[
                const SizedBox(width: 12),
                const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ],
              const SizedBox(width: 8),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            l10n.adminMountLibraryCatalogLabel,
            style: theme.textTheme.labelMedium?.copyWith(color: muted),
          ),
          const SizedBox(height: 6),
          // 三槽位 chip 同行收紧排布；mono 槽位编码内联展示。
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              for (final root in _mountCatalogSlots)
                _CatalogChip(
                  label: _mountCatalogLabel(l10n, root),
                  code: '/$root',
                  present: state.presentRoots.contains(root),
                  enabled: state.provisioned,
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            state.isPartial
                ? l10n.adminMountLibraryPartialHint(state.sourceCount)
                : state.provisioned
                ? l10n.adminMountLibraryEnableHint
                : l10n.adminMountLibraryEnableHintOff,
            style: theme.textTheme.bodySmall?.copyWith(color: muted),
          ),
          const SizedBox(height: 4),
          WorkstationToggle(
            label: l10n.adminMountLibraryEnable,
            // 库不完整时呈现为关闭，打开会补齐缺失的类型库，避免「已打开却无法补齐」。
            value: state.isPartial ? false : state.enabled,
            onChanged: canToggle ? onEnableChanged : null,
          ),
          WorkstationToggle(
            label: l10n.adminMountLibraryAutoImport,
            subtitle: l10n.adminMountLibraryAutoImportHint,
            value: state.autoImport,
            onChanged: canToggle && state.enabled ? onAutoImportChanged : null,
          ),
          Align(
            alignment: Alignment.centerRight,
            child: Padding(
              padding: const EdgeInsets.only(right: 8, bottom: 4),
              child: TextButton.icon(
                onPressed:
                    canManage &&
                            mount.available &&
                            state.provisioned &&
                            state.sourceIds.isNotEmpty &&
                            !busy &&
                            !scanning
                        ? onScanAll
                        : null,
                icon:
                    scanning
                        ? const SizedBox.square(
                          dimension: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                        : const Icon(Icons.manage_search_rounded, size: 18),
                label: Text(l10n.adminMountLibraryScanAll),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CatalogChip extends StatelessWidget {
  const _CatalogChip({
    required this.label,
    required this.code,
    required this.present,
    required this.enabled,
  });

  final String label;

  /// 槽位相对根编码（如 /movie），以 mono 小字内联展示。
  final String code;

  final bool present;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color =
        present
            ? theme.colorScheme.primary
            : theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.55);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        border: Border.all(
          color:
              present
                  ? theme.colorScheme.primary.withValues(alpha: 0.45)
                  : theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
        color:
            present
                ? theme.colorScheme.primary.withValues(alpha: 0.10)
                : Colors.transparent,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            present ? Icons.check_circle_rounded : Icons.circle_outlined,
            size: 14,
            color: color,
          ),
          const SizedBox(width: 5),
          Text(
            label,
            style: theme.textTheme.labelMedium?.copyWith(
              color: present ? theme.colorScheme.onSurface : color,
              fontWeight: present ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
          const SizedBox(width: 4),
          Text(
            code,
            style: TextStyle(
              fontFamily: AppTypography.monoFamily,
              fontFamilyFallback: AppTypography.monoFamilyFallback,
              fontSize: AppTypography.labelSmall,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
