import 'dart:async';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:omninest/app/desktop/desktop_icons.dart';
import 'package:omninest/app/desktop/widgets/desktop_controls.dart';
import 'package:omninest/app/desktop/widgets/desktop_dialogs.dart';
import 'package:omninest/app/desktop/widgets/desktop_fields.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/desktop/desktop_skin.dart';
import 'package:omninest/app/theme/desktop/desktop_type.dart';
import 'package:omninest/core/errors/error_message.dart';
import 'package:omninest/core/theme/motion_token.dart';
import 'package:omninest/features/files/file_dashboard.dart';
import 'package:omninest/features/files/presentation/widgets/media_import_button.dart'
    show mediaImportFilePickerProvider;

part 'desktop_media_import_dialog_parts.dart';

/// 导入目标空间；样例 `useImportSpace` 会记住上一次的选择。
enum DesktopImportSpace { personal, shared }

const _importSpaceStorageKey = 'omninest:importSpace';

enum DesktopMediaImportKind { movies, photos, music, books }

class DesktopMediaImportSelection {
  const DesktopMediaImportSelection({
    this.fileNodeIds = const <String>[],
    this.deviceFiles = const <XFile>[],
    this.matchMetadata = true,
    this.space = DesktopImportSpace.personal,
  });

  final List<String> fileNodeIds;
  final List<XFile> deviceFiles;
  final bool matchMetadata;
  final DesktopImportSpace space;

  String get spaceType =>
      space == DesktopImportSpace.shared ? 'SHARED' : 'PERSONAL';
}

Future<DesktopMediaImportSelection?> showDesktopMediaImportDialog(
  BuildContext context, {
  required DesktopMediaImportKind kind,
  bool allowSharedSpace = true,
}) {
  return showDesktopDialog<DesktopMediaImportSelection>(
    context,
    builder:
        (_) => DesktopMediaImportDialog(
          kind: kind,
          allowSharedSpace: allowSharedSpace,
        ),
  );
}

class DesktopMediaImportDialog extends ConsumerStatefulWidget {
  const DesktopMediaImportDialog({
    required this.kind,
    this.allowSharedSpace = true,
    super.key,
  });

  final DesktopMediaImportKind kind;

  /// 照片导入固定落在个人空间（样例对 photo 不显示 `SpacePicker`）。
  final bool allowSharedSpace;

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
  final TextEditingController _filterController = TextEditingController();
  String? _parentId;
  String? _loadError;
  String _filter = '';
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = false;
  bool _matchMetadata = true;
  DesktopImportSpace _space = DesktopImportSpace.personal;
  int _page = 0;
  int _loadGeneration = 0;
  int _autoScannedPages = 0;

  @override
  void initState() {
    super.initState();
    _listScroll.addListener(_onScroll);
    _restoreImportSpace();
    _loadFiles(reset: true);
  }

  Future<void> _restoreImportSpace() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!mounted) return;
      final stored = prefs.getString(_importSpaceStorageKey);
      if (stored == 'shared') {
        setState(() => _space = DesktopImportSpace.shared);
      }
    } on Object {
      // 偏好存储不可用时保持个人空间，不影响导入本身。
    }
  }

  Future<void> _setSpace(DesktopImportSpace value) async {
    if (_space == value) return;
    setState(() => _space = value);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _importSpaceStorageKey,
        value == DesktopImportSpace.shared ? 'shared' : 'personal',
      );
    } on Object {
      // 记忆失败只影响下次默认值，本次选择仍然生效。
    }
  }

  bool get _showSpacePicker =>
      widget.allowSharedSpace && widget.kind != DesktopMediaImportKind.photos;

  /// part 文件中的 UI 扩展通过这里触发重建，避免越权调用 `State.setState`。
  void applyState(void Function() update) => setState(update);

  @override
  void dispose() {
    _loadGeneration++;
    _listScroll.dispose();
    _filterController.dispose();
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
    DesktopMediaImportKind.books => const <String>[
      'epub',
      'txt',
      'cbz',
      'zip',
      'pdf',
    ],
  };

  String _title(AppLocalizations l10n) => switch (widget.kind) {
    DesktopMediaImportKind.movies => l10n.desktopMediaImportMoviesTitle,
    DesktopMediaImportKind.photos => l10n.desktopMediaImportPhotosTitle,
    DesktopMediaImportKind.music => l10n.desktopMediaImportMusicTitle,
    DesktopMediaImportKind.books => l10n.desktopMediaImportBooksTitle,
  };

  String _hint(AppLocalizations l10n) => switch (widget.kind) {
    DesktopMediaImportKind.movies => l10n.desktopMediaImportMoviesHint,
    DesktopMediaImportKind.photos => l10n.desktopMediaImportPhotosHint,
    DesktopMediaImportKind.music => l10n.desktopMediaImportMusicHint,
    DesktopMediaImportKind.books => l10n.desktopMediaImportBooksHint,
  };

  IconData get _mediaIcon => switch (widget.kind) {
    DesktopMediaImportKind.movies => DesktopIcons.film,
    DesktopMediaImportKind.photos => DesktopIcons.image,
    DesktopMediaImportKind.music => DesktopIcons.music,
    DesktopMediaImportKind.books => DesktopIcons.book,
  };

  List<FileNode> get _visibleFiles => _entries
      .where(
        (node) =>
            (node.isFolder || _isSupported(node.name, node.mimeType)) &&
            _matchesFilter(node.name),
      )
      .toList(growable: false);

  List<XFile> get _visibleDeviceFiles => _deviceFiles
      .where((file) => _matchesFilter(file.name))
      .toList(growable: false);

  bool _matchesFilter(String name) =>
      _filter.trim().isEmpty ||
      name.toLowerCase().contains(_filter.trim().toLowerCase());

  int get _sourceCount =>
      _source == _ImportSource.files
          ? _visibleFiles.length
          : _visibleDeviceFiles.length;

  bool get _allSelected =>
      _sourceCount > 0 &&
      (_source == _ImportSource.files
          ? _visibleFiles.every((node) => _selectedFileIds.contains(node.id))
          : _visibleDeviceFiles.every(
            (file) => _selectedDeviceKeys.contains(_deviceKey(file)),
          ));

  void _toggleAll() {
    final clear = _allSelected;
    setState(() {
      if (_source == _ImportSource.files) {
        for (final node in _visibleFiles) {
          if (clear) {
            _selectedFileIds.remove(node.id);
          } else {
            _selectedFileIds.add(node.id);
          }
        }
      } else {
        for (final file in _visibleDeviceFiles) {
          final key = _deviceKey(file);
          if (clear) {
            _selectedDeviceKeys.remove(key);
          } else {
            _selectedDeviceKeys.add(key);
          }
        }
      }
    });
  }

  bool _isSupported(String name, String? mimeType) {
    final mime = mimeType?.toLowerCase() ?? '';
    final extension = _extension(name);
    if (_extensions.contains(extension)) return true;
    return switch (widget.kind) {
      DesktopMediaImportKind.movies => mime.startsWith('video/'),
      DesktopMediaImportKind.photos => mime.startsWith('image/'),
      DesktopMediaImportKind.music => mime.startsWith('audio/'),
      DesktopMediaImportKind.books =>
        mime.startsWith('text/') ||
            mime.contains('epub') ||
            mime.contains('pdf') ||
            mime.contains('zip'),
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
      space: _space,
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
          if (_showSpacePicker) ...[
            _spacePicker(l10n, skin),
            const SizedBox(height: 14),
          ],
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
          if (_sourceCount > 5 || _filter.isNotEmpty) _listTools(l10n, skin),
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
}
