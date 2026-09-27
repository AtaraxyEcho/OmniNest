import 'dart:async';

import 'package:flutter/material.dart';
import 'package:omninest/features/search/search_ui.dart';
import 'package:go_router/go_router.dart';
import 'package:omninest/app/l10n/app_localizations.dart';

class QuickActionsWidget extends StatelessWidget {
  const QuickActionsWidget({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _ActionButton(
              icon: Icons.cloud_upload_outlined,
              label: l10n.portalQuickUpload,
              onTap: () => context.go('/files'),
            ),
            _ActionButton(
              icon: Icons.download_for_offline_outlined,
              label: l10n.portalQuickDownload,
              onTap: () => context.go('/files'),
            ),
            _ActionButton(
              icon: Icons.create_new_folder_outlined,
              label: l10n.portalQuickNew,
              onTap: () => context.go('/files'),
            ),
            _ActionButton(
              icon: Icons.search_rounded,
              label: l10n.portalQuickSearch,
              onTap: () => unawaited(showGlobalSearchDialog(context)),
            ),
          ],
        ),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 24, color: theme.colorScheme.primary),
            const SizedBox(height: 4),
            Text(label, style: theme.textTheme.labelSmall),
          ],
        ),
      ),
    );
  }
}
