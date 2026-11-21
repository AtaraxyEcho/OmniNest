part of 'admin_operations_pages.dart';

class _DesktopOtherMediaLibrariesCard extends ConsumerStatefulWidget {
  const _DesktopOtherMediaLibrariesCard();

  @override
  ConsumerState<_DesktopOtherMediaLibrariesCard> createState() =>
      _DesktopOtherMediaLibrariesCardState();
}

class _DesktopOtherMediaLibrariesCardState
    extends ConsumerState<_DesktopOtherMediaLibrariesCard> {
  bool _musicScanning = false;
  bool _photoScanning = false;
  String? _musicScanNote;
  String? _photoScanNote;

  Future<void> _triggerAdminScan({
    required String endpoint,
    required bool isMusic,
  }) async {
    if (isMusic ? _musicScanning : _photoScanning) {
      return;
    }
    final l10n = AppLocalizations.of(context);
    setState(() {
      if (isMusic) {
        _musicScanning = true;
      } else {
        _photoScanning = true;
      }
    });
    try {
      final response = await ref
          .read(apiClientProvider)
          .dio
          .post<Map<String, dynamic>>(endpoint);
      final raw = response.data;
      final data =
          raw?['data'] is Map
              ? Map<String, dynamic>.from(raw!['data'] as Map)
              : const <String, dynamic>{};
      final status = data['status']?.toString().trim();
      final jobId = (data['id'] ?? data['jobId'])?.toString().trim();
      final note = [
        if (status != null && status.isNotEmpty) status,
        if (jobId != null && jobId.isNotEmpty) '#$jobId',
      ].join(' · ');
      if (!mounted) return;
      setState(() {
        if (isMusic) {
          _musicScanNote = note.isEmpty ? l10n.musicScanQueued : note;
        } else {
          _photoScanNote = note.isEmpty ? l10n.musicScanQueued : note;
        }
      });
      showOmniFeedback(
        context,
        note.isEmpty ? l10n.musicScanQueued : '${l10n.musicStartScan}: $note',
        severity: OmniFeedbackSeverity.success,
      );
    } on Object catch (error) {
      if (!mounted) return;
      showOmniFeedback(
        context,
        l10n.adminLoadFailed(userFacingErrorText(error, l10n: l10n)),
        severity: OmniFeedbackSeverity.error,
      );
    } finally {
      if (mounted) {
        setState(() {
          if (isMusic) {
            _musicScanning = false;
          } else {
            _photoScanning = false;
          }
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final permissions =
        ref.watch(authSessionProvider).value?.user?.permissions ??
        const <String>{};
    final canManage = permissions.contains('media:library:manage');
    final musicDashboard =
        ref.watch(musicCenterControllerProvider).asData?.value.dashboard;
    final photoDashboard = ref.watch(photoDashboardProvider).asData?.value;
    final readerOverview =
        ref
            .watch(readerCenterControllerProvider)
            .asData
            ?.value
            .dashboard
            .overview;

    final musicSummary =
        musicDashboard == null
            ? '—'
            : '${musicDashboard.trackCount} tracks · '
                '${musicDashboard.albumCount} albums · '
                '${musicDashboard.artistCount} artists'
                '${_musicScanNote != null ? ' · $_musicScanNote' : ''}';

    final photoSummary =
        photoDashboard == null
            ? '—'
            : '${photoDashboard.totalPhotos} photos · '
                '${photoDashboard.totalVideos} videos · '
                '${photoDashboard.totalAlbums} albums'
                '${_photoScanNote != null ? ' · $_photoScanNote' : ''}';

    final readerSummary =
        readerOverview == null
            ? '—'
            : '${readerOverview.totalItems} ${l10n.adminLibraryIndexedUnit} · '
                '${readerOverview.continueCount} reading';

    return AdminCard(
      title: l10n.adminLibraryOtherMediaTitle,
      subtitle: l10n.adminLibraryOtherMediaSubtitle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _OtherMediaLibraryRow(
            icon: DesktopIcons.music,
            title: l10n.desktopNavMusic,
            detail: musicSummary,
            first: true,
            action: DesktopButton(
              label: l10n.musicStartScan,
              icon: DesktopIcons.retry,
              variant: DesktopButtonVariant.soft,
              busy: _musicScanning,
              onPressed:
                  canManage && !_musicScanning
                      ? () => _triggerAdminScan(
                        endpoint: '/admin/music/scan',
                        isMusic: true,
                      )
                      : null,
            ),
          ),
          _OtherMediaLibraryRow(
            icon: DesktopIcons.image,
            title: l10n.desktopNavPhotos,
            detail: photoSummary,
            action: DesktopButton(
              label: l10n.musicStartScan,
              icon: DesktopIcons.retry,
              variant: DesktopButtonVariant.soft,
              busy: _photoScanning,
              onPressed:
                  canManage && !_photoScanning
                      ? () => _triggerAdminScan(
                        endpoint: '/admin/photos/scan',
                        isMusic: false,
                      )
                      : null,
            ),
          ),
          _OtherMediaLibraryRow(
            icon: DesktopIcons.book,
            title: l10n.desktopNavReader,
            detail: readerSummary,
            action: DesktopButton(
              label: l10n.desktopFilesOpen,
              icon: DesktopIcons.chevron,
              variant: DesktopButtonVariant.ghost,
              onPressed: () => context.go(DesktopRoutes.reader),
            ),
          ),
        ],
      ),
    );
  }
}

class _OtherMediaLibraryRow extends StatelessWidget {
  const _OtherMediaLibraryRow({
    required this.icon,
    required this.title,
    required this.detail,
    required this.action,
    this.first = false,
  });

  final IconData icon;
  final String title;
  final String detail;
  final Widget action;
  final bool first;

  @override
  Widget build(BuildContext context) {
    final skin = DesktopSkin.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        border: first ? null : Border(top: BorderSide(color: skin.line)),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: skin.accentWash(0.12),
              borderRadius: BorderRadius.circular(DesktopMetrics.radiusSmall),
            ),
            child: Icon(icon, size: 17, color: skin.accent),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: DesktopType.rowTitle(skin.text)),
                const SizedBox(height: 2),
                Text(
                  detail,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: DesktopType.caption(skin.text3),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          action,
        ],
      ),
    );
  }
}
