import 'package:material_ui/material_ui.dart';
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

/// 最近照片条（样例 `.photo-strip`）：初始严格等宽，悬停目标扩展至 3 倍权重。
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
    final skeleton = SizedBox(
      height: 200,
      child: Row(
        children: [
          for (var index = 0; index < 7; index++)
            Expanded(
              flex: 1,
              child: Padding(
                padding: EdgeInsets.only(right: index == 6 ? 0 : 10),
                child: DesktopSkeletonBox(
                  height: 200,
                  radius: 14,
                  index: index,
                ),
              ),
            ),
        ],
      ),
    );
    final content =
        photos.isEmpty
            ? DesktopEmpty(
              message: l10n.desktopHomeEmptyPhotos,
              icon: DesktopIcons.image,
              actionLabel: l10n.desktopOpenPhotos,
              onAction: () => context.go(DesktopRoutes.photos),
            )
            : SizedBox(
              height: 200,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  const gap = 10.0;
                  final count = photos.length;
                  final available = (constraints.maxWidth - gap * (count - 1))
                      .clamp(0.0, double.infinity);
                  // 样例 `Home.tsx:109-113` & `polish.css:619-620`：
                  // 默认所有缩略图严格等宽 `flex-grow: 1`，悬停项扩展为 `flex-grow: 3`。
                  final grow = List<double>.filled(count, 1.0);
                  if (_hovered != null && _hovered! < count) {
                    grow[_hovered!] = 3.0;
                  }
                  final total = grow.fold<double>(
                    0,
                    (sum, value) => sum + value,
                  );
                  return Row(
                    children: [
                      for (var index = 0; index < count; index++)
                        () {
                          final itemWidth =
                              total == 0
                                  ? 0.0
                                  : available * grow[index] / total;
                          final trailingGap = index == count - 1 ? 0.0 : gap;
                          return MouseRegion(
                            cursor: SystemMouseCursors.click,
                            // 命中区包住卡片的间隙内边缘，宽度动画时指针不会因
                            // padding 重新布局而短暂离开 MouseRegion。
                            onEnter: (_) {
                              if (_hovered != index) {
                                setState(() => _hovered = index);
                              }
                            },
                            onExit: (_) {
                              if (_hovered == index) {
                                setState(() => _hovered = null);
                              }
                            },
                            child: AnimatedContainer(
                              duration: DesktopMotion.of(
                                context,
                                DesktopMotion.photoStrip,
                              ),
                              curve: Curves.easeOutCubic,
                              width: itemWidth + trailingGap,
                              padding: EdgeInsets.only(right: trailingGap),
                              child: GestureDetector(
                                onTap:
                                    () => context.push(
                                      DesktopRoutes.photoDetail(
                                        photos[index].id,
                                      ),
                                    ),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(14),
                                  child: Stack(
                                    fit: StackFit.expand,
                                    children: [
                                      RepaintBoundary(
                                        child: DesktopCover(
                                          url: photos[index].coverUrl,
                                          fallbackIcon: DesktopIcons.image,
                                          // 原型的 `<Img>` 首帧保持照片条的玻璃/背景层，
                                          // 不先替换成带图标的深色卡片；图片到达后直接覆盖。
                                          fallback: const SizedBox.expand(),
                                          cacheKey: photos[index].coverCacheKey,
                                          // 悬停会改变卡片宽度；固定解码宽度，避免
                                          // LayoutBuilder 每帧生成新的图片提供器而闪回占位。
                                          cacheWidth: 800,
                                        ),
                                      ),
                                      AnimatedOpacity(
                                        duration: MotionToken.reduced(
                                          context,
                                          MotionToken.fast,
                                        ),
                                        curve: MotionToken.curve,
                                        opacity: _hovered == index ? 1 : 0,
                                        alwaysIncludeSemantics: true,
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
                                              _photoPlaceLabel(photos[index]) ??
                                                  '',
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
                          );
                        }(),
                    ],
                  );
                },
              ),
            );
    return DesktopSkeletonSwitcher(
      regionId: 'home-photo-strip',
      hasData: dashboard != null,
      loading: dashboard == null && dashboardAsync.isLoading,
      skeleton: skeleton,
      child: content,
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
    final content =
        files.isEmpty
            ? DesktopEmpty(
              message: l10n.desktopHomeEmptyFiles,
              icon: DesktopIcons.folder,
              actionLabel: l10n.desktopOpenFiles,
              onAction: () => context.go(DesktopRoutes.files),
            )
            : Column(
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
                                            formatFileSize(
                                              files[index].sizeBytes,
                                            ),
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
                                color:
                                    hovered ? skin.raise2 : Colors.transparent,
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
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        formatFileSize(files[index].sizeBytes),
                                        style: DesktopType.caption(skin.text3),
                                      ),
                                      if (files[index].updatedAt != null) ...[
                                        const SizedBox(height: 2),
                                        Text(
                                          _formatRelativeTime(
                                            l10n,
                                            files[index].updatedAt!,
                                          ),
                                          style: DesktopType.micro(skin.text3),
                                        ),
                                      ],
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                    ),
                  ),
              ],
            );
    return DesktopSkeletonSwitcher(
      regionId: 'home-recent-files',
      hasData: recentAsync.hasValue,
      loading: recentAsync.isLoading && !recentAsync.hasValue,
      skeleton: const DesktopSkeletonRows(count: 5),
      child: content,
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
class DesktopActivityTimeline extends ConsumerStatefulWidget {
  const DesktopActivityTimeline({super.key});

  @override
  ConsumerState<DesktopActivityTimeline> createState() =>
      _DesktopActivityTimelineState();
}

class _DesktopActivityTimelineState
    extends ConsumerState<DesktopActivityTimeline> {
  bool _initialLoadDispatched = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _initialLoadDispatched) {
        return;
      }
      _initialLoadDispatched = true;
      final state = ref.read(notificationControllerProvider);
      if (state.items.isEmpty &&
          !state.isLoading &&
          !state.loadFailed &&
          state.total == 0) {
        ref
            .read(notificationControllerProvider.notifier)
            .load(page: 0, size: 10);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final skin = DesktopSkin.of(context);
    final l10n = AppLocalizations.of(context);
    final notifState = ref.watch(notificationControllerProvider);
    final items = notifState.items.take(4).toList();

    if (notifState.loadFailed && items.isEmpty) {
      return DesktopErrorView(
        message: l10n.notificationLoadFailed,
        onRetry:
            () => ref
                .read(notificationControllerProvider.notifier)
                .load(page: 0, size: 10),
        minHeightFactor: 0.22,
      );
    }
    final content =
        items.isEmpty
            ? DesktopEmpty(
              message: l10n.desktopHomeEmptyActivity,
              icon: DesktopIcons.clock,
              actionLabel: l10n.notificationTitle,
              onAction: () => context.go(DesktopRoutes.notifications),
            )
            : Column(
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
                                    color: _activityToneFor(
                                      skin,
                                      items[index].type,
                                    ).withValues(alpha: 0.14),
                                    shape: BoxShape.circle,
                                  ),
                                  child: Icon(
                                    _activityIconFor(items[index].type),
                                    size: 13,
                                    color: _activityToneFor(
                                      skin,
                                      items[index].type,
                                    ),
                                  ),
                                ),
                                if (index != items.length - 1)
                                  Expanded(
                                    child: Container(
                                      width: 1,
                                      color: skin.line,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.only(
                                bottom: 14,
                                top: 3,
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          (items[index].title ?? '').isNotEmpty
                                              ? items[index].title!
                                              : items[index].type,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: DesktopType.denseStrong(
                                            skin.text,
                                          ),
                                        ),
                                        if ((items[index].message ?? '')
                                            .isNotEmpty)
                                          Text(
                                            items[index].message!,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: DesktopType.caption(
                                              skin.text3,
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Text(
                                    _formatRelativeTime(
                                      l10n,
                                      items[index].createdAt,
                                    ),
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
    return DesktopSkeletonSwitcher(
      regionId: 'home-activity-timeline',
      hasData: !notifState.isLoading || items.isNotEmpty,
      loading: notifState.isLoading && items.isEmpty,
      skeleton: const DesktopSkeletonRows(count: 4),
      child: content,
    );
  }

  static IconData _activityIconFor(String type) {
    final lower = type.toLowerCase();
    if (lower.contains('video') ||
        lower.contains('movie') ||
        lower.contains('transcode') ||
        lower.contains('scrape')) {
      return DesktopIcons.film;
    }
    if (lower.contains('music') || lower.contains('audio')) {
      return DesktopIcons.music;
    }
    if (lower.contains('photo') ||
        lower.contains('image') ||
        lower.contains('album')) {
      return DesktopIcons.image;
    }
    if (lower.contains('reader') ||
        lower.contains('book') ||
        lower.contains('comic') ||
        lower.contains('manga')) {
      return DesktopIcons.book;
    }
    if (lower.contains('share')) {
      return DesktopIcons.share;
    }
    if (lower.contains('file') ||
        lower.contains('upload') ||
        lower.contains('download') ||
        lower.contains('storage') ||
        lower.contains('quota')) {
      return DesktopIcons.folder;
    }
    if (lower.contains('security') ||
        lower.contains('auth') ||
        lower.contains('login') ||
        lower.contains('password')) {
      return DesktopIcons.shield;
    }
    if (lower.contains('task') ||
        lower.contains('sync') ||
        lower.contains('backup') ||
        lower.contains('import')) {
      return DesktopIcons.tasks;
    }
    return DesktopIcons.bell;
  }

  static Color _activityToneFor(DesktopSkin skin, String type) {
    final lower = type.toLowerCase();
    if (lower.contains('video') ||
        lower.contains('movie') ||
        lower.contains('transcode') ||
        lower.contains('scrape')) {
      return DesktopPalette.kindVideo;
    }
    if (lower.contains('music') || lower.contains('audio')) {
      return DesktopPalette.kindAudio;
    }
    if (lower.contains('photo') ||
        lower.contains('image') ||
        lower.contains('album')) {
      return DesktopPalette.kindImage;
    }
    if (lower.contains('reader') ||
        lower.contains('book') ||
        lower.contains('comic') ||
        lower.contains('manga')) {
      return DesktopPalette.kindDocument;
    }
    return skin.accent;
  }
}

String _formatRelativeTime(AppLocalizations l10n, DateTime timestamp) {
  final local = timestamp.toLocal();
  final diff = DateTime.now().difference(local);
  if (diff.isNegative || diff.inMinutes < 1) {
    return l10n.videoJustNow;
  }
  if (diff.inHours < 1) {
    return l10n.videoMinutesAgo(diff.inMinutes);
  }
  if (diff.inDays < 1) {
    return l10n.videoHoursAgo(diff.inHours);
  }
  if (diff.inDays < 30) {
    return l10n.videoDaysAgo(diff.inDays);
  }
  String two(int part) => part.toString().padLeft(2, '0');
  return '${local.year}-${two(local.month)}-${two(local.day)}';
}
