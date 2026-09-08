import 'package:flutter/material.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:omninest/app/theme/app_typography.dart';
import 'package:omninest/app/theme/feature/reader_colors.dart';
import 'package:omninest/features/reader/application/reader_controller.dart';
import 'package:omninest/features/reader/application/reader_import_queue_controller.dart';
import 'package:omninest/features/reader/domain/reader_models.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_import_section.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_import_queue_cards.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_metadata_section.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_page_scaffold.dart';

/// 内容管理页（仅管理员）：元数据管理、导入与最近阅读。
///
/// 页面骨架对非管理员渲染无权访问兜底视图，页签同样仅对管理员可见。
class ReaderAdminPage extends ConsumerWidget {
  const ReaderAdminPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stateAsync = ref.watch(readerCenterControllerProvider);
    final importJobs = ref.watch(readerImportQueueProvider);
    final items = stateAsync.asData?.value.items ?? const <ReaderItem>[];
    return ReaderPageScaffold(
      target: ReaderPageTarget.admin,
      onRefresh: () async {
        await ref.read(readerCenterControllerProvider.notifier).refresh();
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _AdminSectionHeader(
            label: AppLocalizations.of(context).readerImports,
          ),
          const SizedBox(height: 12),
          const ImportFromDeviceButton(),
          if (importJobs.isNotEmpty) ...[
            const SizedBox(height: 12),
            for (final job in importJobs)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: ImportJobRow(job: job),
              ),
          ],
          const SizedBox(height: 16),
          ImportSection(
            onImported:
                () =>
                    ref.read(readerCenterControllerProvider.notifier).refresh(),
          ),
          const SizedBox(height: 24),
          _AdminSectionHeader(
            label: AppLocalizations.of(context).readerMetadataManagement,
          ),
          const SizedBox(height: 12),
          MetadataSection(items: items),
          const SizedBox(height: 24),
          _AdminSectionHeader(
            label: AppLocalizations.of(context).readerHistory,
          ),
          const SizedBox(height: 8),
          const _RecentReading(),
        ],
      ),
    );
  }
}

class _AdminSectionHeader extends StatelessWidget {
  const _AdminSectionHeader({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: TextStyle(
        color: context.readerColors.onSurface,
        fontSize: AppTypography.titleMedium,
        height: 20 / 15,
        fontWeight: FontWeight.w700,
      ),
    );
  }
}

/// 管理页"最近阅读"区：展示进行中条目（从条目列表本地过滤）。
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
        AppLocalizations.of(context).readerEmptyHint,
        style: TextStyle(
          color: rc.onSurfaceVariant,
          fontSize: AppTypography.bodySmall,
        ),
      );
    }
    return Column(
      children: [
        for (final item in items)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    item.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: rc.onSurface,
                      fontSize: AppTypography.bodyMedium,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  '${((item.progressPercent ?? 0) * 100).round()}%',
                  style: TextStyle(
                    color: rc.onSurfaceVariant,
                    fontSize: AppTypography.labelSmall,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
