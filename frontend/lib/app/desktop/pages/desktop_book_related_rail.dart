import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:omninest/app/desktop/desktop_router_scope.dart';
import 'package:omninest/app/desktop/desktop_routes.dart';
import 'package:omninest/app/desktop/widgets/desktop_surfaces.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/desktop/desktop_skin.dart';
import 'package:omninest/app/theme/desktop/desktop_type.dart';
import 'package:omninest/features/reader/reader_dashboard.dart';

/// 相关书架（样例 `More on your shelf`）：同内容类型的另外 5 本。
class DesktopBookRelatedRail extends ConsumerWidget {
  const DesktopBookRelatedRail({required this.item, super.key});

  final ReaderItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final skin = DesktopSkin.of(context);
    final dashboard = ref.watch(readerDashboardProvider);
    final items =
        dashboard.asData?.value.recentItems
            .where(
              (entry) =>
                  entry.id != item.id && entry.contentKind == item.contentKind,
            )
            .take(5)
            .toList() ??
        const <ReaderItem>[];
    if (items.isEmpty) {
      return const SizedBox.shrink();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.desktopBookRelated,
          style: DesktopType.sectionTitle(skin.text),
        ),
        const SizedBox(height: 14),
        SizedBox(
          height: 230,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: items.length,
            separatorBuilder: (_, _) => const SizedBox(width: 16),
            itemBuilder:
                (context, index) => _RelatedCard(
                  item: items[index],
                  onTap:
                      () => desktopPush(
                        context,
                        DesktopRoutes.bookDetail(items[index].id),
                      ),
                ),
          ),
        ),
      ],
    );
  }
}

class _RelatedCard extends StatelessWidget {
  const _RelatedCard({required this.item, required this.onTap});

  final ReaderItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final skin = DesktopSkin.of(context);
    return SizedBox(
      width: 132,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 132,
              height: 188,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Color.lerp(skin.accent, skin.panelSolid, 0.45)!,
                      skin.panelSolid,
                    ],
                  ),
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(4),
                    topRight: Radius.circular(9),
                    bottomRight: Radius.circular(9),
                    bottomLeft: Radius.circular(4),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.35),
                      blurRadius: 18,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child:
                    item.coverUrl?.isNotEmpty == true
                        ? DesktopImage(url: item.coverUrl)
                        : Padding(
                          padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
                          child: Align(
                            alignment: Alignment.bottomLeft,
                            child: Text(
                              item.title,
                              maxLines: 4,
                              overflow: TextOverflow.ellipsis,
                              style: DesktopType.caption(skin.onStage),
                            ),
                          ),
                        ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              item.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: DesktopType.dense(skin.text),
            ),
            Text(
              item.authorName ?? '',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: DesktopType.nano(skin.text3),
            ),
          ],
        ),
      ),
    );
  }
}
