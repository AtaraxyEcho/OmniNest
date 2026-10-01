part of 'file_browser_page.dart';

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
        borderRadius: BorderRadius.zero,
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
                  filesOperationLabel(l10n, error.operation),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 4),
                // 服务端错误链可能极长（嵌套异常全文），无行数上限会把
                // 壳层主 Column 撑到数千像素高并溢出；封顶截断展示。
                Text(
                  error.displayMessage,
                  maxLines: 6,
                  overflow: TextOverflow.ellipsis,
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

Future<bool> _runFileAction(
  BuildContext context,
  Future<void> Function() action,
) async {
  try {
    await action();
    return true;
  } catch (error) {
    if (!context.mounted) {
      return false;
    }
    final resolved = describeUserFacingError(
      error,
      l10n: AppLocalizations.of(context),
    );
    showOmniFeedback(
      context,
      '${resolved.title}：${resolved.displayMessage}',
      severity: OmniFeedbackSeverity.error,
    );
    return false;
  }
}

Future<void> _confirmAndRun(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
  required Future<void> Function() action,
}) async {
  final confirmed = await showFilesConfirmDialog(
    context,
    title: title,
    message: message,
    confirmLabel: confirmLabel,
  );
  if (!confirmed || !context.mounted) {
    return;
  }
  await _runFileAction(context, action);
}

/// 高危破坏性确认（粉碎等不可逆操作）：键入实体短语后才能执行。
Future<void> _confirmTypedAndRun(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmPhrase,
  required String confirmLabel,
  required Future<void> Function() action,
}) async {
  final confirmed = await showFilesDestructiveConfirm(
    context,
    title: title,
    message: message,
    confirmPhrase: confirmPhrase,
    confirmLabel: confirmLabel,
  );
  if (!confirmed || !context.mounted) {
    return;
  }
  await _runFileAction(context, action);
}

Future<void> _downloadFile(
  BuildContext context,
  FileBrowserController controller,
  FileNode file,
) async {
  final l10n = AppLocalizations.of(context);
  try {
    final url = await controller.downloadUrl(file);
    if (!context.mounted) return;
    // Web 直接开新标签下载；桌面与移动无浏览器上下文时退回复制链接。
    if (openDownloadUrl(url)) {
      if (!context.mounted) return;
      showOmniFeedback(context, l10n.filesDownloadOpened);
      return;
    }
    final copied = await copyTextToClipboard(url);
    if (!context.mounted) return;
    showOmniFeedback(
      context,
      copied ? l10n.filesDownloadLinkCopied : l10n.clipboardCopyFailed,
      severity: OmniFeedbackSeverity.error,
    );
  } catch (e) {
    if (!context.mounted) return;
    showOmniFeedback(
      context,
      '${l10n.filesDownloadFailed}: $e',
      severity: OmniFeedbackSeverity.error,
    );
  }
}

/// 复制文件到目标目录的对话框（与移动共用目录选择器）。
Future<void> _showCopyDialog({
  required BuildContext context,
  required FileBrowserController controller,
  required FileNode file,
}) async {
  final l10n = AppLocalizations.of(context);
  final targetId = await showFilesDialog<String>(
    context: context,
    builder: (ctx) => _FolderPickerDialog(excludeIds: {file.id}),
  );
  if (targetId == null || !context.mounted) return;
  await _runFileAction(context, () async {
    await controller.copyFile(file, targetId.isEmpty ? null : targetId);
    if (!context.mounted) return;
    showOmniFeedback(
      context,
      l10n.filesCopiedFile(file.name),
      severity: OmniFeedbackSeverity.success,
    );
  });
}

Future<void> _showMoveDialog({
  required BuildContext context,
  required FileBrowserController controller,
  required FileNode file,
}) async {
  final l10n = AppLocalizations.of(context);
  final targetId = await showFilesDialog<String>(
    context: context,
    builder: (ctx) => _FolderPickerDialog(excludeIds: {file.id}),
  );
  if (targetId == null || !context.mounted) return;
  await _runFileAction(context, () async {
    await controller.moveFile(file, targetId);
    if (!context.mounted) return;
    showOmniFeedback(
      context,
      l10n.filesMovedFile(file.name),
      severity: OmniFeedbackSeverity.success,
    );
  });
}

/// 文件版本历史对话框：列表 + 恢复。
Future<void> _showVersionsDialog({
  required BuildContext context,
  required FileBrowserController controller,
  required FileNode file,
}) async {
  final l10n = AppLocalizations.of(context);
  await showFilesDialog<void>(
    context: context,
    builder: (ctx) {
      return FilesDialogFrame(
        title: l10n.filesVersionsTitle,
        headerLabel: file.isFolder ? 'FOLDER' : file.nodeType,
        body: SizedBox(
          width: 420,
          height: 360,
          child: FutureBuilder<List<FileVersion>>(
            future: controller.listFileVersions(file.id),
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              }
              final versions = snapshot.data ?? const <FileVersion>[];
              if (versions.isEmpty) {
                return Center(child: Text(l10n.filesVersionsEmpty));
              }
              return ListView.builder(
                itemCount: versions.length,
                itemBuilder: (context, index) {
                  final version = versions[index];
                  final subtitle = [
                    if (version.createdAt != null)
                      version.createdAt!.toIso8601String().substring(0, 19),
                    if (version.remark != null && version.remark!.isNotEmpty)
                      version.remark!,
                  ].join(' · ');
                  return ListTile(
                    title: Text(
                      version.isCurrent
                          ? '#${version.versionNo} · ${l10n.filesVersionsCurrent}'
                          : '#${version.versionNo} · ${version.changeType}',
                    ),
                    subtitle: Text(subtitle),
                    trailing:
                        version.isCurrent || version.id.isEmpty
                            ? null
                            : TextButton(
                              onPressed: () async {
                                final navigator = Navigator.of(ctx);
                                final ok = await _runFileAction(
                                  context,
                                  () async {
                                    await controller.restoreFileVersion(
                                      file,
                                      version.id,
                                    );
                                  },
                                );
                                if (!ok) {
                                  return;
                                }
                                if (context.mounted) {
                                  showOmniFeedback(
                                    context,
                                    l10n.filesVersionsRestored,
                                    severity: OmniFeedbackSeverity.success,
                                  );
                                }
                                if (navigator.canPop()) {
                                  navigator.pop();
                                }
                              },
                              child: Text(l10n.filesVersionsRestore),
                            ),
                  );
                },
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () async {
              final navigator = Navigator.of(ctx);
              // file_selector 的 XFile 在 Web 下没有 path 但可流式读取，与常规
              // 上传走同一条链路；FilePicker 取 path 在 Web 会静默失败。
              final picked = await openFile();
              if (picked == null || !context.mounted) {
                return;
              }
              final ok = await _runFileAction(context, () async {
                await controller.replaceFileWithNewVersion(file, picked);
              });
              if (!ok) {
                return;
              }
              if (context.mounted) {
                showOmniFeedback(context, l10n.filesOpSaveVersion);
              }
              if (navigator.canPop()) {
                navigator.pop();
              }
            },
            child: Text(l10n.filesOpSaveVersion),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(MaterialLocalizations.of(ctx).okButtonLabel),
          ),
        ],
      );
    },
  );
}

Future<void> _showBatchMoveDialog({
  required BuildContext context,
  required FileBrowserController controller,
  required int count,
  required Set<String> excludeIds,
}) async {
  final l10n = AppLocalizations.of(context);
  final targetId = await showFilesDialog<String>(
    context: context,
    builder: (ctx) => _FolderPickerDialog(excludeIds: excludeIds),
  );
  if (targetId == null || !context.mounted) return;
  await _runFileAction(context, () async {
    await controller.batchMoveFiles(targetId);
    if (!context.mounted) return;
    showOmniFeedback(
      context,
      l10n.filesMovedCount(count),
      severity: OmniFeedbackSeverity.success,
    );
  });
}

/// 拍照后直传入库。
Future<void> _pickPhotoFromCamera(
  BuildContext context,
  FileBrowserController controller,
) async {
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
    if (context.mounted) {
      showOmniFeedback(
        context,
        '$failureText: ${error.code}',
        severity: OmniFeedbackSeverity.error,
      );
    }
  }
}

/// 录像后直传入库。
Future<void> _pickVideoFromCamera(
  BuildContext context,
  FileBrowserController controller,
) async {
  final failureText = AppLocalizations.of(context).filesUploadDone;
  try {
    final shot = await ImagePicker().pickVideo(source: ImageSource.camera);
    if (shot == null || !context.mounted) {
      return;
    }
    await _uploadFiles(context, controller, [shot]);
  } on PlatformException catch (error) {
    if (context.mounted) {
      showOmniFeedback(
        context,
        '$failureText: ${error.code}',
        severity: OmniFeedbackSeverity.error,
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
  final l10n = AppLocalizations.of(context);
  await _runFileAction(context, () async {
    final result = await controller.uploadFiles(files);
    if (!context.mounted) {
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
    showOmniFeedback(context, message);
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
  final result = await showFilesDialog<String>(
    context: context,
    builder:
        (context) => _NameDialogFrame(
          title: title,
          actionLabel: actionLabel,
          labelText: labelText,
          hintText: hintText,
          initialValue: initialValue,
        ),
  );
  final value = result?.trim();
  if (value == null || value.isEmpty || !context.mounted) {
    return;
  }
  await _runFileAction(context, () => onSubmit(value));
}

/// 命名对话框（重命名/新建文件夹/离线下载等共用）。
///
/// 输入控制器由弹窗组件自持：showFilesDialog 的 Future 在 pop 调用瞬间
/// 完成，而路由退场动画期间组件仍在树上，此时外部 dispose 控制器会触发
/// “TextEditingController was used after being disposed”并级联污染路由
/// 卸载（Overlay _dependents 断言、ErrorWidget 铺满全屏）。随 State 生命周期
/// dispose 则自然落在动画结束、组件真正卸载之后。
class _NameDialogFrame extends StatefulWidget {
  const _NameDialogFrame({
    required this.title,
    required this.actionLabel,
    required this.labelText,
    this.hintText,
    this.initialValue = '',
  });

  final String title;
  final String actionLabel;
  final String labelText;
  final String? hintText;
  final String initialValue;

  @override
  State<_NameDialogFrame> createState() => _NameDialogFrameState();
}

class _NameDialogFrameState extends State<_NameDialogFrame> {
  late final TextEditingController _textController;

  @override
  void initState() {
    super.initState();
    _textController = TextEditingController(text: widget.initialValue);
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FilesDialogFrame(
      title: widget.title,
      body: TextField(
        controller: _textController,
        autofocus: true,
        minLines: widget.hintText == null ? 1 : 2,
        maxLines: widget.hintText == null ? 1 : 3,
        textInputAction: TextInputAction.done,
        decoration: filesWorkstationInputDecoration(
          context,
          hintText: widget.hintText ?? widget.labelText,
          prefixIcon: Icons.edit_outlined,
        ),
        onChanged: (_) => setState(() {}),
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
              _textController.text.trim().isEmpty
                  ? null
                  : () => Navigator.of(context).pop(_textController.text),
          child: Text(widget.actionLabel),
        ),
      ],
    );
  }
}

Future<ExternalStorageAccount?> _showExternalStorageDialog({
  required BuildContext context,
  required Future<ExternalStorageAccount> Function({
    required String provider,
    required String displayName,
    required String encryptedCredentials,
  })
  onSubmit,
  ExternalStorageAccount? account,
  required WidgetRef ref,
}) async {
  List<ExternalStorageConnector> connectors = const [];
  if (account == null) {
    try {
      final controller = ref.read(fileBrowserControllerProvider.notifier);
      connectors = await controller.listExternalConnectors().timeout(
        const Duration(seconds: 10),
      );
    } on Exception {
      connectors = const [];
    }
  }
  if (!context.mounted) {
    return null;
  }
  final result = await showFilesDialog<
    ({String provider, String displayName, String credentialsJson})
  >(
    context: context,
    builder:
        (context) => ExternalStorageAccountDialog(
          account: account,
          connectors: connectors,
        ),
  );
  if (result == null || !context.mounted) {
    return null;
  }
  ExternalStorageAccount? submitted;
  final ok = await _runFileAction(context, () async {
    submitted = await onSubmit(
      provider: result.provider,
      displayName: result.displayName,
      encryptedCredentials: result.credentialsJson,
    );
  });
  if (!ok) {
    return null;
  }
  return submitted;
}
