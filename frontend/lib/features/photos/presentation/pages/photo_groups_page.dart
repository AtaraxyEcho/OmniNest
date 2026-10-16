import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/app_typography.dart';

import 'package:omninest/app/theme/mobile_env_palette.dart';
import 'package:omninest/core/widgets/app_loading.dart';
import 'package:omninest/core/widgets/env_empty_state.dart';
import 'package:omninest/core/widgets/mobile_ui.dart';
import 'package:omninest/core/widgets/omni_icons.dart';
import 'package:omninest/features/photos/application/photo_controller.dart';
import 'package:omninest/features/photos/domain/photo_timeline.dart';
import 'package:omninest/features/photos/presentation/widgets/photo_thumb_image.dart';

/// 年·月分组页（原型 `photo-groups` 工具页 `.year-jump`）：按年份给出
/// 衬线年份 + 全年张数，再接 4 列方形月份砖（封面 + 月名 + 张数），
/// 点砖进入该月整月浏览。
///
/// 与照片空间的托管时间线同源：时间线只平铺每月预览，这页给出的是
/// 「哪个月有多少张」的入口，两者读同一份 timeline 数据。
class PhotoGroupsPage extends ConsumerStatefulWidget {
  const PhotoGroupsPage({super.key});

  @override
  ConsumerState<PhotoGroupsPage> createState() => _PhotoGroupsPageState();
}

class _PhotoGroupsPageState extends ConsumerState<PhotoGroupsPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      unawaited(
        ref.read(photoCenterControllerProvider.notifier).loadTimeline(),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final center = ref.watch(photoCenterControllerProvider);
    final data = center.asData?.value;
    final timeline = data?.timeline;

    return MobilePageSurface(
      backdropOpacity: 0.92,
      child: Column(
        children: [
          MobileModuleHeader(
            title: l10n.photosGroupsTitle,
            subtitle: l10n.photosGroupsSubtitle,
            backTooltip: MaterialLocalizations.of(context).backButtonTooltip,
            onBack: () => Navigator.of(context).maybePop(),
          ),
          Expanded(child: _body(l10n, data: data, timeline: timeline)),
        ],
      ),
    );
  }

  /// 三态分开：时间线到手且为空才说「没有照片」；取回失败说失败并给原因；
  /// 其余（首屏未回）只给骨架，不把等待伪装成空。
  Widget _body(
    AppLocalizations l10n, {
    required PhotoCenterState? data,
    required PhotoTimeline? timeline,
  }) {
    if (timeline != null) {
      if (timeline.years.isEmpty) {
        return _empty(l10n, l10n.photosGroupsEmptyHint);
      }
      return _YearList(timeline: timeline);
    }
    final error = data?.timelinePageError;
    if (data != null && error != null) {
      return _empty(l10n, error, title: l10n.photosOperationFailed);
    }
    // 整页首屏只留一处动画指示（此前两块占位各带一个转圈）。
    return const AppLoading();
  }

  Widget _empty(AppLocalizations l10n, String message, {String? title}) {
    return ListView(
      padding: EdgeInsets.zero,
      children: [
        EnvEmptyState(
          icon: OmniIcons.image,
          title: title ?? l10n.photosNoPhotos,
          message: message,
        ),
      ],
    );
  }
}

class _YearList extends StatelessWidget {
  const _YearList({required this.timeline});

  final PhotoTimeline timeline;

  @override
  Widget build(BuildContext context) {
    final languageCode = Localizations.localeOf(context).languageCode;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 96),
      children: [
        for (final year in timeline.years) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(2, 3, 2, 20),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  flex: 2,
                  child: Text(
                    '${year.year}',
                    style: TextStyle(
                      fontFamily: AppTypography.serifFamily,
                      fontFamilyFallback: AppTypography.serifFamilyFallback,
                      fontSize: AppTypography.displayMedium,
                      height: 1.0,
                      fontWeight: FontWeight.w400,
                      color: context.env.ink,
                    ),
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Text(
                    AppLocalizations.of(
                      context,
                    ).photosAlbumPhotoCountLabel(_yearPhotoCount(year)),
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      fontSize: 9, // ignore: font_size_whitelist
                      color: context.env.inkMuted,
                    ),
                  ),
                ),
              ],
            ),
          ),
          GridView.count(
            crossAxisCount: 4,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 5,
            crossAxisSpacing: 5,
            children: [
              for (final month in year.months)
                _MonthTile(
                  year: year.year,
                  month: month,
                  label:
                      DateFormat.MMM(
                        languageCode,
                      ).format(DateTime(year.year, month.month)).toUpperCase(),
                ),
            ],
          ),
        ],
      ],
    );
  }

  int _yearPhotoCount(PhotoYearGroup year) {
    return year.months.fold<int>(0, (total, month) => total + month.photoCount);
  }
}

/// 月份砖：封面 + 45% 起的暗向渐变 + 左下月名 / 右下张数。
class _MonthTile extends StatelessWidget {
  const _MonthTile({
    required this.year,
    required this.month,
    required this.label,
  });

  final int year;
  final PhotoMonthGroup month;
  final String label;

  @override
  Widget build(BuildContext context) {
    final cover =
        month.previewPhotos.isEmpty
            ? null
            : (month.previewPhotos.first.coverUrl ??
                month.previewPhotos.first.sourceUrl);
    return MobilePressable(
      semanticLabel: label,
      onTap: () => context.push('/photos/period/$year/${month.month}'),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: AspectRatio(
          aspectRatio: 1,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (cover != null)
                PhotoThumbImage(imageUrl: cover)
              else
                ColoredBox(color: context.env.surfaceRaised),
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.center,
                    end: Alignment.bottomCenter,
                    colors: [Color(0x00000000), Color(0xB3000000)],
                  ),
                ),
              ),
              Positioned(
                left: 7,
                right: 7,
                bottom: 7,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      label,
                      style: const TextStyle(
                        fontSize: 8, // ignore: font_size_whitelist
                        fontWeight: FontWeight.w700,
                        // polarity-stable：压在封面图的黑渐变遮罩上，两极性同值
                        color: Colors.white,
                      ),
                    ),
                    Text(
                      '${month.photoCount}',
                      style: const TextStyle(
                        fontSize: 8, // ignore: font_size_whitelist
                        fontWeight: FontWeight.w700,
                        // polarity-stable：压在封面图的黑渐变遮罩上，两极性同值
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
