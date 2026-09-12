part of 'file_browser_page.dart';

class _PageHeader extends StatelessWidget {
  const _PageHeader({
    required this.title,
    required this.subtitle,
    this.actions = const [],
  });

  final String title;
  final String subtitle;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final titleBlock = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                fontSize: AppTypography.headlineLarge,
                height: 40 / 32,
                color: context.filesColors.primary,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                fontSize: AppTypography.bodyLarge,
                height: 21 / 14,
                color: context.filesColors.onSurfaceVariant,
              ),
            ),
          ],
        );
        if (constraints.maxWidth < 780 || actions.isEmpty) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              titleBlock,
              if (actions.isNotEmpty) ...[
                const SizedBox(height: 14),
                Wrap(spacing: 10, runSpacing: 10, children: actions),
              ],
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: titleBlock),
            const SizedBox(width: 20),
            Wrap(spacing: 10, runSpacing: 10, children: actions),
          ],
        );
      },
    );
  }
}

ButtonStyle _fileHeaderActionButtonStyle() {
  return ButtonStyle(
    minimumSize: const WidgetStatePropertyAll(Size(132, 44)),
    padding: const WidgetStatePropertyAll(
      EdgeInsets.symmetric(horizontal: 18, vertical: 10),
    ),
    shape: WidgetStatePropertyAll(
      RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    ),
    textStyle: const WidgetStatePropertyAll(
      TextStyle(fontSize: AppTypography.bodyLarge, fontWeight: FontWeight.w700),
    ),
  );
}

class _FileActionStatusBar extends StatelessWidget {
  const _FileActionStatusBar({
    required this.error,
    required this.onDismissError,
  });

  final FileBrowserActionError error;
  final VoidCallback onDismissError;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.errorContainer.withValues(alpha: 0.22),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: theme.colorScheme.error.withValues(alpha: 0.32),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline_rounded, color: theme.colorScheme.error),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  error.operationLabel,
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 4),
                Text(
                  error.displayMessage,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: context.filesColors.onSurface,
                  ),
                ),
              ],
            ),
          ),
          TextButton.icon(
            onPressed: onDismissError,
            icon: const Icon(Icons.close_rounded, size: 18),
            label: Text(l10n.filesClose),
          ),
        ],
      ),
    );
  }
}

Future<void> _runFileAction(
  BuildContext context,
  Future<void> Function() action,
) async {
  final messenger = ScaffoldMessenger.of(context);
  await _runFileActionWithMessenger(messenger, action);
}

Future<void> _runFileActionWithMessenger(
  ScaffoldMessengerState messenger,
  Future<void> Function() action,
) async {
  try {
    await action();
  } catch (error) {
    final resolved = describeUserFacingError(error);
    if (!messenger.mounted) {
      return;
    }
    messenger.showSnackBar(
      SnackBar(
        content: Text('${resolved.title}：${resolved.displayMessage}'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}

Future<void> _confirmAndRun(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
  required Future<void> Function() action,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  final confirmed = await confirmDestructiveAction(
    context,
    title: title,
    message: message,
    confirmLabel: confirmLabel,
  );
  if (!confirmed) {
    return;
  }
  await _runFileActionWithMessenger(messenger, action);
}

Future<void> _downloadFile(
  BuildContext context,
  FileBrowserController controller,
  FileNode file,
) async {
  final messenger = ScaffoldMessenger.of(context);
  final l10n = AppLocalizations.of(context);
  try {
    final url = await controller.downloadUrl(file);
    if (!messenger.mounted) return;
    await Clipboard.setData(ClipboardData(text: url));
    messenger.showSnackBar(
      SnackBar(
        content: Text(l10n.filesDownloadLinkCopied),
        behavior: SnackBarBehavior.floating,
      ),
    );
  } catch (e) {
    if (!messenger.mounted) return;
    messenger.showSnackBar(
      SnackBar(
        content: Text('${l10n.filesDownloadFailed}: $e'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}

/// 复制文件到目标目录的对话框（与移动共用目录选择器）。
Future<void> _showCopyDialog({
  required BuildContext context,
  required FileBrowserController controller,
  required FileNode file,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  final l10n = AppLocalizations.of(context);
  final targetId = await showDialog<String>(
    context: context,
    builder: (ctx) => _FolderPickerDialog(excludeIds: {file.id}),
  );
  if (targetId == null || !messenger.mounted) return;
  await _runFileActionWithMessenger(messenger, () async {
    await controller.copyFile(file, targetId.isEmpty ? null : targetId);
    if (!messenger.mounted) return;
    messenger.showSnackBar(
      SnackBar(
        content: Text(l10n.filesCopiedFile(file.name)),
        behavior: SnackBarBehavior.floating,
      ),
    );
  });
}

Future<void> _showMoveDialog({
  required BuildContext context,
  required FileBrowserController controller,
  required FileNode file,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  final l10n = AppLocalizations.of(context);
  final targetId = await showDialog<String>(
    context: context,
    builder: (ctx) => _FolderPickerDialog(excludeIds: {file.id}),
  );
  if (targetId == null || !messenger.mounted) return;
  await _runFileActionWithMessenger(messenger, () async {
    await controller.moveFile(file, targetId);
    if (!messenger.mounted) return;
    messenger.showSnackBar(
      SnackBar(
        content: Text(l10n.filesMovedFile(file.name)),
        behavior: SnackBarBehavior.floating,
      ),
    );
  });
}

Future<void> _showBatchMoveDialog({
  required BuildContext context,
  required FileBrowserController controller,
  required int count,
  required Set<String> excludeIds,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  final l10n = AppLocalizations.of(context);
  final targetId = await showDialog<String>(
    context: context,
    builder: (ctx) => _FolderPickerDialog(excludeIds: excludeIds),
  );
  if (targetId == null || !messenger.mounted) return;
  await _runFileActionWithMessenger(messenger, () async {
    await controller.batchMoveFiles(targetId);
    if (!messenger.mounted) return;
    messenger.showSnackBar(
      SnackBar(
        content: Text(l10n.filesMovedCount(count)),
        behavior: SnackBarBehavior.floating,
      ),
    );
  });
}

class _FolderPickerDialog extends ConsumerStatefulWidget {
  const _FolderPickerDialog({this.excludeIds = const {}});
  final Set<String> excludeIds;

  @override
  ConsumerState<_FolderPickerDialog> createState() =>
      _FolderPickerDialogState();
}

class _FolderPickerDialogState extends ConsumerState<_FolderPickerDialog> {
  String? _currentParentId;
  final List<_FolderBreadcrumb> _breadcrumbs = [];
  List<FileNode> _folders = [];
  bool _loading = true;
  int _loadGeneration = 0;

  @override
  void initState() {
    super.initState();
    _loadFolders();
  }

  Future<void> _loadFolders() async {
    final generation = ++_loadGeneration;
    final parentId = _currentParentId;
    final repo = ref.read(fileRepositoryProvider);
    setState(() => _loading = true);
    try {
      final files = await repo.listFiles(parentId: parentId);
      if (!mounted || generation != _loadGeneration) {
        return;
      }
      setState(() {
        _folders = files.where((f) => f.isFolder).toList();
        _loading = false;
      });
    } catch (_) {
      if (!mounted || generation != _loadGeneration) {
        return;
      }
      setState(() {
        _folders = [];
        _loading = false;
      });
    }
  }

  @override
  void dispose() {
    _loadGeneration++;
    super.dispose();
  }

  void _enterFolder(FileNode folder) {
    setState(() {
      _breadcrumbs.add(_FolderBreadcrumb(id: folder.id, name: folder.name));
      _currentParentId = folder.id;
    });
    _loadFolders();
  }

  void _goToBreadcrumb(int index) {
    setState(() {
      if (index < 0) {
        _breadcrumbs.clear();
        _currentParentId = null;
      } else {
        _breadcrumbs.removeRange(index + 1, _breadcrumbs.length);
        _currentParentId = _breadcrumbs[index].id;
      }
    });
    _loadFolders();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final currentName =
        _breadcrumbs.isEmpty ? l10n.filesRootDirectory : _breadcrumbs.last.name;
    return AlertDialog(
      title: Text(l10n.filesSelectTargetFolder),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420, maxHeight: 380),
        child: SizedBox(
          width: 420,
          height: 380,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 面包屑导航
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    ActionChip(
                      label: Text(l10n.filesRootDirectory),
                      avatar: Icon(
                        Icons.home_outlined,
                        size: 16,
                        color:
                            _breadcrumbs.isEmpty
                                ? context.filesColors.primary
                                : null,
                      ),
                      onPressed: () => _goToBreadcrumb(-1),
                    ),
                    for (int i = 0; i < _breadcrumbs.length; i++) ...[
                      const Icon(Icons.chevron_right_rounded, size: 16),
                      ActionChip(
                        label: Text(_breadcrumbs[i].name),
                        onPressed: () => _goToBreadcrumb(i),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 8),
              // 文件夹列表
              Expanded(
                child:
                    _loading
                        ? const Center(child: CircularProgressIndicator())
                        : _folders.isEmpty
                        ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.folder_open_outlined,
                                size: 36,
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant
                                    .withValues(alpha: 0.5),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                l10n.filesFolderEmpty,
                                style: TextStyle(
                                  color:
                                      Theme.of(
                                        context,
                                      ).colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        )
                        : ListView.builder(
                          itemCount: _folders.length,
                          itemBuilder: (context, index) {
                            final folder = _folders[index];
                            final excluded = widget.excludeIds.contains(
                              folder.id,
                            );
                            return ListTile(
                              leading: Icon(
                                Icons.folder_rounded,
                                color:
                                    excluded
                                        ? Theme.of(context)
                                            .colorScheme
                                            .onSurfaceVariant
                                            .withValues(alpha: 0.3)
                                        : context.filesColors.tertiary,
                              ),
                              title: Text(
                                folder.name,
                                style: TextStyle(
                                  color:
                                      excluded
                                          ? Theme.of(context)
                                              .colorScheme
                                              .onSurfaceVariant
                                              .withValues(alpha: 0.4)
                                          : null,
                                ),
                              ),
                              trailing:
                                  excluded
                                      ? null
                                      : const Icon(Icons.chevron_right_rounded),
                              enabled: !excluded,
                              onTap:
                                  excluded ? null : () => _enterFolder(folder),
                            );
                          },
                        ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.filesCancel),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _currentParentId ?? ''),
          child: Text(l10n.filesMoveToFolder(currentName)),
        ),
      ],
    );
  }
}

class _FolderBreadcrumb {
  const _FolderBreadcrumb({required this.id, required this.name});
  final String id;
  final String name;
}

/// 拍照后直传入库。
Future<void> _pickPhotoFromCamera(
  BuildContext context,
  FileBrowserController controller,
) async {
  final messenger = ScaffoldMessenger.of(context);
  final failureText = AppLocalizations.of(context).filesUploadDone;
  try {
    final shot = await ImagePicker().pickImage(
      source: ImageSource.camera,
      maxWidth: 4096,
    );
    if (shot == null || !context.mounted) {
      return;
    }
    await _uploadFiles(context, controller, [shot]);
  } on PlatformException catch (error) {
    if (messenger.mounted) {
      messenger.showSnackBar(
        SnackBar(content: Text('$failureText: ${error.code}')),
      );
    }
  }
}

/// 录像后直传入库。
Future<void> _pickVideoFromCamera(
  BuildContext context,
  FileBrowserController controller,
) async {
  final messenger = ScaffoldMessenger.of(context);
  final failureText = AppLocalizations.of(context).filesUploadDone;
  try {
    final shot = await ImagePicker().pickVideo(source: ImageSource.camera);
    if (shot == null || !context.mounted) {
      return;
    }
    await _uploadFiles(context, controller, [shot]);
  } on PlatformException catch (error) {
    if (messenger.mounted) {
      messenger.showSnackBar(
        SnackBar(content: Text('$failureText: ${error.code}')),
      );
    }
  }
}

Future<void> _pickAndUploadFiles(
  BuildContext context,
  FileBrowserController controller,
) async {
  final files = await openFiles();
  if (files.isEmpty || !context.mounted) {
    return;
  }
  await _uploadFiles(context, controller, files);
}

Future<void> _uploadFiles(
  BuildContext context,
  FileBrowserController controller,
  List<XFile> files,
) async {
  final messenger = ScaffoldMessenger.of(context);
  final l10n = AppLocalizations.of(context);
  await _runFileActionWithMessenger(messenger, () async {
    final result = await controller.uploadFiles(files);
    if (!messenger.mounted) {
      return;
    }
    final message =
        result.completed == result.total
            ? l10n.filesUploadComplete(result.completed)
            : l10n.filesUploadBatchSummary(
              result.completed,
              result.conflicts,
              result.failed,
              result.paused,
            );
    messenger.showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  });
}

Future<void> _showNameDialog({
  required BuildContext context,
  required String title,
  required String actionLabel,
  required String labelText,
  required Future<void> Function(String name) onSubmit,
  String? hintText,
  String initialValue = '',
}) async {
  final messenger = ScaffoldMessenger.of(context);
  final textController = TextEditingController(text: initialValue);
  final result = await showDialog<String>(
    context: context,
    builder:
        (context) => StatefulBuilder(
          builder:
              (context, setDialogState) => AlertDialog(
                title: Text(title),
                content: TextField(
                  controller: textController,
                  autofocus: true,
                  minLines: hintText == null ? 1 : 2,
                  maxLines: hintText == null ? 1 : 3,
                  textInputAction: TextInputAction.done,
                  decoration: InputDecoration(
                    labelText: labelText,
                    hintText: hintText,
                  ),
                  onChanged: (_) => setDialogState(() {}),
                  onSubmitted: (value) {
                    if (value.trim().isNotEmpty) {
                      Navigator.of(context).pop(value);
                    }
                  },
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text(AppLocalizations.of(context).filesCancel),
                  ),
                  FilledButton(
                    onPressed:
                        textController.text.trim().isEmpty
                            ? null
                            : () =>
                                Navigator.of(context).pop(textController.text),
                    child: Text(actionLabel),
                  ),
                ],
              ),
        ),
  );
  textController.dispose();
  final value = result?.trim();
  if (value == null || value.isEmpty) {
    return;
  }
  await _runFileActionWithMessenger(messenger, () => onSubmit(value));
}

Future<void> _showExternalStorageDialog({
  required BuildContext context,
  required Future<void> Function({
    required String provider,
    required String displayName,
    required String encryptedCredentials,
  })
  onSubmit,
  ExternalStorageAccount? account,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  final result = await showDialog<
    ({String provider, String displayName, String credentialsJson})
  >(
    context: context,
    builder: (context) => ExternalStorageAccountDialog(account: account),
  );
  if (result != null) {
    await _runFileActionWithMessenger(
      messenger,
      () => onSubmit(
        provider: result.provider,
        displayName: result.displayName,
        encryptedCredentials: result.credentialsJson,
      ),
    );
  }
}
