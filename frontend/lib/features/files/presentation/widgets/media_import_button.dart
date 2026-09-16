import 'dart:async';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/providers.dart';
import 'package:omninest/core/errors/error_message.dart';
import 'package:omninest/core/widgets/responsive_breakpoints.dart';
import 'package:omninest/core/widgets/space_selector_sheet.dart';
import 'package:omninest/features/files/application/media_import_file_picker.dart';
import 'package:omninest/features/files/application/media_import_service.dart';

/// 导入按钮样式。
enum ImportButtonStyle { textButton, iconButton }

/// 媒体导入使用的文件选择函数。
typedef MediaImportFilePicker =
    Future<List<XFile>> Function(List<XTypeGroup> acceptedTypeGroups);

/// 提供可替换的文件选择入口，便于隔离原生选择器并覆盖测试场景。
final mediaImportFilePickerProvider = Provider<MediaImportFilePicker>((ref) {
  return pickMediaImportFiles;
});

/// 可复用的媒体导入按钮。
///
/// 默认流程：文件选择 → 空间选择 → 目录解析 → 上传 → 完成回调。
/// 提供 [onFilesPicked] 时改为后台队列模式：选择后立即返回，不阻塞当前页。
class MediaImportButton extends ConsumerStatefulWidget {
  const MediaImportButton({
    required this.subsystemDirectory,
    required this.onImportComplete,
    this.onImportCompleteWithResult,
    this.allowSharedSpace = true,
    this.style = ImportButtonStyle.textButton,
    this.color,
    this.acceptedExtensions = const <String>[],
    this.unsupportedExtensions = const <String>[],
    this.reuseExistingFiles = false,
    this.enableCamera = false,
    this.onFilesPicked,
    super.key,
  });

  /// 子系统目录名称（如 'Movies'、'Music'）。
  final String subsystemDirectory;

  /// 导入完成后的刷新回调。
  final FutureOr<void> Function() onImportComplete;

  /// 需要导入文件 ID 的业务模块可使用的详细完成回调。
  final FutureOr<MediaImportCompletionState?> Function(
    MediaImportBatchResult result,
  )?
  onImportCompleteWithResult;

  /// 是否允许导入到共享空间。
  final bool allowSharedSpace;

  /// 按钮样式。
  final ImportButtonStyle style;

  /// 图标颜色，不传则使用主题默认。
  final Color? color;

  /// 允许选择的扩展名。空列表表示由系统展示全部文件。
  final List<String> acceptedExtensions;

  /// 选择器可展示但当前业务明确拒绝的扩展名，拒绝时给出格式反馈。
  final List<String> unsupportedExtensions;

  /// 是否允许复用目标目录或回收站中的同名同大小文件。
  final bool reuseExistingFiles;

  /// 移动端是否提供「拍摄上传」入口。
  final bool enableCamera;

  /// 选择文件后交给外部队列处理，不弹模态进度窗口。
  ///
  /// 设置后跳过空间选择与阻塞式上传对话框；上传、扫描与入库由调用方异步完成。
  final void Function(List<XFile> files)? onFilesPicked;

  @override
  ConsumerState<MediaImportButton> createState() => _MediaImportButtonState();
}

class _MediaImportButtonState extends ConsumerState<MediaImportButton> {
  bool _busy = false;
  bool _routeClosing = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return switch (widget.style) {
      ImportButtonStyle.textButton => TextButton.icon(
        onPressed: _busy ? null : _handleImport,
        icon: _ImportButtonIcon(busy: _busy, color: widget.color, size: 18),
        label: Text(l10n.importFiles),
      ),
      ImportButtonStyle.iconButton => IconButton(
        onPressed: _busy ? null : _handleImport,
        icon: _ImportButtonIcon(busy: _busy, color: widget.color, size: 20),
        tooltip: l10n.importFiles,
      ),
    };
  }

  Future<void> _handleImport() async {
    if (_busy) return;
    setState(() => _busy = true);
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final files = await _pickImportFiles(l10n);
      if (files.isEmpty || !mounted) return;

      final unsupportedFiles = _unsupportedFiles(files);
      if (unsupportedFiles.isNotEmpty) {
        if (!mounted || !messenger.mounted) return;
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              l10n.importUnsupportedFormat(
                _unsupportedFileNames(unsupportedFiles),
                _supportedExtensionNames(),
              ),
            ),
          ),
        );
        return;
      }

      final onFilesPicked = widget.onFilesPicked;
      if (onFilesPicked != null) {
        onFilesPicked(files);
        return;
      }

      final spaceSelection = await showSpaceSelectorSheet(
        context,
        allowShared: widget.allowSharedSpace,
      );
      if (spaceSelection == null || !mounted) return;

      final spaceType =
          spaceSelection == SpaceSelection.shared ? 'SHARED' : 'PERSONAL';
      final importService = ref.read(mediaImportServiceProvider);
      final isCompact = ResponsiveBreakpoints.isCompact(
        MediaQuery.sizeOf(context).width,
      );

      if (isCompact) {
        await _showProgressSheet(
          context,
          importService: importService,
          files: files,
          spaceType: spaceType,
          l10n: l10n,
          messenger: messenger,
        );
      } else {
        await _showProgressDialog(
          context,
          importService: importService,
          files: files,
          spaceType: spaceType,
          l10n: l10n,
          messenger: messenger,
        );
      }
    } on Object {
      if (mounted && messenger.mounted) {
        messenger.showSnackBar(SnackBar(content: Text(l10n.importFailed)));
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<List<XFile>> _pickImportFiles(AppLocalizations l10n) async {
    if (widget.enableCamera && _cameraSupported) {
      final source = await showModalBottomSheet<String>(
        context: context,
        builder: (sheetContext) {
          return SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: const Icon(Icons.photo_library_outlined),
                  title: Text(l10n.importFiles),
                  onTap: () => Navigator.of(sheetContext).pop('files'),
                ),
                ListTile(
                  leading: const Icon(Icons.photo_camera_outlined),
                  title: Text(l10n.filesCameraTakePhoto),
                  onTap: () => Navigator.of(sheetContext).pop('camera'),
                ),
              ],
            ),
          );
        },
      );
      if (!mounted) {
        return const <XFile>[];
      }
      if (source == 'camera') {
        try {
          final shot = await ImagePicker().pickImage(
            source: ImageSource.camera,
            maxWidth: 4096,
          );
          return shot == null ? const <XFile>[] : <XFile>[shot];
        } on Exception {
          return const <XFile>[];
        }
      }
      if (source != 'files') {
        return const <XFile>[];
      }
    }
    final acceptedTypeGroups =
        widget.acceptedExtensions.isEmpty
            ? const <XTypeGroup>[]
            : <XTypeGroup>[
              XTypeGroup(
                label: widget.subsystemDirectory,
                extensions: widget.acceptedExtensions,
              ),
            ];
    return ref.read(mediaImportFilePickerProvider)(acceptedTypeGroups);
  }

  bool get _cameraSupported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  Future<void> _showProgressSheet(
    BuildContext context, {
    required MediaImportService importService,
    required List<XFile> files,
    required String spaceType,
    required AppLocalizations l10n,
    required ScaffoldMessengerState messenger,
  }) async {
    _routeClosing = false;
    final result = await showModalBottomSheet<MediaImportBatchResult>(
      context: context,
      isScrollControlled: true,
      isDismissible: false,
      enableDrag: false,
      builder:
          (sheetContext) => _ImportProgressContent(
            importService: importService,
            files: files,
            subsystemDirectory: widget.subsystemDirectory,
            spaceType: spaceType,
            reuseExistingFiles: widget.reuseExistingFiles,
            l10n: l10n,
            onComplete: (result) => _completeImport(sheetContext, result),
            onClose: () => _closeProgressRoute(sheetContext),
          ),
    );
    await _handleImportComplete(result, l10n, messenger);
  }

  Future<void> _showProgressDialog(
    BuildContext context, {
    required MediaImportService importService,
    required List<XFile> files,
    required String spaceType,
    required AppLocalizations l10n,
    required ScaffoldMessengerState messenger,
  }) async {
    _routeClosing = false;
    final result = await showDialog<MediaImportBatchResult>(
      context: context,
      barrierDismissible: false,
      builder:
          (dialogContext) => Dialog(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 360),
              child: _ImportProgressContent(
                importService: importService,
                files: files,
                subsystemDirectory: widget.subsystemDirectory,
                spaceType: spaceType,
                reuseExistingFiles: widget.reuseExistingFiles,
                l10n: l10n,
                onComplete: (result) => _completeImport(dialogContext, result),
                onClose: () => _closeProgressRoute(dialogContext),
              ),
            ),
          ),
    );
    await _handleImportComplete(result, l10n, messenger);
  }

  void _closeProgressRoute<T>(BuildContext routeContext, [T? result]) {
    if (_routeClosing || !routeContext.mounted) return;
    final navigator = Navigator.of(routeContext);
    if (!navigator.canPop()) return;
    _routeClosing = true;
    navigator.pop<T>(result);
  }

  Future<void> _completeImport(
    BuildContext routeContext,
    MediaImportBatchResult result,
  ) async {
    if (!mounted || !routeContext.mounted) return;
    _closeProgressRoute(routeContext, result);
  }

  Future<void> _handleImportComplete(
    MediaImportBatchResult? result,
    AppLocalizations l10n,
    ScaffoldMessengerState messenger,
  ) async {
    if (result == null || result.imported.isEmpty || !mounted) {
      return;
    }
    try {
      final callback = widget.onImportCompleteWithResult;
      if (callback != null) {
        final completionState = await callback(result);
        if (completionState == MediaImportCompletionState.processing) {
          if (!mounted || !messenger.mounted) return;
          final failureSuffix =
              result.failures.isEmpty
                  ? ''
                  : ' (${result.failures.take(2).map(_failureSummary).join('; ')})';
          messenger.showSnackBar(
            SnackBar(
              content: Text(
                '${l10n.importProcessing(result.imported.length)}$failureSuffix',
              ),
            ),
          );
          return;
        }
        if (completionState == MediaImportCompletionState.failed) {
          return;
        }
      } else {
        await widget.onImportComplete();
      }
      if (!mounted || !messenger.mounted) return;
      final failureSuffix =
          result.failures.isEmpty
              ? ''
              : ' (${result.failures.take(2).map(_failureSummary).join('; ')})';
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            '${l10n.importComplete(result.imported.length)}$failureSuffix',
          ),
        ),
      );
    } on Object {
      if (!mounted || !messenger.mounted) return;
      messenger.showSnackBar(SnackBar(content: Text(l10n.importRefreshFailed)));
    }
  }

  String _failureSummary(MediaImportFailure failure) {
    final message = describeUserFacingError(failure.error).displayMessage;
    return '${failure.fileName}: $message';
  }

  List<XFile> _unsupportedFiles(List<XFile> files) {
    final supported =
        widget.acceptedExtensions.map(_normalizeExtension).toSet();
    final unsupported =
        widget.unsupportedExtensions.map(_normalizeExtension).toSet();
    if (supported.isEmpty && unsupported.isEmpty) {
      return const <XFile>[];
    }
    return files.where((file) {
      final extension = _fileExtension(file);
      return unsupported.contains(extension) ||
          (supported.isNotEmpty && !supported.contains(extension));
    }).toList();
  }

  String _supportedExtensionNames() {
    final unsupported =
        widget.unsupportedExtensions.map(_normalizeExtension).toSet();
    return widget.acceptedExtensions
        .map(_normalizeExtension)
        .where((extension) => !unsupported.contains(extension))
        .where((extension) => extension.isNotEmpty)
        .map((extension) => extension.toUpperCase())
        .join(', ');
  }

  String _unsupportedFileNames(List<XFile> files) {
    final names = files
        .take(3)
        .map((file) => file.name.isNotEmpty ? file.name : file.path)
        .join(', ');
    if (files.length <= 3) return names;
    return '$names ...';
  }
}

String _fileExtension(XFile file) {
  final name = file.name.isNotEmpty ? file.name : file.path;
  final separator = name.lastIndexOf('.');
  if (separator < 0 || separator == name.length - 1) return '';
  return _normalizeExtension(name.substring(separator + 1));
}

String _normalizeExtension(String extension) {
  return extension.replaceFirst(RegExp(r'^\.'), '').trim().toLowerCase();
}

class _ImportButtonIcon extends StatelessWidget {
  const _ImportButtonIcon({
    required this.busy,
    required this.color,
    required this.size,
  });

  final bool busy;
  final Color? color;
  final double size;

  @override
  Widget build(BuildContext context) {
    if (!busy) {
      return Icon(Icons.cloud_upload_outlined, size: size, color: color);
    }
    return SizedBox.square(
      dimension: size,
      child: CircularProgressIndicator(
        strokeWidth: 2,
        color: color ?? Theme.of(context).colorScheme.primary,
      ),
    );
  }
}

class _ImportProgressContent extends StatefulWidget {
  const _ImportProgressContent({
    required this.importService,
    required this.files,
    required this.subsystemDirectory,
    required this.spaceType,
    required this.reuseExistingFiles,
    required this.l10n,
    required this.onComplete,
    required this.onClose,
  });

  final MediaImportService importService;
  final List<XFile> files;
  final String subsystemDirectory;
  final String spaceType;
  final bool reuseExistingFiles;
  final AppLocalizations l10n;
  final Future<void> Function(MediaImportBatchResult result) onComplete;
  final VoidCallback onClose;

  @override
  State<_ImportProgressContent> createState() => _ImportProgressContentState();
}

class _ImportProgressContentState extends State<_ImportProgressContent> {
  String _currentFile = '';
  double _progress = 0;
  bool _started = false;
  String? _error;
  MediaImportCancellationToken _cancellationToken =
      MediaImportCancellationToken();

  @override
  void initState() {
    super.initState();
    unawaited(_startImport());
  }

  Future<void> _startImport() async {
    if (_started) return;
    _started = true;

    try {
      final importService = widget.importService;

      // 确保目录存在
      final parentId = await importService.ensureDefaultDirectory(
        directoryName: widget.subsystemDirectory,
        spaceType: widget.spaceType,
      );
      if (!mounted) return;
      _cancellationToken.throwIfCancelled();
      if (parentId == null) {
        setState(() => _error = widget.l10n.importFailed);
        return;
      }

      // 上传文件
      final batchResult = await importService.importFilesDetailed(
        files: widget.files,
        parentId: parentId,
        spaceType: widget.spaceType,
        reuseExistingFiles: widget.reuseExistingFiles,
        cancellationToken: _cancellationToken,
        onProgress: (fileName, uploaded, total) {
          if (mounted) {
            setState(() {
              _currentFile = fileName;
              _progress = total > 0 ? uploaded / total : 0;
            });
          }
        },
      );
      if (!mounted) return;
      if (batchResult.imported.isEmpty) {
        setState(() => _error = _formatFailures(batchResult));
        return;
      }
      await widget.onComplete(batchResult);
      if (!mounted) return;
    } on MediaImportCancelledException {
      if (mounted) widget.onClose();
    } on Object catch (error) {
      if (mounted) {
        setState(() => _error = describeUserFacingError(error).displayMessage);
      }
    }
  }

  String _formatFailures(MediaImportBatchResult result) {
    if (result.failures.isEmpty) return widget.l10n.importFailed;
    final details = result.failures
        .take(3)
        .map(
          (failure) =>
              '${failure.fileName}: ${describeUserFacingError(failure.error).displayMessage}',
        )
        .join('\n');
    final suffix = result.failures.length > 3 ? '\n...' : '';
    return '${widget.l10n.importFailed}\n$details$suffix';
  }

  @override
  void dispose() {
    _cancellationToken.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.l10n.importUploading,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 16),
          if (_error != null)
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _error!,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.error,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 18),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilledButton.tonalIcon(
                      onPressed: () {
                        if (!mounted) return;
                        if (_cancellationToken.isCancelled) {
                          _cancellationToken = MediaImportCancellationToken();
                        }
                        setState(() {
                          _error = null;
                          _progress = 0;
                          _currentFile = '';
                          _started = false;
                        });
                        unawaited(_startImport());
                      },
                      icon: const Icon(Icons.refresh_rounded, size: 18),
                      label: Text(widget.l10n.coreRetry),
                    ),
                    TextButton(
                      onPressed: widget.onClose,
                      child: Text(widget.l10n.coreClose),
                    ),
                  ],
                ),
              ],
            )
          else ...[
            Text(
              _currentFile,
              style: theme.textTheme.bodyMedium,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 8),
            LinearProgressIndicator(value: _progress > 0 ? _progress : null),
            const SizedBox(height: 4),
            Text(
              '${widget.files.length} ${widget.l10n.importFiles}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            TextButton.icon(
              onPressed: () {
                _cancellationToken.cancel();
                widget.onClose();
              },
              icon: const Icon(Icons.close_rounded, size: 18),
              label: Text(widget.l10n.coreCancel),
            ),
          ],
        ],
      ),
    );
  }
}
