import 'dart:async';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:omninest/app/desktop/desktop_icons.dart';
import 'package:omninest/app/desktop/widgets/desktop_controls.dart';
import 'package:omninest/app/desktop/widgets/desktop_dialogs.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/desktop/desktop_skin.dart';
import 'package:omninest/app/theme/desktop/desktop_type.dart';
import 'package:omninest/core/errors/error_message.dart';
import 'package:omninest/core/theme/motion_token.dart';
import 'package:omninest/features/files/file_dashboard.dart';
import 'package:omninest/features/files/presentation/widgets/media_import_button.dart'
    show mediaImportFilePickerProvider;

enum DesktopMediaImportKind { movies, photos, music }

class DesktopMediaImportSelection {
  const DesktopMediaImportSelection({
    this.fileNodeIds = const <String>[],
    this.deviceFiles = const <XFile>[],
    this.matchMetadata = true,
  });

  final List<String> fileNodeIds;
  final List<XFile> deviceFiles;
  final bool matchMetadata;
}

Future<DesktopMediaImportSelection?> showDesktopMediaImportDialog(
  BuildContext context, {
  required DesktopMediaImportKind kind,
}) {
  return showDesktopDialog<DesktopMediaImportSelection>(
    context,
    builder: (_) => DesktopMediaImportDialog(kind: kind),
  );
}

class DesktopMediaImportDialog extends ConsumerStatefulWidget {
  const DesktopMediaImportDialog({required this.kind, super.key});

  final DesktopMediaImportKind kind;

  @override
  ConsumerState<DesktopMediaImportDialog> createState() =>
      _DesktopMediaImportDialogState();
}

enum _ImportSource { files, device }

class _DesktopMediaImportDialogState
    extends ConsumerState<DesktopMediaImportDialog> {
  _ImportSource _source = _ImportSource.files;
  final Set<String> _selectedFileIds = <String>{};
  final Set<String> _selectedDeviceKeys = <String>{};
  final List<FileNode> _entries = <FileNode>[];
  final List<FileNode> _breadcrumbs = <FileNode>[];
  final List<XFile> _deviceFiles = <XFile>[];
  final Map<String, int> _deviceSizes = <String, int>{};
  final ScrollController _listScroll = ScrollController();
  String? _parentId;
  String? _loadError;
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = false;
  bool _matchMetadata = true;
  int _page = 0;
  int _loadGeneration = 0;
  int _autoScannedPages = 0;

  @override
  void initState() {
    super.initState();
    _listScroll.addListener(_onScroll);
    _loadFiles(reset: true);
  }

  @override
  void dispose() {
    _loadGeneration++;
    _listScroll.dispose();
    super.dispose();
  }

  List<String> get _extensions => switch (widget.kind) {
    DesktopMediaImportKind.movies => const <String>[
      'mp4',
      'mkv',
      'webm',
      'mov',
      'm4v',
      'avi',
      'flv',
      'wmv',
      'ts',
      'm2ts',
    ],
    DesktopMediaImportKind.photos => const <String>[
      'jpg',
      'jpeg',
      'png',
      'gif',
      'heic',
      'heif',
      'bmp',
      'tif',
      'tiff',
      'cr2',
      'nef',
      'arw',
      'dng',
      'mp4',
      'mkv',
      'webm',
      'mov',
      'm4v',
      'avi',
      'flv',
      'wmv',
      'ts',
      'm2ts',
    ],
    DesktopMediaImportKind.music => const <String>[
      'mp3',
      'flac',
      'aac',
      'm4a',
      'ogg',
      'opus',
      'wav',
      'wma',
    ],
  };

  String _title(AppLocalizations l10n) => switch (widget.kind) {
    DesktopMediaImportKind.movies => l10n.desktopMediaImportMoviesTitle,
    DesktopMediaImportKind.photos => l10n.desktopMediaImportPhotosTitle,
    DesktopMediaImportKind.music => l10n.desktopMediaImportMusicTitle,
  };

  String _hint(AppLocalizations l10n) => switch (widget.kind) {
    DesktopMediaImportKind.movies => l10n.desktopMediaImportMoviesHint,
    DesktopMediaImportKind.photos => l10n.desktopMediaImportPhotosHint,
    DesktopMediaImportKind.music => l10n.desktopMediaImportMusicHint,
  };

  IconData get _mediaIcon => switch (widget.kind) {
    DesktopMediaImportKind.movies => DesktopIcons.film,
    DesktopMediaImportKind.photos => DesktopIcons.image,
    DesktopMediaImportKind.music => DesktopIcons.music,
  };

  List<FileNode> get _visibleFiles => _entries
      .where((node) => node.isFolder || _isSupported(node.name, node.mimeType))
      .toList(growable: false);

  bool _isSupported(String name, String? mimeType) {
    final mime = mimeType?.toLowerCase() ?? '';
    final extension = _extension(name);
    if (_extensions.contains(extension)) return true;
    return switch (widget.kind) {
      DesktopMediaImportKind.movies => mime.startsWith('video/'),
      DesktopMediaImportKind.photos => mime.startsWith('image/'),
      DesktopMediaImportKind.music => mime.startsWith('audio/'),
    };
  }

  String _extension(String name) {
    final dot = name.lastIndexOf('.');
    return dot < 0 ? '' : name.substring(dot + 1).toLowerCase();
  }

  void _onScroll() {
    if (_source == _ImportSource.files &&
        _listScroll.hasClients &&
        _listScroll.position.extentAfter < 120) {
      unawaited(_loadFiles());
    }
  }

  Future<void> _loadFiles({bool reset = false}) async {
    if (!reset && (_loading || _loadingMore || !_hasMore)) return;
    final generation = ++_loadGeneration;
    final requestedPage = reset ? 0 : _page + 1;
    final requestedParent = _parentId;
    setState(() {
      _loadError = null;
      if (reset) {
        _entries.clear();
        _page = 0;
        _hasMore = true;
        _autoScannedPages = 0;
      }
      _loading = reset;
      _loadingMore = !reset;
    });
    try {
      final result = await ref
          .read(fileBrowserControllerProvider.notifier)
          .listFolderOptionsPage(
            requestedParent,
            page: requestedPage,
            size: 100,
          );
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        final existing = _entries.map((node) => node.id).toSet();
        _entries.addAll(
          result.items.where((node) => !existing.contains(node.id)),
        );
        _page = result.page;
        _hasMore = result.hasNextPage;
        _loading = false;
        _loadingMore = false;
      });
      if (_hasMore && _visibleFiles.length < 6 && _autoScannedPages < 5) {
        _autoScannedPages++;
        unawaited(_loadFiles());
      }
    } on Object catch (error) {
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _loadError = userFacingErrorText(
          error,
          l10n: AppLocalizations.of(context),
        );
        _loading = false;
        _loadingMore = false;
      });
    }
  }

  void _enterFolder(FileNode folder) {
    setState(() {
      _breadcrumbs.add(folder);
      _parentId = folder.id;
      if (_listScroll.hasClients) _listScroll.jumpTo(0);
    });
    _loadFiles(reset: true);
  }

  void _goToBreadcrumb(int index) {
    setState(() {
      if (index < 0) {
        _breadcrumbs.clear();
        _parentId = null;
      } else {
        _breadcrumbs.removeRange(index + 1, _breadcrumbs.length);
        _parentId = _breadcrumbs[index].id;
      }
      if (_listScroll.hasClients) _listScroll.jumpTo(0);
    });
    _loadFiles(reset: true);
  }

  Future<void> _chooseDeviceFiles(AppLocalizations l10n) async {
    try {
      final files = await ref.read(mediaImportFilePickerProvider)(<XTypeGroup>[
        XTypeGroup(label: _title(l10n), extensions: _extensions),
      ]);
      if (!mounted || files.isEmpty) return;
      final knownKeys = _deviceFiles.map(_deviceKey).toSet();
      final additions = files.where(
        (file) => !knownKeys.contains(_deviceKey(file)),
      );
      final newFiles = additions.toList(growable: false);
      final sizes = await Future.wait<int?>(
        newFiles.map((file) async {
          try {
            return await file.length();
          } on Object {
            return null;
          }
        }),
      );
      if (!mounted) return;
      setState(() {
        _deviceFiles.addAll(newFiles);
        for (var index = 0; index < newFiles.length; index++) {
          final size = sizes[index];
          if (size != null) _deviceSizes[_deviceKey(newFiles[index])] = size;
          _selectedDeviceKeys.add(_deviceKey(newFiles[index]));
        }
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _loadError = userFacingErrorText(
          error,
          l10n: AppLocalizations.of(context),
        );
      });
    }
  }

  String _deviceKey(XFile file) => file.path.isEmpty ? file.name : file.path;

  void _complete() {
    final selection = DesktopMediaImportSelection(
      fileNodeIds:
          _source == _ImportSource.files
              ? _selectedFileIds.toList(growable: false)
              : const <String>[],
      deviceFiles:
          _source == _ImportSource.device
              ? _deviceFiles
                  .where(
                    (file) => _selectedDeviceKeys.contains(_deviceKey(file)),
                  )
                  .toList(growable: false)
              : const <XFile>[],
      matchMetadata: _matchMetadata,
    );
    closeDesktopModal(context, selection);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final skin = DesktopSkin.of(context);
    final selectedCount =
        _source == _ImportSource.files
            ? _selectedFileIds.length
            : _selectedDeviceKeys.length;
    return DesktopDialog(
      eyebrow: l10n.filesImport,
      title: _title(l10n),
      width: 760,
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _sourceTabs(l10n, skin),
          const SizedBox(height: 10),
          Text(
            _source == _ImportSource.files
                ? _hint(l10n)
                : l10n.desktopMediaImportDeviceHint,
            style: DesktopType.secondary(skin.text2),
          ),
          if (_source == _ImportSource.device) ...[
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: DesktopButton(
                label: l10n.desktopMediaImportChooseFiles,
                icon: DesktopIcons.upload,
                variant: DesktopButtonVariant.soft,
                onPressed: () => _chooseDeviceFiles(l10n),
              ),
            ),
          ] else if (_breadcrumbs.isNotEmpty) ...[
            const SizedBox(height: 8),
            _breadcrumbsView(l10n, skin),
          ],
          const SizedBox(height: 8),
          _fileList(l10n, skin),
          if (widget.kind == DesktopMediaImportKind.movies) ...[
            const SizedBox(height: 8),
            _metadataSetting(l10n, skin),
          ],
        ],
      ),
      actions: [
        DesktopButton(
          label: l10n.coreCancel,
          variant: DesktopButtonVariant.ghost,
          onPressed: () => closeDesktopModal(context),
        ),
        DesktopButton(
          label: '${l10n.filesImport} $selectedCount',
          variant: DesktopButtonVariant.primary,
          onPressed: selectedCount == 0 ? null : _complete,
        ),
      ],
    );
  }

  Widget _sourceTabs(AppLocalizations l10n, DesktopSkin skin) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: skin.raise,
        border: Border.all(color: skin.line),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _sourceTab(
            label: l10n.desktopMediaImportFromFiles,
            icon: DesktopIcons.folder,
            selected: _source == _ImportSource.files,
            onPressed:
                () => setState(() {
                  _source = _ImportSource.files;
                  _loadError = null;
                }),
          ),
          _sourceTab(
            label: l10n.desktopMediaImportFromDevice,
            icon: DesktopIcons.upload,
            selected: _source == _ImportSource.device,
            onPressed:
                () => setState(() {
                  _source = _ImportSource.device;
                  _loadError = null;
                }),
          ),
        ],
      ),
    );
  }

  Widget _sourceTab({
    required String label,
    required IconData icon,
    required bool selected,
    required VoidCallback onPressed,
  }) {
    final skin = DesktopSkin.of(context);
    return DesktopHover(
      builder:
          (context, hovered) => GestureDetector(
            onTap: onPressed,
            behavior: HitTestBehavior.opaque,
            child: AnimatedContainer(
              duration: MotionToken.reduced(context, MotionToken.fast),
              curve: MotionToken.curve,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              height: 30,
              decoration: BoxDecoration(
                color: selected ? skin.raise2 : (hovered ? skin.raise : null),
                borderRadius: BorderRadius.circular(9),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    icon,
                    size: 14,
                    color: selected ? skin.text : skin.text2,
                  ),
                  const SizedBox(width: 7),
                  Text(
                    label,
                    style: DesktopType.dense(selected ? skin.text : skin.text2),
                  ),
                ],
              ),
            ),
          ),
    );
  }

  Widget _breadcrumbsView(AppLocalizations l10n, DesktopSkin skin) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          TextButton(
            onPressed: () => _goToBreadcrumb(-1),
            child: Text(l10n.filesRootDirectory),
          ),
          for (var index = 0; index < _breadcrumbs.length; index++) ...[
            Icon(DesktopIcons.chevron, size: 14, color: skin.text3),
            TextButton(
              onPressed: () => _goToBreadcrumb(index),
              child: Text(_breadcrumbs[index].name),
            ),
          ],
        ],
      ),
    );
  }

  Widget _fileList(AppLocalizations l10n, DesktopSkin skin) {
    if (_loadError != null && _source == _ImportSource.device) {
      return _listMessage(skin, _loadError!);
    }
    if (_loadError != null && _source == _ImportSource.files) {
      return _listMessage(
        skin,
        _loadError!,
        action: l10n.coreRetry,
        onAction: () => _loadFiles(reset: true),
      );
    }
    if (_loading && _source == _ImportSource.files) {
      return const SizedBox(
        height: 126,
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }
    final deviceMode = _source == _ImportSource.device;
    final rows = deviceMode ? _deviceFiles : _visibleFiles;
    if (rows.isEmpty) {
      return _listMessage(
        skin,
        deviceMode
            ? l10n.desktopMediaImportNoFiles
            : l10n.desktopMediaImportNoCompatibleFiles,
      );
    }
    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 340),
      child: Scrollbar(
        controller: _listScroll,
        child: ListView.separated(
          controller: _listScroll,
          shrinkWrap: true,
          itemCount: rows.length + (_loadingMore ? 1 : 0),
          separatorBuilder: (_, _) => const SizedBox(height: 6),
          itemBuilder: (context, index) {
            if (index >= rows.length) {
              return const Padding(
                padding: EdgeInsets.all(12),
                child: Center(
                  child: SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              );
            }
            if (deviceMode) {
              final file = _deviceFiles[index];
              final key = _deviceKey(file);
              return _candidateRow(
                name: file.name,
                detail:
                    '${_extension(file.name).toUpperCase()} · ${_sizeText(_deviceSizes[key])}',
                selected: _selectedDeviceKeys.contains(key),
                icon: _mediaIcon,
                onPressed:
                    () => setState(() {
                      if (!_selectedDeviceKeys.add(key)) {
                        _selectedDeviceKeys.remove(key);
                      }
                    }),
              );
            }
            final node = _visibleFiles[index];
            if (node.isFolder) {
              return _candidateRow(
                name: node.name,
                detail: '${l10n.filesFolder} · ${_sizeText(node.sizeBytes)}',
                selected: _selectedFileIds.contains(node.id),
                icon: DesktopIcons.folder,
                onPressed:
                    () => setState(() {
                      if (!_selectedFileIds.add(node.id)) {
                        _selectedFileIds.remove(node.id);
                      }
                    }),
                onDoubleTap: () => _enterFolder(node),
              );
            }
            return _candidateRow(
              name: node.name,
              detail:
                  '${_extension(node.name).toUpperCase()} · ${_sizeText(node.sizeBytes)}',
              selected: _selectedFileIds.contains(node.id),
              icon: _mediaIcon,
              onPressed:
                  () => setState(() {
                    if (!_selectedFileIds.add(node.id)) {
                      _selectedFileIds.remove(node.id);
                    }
                  }),
            );
          },
        ),
      ),
    );
  }

  Widget _candidateRow({
    required String name,
    required String detail,
    required bool selected,
    required IconData icon,
    required VoidCallback onPressed,
    VoidCallback? onDoubleTap,
  }) {
    final skin = DesktopSkin.of(context);
    return DesktopHover(
      builder:
          (context, hovered) => GestureDetector(
            onTap: onPressed,
            onDoubleTap: onDoubleTap,
            behavior: HitTestBehavior.opaque,
            child: AnimatedContainer(
              duration: MotionToken.reduced(context, MotionToken.fast),
              curve: MotionToken.curve,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color:
                    selected
                        ? skin.accent.withValues(alpha: 0.10)
                        : (hovered ? skin.raise2 : skin.raise),
                border: Border.all(
                  color:
                      selected
                          ? skin.accent.withValues(alpha: 0.45)
                          : skin.line,
                ),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Container(
                    width: 18,
                    height: 18,
                    decoration: BoxDecoration(
                      color: selected ? skin.accent : Colors.transparent,
                      border: Border.all(
                        color: selected ? skin.accent : skin.line2,
                      ),
                      borderRadius: BorderRadius.circular(5),
                    ),
                    child:
                        selected
                            ? Icon(
                              DesktopIcons.check,
                              size: 12,
                              color: skin.accentInk,
                            )
                            : null,
                  ),
                  const SizedBox(width: 12),
                  Icon(icon, size: 16, color: skin.text2),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: DesktopType.denseStrong(skin.text),
                        ),
                        Text(detail, style: DesktopType.caption(skin.text3)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
    );
  }

  Widget _listMessage(
    DesktopSkin skin,
    String text, {
    String? action,
    VoidCallback? onAction,
  }) {
    return SizedBox(
      height: 110,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(text, style: DesktopType.secondary(skin.text3)),
            if (action != null && onAction != null)
              TextButton(onPressed: onAction, child: Text(action)),
          ],
        ),
      ),
    );
  }

  Widget _metadataSetting(AppLocalizations l10n, DesktopSkin skin) {
    return Container(
      padding: const EdgeInsets.only(top: 12),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: skin.line)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.desktopMediaImportMatchMetadata,
                  style: DesktopType.denseStrong(skin.text),
                ),
                Text(
                  l10n.desktopMediaImportMetadataHint,
                  style: DesktopType.caption(skin.text3),
                ),
              ],
            ),
          ),
          DesktopToggle(
            value: _matchMetadata,
            label: l10n.desktopMediaImportMatchMetadata,
            onChanged: (value) => setState(() => _matchMetadata = value),
          ),
        ],
      ),
    );
  }

  String _sizeText(int? bytes) {
    if (bytes == null) return '—';
    if (bytes >= 1000000000) {
      return '${(bytes / 1000000000).toStringAsFixed(1)} GB';
    }
    if (bytes >= 1000000) return '${(bytes / 1000000).toStringAsFixed(1)} MB';
    return '${(bytes / 1000).round().clamp(1, 999)} KB';
  }
}
