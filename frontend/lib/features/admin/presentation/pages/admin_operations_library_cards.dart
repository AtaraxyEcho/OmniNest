part of 'admin_operations_pages.dart';

class _DesktopLibraryMetrics extends StatelessWidget {
  const _DesktopLibraryMetrics({required this.sources});

  final List<VideoLibrarySource> sources;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final indexed = sources.fold<int>(
      0,
      (total, source) => total + source.indexedItemCount,
    );
    final awaitingReview =
        sources.where((source) => source.scanStatus == 'READY').length;
    final scanning =
        sources
            .where(
              (source) => const <String>{
                'QUEUED',
                'DISCOVERING',
                'APPLYING',
              }.contains(source.scanStatus),
            )
            .length;
    final issues =
        sources
            .where(
              (source) =>
                  source.enabled &&
                  source.healthStatus.toUpperCase() != 'AVAILABLE',
            )
            .length;
    final metrics = [
      (
        l10n.adminLibraryMetricSources,
        sources.length.toString(),
        l10n.adminLibraryMetricSourcesHint,
      ),
      (
        l10n.adminLibraryMetricIndexedTitles,
        indexed.toString(),
        l10n.adminLibraryMetricIndexedTitlesHint,
      ),
      (
        l10n.adminLibraryMetricAwaitingReview,
        awaitingReview.toString(),
        l10n.adminLibraryMetricAwaitingReviewHint,
      ),
      (
        l10n.adminLibraryMetricScansRunning,
        scanning.toString(),
        l10n.adminLibraryMetricScansRunningHint,
      ),
      (
        l10n.adminLibraryMetricStorageIssues,
        issues.toString(),
        l10n.adminLibraryMetricStorageIssuesHint,
      ),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns =
            constraints.maxWidth >= 1200
                ? 5
                : constraints.maxWidth >= 850
                ? 3
                : 2;
        final width = (constraints.maxWidth - (columns - 1) * 12) / columns;
        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            for (final metric in metrics)
              SizedBox(
                width: width,
                child: _DesktopLibraryMetricCard(
                  label: metric.$1,
                  value: metric.$2,
                  hint: metric.$3,
                ),
              ),
          ],
        );
      },
    );
  }
}

/// 媒体库统计使用原型的紧凑 `.lib-stats` 几何；管理总览的统计卡
/// 更高更大，直接复用会把媒体库首屏撑得过长。
class _DesktopLibraryMetricCard extends StatelessWidget {
  const _DesktopLibraryMetricCard({
    required this.label,
    required this.value,
    required this.hint,
  });

  final String label;
  final String value;
  final String hint;

  @override
  Widget build(BuildContext context) {
    final skin = DesktopSkin.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: skin.panel,
        borderRadius: BorderRadius.circular(DesktopMetrics.radiusSmall),
        border: Border.all(color: skin.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label.toUpperCase(), style: DesktopType.micro(skin.text3)),
          const SizedBox(height: 4),
          Text(
            value,
            style: DesktopType.statValue(
              skin.text,
            ).copyWith(fontSize: 24), // ignore: font_size_whitelist
          ),
          Text(
            hint,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: DesktopType.caption(skin.text3),
          ),
        ],
      ),
    );
  }
}

class _DesktopLibrarySourceCard extends ConsumerWidget {
  const _DesktopLibrarySourceCard({
    required this.source,
    required this.locationName,
    required this.canManage,
    required this.onScan,
    required this.onPause,
    required this.onCancel,
    required this.onReview,
    required this.onAccess,
    required this.onEdit,
    required this.onDelete,
  });

  final VideoLibrarySource source;
  final String locationName;
  final bool canManage;
  final Future<void> Function(VideoLibrarySource source) onScan;
  final Future<void> Function(MediaScanRun run) onPause;
  final Future<void> Function(MediaScanRun run) onCancel;
  final VoidCallback onReview;
  final VoidCallback onAccess;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final skin = DesktopSkin.of(context);
    final run = ref.watch(latestMediaScanRunProvider(source.id)).asData?.value;
    final active = run?.active == true;
    final reviewable = run?.reviewable == true || source.scanStatus == 'READY';
    final indexed = NumberFormat.decimalPattern(
      l10n.localeName,
    ).format(source.indexedItemCount);
    final policy =
        source.importPolicy == 'MANUAL_REVIEW'
            ? l10n.adminLibraryPolicyManualReview
            : l10n.adminLibraryPolicyAutomaticImport;
    final status = active ? run!.status : source.scanStatus;
    return DesktopHover(
      builder:
          (context, hovered) => AnimatedContainer(
            duration: DesktopMotion.of(context, DesktopMotion.fast),
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
            decoration: BoxDecoration(
              color: hovered ? skin.raise2 : skin.raise,
              borderRadius: BorderRadius.circular(DesktopMetrics.radiusCard),
              border: Border.all(color: hovered ? skin.line2 : skin.line),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: skin.accentWash(0.14),
                        borderRadius: BorderRadius.circular(
                          DesktopMetrics.radiusSmall,
                        ),
                      ),
                      child: Icon(
                        DesktopIcons.film,
                        size: 19,
                        color: skin.accent,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            source.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: DesktopType.rowTitle(skin.text),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            '$locationName · ${source.relativeRoot}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: DesktopType.caption(skin.text3),
                          ),
                        ],
                      ),
                    ),
                    _DesktopLibraryStatusPill(
                      label: _scanStatusLabel(l10n, status),
                      tone: _scanStatusTone(status),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _DesktopLibraryPill(
                      label: _libraryTypeLabel(l10n, source.libraryType),
                    ),
                    _DesktopLibraryPill(
                      label: '$indexed ${l10n.adminLibraryIndexedUnit}',
                    ),
                    _DesktopLibraryPill(label: policy),
                    _DesktopLibraryPill(
                      label: _libraryVisibilityLabel(l10n, source.visibility),
                    ),
                    _DesktopLibraryPill(
                      label: _libraryHealthLabel(l10n, source.healthStatus),
                    ),
                  ],
                ),
                _DesktopLibrarySourceFlow(
                  source: source,
                  run: run,
                  status: status,
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (reviewable)
                      DesktopButton(
                        label: l10n.adminLibraryReviewCandidates,
                        icon: DesktopIcons.list2,
                        variant: DesktopButtonVariant.primary,
                        onPressed: canManage ? onReview : null,
                      )
                    else if (active && run != null) ...[
                      if (run.status == 'APPLYING')
                        DesktopButton(
                          label: l10n.adminLibraryPauseScan,
                          icon: DesktopIcons.pause,
                          variant: DesktopButtonVariant.soft,
                          onPressed: canManage ? () => onPause(run) : null,
                        ),
                      DesktopButton(
                        label: l10n.adminLibraryCancelScan,
                        icon: DesktopIcons.close,
                        variant: DesktopButtonVariant.ghost,
                        onPressed: canManage ? () => onCancel(run) : null,
                      ),
                    ] else
                      DesktopButton(
                        label: l10n.adminLibraryDiscoverUpdates,
                        icon: DesktopIcons.retry,
                        variant: DesktopButtonVariant.soft,
                        onPressed:
                            canManage && source.enabled
                                ? () => onScan(source)
                                : null,
                      ),
                    DesktopButton.iconOnly(
                      icon: DesktopIcons.users,
                      tooltip: l10n.adminLibraryAccessTitle,
                      onPressed: canManage ? onAccess : null,
                    ),
                    DesktopButton.iconOnly(
                      icon: DesktopIcons.edit,
                      tooltip: l10n.videoEditLibrarySource,
                      onPressed: canManage ? onEdit : null,
                    ),
                    DesktopButton.iconOnly(
                      icon: DesktopIcons.trash,
                      variant: DesktopButtonVariant.danger,
                      tooltip: l10n.adminLibraryDeleteSourceTitle,
                      onPressed: canManage ? onDelete : null,
                    ),
                  ],
                ),
              ],
            ),
          ),
    );
  }
}

class _DesktopScanProgress extends StatelessWidget {
  const _DesktopScanProgress({required this.run});

  final MediaScanRun run;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final skin = DesktopSkin.of(context);
    final total = run.discoveredCount > 0 ? run.discoveredCount : 1;
    final done = run.candidateCount + run.existingCount + run.unmatchedCount;
    final progress = (done / total).clamp(0.0, 1.0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                l10n.adminLibraryScanProgress(
                  _scanPhaseLabel(l10n, run.phase),
                  run.discoveredCount,
                ),
                style: DesktopType.caption(skin.text2),
              ),
            ),
            Text(
              '${(progress * 100).round()}%',
              style: DesktopType.caption(skin.text3),
            ),
          ],
        ),
        const SizedBox(height: 7),
        ClipRRect(
          borderRadius: BorderRadius.circular(99),
          child: LinearProgressIndicator(
            value: progress,
            minHeight: 4,
            color: skin.accent,
            backgroundColor: skin.raise3,
          ),
        ),
      ],
    );
  }
}

/// 样例 `.src-flow`：来源卡底部同时展示发现/审阅/导入阶段、当前状态与
/// 最近扫描信息。它是来源卡的一部分，不再把运行中的进度孤零零地放在
/// 操作按钮上方，避免状态切换时卡片高度和信息顺序跳变。
class _DesktopLibrarySourceFlow extends StatelessWidget {
  const _DesktopLibrarySourceFlow({
    required this.source,
    required this.run,
    required this.status,
  });

  final VideoLibrarySource source;
  final MediaScanRun? run;
  final String status;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final skin = DesktopSkin.of(context);
    final step = switch (status) {
      'QUEUED' || 'DISCOVERING' || 'SCANNING' => 0,
      'READY' => 1,
      'APPLYING' => 2,
      'COMPLETED' || 'PARTIAL' => 3,
      _ => -1,
    };
    final labels = <String>[
      l10n.statusPhaseDiscovery,
      l10n.statusPhaseReview,
      l10n.statusPhaseApply,
    ];
    final lastScan =
        source.lastScannedAt == null
            ? l10n.adminLibraryScanNever
            : '${l10n.adminLibraryColumnLastScan}: ${DateFormat.yMMMd(l10n.localeName).add_jm().format(source.lastScannedAt!)} · ${_lastScanSummary(l10n, source)}';
    return Container(
      margin: const EdgeInsets.only(top: 14),
      padding: const EdgeInsets.only(top: 14),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: skin.line)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    for (var index = 0; index < labels.length; index++)
                      _DesktopLibraryStep(
                        label: labels[index],
                        index: index,
                        currentStep: step,
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Flexible(
                child: Align(
                  alignment: Alignment.topRight,
                  child: Wrap(
                    alignment: WrapAlignment.end,
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      _DesktopLibraryStatusPill(
                        label: _scanStatusLabel(l10n, status),
                        tone: _scanStatusTone(status),
                      ),
                      Text(
                        run == null
                            ? lastScan
                            : l10n.adminLibraryScanProgress(
                              _scanPhaseLabel(l10n, run!.phase),
                              run!.discoveredCount,
                            ),
                        style: DesktopType.caption(skin.text3),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          if (run != null && run!.active) ...[
            const SizedBox(height: 10),
            _DesktopScanProgress(run: run!),
          ],
        ],
      ),
    );
  }
}

class _DesktopLibraryStep extends StatelessWidget {
  const _DesktopLibraryStep({
    required this.label,
    required this.index,
    required this.currentStep,
  });

  final String label;
  final int index;
  final int currentStep;

  @override
  Widget build(BuildContext context) {
    final skin = DesktopSkin.of(context);
    final done = currentStep > index;
    final active = currentStep == index;
    final tone = done || active ? skin.accent : skin.text3;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 18,
          height: 18,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: done ? skin.accent : Colors.transparent,
            border: Border.all(
              color: active || done ? skin.accent : skin.line2,
              width: 1.5,
            ),
          ),
          child:
              done
                  ? Icon(DesktopIcons.check, size: 10, color: skin.accentInk)
                  : Text(
                    '${index + 1}',
                    style: DesktopType.nano(
                      tone,
                    ).copyWith(fontWeight: FontWeight.w600),
                  ),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: DesktopType.caption(active || done ? skin.text2 : skin.text3),
        ),
      ],
    );
  }
}

class _DesktopLibraryPill extends StatelessWidget {
  const _DesktopLibraryPill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final skin = DesktopSkin.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: skin.raise3,
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: skin.line),
      ),
      child: Text(label, style: DesktopType.caption(skin.text3)),
    );
  }
}

class _DesktopLibraryStatusPill extends StatelessWidget {
  const _DesktopLibraryStatusPill({required this.label, required this.tone});

  final String label;
  final AdminTagTone tone;

  @override
  Widget build(BuildContext context) {
    final skin = DesktopSkin.of(context);
    final color = switch (tone) {
      AdminTagTone.success => skin.ok,
      AdminTagTone.warning => skin.warn,
      AdminTagTone.error => skin.bad,
      AdminTagTone.info => skin.accent,
      AdminTagTone.neutral => skin.text3,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.13),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: color.withValues(alpha: 0.32)),
      ),
      child: Text(label, style: DesktopType.caption(color)),
    );
  }
}

class _DesktopLibrarySourcesSkeleton extends StatelessWidget {
  const _DesktopLibrarySourcesSkeleton();

  @override
  Widget build(BuildContext context) => Column(
    children: [
      for (var index = 0; index < 3; index++) ...[
        if (index > 0) const SizedBox(height: 12),
        const DesktopSkeletonBox(height: 174, radius: 16),
      ],
    ],
  );
}

class _DesktopLibraryLoadFailure extends StatelessWidget {
  const _DesktopLibraryLoadFailure({
    required this.message,
    required this.onRetry,
  });

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final skin = DesktopSkin.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(message, style: DesktopType.caption(skin.bad)),
        const SizedBox(height: 10),
        DesktopButton(
          label: AppLocalizations.of(context).coreRetry,
          icon: DesktopIcons.retry,
          onPressed: onRetry,
        ),
      ],
    );
  }
}

class _DesktopLibraryEmpty extends StatelessWidget {
  const _DesktopLibraryEmpty({
    required this.message,
    this.availableMounts = const <VideoTrustedMount>[],
    this.selectedMountKey,
    this.busy = false,
    this.onMountChanged,
    this.onInitialize,
    this.explainMissingMount = false,
  });

  final String message;
  final List<VideoTrustedMount> availableMounts;
  final String? selectedMountKey;
  final bool busy;
  final ValueChanged<String>? onMountChanged;
  final VoidCallback? onInitialize;
  final bool explainMissingMount;

  @override
  Widget build(BuildContext context) {
    final skin = DesktopSkin.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 20),
      child: Column(
        children: [
          Icon(DesktopIcons.library, size: 30, color: skin.text3),
          const SizedBox(height: 12),
          Text(
            message,
            textAlign: TextAlign.center,
            style: DesktopType.caption(skin.text3),
          ),
          if (availableMounts.isNotEmpty &&
              selectedMountKey != null &&
              onMountChanged != null &&
              onInitialize != null) ...[
            const SizedBox(height: 14),
            DesktopSelect<String>(
              value: selectedMountKey!,
              width: 280,
              variant: DesktopSelectVariant.small,
              options: [
                for (final mount in availableMounts)
                  DesktopSelectOption<String>(
                    value: mount.mountKey,
                    label:
                        mount.displayName.trim().isEmpty
                            ? mount.mountKey
                            : mount.displayName,
                  ),
              ],
              onChanged: onMountChanged!,
            ),
            const SizedBox(height: 10),
            DesktopButton(
              label: AppLocalizations.of(context).adminLibrarySetupDefault,
              icon: DesktopIcons.plus,
              variant: DesktopButtonVariant.primary,
              busy: busy,
              onPressed: onInitialize,
            ),
          ] else if (explainMissingMount) ...[
            const SizedBox(height: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Text(
                AppLocalizations.of(
                  context,
                ).adminLibraryDefaultMountUnavailable,
                textAlign: TextAlign.center,
                style: DesktopType.caption(skin.text3),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// 其他媒体库：Music / Photos / Books & Comics 三行真实状态；
/// Music 与 Photos 直连后端既有扫描接口（`/api/v1/admin/music/scan`、
/// `/api/v1/admin/photos/scan`），Reader 展示真实书库统计并提供跳转入口。
