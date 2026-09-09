import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/app_typography.dart';
import 'package:omninest/features/backdrop/application/app_backdrop_controller.dart';
import 'package:omninest/features/backdrop/domain/app_backdrop.dart';
import 'package:omninest/features/backdrop/presentation/app_backdrop_controls.dart';
import 'package:omninest/features/backdrop/presentation/app_backdrop_image.dart';
import 'package:omninest/features/backdrop/presentation/app_backdrop_palette.dart';

export 'package:omninest/features/backdrop/presentation/app_backdrop_palette.dart';

const _allBackdropFilter = 'all';

/// 显示应用本机背景设置面板。
Future<void> showAppBackdropSettings(
  BuildContext context, {
  required AppBackdropPalette palette,
}) {
  return showDialog(
    context: context,
    barrierColor: Colors.black54,
    builder: (_) => _AppBackdropSettingsDialog(palette: palette),
  );
}

class _AppBackdropSettingsDialog extends ConsumerWidget {
  const _AppBackdropSettingsDialog({required this.palette});

  final AppBackdropPalette palette;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final mediaQuery = MediaQuery.of(context);
    final compact = mediaQuery.size.width < 720;
    final asyncState = ref.watch(appBackdropControllerProvider);
    final notifier = ref.read(appBackdropControllerProvider.notifier);
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding:
          compact
              ? const EdgeInsets.symmetric(horizontal: 12, vertical: 16)
              : const EdgeInsets.symmetric(horizontal: 42, vertical: 36),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 980,
          maxHeight: compact ? mediaQuery.size.height - 32 : 720,
        ),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: const Color(0xF20A1117),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.36),
                blurRadius: 44,
                offset: const Offset(0, 22),
              ),
            ],
          ),
          child: asyncState.when(
            data:
                (state) => _AppBackdropSettingsContent(
                  palette: palette,
                  state: state,
                  notifier: notifier,
                ),
            loading:
                () => const SizedBox(
                  height: 420,
                  child: Center(child: CircularProgressIndicator()),
                ),
            error:
                (error, stackTrace) => SizedBox(
                  height: 420,
                  child: Center(
                    child: Text(
                      l10n.portalLocalBackdropLoadFailed,
                      style: TextStyle(color: palette.text),
                    ),
                  ),
                ),
          ),
        ),
      ),
    );
  }
}

class _AppBackdropSettingsContent extends StatefulWidget {
  const _AppBackdropSettingsContent({
    required this.palette,
    required this.state,
    required this.notifier,
  });

  final AppBackdropPalette palette;
  final AppBackdropState state;
  final AppBackdropController notifier;

  @override
  State<_AppBackdropSettingsContent> createState() =>
      _AppBackdropSettingsContentState();
}

class _AppBackdropSettingsContentState
    extends State<_AppBackdropSettingsContent> {
  String _filter = _allBackdropFilter;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final compact = MediaQuery.sizeOf(context).width < 720;
    final filterOptions = _buildFilterOptions(l10n, widget.state.backdrops);
    if (!filterOptions.any((option) => option.key == _filter)) {
      _filter = _allBackdropFilter;
    }
    final filteredBackdrops = _applyFilter(widget.state.backdrops);
    return Padding(
      padding: EdgeInsets.all(compact ? 16 : 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.photo_library_rounded,
                color: widget.palette.accent,
                size: 22,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.portalLocalBackdropTitle,
                      style: TextStyle(
                        color: widget.palette.text,
                        fontSize: AppTypography.titleLarge,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      l10n.portalLocalBackdropSubtitle,
                      style: TextStyle(
                        color: widget.palette.muted,
                        fontSize: AppTypography.bodySmall,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
                onPressed: () => Navigator.of(context).pop(),
                icon: Icon(Icons.close_rounded, color: widget.palette.text),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Wrap(
                  spacing: 10,
                  runSpacing: 8,
                  children: [
                    AppBackdropActionButton(
                      palette: widget.palette,
                      icon: Icons.add_photo_alternate_rounded,
                      label: l10n.portalLocalBackdropAddFiles,
                      onTap:
                          widget.state.uploading
                              ? null
                              : () => widget.notifier.addBackdropFiles(),
                    ),
                    if (widget.state.backdrops.any(
                      (backdrop) => !backdrop.isBundled,
                    ))
                      AppBackdropActionButton(
                        palette: widget.palette,
                        icon: Icons.delete_sweep_rounded,
                        label: l10n.portalLocalBackdropClearAll,
                        onTap: () => _confirmClearAll(context, l10n),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Padding(
                padding: const EdgeInsets.only(top: 9),
                child: Text(
                  l10n.portalLocalBackdropCount(widget.state.backdrops.length),
                  style: TextStyle(
                    color: widget.palette.muted,
                    fontSize: AppTypography.bodySmall,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _BackdropFilterBar(
            palette: widget.palette,
            value: _filter,
            options: filterOptions,
            onChanged: (value) => setState(() => _filter = value),
          ),
          if (_uploadFeedback(l10n) != null) ...[
            const SizedBox(height: 10),
            Text(
              _uploadFeedback(l10n)!,
              style: TextStyle(
                color: widget.palette.accentAlt,
                fontSize: AppTypography.bodySmall,
              ),
            ),
          ],
          const SizedBox(height: 18),
          Expanded(
            child:
                compact
                    ? ListView(
                      children: [
                        SizedBox(
                          height: 280,
                          child: _BackdropGrid(
                            palette: widget.palette,
                            state: widget.state,
                            backdrops: filteredBackdrops,
                            notifier: widget.notifier,
                          ),
                        ),
                        const SizedBox(height: 14),
                        AppBackdropControls(
                          palette: widget.palette,
                          state: widget.state,
                          notifier: widget.notifier,
                        ),
                      ],
                    )
                    : Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(
                          flex: 5,
                          child: _BackdropGrid(
                            palette: widget.palette,
                            state: widget.state,
                            backdrops: filteredBackdrops,
                            notifier: widget.notifier,
                          ),
                        ),
                        const SizedBox(width: 18),
                        SizedBox(
                          width: 300,
                          child: AppBackdropControls(
                            palette: widget.palette,
                            state: widget.state,
                            notifier: widget.notifier,
                          ),
                        ),
                      ],
                    ),
          ),
        ],
      ),
    );
  }

  /// 上传进行中/最近失败的用户反馈文案;无反馈时为空。
  String? _uploadFeedback(AppLocalizations l10n) {
    if (widget.state.uploading) {
      return l10n.portalLocalBackdropUploading;
    }
    final failures = widget.state.failedUploads;
    if (failures.isEmpty) {
      return null;
    }
    if (failures.length == 1) {
      final failure = failures.single;
      return switch (failure.code) {
        '8003' || '4003' => l10n.portalLocalBackdropQuotaExceeded,
        '8002' => l10n.portalLocalBackdropUnsupportedFormat,
        '8004' => l10n.portalLocalBackdropFileTooLarge,
        '8005' => l10n.portalLocalBackdropScanUnavailable,
        '8006' => l10n.portalLocalBackdropMalwareDetected,
        '8007' => l10n.portalLocalBackdropScanFailed,
        '429' => l10n.portalLocalBackdropRateLimited,
        _ => l10n.portalLocalBackdropUploadFailedNames(failure.title),
      };
    }
    return l10n.portalLocalBackdropUploadFailedNames(
      failures.map((failure) => failure.title).join(', '),
    );
  }

  List<AppBackdropAsset> _applyFilter(List<AppBackdropAsset> backdrops) {
    if (_filter == _allBackdropFilter) {
      return backdrops;
    }
    return backdrops
        .where((backdrop) => _extensionOf(backdrop.path) == _filter)
        .toList(growable: false);
  }

  String _extensionOf(String path) {
    final lower = path.toLowerCase();
    final index = lower.lastIndexOf('.');
    return index < 0 ? '' : lower.substring(index);
  }

  List<_FilterOption> _buildFilterOptions(
    AppLocalizations l10n,
    List<AppBackdropAsset> backdrops,
  ) {
    final counts = <String, int>{};
    for (final backdrop in backdrops) {
      final extension = _extensionOf(backdrop.path);
      if (extension.isNotEmpty) {
        counts[extension] = (counts[extension] ?? 0) + 1;
      }
    }
    final entries =
        counts.entries.toList()..sort((a, b) => a.key.compareTo(b.key));
    return [
      _FilterOption(
        key: _allBackdropFilter,
        label: l10n.portalLocalBackdropFilterAll,
        count: backdrops.length,
      ),
      for (final entry in entries)
        _FilterOption(
          key: entry.key,
          label: entry.key.replaceFirst('.', '').toUpperCase(),
          count: entry.value,
        ),
    ];
  }

  Future<void> _confirmClearAll(
    BuildContext context,
    AppLocalizations l10n,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      barrierColor: Colors.black54,
      builder:
          (dialogContext) => AlertDialog(
            backgroundColor: const Color(0xFF101820),
            titleTextStyle: TextStyle(
              color: widget.palette.text,
              fontSize: AppTypography.titleLarge,
              fontWeight: FontWeight.w800,
            ),
            contentTextStyle: TextStyle(
              color: widget.palette.muted,
              fontSize: AppTypography.bodyMedium,
              height: 1.55,
            ),
            title: Text(l10n.portalLocalBackdropClearAllTitle),
            content: Text(l10n.portalLocalBackdropClearAllMessage),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: Text(
                  MaterialLocalizations.of(context).cancelButtonLabel,
                ),
              ),
              FilledButton(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: Text(l10n.portalLocalBackdropClearAllConfirm),
              ),
            ],
          ),
    );
    if (!mounted || confirmed != true) {
      return;
    }
    await widget.notifier.clearBackdrops();
    if (mounted) {
      setState(() => _filter = _allBackdropFilter);
    }
  }
}

class _BackdropFilterBar extends StatelessWidget {
  const _BackdropFilterBar({
    required this.palette,
    required this.value,
    required this.options,
    required this.onChanged,
  });

  final AppBackdropPalette palette;
  final String value;
  final List<_FilterOption> options;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: options
            .map(
              (option) => Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  selected: value == option.key,
                  label: Text('${option.label} ${option.count}'),
                  onSelected: (_) => onChanged(option.key),
                  showCheckmark: false,
                  labelStyle: TextStyle(
                    color: Colors.black,
                    fontSize: AppTypography.bodySmall,
                    fontWeight: FontWeight.w700,
                  ),
                  selectedColor: palette.accent,
                  backgroundColor: Colors.white.withValues(alpha: 0.86),
                  side: BorderSide(color: Colors.white.withValues(alpha: 0.14)),
                  visualDensity: VisualDensity.compact,
                ),
              ),
            )
            .toList(growable: false),
      ),
    );
  }
}

class _FilterOption {
  const _FilterOption({
    required this.key,
    required this.label,
    required this.count,
  });

  final String key;
  final String label;
  final int count;
}

class _BackdropGrid extends StatelessWidget {
  const _BackdropGrid({
    required this.palette,
    required this.state,
    required this.backdrops,
    required this.notifier,
  });

  final AppBackdropPalette palette;
  final AppBackdropState state;
  final List<AppBackdropAsset> backdrops;
  final AppBackdropController notifier;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    if (state.backdrops.isEmpty || backdrops.isEmpty) {
      return DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.055),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
        ),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Text(
              state.backdrops.isEmpty
                  ? l10n.portalLocalBackdropEmpty
                  : l10n.portalLocalBackdropFilterEmpty,
              textAlign: TextAlign.center,
              style: TextStyle(color: palette.muted, height: 1.55),
            ),
          ),
        ),
      );
    }
    return GridView.builder(
      itemCount: backdrops.length,
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 190,
        mainAxisExtent: 142,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
      ),
      itemBuilder: (context, index) {
        final backdrop = backdrops[index];
        final selected = backdrop.id == state.selectedBackdropId;
        return _BackdropTile(
          palette: palette,
          backdrop: backdrop,
          selected: selected,
          onTap: () => notifier.selectBackdrop(backdrop.id),
          onRemove:
              backdrop.isBundled
                  ? null
                  : () => notifier.removeBackdrop(backdrop.id),
        );
      },
    );
  }
}

class _BackdropTile extends StatelessWidget {
  const _BackdropTile({
    required this.palette,
    required this.backdrop,
    required this.selected,
    required this.onTap,
    required this.onRemove,
  });

  final AppBackdropPalette palette;
  final AppBackdropAsset backdrop;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: backdrop.missing ? null : onTap,
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: selected ? 0.13 : 0.06),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color:
                  selected
                      ? palette.accent.withValues(alpha: 0.70)
                      : Colors.white.withValues(alpha: 0.12),
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            children: [
              Positioned.fill(child: _BackdropTilePreview(backdrop: backdrop)),
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.transparent,
                        Colors.black.withValues(alpha: 0.64),
                      ],
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 10,
                right: onRemove == null ? 10 : 34,
                bottom: 9,
                child: Text(
                  backdrop.missing
                      ? l10n.portalLocalBackdropMissing
                      : backdrop.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: palette.text,
                    fontSize: AppTypography.bodySmall,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (onRemove != null)
                Positioned(
                  right: 4,
                  top: 4,
                  child: IconButton(
                    tooltip: l10n.portalLocalBackdropRemove,
                    onPressed: onRemove,
                    icon: const Icon(Icons.close_rounded, size: 16),
                    color: palette.text,
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.black.withValues(alpha: 0.28),
                      minimumSize: const Size(28, 28),
                      fixedSize: const Size(28, 28),
                      padding: EdgeInsets.zero,
                    ),
                  ),
                ),
              if (selected)
                Positioned(
                  left: 8,
                  top: 8,
                  child: Icon(
                    Icons.check_circle_rounded,
                    color: palette.accent,
                    size: 20,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BackdropTilePreview extends StatelessWidget {
  const _BackdropTilePreview({required this.backdrop});

  final AppBackdropAsset backdrop;

  @override
  Widget build(BuildContext context) {
    if (backdrop.sourceType == AppBackdropSourceType.server) {
      final thumbnailUrl = backdrop.thumbnailPath;
      if (thumbnailUrl != null && thumbnailUrl.isNotEmpty) {
        return AppBackdropImage(
          url: thumbnailUrl,
          cacheKey: 'backdrop-preview:${backdrop.id}',
          fit: BoxFit.cover,
        );
      }
      if (!backdrop.isVideo && backdrop.path.isNotEmpty) {
        return AppBackdropImage(
          url: backdrop.path,
          cacheKey: 'backdrop-preview-full:${backdrop.id}',
          fit: BoxFit.cover,
        );
      }
      return const _BackdropVideoPlaceholder();
    }
    if (backdrop.isVideo) {
      return Image.asset(bundledDefaultWallpaperPosterAsset, fit: BoxFit.cover);
    }
    return const _BackdropVideoPlaceholder();
  }
}

class _BackdropVideoPlaceholder extends StatelessWidget {
  const _BackdropVideoPlaceholder();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF0B1720), Color(0xFF162234)],
        ),
      ),
      child: Center(
        child: Icon(
          Icons.play_circle_outline_rounded,
          color: Colors.white.withValues(alpha: 0.62),
          size: 34,
        ),
      ),
    );
  }
}
