import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:omninest/app/desktop/widgets/desktop_controls.dart';
import 'package:omninest/app/desktop/widgets/desktop_pager.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/desktop/desktop_palette.dart';
import 'package:omninest/app/theme/desktop/desktop_skin.dart';
import 'package:omninest/app/theme/desktop/desktop_type.dart';
import 'package:omninest/core/feedback/omni_feedback.dart';
import 'package:omninest/core/theme/motion_token.dart';
import 'package:omninest/core/widgets/responsive_search_field.dart';
import 'package:omninest/features/admin/application/admin_log_csv.dart';
import 'package:omninest/features/admin/application/admin_operations_controller.dart';
import 'package:omninest/features/admin/domain/admin_operations.dart';
import 'package:omninest/features/admin/domain/admin_paging.dart';
import 'package:omninest/features/admin/presentation/widgets/admin_list_components.dart';

/// 原型 Operations/System logs：级别与来源筛选、搜索、展开、导出和分页。
class AdminSystemLogsPage extends ConsumerStatefulWidget {
  const AdminSystemLogsPage({super.key});

  @override
  ConsumerState<AdminSystemLogsPage> createState() =>
      _AdminSystemLogsPageState();
}

class _AdminSystemLogsPageState extends ConsumerState<AdminSystemLogsPage> {
  static const _pageSizes = <int>[20, 50, 100];
  static const _levels = <String>['ALL', 'ERROR', 'WARN', 'INFO', 'DEBUG'];

  final TextEditingController _searchController = TextEditingController();
  Timer? _searchDebounce;
  int _page = 0;
  int _size = 20;
  String _level = 'ALL';
  String _source = 'ALL';
  String _query = '';
  String? _expandedId;

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  AdminSystemLogPageQuery get _pageQuery => (
    page: _page,
    size: _size,
    level: _level,
    source: _source,
    query: _query,
  );

  void _onSearchChanged(String value) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(
      Duration(milliseconds: MotionToken.fast.inMilliseconds + 100),
      () {
        if (!mounted) return;
        setState(() {
          _query = value.trim();
          _page = 0;
          _expandedId = null;
        });
      },
    );
  }

  Future<void> _export(AdminSystemLogPage firstPage) async {
    final l10n = AppLocalizations.of(context);
    final level = _level == 'ALL' ? '' : _level;
    final source = _source == 'ALL' ? '' : _source;
    final query = _query;
    try {
      final api = ref.read(adminOperationsApiProvider);
      final entries = <AdminSystemLogItem>[];
      final pageCount = (firstPage.totalElements + 99) ~/ 100;
      for (var pageIndex = 0; pageIndex < pageCount; pageIndex++) {
        final page = await api.systemLogPage(
          page: pageIndex,
          size: 100,
          level: level,
          source: source,
          query: query,
        );
        entries.addAll(page.items);
      }
      final csv = adminCsvDocument(
        header: [
          l10n.adminLogTime,
          l10n.adminFilterStatus,
          l10n.adminSystemLogSource,
          l10n.adminSystemLogMessage,
        ],
        rows: [
          for (final entry in entries)
            [entry.timestamp, entry.level, entry.source, entry.message],
        ],
      );
      final path = await saveAdminCsvToDisk(
        suggestedName: 'system-logs.csv',
        csv: csv,
      );
      if (!mounted || path == null) return;
      showOmniFeedback(
        context,
        l10n.adminCsvExported,
        severity: OmniFeedbackSeverity.success,
      );
    } on Object catch (error) {
      if (!mounted) return;
      showOmniFeedback(
        context,
        l10n.adminLoadFailed(error.toString()),
        severity: OmniFeedbackSeverity.error,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final pageAsync = ref.watch(adminSystemLogPageProvider(_pageQuery));
    final page = pageAsync.asData?.value;
    final sources = <String>{
      'ALL',
      ...?page?.sources,
      if (_source != 'ALL') _source,
    }.toList(growable: false);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 14,
          runSpacing: 12,
          children: [
            ResponsiveSearchField(
              controller: _searchController,
              hintText: l10n.adminSearchHint,
              maxWidth: 340,
              onChanged: _onSearchChanged,
            ),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (page != null)
                  AppDropdown<String>(
                    width: 240,
                    dense: true,
                    label: l10n.adminSystemLogSource,
                    value: sources.contains(_source) ? _source : 'ALL',
                    items: [
                      for (final source in sources)
                        AppDropdownItem<String>(
                          value: source,
                          label: source == 'ALL' ? l10n.adminAll : source,
                        ),
                    ],
                    onChanged: (value) {
                      if (value == null) return;
                      setState(() {
                        _source = value;
                        _page = 0;
                        _expandedId = null;
                      });
                    },
                  ),
                DesktopButton(
                  label: l10n.adminListExportCsv,
                  icon: Icons.file_download_outlined,
                  variant: DesktopButtonVariant.ghost,
                  onPressed: page == null ? null : () => _export(page),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final level in _levels)
              DesktopChipButton(
                label:
                    level == 'ALL'
                        ? l10n.adminAll
                        : '$level${level == 'ALL' ? '' : ' · ${page?.levelCounts[level] ?? 0}'}',
                selected: _level == level,
                onTap: () {
                  setState(() {
                    _level = level;
                    _page = 0;
                    _expandedId = null;
                  });
                },
              ),
          ],
        ),
        const SizedBox(height: 12),
        Expanded(
          child: pageAsync.when(
            loading: () => const AdminListSkeleton(rows: 8),
            error:
                (error, _) => Row(
                  children: [
                    Expanded(
                      child: Text(l10n.adminLoadFailed(error.toString())),
                    ),
                    DesktopButton(
                      label: l10n.coreRetry,
                      onPressed:
                          () => ref.invalidate(
                            adminSystemLogPageProvider(_pageQuery),
                          ),
                    ),
                  ],
                ),
            data:
                (result) => Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (result.items.isEmpty)
                      Expanded(
                        child: Center(
                          child: AdminListEmptyState(
                            message: l10n.adminNoMatch,
                          ),
                        ),
                      )
                    else
                      Expanded(
                        child: ListView.builder(
                          itemCount: result.items.length,
                          itemBuilder: (context, index) {
                            final entry = result.items[index];
                            return _SystemLogRow(
                              entry: entry,
                              expanded: _expandedId == entry.id,
                              onTap:
                                  () => setState(
                                    () =>
                                        _expandedId =
                                            _expandedId == entry.id
                                                ? null
                                                : entry.id,
                                  ),
                            );
                          },
                        ),
                      ),
                    DesktopPager(
                      page: result.page,
                      totalPages: result.totalPages,
                      pageSize: _size,
                      pageSizeOptions: _pageSizes,
                      summary:
                          '${result.totalElements} ${l10n.adminSystemLogs}',
                      onPageChanged:
                          (value) => setState(() {
                            _page = value;
                            _expandedId = null;
                          }),
                      onPageSizeChanged:
                          (value) => setState(() {
                            _size = value;
                            _page = 0;
                            _expandedId = null;
                          }),
                    ),
                  ],
                ),
          ),
        ),
      ],
    );
  }
}

class _SystemLogRow extends StatelessWidget {
  const _SystemLogRow({
    required this.entry,
    required this.expanded,
    required this.onTap,
  });

  final AdminSystemLogItem entry;
  final bool expanded;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final skin = DesktopSkin.of(context);
    final tone = switch (entry.level.toUpperCase()) {
      'ERROR' => DesktopPalette.bad,
      'WARN' => DesktopPalette.warn,
      'INFO' => skin.accent,
      _ => skin.text3,
    };
    return DesktopHover(
      builder:
          (context, hovered) => Container(
            decoration: BoxDecoration(
              color: hovered ? skin.raise2 : Colors.transparent,
              border: Border(bottom: BorderSide(color: skin.line)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                InkWell(
                  onTap: onTap,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: 10,
                      horizontal: 4,
                    ),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 150,
                          child: Text(
                            _systemLogTimestamp(entry.timestamp),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: DesktopType.numeric(skin.text3),
                          ),
                        ),
                        SizedBox(
                          width: 92,
                          child: AdminStatusTag(
                            label: entry.level,
                            tone: switch (entry.level.toUpperCase()) {
                              'ERROR' => AdminTagTone.error,
                              'WARN' => AdminTagTone.warning,
                              'INFO' => AdminTagTone.info,
                              _ => AdminTagTone.neutral,
                            },
                          ),
                        ),
                        SizedBox(
                          width: 190,
                          child: Text(
                            entry.source,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: DesktopType.caption(skin.text3),
                          ),
                        ),
                        Expanded(
                          child: Text(
                            entry.message,
                            maxLines: expanded ? 4 : 1,
                            overflow: TextOverflow.ellipsis,
                            style: DesktopType.body(skin.text),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Icon(
                          expanded ? Icons.expand_less : Icons.expand_more,
                          size: 17,
                          color: tone,
                        ),
                      ],
                    ),
                  ),
                ),
                AnimatedSize(
                  duration: MotionToken.reduced(context, MotionToken.fast),
                  curve: MotionToken.curve,
                  alignment: Alignment.topCenter,
                  child:
                      expanded
                          ? Container(
                            width: double.infinity,
                            padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                            child: SelectableText(
                              entry.message,
                              style: DesktopType.caption(skin.text2),
                            ),
                          )
                          : const SizedBox(width: double.infinity, height: 0),
                ),
              ],
            ),
          ),
    );
  }
}

String _systemLogTimestamp(String value) {
  final parsed = DateTime.tryParse(value)?.toLocal();
  if (parsed == null) return value;
  String pad(int part) => part.toString().padLeft(2, '0');
  return '${parsed.year}-${pad(parsed.month)}-${pad(parsed.day)} '
      '${pad(parsed.hour)}:${pad(parsed.minute)}:${pad(parsed.second)}';
}
