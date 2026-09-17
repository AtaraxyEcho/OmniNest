import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/app_typography.dart';
import 'package:omninest/app/theme/global_theme_colors.dart';
import 'package:omninest/core/widgets/user_avatar_menu.dart';
import 'package:omninest/features/tasks/application/task_controller.dart';
import 'package:omninest/features/tasks/presentation/widgets/task_card.dart';

class TasksPage extends ConsumerStatefulWidget {
  const TasksPage({this.embedded = false, super.key});

  final bool embedded;

  @override
  ConsumerState<TasksPage> createState() => _TasksPageState();
}

class _TasksPageState extends ConsumerState<TasksPage> {
  final _scrollController = ScrollController();
  String _statusFilter = 'ALL';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      ref.read(taskListProvider.notifier).load();
    });
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!mounted || !_scrollController.hasClients) {
      return;
    }
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      ref.read(taskListProvider.notifier).loadMore();
    }
  }

  @override
  Widget build(BuildContext context) {
    final tasks = ref.watch(taskListProvider);
    final filtered =
        _statusFilter == 'ALL'
            ? tasks
            : tasks.where((t) => t.status == _statusFilter).toList();
    final colors = context.globalColors;
    final content = Column(
      children: [
        _StatusFilterBar(
          selected: _statusFilter,
          onSelected: (value) => setState(() => _statusFilter = value),
        ),
        Expanded(
          child:
              filtered.isEmpty
                  ? const _EmptyState()
                  : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: filtered.length,
                    itemBuilder:
                        (context, index) => TaskCard(
                          task: filtered[index],
                          onRetry:
                              filtered[index].canRetry
                                  ? () => ref
                                      .read(taskListProvider.notifier)
                                      .retry(filtered[index].id)
                                  : null,
                        ),
                  ),
        ),
      ],
    );
    if (widget.embedded) {
      return ColoredBox(color: colors.surfaceContainerLowest, child: content);
    }
    return Scaffold(
      backgroundColor: colors.surfaceContainerLowest,
      appBar: AppBar(
        backgroundColor: colors.surface.withValues(alpha: 0.86),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => context.go('/portal'),
        ),
        title: Text(
          AppLocalizations.of(context).tasksTitle,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        actions: const [UserAvatarMenu(), SizedBox(width: 8)],
      ),
      body: content,
    );
  }
}

class _StatusFilterBar extends StatelessWidget {
  const _StatusFilterBar({required this.selected, required this.onSelected});

  final String selected;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final filters = [
      ('ALL', l10n.tasksFilterAll),
      ('PENDING', l10n.tasksFilterPending),
      ('RUNNING', l10n.tasksFilterRunning),
      ('COMPLETED', l10n.tasksFilterCompleted),
      ('FAILED', l10n.tasksFilterFailed),
    ];
    final colors = context.globalColors;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          for (final (value, label) in filters)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Text(label),
                selected: selected == value,
                onSelected: (_) => onSelected(value),
                selectedColor: colors.primaryContainer,
                labelStyle: TextStyle(
                  fontSize: AppTypography.bodyMedium,
                  fontWeight:
                      selected == value ? FontWeight.w700 : FontWeight.w500,
                  color:
                      selected == value
                          ? colors.onPrimaryContainer
                          : colors.onSurfaceVariant,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final colors = context.globalColors;
    final l10n = AppLocalizations.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.task_alt_rounded,
            size: 64,
            color: colors.onSurfaceVariant.withValues(alpha: 0.3),
          ),
          const SizedBox(height: 16),
          Text(
            l10n.tasksEmpty,
            style: TextStyle(
              fontSize: AppTypography.titleMedium,
              fontWeight: FontWeight.w600,
              color: colors.onSurfaceVariant.withValues(alpha: 0.5),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            l10n.tasksEmptyHint,
            style: TextStyle(
              fontSize: AppTypography.bodyMedium,
              color: colors.onSurfaceVariant.withValues(alpha: 0.4),
            ),
          ),
        ],
      ),
    );
  }
}
