import 'package:flutter/material.dart';
import 'package:omninest/app/l10n/app_localizations.dart';

class AppErrorView extends StatelessWidget {
  const AppErrorView({
    required this.message,
    this.onRetry,
    this.onBack,
    super.key,
  });

  final String message;
  final VoidCallback? onRetry;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(message),
          if (onRetry != null || onBack != null) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              alignment: WrapAlignment.center,
              children: [
                if (onBack != null)
                  OutlinedButton(onPressed: onBack, child: Text(l10n.coreBack)),
                if (onRetry != null)
                  FilledButton(onPressed: onRetry, child: Text(l10n.coreRetry)),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
