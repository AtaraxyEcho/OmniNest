import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/features/photos/application/photo_backup_albums.dart';
import 'package:omninest/features/photos/application/photo_backup_preferences.dart';

/// 备份开关统一交互流（桌面面板与移动设置页共用）。
///
/// 关闭直接生效；开启弹单个确认弹窗：上传去向 + 范围选择 + 网络策略
/// （全部相册 / 自选相册，自选时内联展开相册清单；「无 Wi-Fi 时也使用
/// 移动数据」默认不勾选）。「开启」在自选范围为空时置灰。
Future<void> showPhotoBackupEnableFlow(
  BuildContext context,
  WidgetRef ref, {
  required bool enable,
}) async {
  if (!enable) {
    await ref.read(photoBackupPreferencesControllerProvider.notifier).disable();
    return;
  }
  final current =
      ref.read(photoBackupPreferencesControllerProvider).asData?.value;
  final decision = await showDialog<_BackupEnableDecision>(
    context: context,
    builder:
        (_) => _BackupEnableDialog(
          initialScope: current?.scope ?? PhotoBackupScope.all,
          initialSelection: current?.selectedAlbumIds ?? const <String>{},
          initialAllowMobileData:
              current?.networkPolicy == PhotoBackupNetworkPolicy.any,
        ),
  );
  if (decision == null) {
    return;
  }
  await ref
      .read(photoBackupPreferencesControllerProvider.notifier)
      .enable(
        scope: decision.scope,
        selectedAlbumIds: decision.albumIds,
        networkPolicy:
            decision.allowMobileData
                ? PhotoBackupNetworkPolicy.any
                : PhotoBackupNetworkPolicy.wifiOnly,
      );
}

/// 弹窗确认结果。
class _BackupEnableDecision {
  const _BackupEnableDecision({
    required this.scope,
    required this.albumIds,
    required this.allowMobileData,
  });

  final PhotoBackupScope scope;
  final Set<String> albumIds;
  final bool allowMobileData;
}

/// 开启确认弹窗：范围单选 + 自选时内联相册清单 + 网络策略勾选。
class _BackupEnableDialog extends StatefulWidget {
  const _BackupEnableDialog({
    required this.initialScope,
    required this.initialSelection,
    required this.initialAllowMobileData,
  });

  final PhotoBackupScope initialScope;
  final Set<String> initialSelection;
  final bool initialAllowMobileData;

  @override
  State<_BackupEnableDialog> createState() => _BackupEnableDialogState();
}

class _BackupEnableDialogState extends State<_BackupEnableDialog> {
  late PhotoBackupScope _scope = widget.initialScope;
  late Set<String> _selected = Set<String>.of(widget.initialSelection);
  late bool _allowMobileData = widget.initialAllowMobileData;
  List<PhotoBackupAlbumOption>? _albums;
  String? _albumsError;
  bool _albumsRequested = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final canEnable = _scope == PhotoBackupScope.all || _selected.isNotEmpty;
    return AlertDialog(
      title: Text(l10n.photoBackupConfirmTitle),
      content: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _scope == PhotoBackupScope.all
                  ? l10n.photoBackupConfirmBody
                  : l10n.photoBackupConfirmBodyScoped,
            ),
            RadioGroup<PhotoBackupScope>(
              groupValue: _scope,
              onChanged: (value) {
                setState(() => _scope = value!);
                // 首次切到自选才拉相册清单：选「全部」的用户不必提前
                // 触发系统相册权限弹窗（运行时备份仍会按需请求）。
                if (_scope == PhotoBackupScope.selected && !_albumsRequested) {
                  _albumsRequested = true;
                  _loadAlbums();
                }
              },
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
            if (_scope == PhotoBackupScope.selected)
              Flexible(child: _buildAlbumSection(l10n)),
            CheckboxListTile(
              value: _allowMobileData,
              onChanged:
                  (checked) =>
                      setState(() => _allowMobileData = checked ?? false),
              title: Text(l10n.photoBackupAllowMobileData),
              subtitle: Text(l10n.photoBackupAllowMobileDataHint),
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              dense: true,
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
          onPressed:
              canEnable
                  ? () => Navigator.of(context).pop(
                    _BackupEnableDecision(
                      scope: _scope,
                      albumIds: _selected,
                      allowMobileData: _allowMobileData,
                    ),
                  )
                  : null,
          child: Text(l10n.photoBackupConfirmEnable),
        ),
      ],
    );
  }

  Widget _buildAlbumSection(AppLocalizations l10n) {
    if (_albumsError != null) {
      return Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Text(_albumsError!),
      );
    }
    final albums = _albums;
    if (albums == null) {
      return const Padding(
        padding: EdgeInsets.only(top: 16),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (albums.isEmpty) {
      return Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Text(l10n.photoBackupAlbumPickerEmpty),
      );
    }
    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 264),
      child: ListView(
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
    );
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
      setState(() => _albumsError = error.toString());
    }
  }
}
