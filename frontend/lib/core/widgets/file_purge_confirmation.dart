import 'package:flutter/material.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/core/errors/app_exception.dart';
import 'package:omninest/core/widgets/workstation_dialog.dart';

/// 统一执行永久删除确认，并在存在共享引用时提供级联二次确认。
Future<bool> confirmAndRunFilePurge(
  BuildContext context, {
  required String resourceName,
  required Future<void> Function(bool cascade) action,
}) async {
  final l10n = AppLocalizations.of(context);
  final confirmed = await _showConfirmation(
    context,
    title: l10n.filePurgeDeleteTitle,
    message: l10n.filePurgeDeleteMessage(resourceName),
    confirmLabel: l10n.coreDelete,
  );
  if (!confirmed || !context.mounted) {
    return false;
  }

  try {
    await action(false);
    return true;
  } on AppException catch (error) {
    if (!_isResourceInUse(error) || !context.mounted) {
      rethrow;
    }
    final impact = _PurgeImpact.fromException(error);
    final cascadeConfirmed = await _showConfirmation(
      context,
      title: l10n.filePurgeImpactTitle,
      message: l10n.filePurgeImpactMessage(
        impact.fileNodeCount,
        impact.referenceCount,
      ),
      confirmLabel: l10n.filePurgeCascadeDelete,
    );
    if (!cascadeConfirmed || !context.mounted) {
      return false;
    }
    await action(true);
    return true;
  }
}

Future<bool> _showConfirmation(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
}) async {
  final l10n = AppLocalizations.of(context);
  return await showWorkstationDialog<bool>(
        context: context,
        builder:
            (dialogContext) => AlertDialog(
              title: Text(title),
              content: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 460),
                child: Text(message),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext, false),
                  child: Text(l10n.coreCancel),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(dialogContext, true),
                  style: FilledButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.error,
                  ),
                  child: Text(confirmLabel),
                ),
              ],
            ),
      ) ??
      false;
}

bool _isResourceInUse(AppException error) {
  return error.code == '4006' || error.code == 'RESOURCE_IN_USE';
}

class _PurgeImpact {
  const _PurgeImpact({
    required this.fileNodeCount,
    required this.referenceCount,
  });

  factory _PurgeImpact.fromException(AppException error) {
    final responseDetails = error.details['details'];
    final details = responseDetails is Map ? responseDetails : error.details;
    final rawImpact = details['impact'];
    final impact = rawImpact is Map ? rawImpact : const <Object?, Object?>{};
    return _PurgeImpact(
      fileNodeCount: _asInt(impact['fileNodeCount'], fallback: 1),
      referenceCount: _asInt(impact['referenceCount'], fallback: 1),
    );
  }

  final int fileNodeCount;
  final int referenceCount;

  static int _asInt(Object? value, {required int fallback}) {
    if (value is num) {
      return value.toInt();
    }
    return int.tryParse(value?.toString() ?? '') ?? fallback;
  }
}
