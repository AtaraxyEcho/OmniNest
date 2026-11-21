import 'package:material_ui/material_ui.dart';
import 'package:omninest/app/desktop/widgets/desktop_dialogs.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/desktop/desktop_skin.dart';
import 'package:omninest/core/widgets/mobile_shell_scope.dart';
import 'package:omninest/core/widgets/workstation_dialog.dart';

Future<bool> confirmDestructiveAction(
  BuildContext context, {
  required String title,
  required String message,
  String? confirmLabel,
}) async {
  final l10n = AppLocalizations.of(context);
  if (!MobileShellScope.isHosted(context) &&
      Theme.of(context).extension<DesktopSkin>() != null) {
    return showDesktopConfirm(
      context,
      title: title,
      message: message,
      confirmLabel: confirmLabel ?? l10n.coreConfirm,
      cancelLabel: l10n.coreCancel,
      destructive: true,
    );
  }
  final result = await showWorkstationDialog<bool>(
    context: context,
    builder:
        (context) => AlertDialog(
          title: Text(title),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(l10n.coreCancel),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.error,
                foregroundColor: Theme.of(context).colorScheme.onError,
              ),
              child: Text(confirmLabel ?? l10n.coreConfirm),
            ),
          ],
        ),
  );
  return result == true;
}
