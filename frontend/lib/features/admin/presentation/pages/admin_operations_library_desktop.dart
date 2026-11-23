part of 'admin_operations_pages.dart';

/// 桌面端媒体库管理页。
///
/// 原型 `LibraryManager.tsx` 把库源从宽表拆为状态卡：扫描中的来源能就地
/// 暂停/取消，待审阅来源直接进入抽屉。所有数值均来自真实库源或扫描 run，
/// 不以原型示例数字补齐空状态。
class _DesktopMediaLibraryPanel extends ConsumerStatefulWidget {
  const _DesktopMediaLibraryPanel();

  @override
  ConsumerState<_DesktopMediaLibraryPanel> createState() =>
      _DesktopMediaLibraryPanelState();
}

class _DesktopMediaLibraryPanelState
    extends ConsumerState<_DesktopMediaLibraryPanel> {
  bool _scanAllBusy = false;
  bool _defaultLibraryBusy = false;
  String? _selectedMountKey;

  bool get _canManage {
    final permissions =
        ref.read(authSessionProvider).value?.user?.permissions ??
        const <String>{};
    return permissions.contains('media:library:manage');
  }

  Future<void> _setupDefaultLibrary(String mountKey) async {
    if (_defaultLibraryBusy) return;
    final l10n = AppLocalizations.of(context);
    setState(() => _defaultLibraryBusy = true);
    try {
      await ref
          .read(videoLibrarySourceActionsProvider)
          .provisionMountLibrary(
            mountKey: mountKey,
            enabled: true,
            autoImport: false,
          );
      if (!mounted) return;
      ref.read(adminOperationsActionsProvider).scheduleStorageRelatedRefresh();
      showOmniFeedback(
        context,
        l10n.adminMountLibraryProvisionSuccess,
        severity: OmniFeedbackSeverity.success,
      );
    } on Object catch (error) {
      if (!mounted) return;
      showOmniFeedback(
        context,
        '${l10n.adminMountLibraryProvisionFailed}: '
        '${userFacingErrorText(error, l10n: l10n)}',
        severity: OmniFeedbackSeverity.error,
      );
    } finally {
      if (mounted) setState(() => _defaultLibraryBusy = false);
    }
  }

  Future<void> _scanAll(List<VideoLibrarySource> sources) async {
    if (_scanAllBusy) return;
    final l10n = AppLocalizations.of(context);
    final eligible = sources
        .where(
          (source) =>
              source.enabled &&
              !const <String>{
                'QUEUED',
                'DISCOVERING',
                'APPLYING',
              }.contains(source.scanStatus),
        )
        .map((source) => source.id)
        .toList(growable: false);
    if (eligible.isEmpty) return;
    setState(() => _scanAllBusy = true);
    try {
      final result = await ref
          .read(videoLibrarySourceActionsProvider)
          .scanAll(eligible);
      if (!mounted) return;
      showOmniFeedback(
        context,
        result.failed == 0
            ? l10n.adminMountLibraryScanAllSuccess(result.success)
            : l10n.adminMountLibraryScanAllPartial(
              result.success,
              result.failed,
            ),
        severity:
            result.failed == 0
                ? OmniFeedbackSeverity.success
                : OmniFeedbackSeverity.warning,
      );
    } on Object catch (error) {
      if (!mounted) return;
      showOmniFeedback(
        context,
        l10n.adminLoadFailed(userFacingErrorText(error, l10n: l10n)),
        severity: OmniFeedbackSeverity.error,
      );
    } finally {
      if (mounted) setState(() => _scanAllBusy = false);
    }
  }

  Future<void> _scan(VideoLibrarySource source) async {
    final l10n = AppLocalizations.of(context);
    try {
      final task = await ref
          .read(videoLibrarySourceActionsProvider)
          .scan(source.id);
      if (mounted) showOmniFeedback(context, task.message);
    } on Object catch (error) {
      if (!mounted) return;
      showOmniFeedback(
        context,
        l10n.adminLoadFailed(userFacingErrorText(error, l10n: l10n)),
        severity: OmniFeedbackSeverity.error,
      );
    }
  }

  Future<void> _pause(MediaScanRun run) async {
    final l10n = AppLocalizations.of(context);
    try {
      await ref.read(videoLibrarySourceActionsProvider).pause(run);
    } on Object catch (error) {
      if (!mounted) return;
      showOmniFeedback(
        context,
        l10n.adminLoadFailed(userFacingErrorText(error, l10n: l10n)),
        severity: OmniFeedbackSeverity.error,
      );
    }
  }

  Future<void> _cancel(MediaScanRun run) async {
    final l10n = AppLocalizations.of(context);
    try {
      await ref.read(videoLibrarySourceActionsProvider).cancel(run);
    } on Object catch (error) {
      if (!mounted) return;
      showOmniFeedback(
        context,
        l10n.adminLoadFailed(userFacingErrorText(error, l10n: l10n)),
        severity: OmniFeedbackSeverity.error,
      );
    }
  }

  void _openReview(VideoLibrarySource source, String locationName) {
    final l10n = AppLocalizations.of(context);
    showDesktopDrawer<void>(
      context,
      width: 620,
      builder:
          (_) => DesktopDrawerFrame(
            title: source.name,
            eyebrow: l10n.adminLibraryManageReviewSection,
            subtitle: '$locationName · ${source.relativeRoot}',
            child: MediaLibraryReviewWorkspace(
              source: source,
              treeHeight:
                  (MediaQuery.sizeOf(context).height - 300)
                      .clamp(280, 540)
                      .toDouble(),
            ),
          ),
    );
  }

  void _openAccess(VideoLibrarySource source) {
    final l10n = AppLocalizations.of(context);
    showDesktopDrawer<void>(
      context,
      width: 520,
      builder:
          (_) => DesktopDrawerFrame(
            title: l10n.adminLibraryAccessTitle,
            eyebrow: source.name,
            child: MediaLibraryAccessPanel(source: source),
          ),
    );
  }

  void _edit(VideoLibrarySource? source, List<VideoStorageLocation> locations) {
    showDesktopDrawer<void>(
      context,
      width: 520,
      builder:
          (_) => DesktopVideoLibrarySourceDrawer(
            source: source,
            locations: locations,
          ),
    );
  }

  Future<void> _delete(VideoLibrarySource source) async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showWorkstationConfirmDialog(
      context,
      title: l10n.adminLibraryDeleteSourceTitle,
      message: l10n.adminLibraryDeleteSourceBody(source.name),
      confirmLabel: l10n.adminStorageDeleteAction,
      destructive: true,
    );
    if (!confirmed || !mounted) return;
    try {
      await ref.read(videoLibrarySourceActionsProvider).delete(source.id);
      ref.invalidate(adminStorageProvider);
    } on Object catch (error) {
      if (!mounted) return;
      showOmniFeedback(
        context,
        l10n.adminLoadFailed(userFacingErrorText(error, l10n: l10n)),
        severity: OmniFeedbackSeverity.error,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final sourcesAsync = ref.watch(videoLibrarySourcesProvider);
    final locationsAsync = ref.watch(videoStorageLocationsProvider);
    final sources = sourcesAsync.asData?.value ?? const <VideoLibrarySource>[];
    final locations =
        locationsAsync.asData?.value ?? const <VideoStorageLocation>[];
    final canAdd = locations.any((location) => location.available);
    final permissions =
        ref.watch(authSessionProvider).value?.user?.permissions ??
        const <String>{};
    final canProvisionDefault =
        permissions.contains('media:library:manage') &&
        permissions.contains('system:config:manage');
    final mountsAsync =
        canProvisionDefault ? ref.watch(videoTrustedMountsProvider) : null;
    final availableMounts =
        mountsAsync?.asData?.value
            .where((mount) => mount.available)
            .toList(growable: false) ??
        const <VideoTrustedMount>[];
    final selectedMountKey =
        availableMounts
            .where((mount) => mount.mountKey == _selectedMountKey)
            .firstOrNull
            ?.mountKey ??
        availableMounts
            .where((mount) => mount.mountKey == 'library')
            .firstOrNull
            ?.mountKey ??
        availableMounts.firstOrNull?.mountKey;
    final query = ref.watch(adminSearchProvider).trim().toLowerCase();
    final filtered =
        query.isEmpty
            ? sources
            : sources
                .where(
                  (source) =>
                      source.name.toLowerCase().contains(query) ||
                      source.relativeRoot.toLowerCase().contains(query),
                )
                .toList(growable: false);

    String locationName(VideoLibrarySource source) =>
        locations
            .where((location) => location.id == source.storageLocationId)
            .firstOrNull
            ?.name ??
        source.storageLocationId;

    // 桌面壳层已经提供 `.route` 入场；媒体库原型的统计卡和来源卡
    // 只保留各自的静态层级，不能再套管理台旧版整页交错动画。
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AdminPageHeader(
          title: l10n.adminMediaLibraryTitle,
          subtitle: l10n.adminMediaLibrarySubtitle,
        ),
        const SizedBox(height: 20),
        _DesktopLibraryMetrics(sources: sources),
        const SizedBox(height: 16),
        AdminCard(
          title: l10n.adminLibrarySourcesSection,
          count: filtered.length,
          subtitle: l10n.adminLibrarySourcesSubtitle,
          action: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              DesktopButton(
                label: l10n.adminMountLibraryScanAll,
                icon: DesktopIcons.retry,
                variant: DesktopButtonVariant.soft,
                busy: _scanAllBusy,
                tooltip: l10n.adminMountLibraryScanAllHint,
                onPressed:
                    _canManage &&
                            sources.any(
                              (source) =>
                                  source.enabled &&
                                  !const <String>{
                                    'QUEUED',
                                    'DISCOVERING',
                                    'APPLYING',
                                  }.contains(source.scanStatus),
                            )
                        ? () => _scanAll(sources)
                        : null,
              ),
              DesktopButton(
                label: l10n.adminLibrarySourceAdd,
                icon: DesktopIcons.plus,
                variant: DesktopButtonVariant.primary,
                tooltip:
                    canAdd ? null : l10n.videoNoAvailableStorageLocationHint,
                onPressed:
                    _canManage && canAdd ? () => _edit(null, locations) : null,
              ),
            ],
          ),
          child: sourcesAsync.when(
            loading: () => const _DesktopLibrarySourcesSkeleton(),
            error:
                (error, _) => _DesktopLibraryLoadFailure(
                  message: errorReason(error, l10n),
                  onRetry: () => ref.invalidate(videoLibrarySourcesProvider),
                ),
            data:
                (_) =>
                    filtered.isEmpty
                        ? query.isNotEmpty
                            ? _DesktopLibraryEmpty(message: l10n.adminNoMatch)
                            : mountsAsync?.isLoading == true
                            ? const _DesktopLibrarySourcesSkeleton()
                            : _DesktopLibraryEmpty(
                              message: l10n.adminLibrarySourcesEmpty,
                              availableMounts: availableMounts,
                              selectedMountKey: selectedMountKey,
                              busy: _defaultLibraryBusy,
                              onMountChanged:
                                  (key) =>
                                      setState(() => _selectedMountKey = key),
                              onInitialize:
                                  selectedMountKey == null
                                      ? null
                                      : () => _setupDefaultLibrary(
                                        selectedMountKey,
                                      ),
                              explainMissingMount:
                                  canProvisionDefault &&
                                  mountsAsync?.hasValue == true &&
                                  availableMounts.isEmpty,
                            )
                        : Column(
                          children: [
                            for (
                              var index = 0;
                              index < filtered.length;
                              index++
                            )
                              Padding(
                                padding: EdgeInsets.only(
                                  bottom: index == filtered.length - 1 ? 0 : 12,
                                ),
                                child: _DesktopLibrarySourceCard(
                                  source: filtered[index],
                                  locationName: locationName(filtered[index]),
                                  canManage: _canManage,
                                  onScan: _scan,
                                  onPause: _pause,
                                  onCancel: _cancel,
                                  onReview:
                                      () => _openReview(
                                        filtered[index],
                                        locationName(filtered[index]),
                                      ),
                                  onAccess: () => _openAccess(filtered[index]),
                                  onEdit:
                                      () => _edit(filtered[index], locations),
                                  onDelete: () => _delete(filtered[index]),
                                ),
                              ),
                          ],
                        ),
          ),
        ),
        const SizedBox(height: 16),
        const _DesktopOtherMediaLibrariesCard(),
      ],
    );
  }
}
