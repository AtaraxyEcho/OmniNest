import 'package:flutter/material.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:omninest/app/theme/app_typography.dart';
import 'package:omninest/app/theme/feature/reader_colors.dart';
import 'package:omninest/features/reader/application/reader_controller.dart';
import 'package:omninest/features/reader/application/reader_import_queue_controller.dart';
import 'package:omninest/features/reader/domain/reader_models.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_import_section.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_import_queue_cards.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_metadata_section.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_page_scaffold.dart';

/// 内容管理页（仅管理员）：导入、待导入文件、元数据管理与历史。
///
/// 页面骨架对非管理员渲染无权访问兜底视图，页签同样仅对管理员可见。
class ReaderAdminPage extends ConsumerWidget {
  const ReaderAdminPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stateAsync = ref.watch(readerCenterControllerProvider);
    final importJobs = ref.watch(readerImportQueueProvider);
    final items = stateAsync.asData?.value.items ?? const <ReaderItem>[];
    final inProgressCount =
        items
            .where(
              (item) =>
                  (item.progressPercent ?? 0) > 0 &&
                  (item.progressPercent ?? 0) < 1,
            )
            .length;
    return ReaderPageScaffold(
      target: ReaderPageTarget.admin,
      onRefresh: () async {
        await ref.read(readerCenterControllerProvider.notifier).refresh();
      },
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 768),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _AdminSectionHeader(labelKey: 'readerImports'),
              const SizedBox(height: 16),
              const ImportFromDeviceButton(),
              if (importJobs.isNotEmpty) ...[
                const SizedBox(height: 4),
                for (final job in importJobs)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: ImportJobRow(job: job),
                  ),
              ],
              const _AdminDivider(),
              // ImportSection 自带「待导入文件」标题，此处不再重复
              ImportSection(
                onImported:
                    () =>
                        ref
                            .read(readerCenterControllerProvider.notifier)
                            .refresh(),
              ),
              const _AdminDivider(),
              // MetadataSection 自带「元数据管理」标题与搜索，此处不再重复
              MetadataSection(items: items),
              const _AdminDivider(),
              _AdminSectionHeader(
                labelKey: 'readerHistory',
                count: inProgressCount,
              ),
              const SizedBox(height: 16),
              const _RecentReading(),
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }
}

/// 区块间 1px 分隔线。
class _AdminDivider extends StatelessWidget {
  const _AdminDivider();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Container(
        height: 1,
        color: context.readerColors.outlineVariant.withValues(alpha: 0.6),
      ),
    );
  }
}

/// 小节标签：大写等宽小字（样例 SectionHeader 模式）。
class _AdminSectionHeader extends StatelessWidget {
  const _AdminSectionHeader({required this.labelKey, this.count});

  final String labelKey;
  final int? count;

  @override
  Widget build(BuildContext context) {
    final rc = context.readerColors;
    final label = switch (labelKey) {
      'readerImports' => AppLocalizations.of(context).readerImports,
      'readerPendingImport' => AppLocalizations.of(context).readerPendingImport,
      'readerMetadataManagement' =>
        AppLocalizations.of(context).readerMetadataManagement,
      _ => AppLocalizations.of(context).readerHistory,
    };
    return Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Text(
          label.toUpperCase(),
          style: TextStyle(
            color: rc.onSurfaceVariant,
            fontSize: 10,
            height: 1.2,
            letterSpacing: 2.4,
            fontWeight: FontWeight.w600,
          ),
        ),
        if (count != null) ...[
          const SizedBox(width: 12),
          Text(
            '$count',
            style: TextStyle(
              color: rc.onSurfaceVariant,
              fontSize: 10,
              height: 1.2,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ],
    );
  }
}

/// 管理页"最近阅读"区：展示进行中条目（从条目列表本地过滤），点击进详情。
class _RecentReading extends ConsumerWidget {
  const _RecentReading();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rc = context.readerColors;
    final items =
        ref
            .watch(readerCenterControllerProvider)
            .asData
            ?.value
            .items
            .where(
              (item) =>
                  (item.progressPercent ?? 0) > 0 &&
                  (item.progressPercent ?? 0) < 1,
            )
            .toList() ??
        const <ReaderItem>[];
    if (items.isEmpty) {
      return Text(
        AppLocalizations.of(context).adminHistoryEmpty,
        style: TextStyle(
          color: rc.onSurfaceVariant,
          fontSize: AppTypography.bodySmall,
        ),
      );
    }
    return Column(
      children: [
        for (final item in items)
          InkWell(
            onTap: () => context.push('/reader/items/${item.id}'),
            hoverColor: rc.surfaceContainerHigh,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: rc.onSurface,
                            fontSize: 14,
                            height: 1.3,
                            fontFamily: kReaderSerifFamily,
                          ),
                        ),
                        if (item.authorName?.isNotEmpty == true) ...[
                          const SizedBox(height: 2),
                          Text(
                            item.authorName!,
                            style: TextStyle(
                              color: rc.onSurfaceVariant,
                              fontSize: 11,
                              height: 1.2,
                            ),
                          ),
                        ],
                        const SizedBox(height: 6),
                        Container(
                          height: 1,
                          color: rc.outlineVariant,
                          alignment: Alignment.centerLeft,
                          child: FractionallySizedBox(
                            widthFactor: (item.progressPercent ?? 0).clamp(
                              0.0,
                              1.0,
                            ),
                            child: Container(height: 1, color: rc.reading),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  Text(
                    '${((item.progressPercent ?? 0) * 100).round()}%',
                    style: TextStyle(
                      color: rc.onSurfaceVariant,
                      fontSize: 12,
                      height: 1.2,
                      fontFeatures: const [FontFeature.tabularFigures()],
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
