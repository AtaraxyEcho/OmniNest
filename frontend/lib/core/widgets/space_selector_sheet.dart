import 'package:flutter/material.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/core/widgets/responsive_breakpoints.dart';
import 'package:omninest/core/widgets/workstation_dialog.dart';

/// 空间选择结果。
enum SpaceSelection { personal, shared }

/// 显示空间选择弹窗，桌面端用 Dialog，移动端用 BottomSheet。
///
/// 返回 [SpaceSelection]，取消返回 `null`。
/// [allowShared] 为 `false` 时直接返回 [SpaceSelection.personal]，不弹窗。
Future<SpaceSelection?> showSpaceSelectorSheet(
  BuildContext context, {
  bool allowShared = true,
}) async {
  if (!allowShared) {
    return SpaceSelection.personal;
  }

  final isCompact = ResponsiveBreakpoints.isCompact(
    MediaQuery.sizeOf(context).width,
  );

  if (isCompact) {
    return showModalBottomSheet<SpaceSelection>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _SpaceSelectorContent(),
    );
  }
  return showWorkstationDialog<SpaceSelection>(
    context: context,
    builder:
        (_) => Dialog(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: const _SpaceSelectorContent(),
          ),
        ),
  );
}

class _SpaceSelectorContent extends StatefulWidget {
  const _SpaceSelectorContent();

  @override
  State<_SpaceSelectorContent> createState() => _SpaceSelectorContentState();
}

class _SpaceSelectorContentState extends State<_SpaceSelectorContent> {
  SpaceSelection _selection = SpaceSelection.personal;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.importSpaceSelectorTitle,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              l10n.importSpaceSelectorDesc,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            _SpaceOption(
              title: l10n.importToPersonalSpace,
              subtitle: l10n.importPersonalSpaceDesc,
              icon: Icons.person_outline,
              selected: _selection == SpaceSelection.personal,
              onTap: () => setState(() => _selection = SpaceSelection.personal),
            ),
            const SizedBox(height: 8),
            _SpaceOption(
              title: l10n.importToSharedSpace,
              subtitle: l10n.importSharedSpaceDesc,
              icon: Icons.people_outline,
              selected: _selection == SpaceSelection.shared,
              onTap: () => setState(() => _selection = SpaceSelection.shared),
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(
                    MaterialLocalizations.of(context).cancelButtonLabel,
                  ),
                ),
                const SizedBox(width: 12),
                FilledButton(
                  onPressed: () => Navigator.pop(context, _selection),
                  child: Text(MaterialLocalizations.of(context).okButtonLabel),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SpaceOption extends StatelessWidget {
  const _SpaceOption({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? colorScheme.primary : colorScheme.outlineVariant,
            width: selected ? 2 : 1,
          ),
          color:
              selected
                  ? colorScheme.primaryContainer.withValues(alpha: 0.3)
                  : null,
        ),
        child: Row(
          children: [
            Icon(icon, size: 20, color: colorScheme.onSurfaceVariant),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            if (selected)
              Icon(Icons.check_circle, size: 20, color: colorScheme.primary),
          ],
        ),
      ),
    );
  }
}
