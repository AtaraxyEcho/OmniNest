import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/features/photos/application/photo_backup_albums.dart';
import 'package:omninest/features/photos/application/photo_backup_preferences.dart';

/// 备份开关统一交互流（桌面面板与移动设置页共用）。
///
/// 关闭直接生效；开启必须经二次确认弹窗选择范围（全部相册/自选相册），
/// 自选范围至少勾选一个相册，否则拦截提示且不开启。取消流程时开关
/// 由偏好驱动回弹。
Future<void> showPhotoBackupEnableFlow(
  BuildContext context,
  WidgetRef ref, {
  required bool enable,
}) async {
  if (!enable) {
    await ref.read(photoBackupPreferencesControllerProvider.notifier).disable();
    return;
  }
  final scope = await showDialog<PhotoBackupScope>(
    context: context,
    builder: (_) => const _BackupEnableConfirmDialog(),
  );
  if (scope == null || !context.mounted) {
    return;
  }
  if (scope == PhotoBackupScope.selected) {
    final current =
        ref.read(photoBackupPreferencesControllerProvider).asData?.value;
    final selected = await showDialog<Set<String>>(
      context: context,
      builder:
          (_) => _BackupAlbumPickerDialog(
            initialSelection: current?.selectedAlbumIds ?? const <String>{},
          ),
    );
    if (selected == null || !context.mounted) {
      return;
    }
    if (selected.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppLocalizations.of(context).photoBackupNeedSelectAlbum,
          ),
        ),
      );
      return;
    }
    await ref
        .read(photoBackupPreferencesControllerProvider.notifier)
        .enable(scope: scope, selectedAlbumIds: selected);
    return;
  }
  await ref
      .read(photoBackupPreferencesControllerProvider.notifier)
      .enable(scope: scope, selectedAlbumIds: const <String>{});
}

/// 开启前的二次确认：说明上传去向，并让用户选择全部或自选相册。
class _BackupEnableConfirmDialog extends StatefulWidget {
  const _BackupEnableConfirmDialog();

  @override
  State<_BackupEnableConfirmDialog> createState() =>
      _BackupEnableConfirmDialogState();
}

class _BackupEnableConfirmDialogState
    extends State<_BackupEnableConfirmDialog> {
  PhotoBackupScope _scope = PhotoBackupScope.all;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(l10n.photoBackupConfirmTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.photoBackupConfirmBody),
          RadioGroup<PhotoBackupScope>(
            groupValue: _scope,
            onChanged: (value) => setState(() => _scope = value!),
            child: Column(
              children: [
                RadioListTile<PhotoBackupScope>(
                  value: PhotoBackupScope.all,
                  title: Text(l10n.photoBackupScopeOptionAll),
                  contentPadding: EdgeInsets.zero,
                ),
                RadioListTile<PhotoBackupScope>(
                  value: PhotoBackupScope.selected,
                  title: Text(l10n.photoBackupScopeOptionSelected),
                  contentPadding: EdgeInsets.zero,
                ),
              ],
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.coreCancel),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_scope),
          child: Text(l10n.photoBackupConfirmEnable),
        ),
      ],
    );
  }
}

/// 自选相册选择器：多选相册，确认返回选中集合（空集由调用方拦截）。
class _BackupAlbumPickerDialog extends StatefulWidget {
  const _BackupAlbumPickerDialog({required this.initialSelection});

  final Set<String> initialSelection;

  @override
  State<_BackupAlbumPickerDialog> createState() =>
      _BackupAlbumPickerDialogState();
}

class _BackupAlbumPickerDialogState extends State<_BackupAlbumPickerDialog> {
  Set<String> _selected = const {};
  List<PhotoBackupAlbumOption>? _albums;
  String? _error;

  @override
  void initState() {
    super.initState();
    _selected = Set<String>.of(widget.initialSelection);
    _loadAlbums();
  }

  Future<void> _loadAlbums() async {
    try {
      final albums = await photoBackupAlbumLoader();
      if (!mounted) {
        return;
      }
      setState(() => _albums = albums);
    } on Exception catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _error = error.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final albums = _albums;
    return AlertDialog(
      title: Text(l10n.photoBackupAlbumPickerTitle),
      content: SizedBox(
        width: 360,
        child:
            _error != null
                ? Text(_error!)
                : albums == null
                ? const Center(child: CircularProgressIndicator())
                : albums.isEmpty
                ? Text(l10n.photoBackupAlbumPickerEmpty)
                : ListView(
                  shrinkWrap: true,
                  children: [
                    for (final album in albums)
                      CheckboxListTile(
                        value: _selected.contains(album.id),
                        onChanged: (checked) {
                          setState(() {
                            final next = Set<String>.of(_selected);
                            if (checked == true) {
                              next.add(album.id);
                            } else {
                              next.remove(album.id);
                            }
                            _selected = next;
                          });
                        },
                        title: Text(album.name),
                        subtitle: Text('${album.assetCount}'),
                        contentPadding: EdgeInsets.zero,
                      ),
                  ],
                ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.coreCancel),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_selected),
          child: Text(l10n.coreConfirm),
        ),
      ],
    );
  }
}
