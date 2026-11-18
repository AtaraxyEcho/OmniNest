part of 'admin_list_components.dart';

/// 分页条、列表分区骨架、空态与骨架屏。

/// 列表分区骨架：无卡片容器的标准列表分区。
///
/// 结构为标题行（标题 + 副标题 + 操作区）、可选筛选行与内容区（表格 +
/// 分页由调用方传入）。列表页统一使用本骨架，禁止卡片套列表。
class AdminTableSection extends StatelessWidget {
  const AdminTableSection({
    required this.title,
    required this.children,
    this.subtitle,
    this.trailing = const <Widget>[],
    this.filters = const <Widget>[],
    super.key,
  });

  final String title;
  final String? subtitle;
  final List<Widget> trailing;
  final List<Widget> filters;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    // 桌面统一壳：同一份列表分区在桌面收进样例卡片，标题、说明、
    // 右侧动作与筛选 chips 保持同一套排布，只是换掉外层容器。
    if (DesktopShellScope.isHosted(context)) {
      return AdminCard(
        title: title,
        subtitle: subtitle,
        action:
            trailing.isEmpty
                ? null
                : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final action in trailing) ...[
                      action,
                      if (action != trailing.last) const SizedBox(width: 8),
                    ],
                  ],
                ),
        childGap: 12,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (filters.isNotEmpty) ...[
              Wrap(spacing: 6, runSpacing: 6, children: filters),
              const SizedBox(height: 12),
            ],
            ...children,
          ],
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (subtitle != null)
                    Text(
                      subtitle!,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
            ),
            if (trailing.isNotEmpty)
              Wrap(
                spacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: trailing,
              ),
          ],
        ),
        if (filters.isNotEmpty) ...[
          const SizedBox(height: 12),
          Wrap(spacing: 8, runSpacing: 8, children: filters),
        ],
        const SizedBox(height: 12),
        ...children,
      ],
    );
  }
}

/// 列表空态：左对齐行式提示（符合 admin 页面布局惯例）。
class AdminListEmptyState extends StatelessWidget {
  const AdminListEmptyState({
    required this.message,
    this.actionLabel,
    this.onAction,
    super.key,
  });

  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Row(
        children: [
          Icon(
            Icons.inbox_outlined,
            size: 18,
            color: Theme.of(context).colorScheme.outline,
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(message, style: Theme.of(context).textTheme.bodyMedium),
          ),
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(width: 12),
            TextButton(onPressed: onAction, child: Text(actionLabel!)),
          ],
        ],
      ),
    );
  }
}

/// 桌面列表加载时保留表格节奏；移动端继续使用轻量加载指示。
class AdminListSkeleton extends StatelessWidget {
  const AdminListSkeleton({this.rows = 8, super.key});

  final int rows;

  @override
  Widget build(BuildContext context) {
    if (DesktopShellScope.isHosted(context)) {
      return DesktopSkeletonRows(count: rows);
    }
    return const Center(
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: 48),
        child: SizedBox.square(
          dimension: 28,
          child: CircularProgressIndicator(strokeWidth: 2.5),
        ),
      ),
    );
  }
}
