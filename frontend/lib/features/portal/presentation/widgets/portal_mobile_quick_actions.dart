part of 'portal_mobile_shell.dart';

class _MobileQuickActions extends ConsumerWidget {
  const _MobileQuickActions();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final accent = scheme.primary;
    final canAccessAdmin = ref.watch(canAccessAdminConsoleProvider);
    final actions = [
      _MobileQuickAction(
        icon: Icons.menu_book_rounded,
        label: l10n.portalDockReading,
        route: '/reader',
      ),
      _MobileQuickAction(
        icon: Icons.movie_rounded,
        label: l10n.portalDockMovies,
        route: '/video',
      ),
      _MobileQuickAction(
        icon: Icons.music_note_rounded,
        label: l10n.portalDockMusic,
        route: '/music',
      ),
      _MobileQuickAction(
        icon: Icons.photo_library_rounded,
        label: l10n.portalDockPhotos,
        route: '/photos',
      ),
      _MobileQuickAction(
        icon: Icons.folder_rounded,
        label: l10n.portalDockFiles,
        route: '/files',
      ),
      if (canAccessAdmin)
        _MobileQuickAction(
          icon: Icons.admin_panel_settings_rounded,
          label: l10n.portalAdmin,
          route: '/admin',
        ),
    ];

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.bolt_rounded, size: 18, color: accent),
                const SizedBox(width: 8),
                Text(
                  l10n.portalQuickActions,
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              alignment: WrapAlignment.start,
              runAlignment: WrapAlignment.start,
              crossAxisAlignment: WrapCrossAlignment.start,
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final action in actions)
                  _MobileQuickActionChip(action: action, accent: accent),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _MobileQuickAction {
  const _MobileQuickAction({
    required this.icon,
    required this.label,
    required this.route,
  });

  final IconData icon;
  final String label;
  final String route;
}

class _MobileQuickActionChip extends StatelessWidget {
  const _MobileQuickActionChip({required this.action, required this.accent});

  final _MobileQuickAction action;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => context.go(action.route),
        child: Container(
          height: 38,
          constraints: const BoxConstraints(minWidth: 86),
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHigh.withValues(alpha: 0.74),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: scheme.outlineVariant.withValues(alpha: 0.42),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(action.icon, size: 16, color: accent),
              const SizedBox(width: 7),
              Text(
                action.label,
                style: TextStyle(
                  color: scheme.onSurface,
                  fontSize: AppTypography.bodySmall,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── 系统卡片（主题切换带渐进过渡）────────────────────────────────────────────
