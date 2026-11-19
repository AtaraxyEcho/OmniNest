import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:omninest/app/desktop/desktop_icons.dart';
import 'package:omninest/app/desktop/desktop_routes.dart';
import 'package:omninest/app/desktop/desktop_shell_state.dart';
import 'package:omninest/app/desktop/widgets/desktop_controls.dart';
import 'package:omninest/app/desktop/widgets/desktop_cover.dart';
import 'package:omninest/app/desktop/widgets/desktop_error_view.dart';
import 'package:omninest/app/desktop/widgets/desktop_skeleton.dart';
import 'package:omninest/app/desktop/widgets/desktop_surfaces.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/desktop/desktop_palette.dart';
import 'package:omninest/app/theme/desktop/desktop_skin.dart';
import 'package:omninest/app/theme/desktop/desktop_type.dart';
import 'package:omninest/app/theme/desktop/desktop_motion.dart';
import 'package:omninest/core/theme/motion_token.dart';
import 'package:omninest/core/errors/error_message.dart';
import 'package:omninest/core/utils/file_size_formatter.dart';
import 'package:omninest/features/files/file_dashboard.dart';
import 'package:omninest/features/notifications/application/notification_controller.dart';
import 'package:omninest/features/photos/photo_dashboard.dart';

/// 最近照片条（样例 `.photo-strip`）：按原始宽高比分配宽度，悬停扩张。
class DesktopPhotoStrip extends ConsumerStatefulWidget {
  const DesktopPhotoStrip({super.key});

  @override
  ConsumerState<DesktopPhotoStrip> createState() => _DesktopPhotoStripState();
}

class _DesktopPhotoStripState extends ConsumerState<DesktopPhotoStrip> {
  int? _hovered;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final dashboardAsync = ref.watch(photoDashboardProvider);
    final dashboard = dashboardAsync.asData?.value;
    final photos =
        (dashboard?.recentPhotos ?? const <PhotoItem>[]).take(7).toList();
    if (dashboard == null && dashboardAsync.hasError) {
      return DesktopErrorView(
        message: errorReason(dashboardAsync.error!, l10n),
        onRetry: () => ref.invalidate(photoDashboardProvider),
        minHeightFactor: 0.22,
      );
    }
    if (dashboard == null && dashboardAsync.isLoading) {
      return SizedBox(
        height: 200,
        child: Row(
          children: [
            for (var index = 0; index < 7; index++)
              Expanded(
                flex: const [160, 120, 220, 140, 180, 140, 160][index],
                child: Padding(
                  padding: EdgeInsets.only(right: index == 6 ? 0 : 10),
                  child: DesktopSkeletonBox(radius: 14, index: index),
                ),
              ),
          ],
        ),
      );
    }
    if (photos.isEmpty) {
      return DesktopEmpty(
        message: l10n.desktopHomeEmptyPhotos,
        icon: DesktopIcons.image,
        actionLabel: l10n.desktopOpenPhotos,
        onAction: () => context.go(DesktopRoutes.photos),
      );
    }
    return SizedBox(
      height: 200,
      child: LayoutBuilder(
        builder: (context, constraints) {
          const gap = 10.0;
          final count = photos.length;
          final available = (constraints.maxWidth - gap * (count - 1)).clamp(
            0.0,
            double.infinity,
          );
          // 样例 `Home.tsx`：`flexGrow: p.ratio`（宽高比原值），
          // hover 时 `.ps:hover { flex-grow: 3 !important }`。
          // 两边同乘 100 保留比例，避免把比例 clamp 到某个像素区间。
          final grow = <double>[
            for (final photo in photos)
              ((photo.width ?? 4) / (photo.height ?? 3) * 100).clamp(
                20.0,
                800.0,
              ),
          ];
          if (_hovered != null && _hovered! < grow.length) {
            grow[_hovered!] = 300;
          }
          final total = grow.fold<double>(0, (sum, value) => sum + value);
          return Row(
            children: [
              for (var index = 0; index < count; index++)
                AnimatedContainer(
                  duration: DesktopMotion.of(context, DesktopMotion.photoStrip),
                  curve: Curves.easeOutCubic,
                  width: total == 0 ? 0 : available * grow[index] / total,
                  padding: EdgeInsets.only(right: index == count - 1 ? 0 : gap),
                  child: MouseRegion(
                    cursor: SystemMouseCursors.click,
                    onEnter: (_) => setState(() => _hovered = index),
                    onExit: (_) => setState(() => _hovered = null),
                    child: GestureDetector(
                      onTap:
                          () => context.push(
                            DesktopRoutes.photoDetail(photos[index].id),
                          ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(14),
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            DesktopCover(
                              url: photos[index].coverUrl,
                              fallbackIcon: DesktopIcons.image,
                              cacheKey: photos[index].coverCacheKey,
                            ),
                            AnimatedOpacity(
                              duration: MotionToken.reduced(
                                context,
                                MotionToken.fast,
                              ),
                              curve: MotionToken.curve,
                              opacity: _hovered == index ? 1 : 0,
                              child: Align(
                                alignment: Alignment.bottomLeft,
                                child: Padding(
                                  padding: const EdgeInsets.fromLTRB(
                                    12,
                                    12,
                                    12,
                                    10,
                                  ),
                                  child: Text(
                                    // 样例标签显示 `place`，不是照片标题。
                                    _photoPlaceLabel(photos[index]) ?? '',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: DesktopType.caption(
                                      DesktopPalette.onStage,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

/// 样例 `p.place`：取 `gpsLocation` 里第一个可读地名。
String? _photoPlaceLabel(PhotoItem photo) {
  final location = photo.gpsLocation;
  if (location == null || location.isEmpty) {
    return null;
  }
  for (final key in const ['name', 'displayName', 'locality', 'city']) {
    final value = location[key];
    if (value is String && value.isNotEmpty) {
      return value;
    }
  }
  return null;
}

/// 最近文件小列表（样例 `.mini-list`）。
class DesktopRecentFiles extends ConsumerWidget {
  const DesktopRecentFiles({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final skin = DesktopSkin.of(context);
    final l10n = AppLocalizations.of(context);
    final recentAsync = ref.watch(fileRecentEntriesProvider);
    final files =
        (recentAsync.asData?.value ?? const <FileNode>[])
            .where((node) => !node.isFolder)
            .take(5)
            .toList();
    if (recentAsync.hasError && !recentAsync.hasValue) {
      return DesktopErrorView(
        message: errorReason(recentAsync.error!, l10n),
        onRetry: () => ref.invalidate(fileRecentEntriesProvider),
        minHeightFactor: 0.22,
      );
    }
    if (recentAsync.isLoading && !recentAsync.hasValue) {
      return const DesktopSkeletonRows(count: 5);
    }
    if (files.isEmpty) {
      return DesktopEmpty(
        message: l10n.desktopHomeEmptyFiles,
        icon: DesktopIcons.folder,
        actionLabel: l10n.desktopOpenFiles,
        onAction: () => context.go(DesktopRoutes.files),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 样例 `.mini-list > *`：逐行 55ms 交错。
        for (var index = 0; index < files.length; index++)
          DesktopStagger(
            index: index,
            child: DesktopHover(
              builder:
                  (context, hovered) => GestureDetector(
                    onTap:
                        () => context.push(
                          DesktopRoutes.filePreview(files[index].id),
                        ),
                    onSecondaryTap:
                        () => ref
                            .read(desktopShellProvider.notifier)
                            .showDetail(
                              DesktopDetailData(
                                kind: 'file',
                                title: files[index].name,
                                subtitle: formatFileSize(
                                  files[index].sizeBytes,
                                ),
                                squareArt: true,
                                facts: [
                                  MapEntry(
                                    l10n.desktopFileSection,
                                    files[index].nodeType,
                                  ),
                                  MapEntry(
                                    l10n.desktopStorage,
                                    formatFileSize(files[index].sizeBytes),
                                  ),
                                ],
                              ),
                            ),
                    behavior: HitTestBehavior.opaque,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 9,
                      ),
                      decoration: BoxDecoration(
                        color: hovered ? skin.raise2 : Colors.transparent,
                        borderRadius: BorderRadius.circular(
                          DesktopMetrics.radius,
                        ),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 34,
                            height: 34,
                            decoration: BoxDecoration(
                              color: _toneFor(
                                files[index].nodeType,
                              ).withValues(alpha: 0.16),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Icon(
                              _iconFor(files[index].nodeType),
                              size: 15,
                              color: _toneFor(files[index].nodeType),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              files[index].name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: DesktopType.rowTitle(skin.text),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Text(
                            formatFileSize(files[index].sizeBytes),
                            style: DesktopType.caption(skin.text3),
                          ),
                        ],
                      ),
                    ),
                  ),
            ),
          ),
      ],
    );
  }

  static IconData _iconFor(String nodeType) {
    final lower = nodeType.toLowerCase();
    if (lower.contains('video')) {
      return DesktopIcons.film;
    }
    if (lower.contains('audio')) {
      return DesktopIcons.music;
    }
    if (lower.contains('image')) {
      return DesktopIcons.image;
    }
    if (lower.contains('novel') || lower.contains('book')) {
      return DesktopIcons.book;
    }
    return DesktopIcons.list2;
  }

  static Color _toneFor(String nodeType) {
    final lower = nodeType.toLowerCase();
    if (lower.contains('video')) {
      return DesktopPalette.kindVideo;
    }
    if (lower.contains('audio')) {
      return DesktopPalette.kindAudio;
    }
    if (lower.contains('image')) {
      return DesktopPalette.kindImage;
    }
    if (lower.contains('novel') || lower.contains('book')) {
      return DesktopPalette.kindDocument;
    }
    return DesktopPalette.kindText;
  }
}

/// 动态时间线（样例 `.timeline`），数据取通知中心。
class DesktopActivityTimeline extends ConsumerWidget {
  const DesktopActivityTimeline({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final skin = DesktopSkin.of(context);
    final l10n = AppLocalizations.of(context);
    final items =
        ref.watch(notificationControllerProvider).items.take(4).toList();
    if (items.isEmpty) {
      return DesktopEmpty(
        message: l10n.desktopHomeEmptyActivity,
        icon: DesktopIcons.clock,
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 样例 `.timeline > *`：逐条 55ms 交错。
        for (var index = 0; index < items.length; index++)
          DesktopStagger(
            index: index,
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    width: 28,
                    child: Column(
                      children: [
                        Container(
                          width: 28,
                          height: 28,
                          decoration: BoxDecoration(
                            color: skin.accentWash(0.14),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            DesktopIcons.sparkle,
                            size: 13,
                            color: skin.accent,
                          ),
                        ),
                        if (index != items.length - 1)
                          Expanded(
                            child: Container(width: 1, color: skin.line),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 14, top: 3),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            items[index].title ?? items[index].type,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: DesktopType.denseStrong(skin.text),
                          ),
                          if ((items[index].message ?? '').isNotEmpty)
                            Text(
                              items[index].message!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: DesktopType.caption(skin.text3),
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
