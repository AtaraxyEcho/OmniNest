import 'dart:async';
import 'dart:ui' show PathMetric;

import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:omninest/app/desktop/desktop_icons.dart';
import 'package:omninest/app/desktop/desktop_import_filter.dart';
import 'package:omninest/app/desktop/desktop_toast.dart';
import 'package:omninest/app/desktop/widgets/desktop_controls.dart';
import 'package:omninest/app/desktop/widgets/desktop_dialogs.dart';
import 'package:omninest/app/desktop/widgets/desktop_fields.dart';
import 'package:omninest/app/desktop/widgets/desktop_surfaces.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/desktop/desktop_skin.dart';
import 'package:omninest/app/theme/desktop/desktop_type.dart';
import 'package:omninest/core/errors/error_message.dart';
import 'package:omninest/core/theme/motion_token.dart';
import 'package:omninest/features/files/file_dashboard.dart';
import 'package:omninest/features/files/presentation/widgets/media_import_button.dart'
    show mediaImportFilePickerProvider;
import 'package:omninest/platform/platform_capabilities.dart';

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
  final List<ImportRejectedItem> _rejectedItems = <ImportRejectedItem>[];
  final ScrollController _listScroll = ScrollController();
  final TextEditingController _filterController = TextEditingController();
  String? _parentId;
  String? _loadError;
  String _filter = '';
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = false;
  bool _matchMetadata = true;
  bool _dragOver = false;
  bool _scanningDrop = false;
  bool _showUnsupported = false;
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

  DesktopImportModule get _importModule => switch (widget.kind) {
    DesktopMediaImportKind.movies => DesktopImportModule.film,
    DesktopMediaImportKind.photos => DesktopImportModule.photo,
    DesktopMediaImportKind.music => DesktopImportModule.music,
    DesktopMediaImportKind.books => DesktopImportModule.book,
  };

  /// part 文件中的 UI 扩展通过这里触发重建，避免越权调用 `State.setState`。
  void applyState(void Function() update) => setState(update);

  @override
  void dispose() {
    _loadGeneration++;
    _listScroll.dispose();
    _filterController.dispose();
    super.dispose();
  }

  List<String> get _extensions => importExtensionsFor(_importModule);

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

  String get _supportedTypesSummary => switch (widget.kind) {
    DesktopMediaImportKind.movies => 'MKV, MP4, MOV, AVI, WEBM, TS…',
    DesktopMediaImportKind.photos => 'JPG, HEIC, PNG, AVIF, RAW, MP4, MOV…',
    DesktopMediaImportKind.music => 'FLAC, MP3, AAC, WAV, APE, AIFF…',
    DesktopMediaImportKind.books => 'EPUB, TXT, CBZ, ZIP, PDF',
  };

  IconData get _mediaIcon => switch (widget.kind) {
    DesktopMediaImportKind.movies => DesktopIcons.film,
    DesktopMediaImportKind.photos => DesktopIcons.image,
    DesktopMediaImportKind.music => DesktopIcons.music,
    DesktopMediaImportKind.books => DesktopIcons.book,
  };

  /// 当前目录中可导入的媒体文件（排除文件夹、空文件与不支持格式）。
  bool _isImportableFile(FileNode node) =>
      !node.isFolder &&
      node.sizeBytes != 0 &&
      _isSupported(node.name, node.mimeType);

  /// 自动翻页扫描统计：当前目录已加载的匹配媒体文件总数（不含文件夹）。
  int get _matchedMediaCount => _entries.where(_isImportableFile).length;

  /// 当前目录经过关键词过滤后、可被全选/勾选的媒体文件列表。
  List<FileNode> get _importableFiles => _entries
      .where((node) => _isImportableFile(node) && _matchesFilter(node.name))
      .toList(growable: false);

  /// 列表实际展示条目：文件夹与可导入文件在前；展开全部时，不支持或空文件排在末尾。
  List<FileNode> get _visibleFiles {
    final supported = <FileNode>[];
    final unsupported = <FileNode>[];
    for (final node in _entries) {
      if (!_matchesFilter(node.name)) {
        continue;
      }
      if (node.isFolder || _isImportableFile(node)) {
        supported.add(node);
      } else if (_showUnsupported) {
        unsupported.add(node);
      }
    }
    if (unsupported.isEmpty) {
      return supported;
    }
    return <FileNode>[...supported, ...unsupported];
  }

  int get _hiddenFilesCount =>
      _entries
          .where((node) => !node.isFolder && !_isImportableFile(node))
          .length;

  List<XFile> get _visibleDeviceFiles => _deviceFiles
      .where((file) => _matchesFilter(file.name))
      .toList(growable: false);

  bool _matchesFilter(String name) =>
      _filter.trim().isEmpty ||
      name.toLowerCase().contains(_filter.trim().toLowerCase());

  int get _selectableCount =>
      _source == _ImportSource.files
          ? _importableFiles.length
          : _visibleDeviceFiles.length;

  int get _sourceCount =>
      _source == _ImportSource.files
          ? _visibleFiles.length
          : _visibleDeviceFiles.length;

  bool get _allSelected =>
      _selectableCount > 0 &&
      (_source == _ImportSource.files
          ? _importableFiles.every((node) => _selectedFileIds.contains(node.id))
          : _visibleDeviceFiles.every(
            (file) => _selectedDeviceKeys.contains(_deviceKey(file)),
          ));

  void _toggleAll() {
    final clear = _allSelected;
    setState(() {
      if (_source == _ImportSource.files) {
        for (final node in _importableFiles) {
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

  bool _isSupported(String name, String? mimeType) =>
      !isJunkFile(name) &&
      acceptsImportFile(_importModule, name, mimeType: mimeType);

  String _extension(String name) => importExtensionOf(name);

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
      if (_hasMore && _matchedMediaCount < 6 && _autoScannedPages < 10) {
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

  Future<void> _ingestDeviceFiles(List<XFile> incoming) async {
    if (incoming.isEmpty) return;
    final sizes = await Future.wait<int?>(
      incoming.map((file) async {
        try {
          return await file.length();
        } on Object {
          return null;
        }
      }),
    );
    if (!mounted) return;
    final candidates = <ImportCandidate<XFile>>[
      for (var i = 0; i < incoming.length; i++)
        ImportCandidate<XFile>(
          name: incoming[i].name,
          sizeBytes: sizes[i],
          item: incoming[i],
          key: _deviceKey(incoming[i]),
          mimeType: incoming[i].mimeType,
        ),
    ];
    final knownKeys = _deviceFiles.map(_deviceKey).toSet();
    final filtered = filterImportCandidates<XFile>(
      candidates,
      _importModule,
      existingKeys: knownKeys,
    );
    setState(() {
      _loadError = null;
      _rejectedItems
        ..clear()
        ..addAll(filtered.rejected);
      for (final accepted in filtered.accepted) {
        final key = _deviceKey(accepted.item);
        _deviceFiles.add(accepted.item);
        if (accepted.sizeBytes != null) {
          _deviceSizes[key] = accepted.sizeBytes!;
        }
        _selectedDeviceKeys.add(key);
      }
    });
    if (filtered.duplicateCount > 0 && mounted) {
      showDesktopToast(
        context,
        '已跳过 ${filtered.duplicateCount} 个重复文件',
        kind: DesktopToastKind.info,
        icon: DesktopIcons.info,
      );
    }
  }

  Future<void> _chooseDeviceFiles(AppLocalizations l10n) async {
    try {
      final files = await ref.read(mediaImportFilePickerProvider)(<XTypeGroup>[
        XTypeGroup(label: _title(l10n), extensions: _extensions),
      ]);
      if (!mounted || files.isEmpty) return;
      await _ingestDeviceFiles(files);
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

  Future<void> _chooseDeviceFolder() async {
    setState(() => _scanningDrop = true);
    try {
      final dirPath = await getDirectoryPath();
      if (!mounted || dirPath == null || dirPath.isEmpty) return;
      final expanded = await expandDirectoryPath(dirPath);
      if (!mounted) return;
      await _ingestDeviceFiles(expanded);
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _loadError = userFacingErrorText(
          error,
          l10n: AppLocalizations.of(context),
        );
      });
    } finally {
      if (mounted) {
        setState(() => _scanningDrop = false);
      }
    }
  }

  Future<void> _handleDroppedItems(List<DropItem> items) async {
    if (items.isEmpty) return;
    setState(() {
      _dragOver = false;
      _scanningDrop = true;
    });
    try {
      final expanded = await expandDroppedItems(items);
      if (!mounted) return;
      await _ingestDeviceFiles(expanded);
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _loadError = userFacingErrorText(
          error,
          l10n: AppLocalizations.of(context),
        );
      });
    } finally {
      if (mounted) {
        setState(() => _scanningDrop = false);
      }
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

  Widget _hiddenFilesNotice(DesktopSkin skin) {
    final hidden = _hiddenFilesCount;
    final isZh = Localizations.localeOf(context).languageCode == 'zh';
    final summaryText =
        hidden > 0
            ? (isZh
                ? '仅支持 $_supportedTypesSummary · 已隐藏 $hidden 个不支持或空文件'
                : 'Supports $_supportedTypesSummary · $hidden unsupported or empty hidden')
            : (isZh
                ? '支持格式：$_supportedTypesSummary'
                : 'Supported formats: $_supportedTypesSummary');
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: skin.raise,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: skin.line),
        ),
        child: Row(
          children: [
            Icon(DesktopIcons.info, size: 14, color: skin.text3),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                summaryText,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: DesktopType.caption(skin.text3),
              ),
            ),
            if (hidden > 0) ...[
              const SizedBox(width: 10),
              DesktopLink(
                label:
                    _showUnsupported
                        ? (isZh ? '仅看可导入' : 'Importable only')
                        : (isZh ? '显示全部' : 'Show all'),
                trailing: false,
                onPressed:
                    () => setState(() => _showUnsupported = !_showUnsupported),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _dropZone(AppLocalizations l10n, DesktopSkin skin) {
    final borderColor =
        _dragOver ? skin.accent : skin.line2.withValues(alpha: 0.9);
    final fillColor =
        _dragOver ? skin.accent.withValues(alpha: 0.08) : skin.raise;
    final zone = AnimatedContainer(
      duration: MotionToken.reduced(context, MotionToken.fast),
      curve: MotionToken.curve,
      decoration: BoxDecoration(
        color: fillColor,
        borderRadius: BorderRadius.circular(14),
      ),
      child: CustomPaint(
        painter: _DashedRectPainter(
          color: borderColor,
          radius: 14,
          strokeWidth: _dragOver ? 1.6 : 1.2,
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: skin.accent.withValues(alpha: 0.14),
                ),
                child: Icon(DesktopIcons.upload, size: 18, color: skin.accent),
              ),
              const SizedBox(height: 10),
              Text(
                _scanningDrop ? '正在扫描拖入的文件与文件夹…' : '拖拽文件或文件夹到此处',
                style: DesktopType.denseStrong(skin.text),
              ),
              const SizedBox(height: 4),
              Text(
                '支持递归扫描子文件夹 · 格式：$_supportedTypesSummary',
                textAlign: TextAlign.center,
                style: DesktopType.caption(skin.text3),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 10,
                runSpacing: 8,
                alignment: WrapAlignment.center,
                children: [
                  DesktopButton(
                    label: l10n.desktopMediaImportChooseFiles,
                    icon: DesktopIcons.upload,
                    variant: DesktopButtonVariant.soft,
                    onPressed:
                        _scanningDrop ? null : () => _chooseDeviceFiles(l10n),
                  ),
                  DesktopButton(
                    label: '选择文件夹',
                    icon: DesktopIcons.folder,
                    variant: DesktopButtonVariant.ghost,
                    onPressed: _scanningDrop ? null : _chooseDeviceFolder,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    if (!PlatformCapabilities.current().supportsDragAndDropUpload) {
      return zone;
    }
    return DropTarget(
      enable: !_scanningDrop,
      onDragEntered: (_) {
        if (mounted && !_dragOver) setState(() => _dragOver = true);
      },
      onDragExited: (_) {
        if (mounted && _dragOver) setState(() => _dragOver = false);
      },
      onDragDone: (details) {
        unawaited(_handleDroppedItems(details.files));
      },
      child: zone,
    );
  }

  Widget _rejectedReportCard(DesktopSkin skin) {
    if (_rejectedItems.isEmpty) return const SizedBox.shrink();
    final preview = _rejectedItems.take(6).toList(growable: false);
    final overflow = _rejectedItems.length - preview.length;
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
        decoration: BoxDecoration(
          color: skin.bad.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: skin.bad.withValues(alpha: 0.30)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(DesktopIcons.info, size: 14, color: skin.bad),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    '已过滤 ${_rejectedItems.length} 个未添加项目',
                    style: DesktopType.denseStrong(skin.bad),
                  ),
                ),
                GestureDetector(
                  onTap: () => setState(() => _rejectedItems.clear()),
                  behavior: HitTestBehavior.opaque,
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Icon(
                      DesktopIcons.close,
                      size: 13,
                      color: skin.text2,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            for (final item in preview)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        item.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: DesktopType.caption(skin.text2),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      item.reason == ImportRejectReason.emptyFile
                          ? '空文件 (0 B)'
                          : '不支持的格式 .${item.extension.isEmpty ? '?' : item.extension}',
                      style: DesktopType.caption(skin.bad),
                    ),
                  ],
                ),
              ),
            if (overflow > 0)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  '另有 $overflow 项未显示',
                  style: DesktopType.caption(skin.text3),
                ),
              ),
          ],
        ),
      ),
    );
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
            _dropZone(l10n, skin),
            _rejectedReportCard(skin),
          ] else ...[
            _hiddenFilesNotice(skin),
            if (_breadcrumbs.isNotEmpty) ...[
              const SizedBox(height: 8),
              _breadcrumbsView(l10n, skin),
            ],
          ],
          const SizedBox(height: 8),
          if (_sourceCount > 5 || _selectableCount > 0 || _filter.isNotEmpty)
            _listTools(l10n, skin),
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

class _DashedRectPainter extends CustomPainter {
  const _DashedRectPainter({
    required this.color,
    required this.radius,
    required this.strokeWidth,
  });

  final Color color;
  final double radius;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final paint =
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = strokeWidth;
    final rrect = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(radius),
    );
    final path = Path()..addRRect(rrect);
    const dashLength = 6.0;
    const gapLength = 4.0;
    for (final PathMetric metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        final end = (distance + dashLength).clamp(0.0, metric.length);
        canvas.drawPath(metric.extractPath(distance, end), paint);
        distance += dashLength + gapLength;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashedRectPainter oldDelegate) {
    return oldDelegate.color != color ||
        oldDelegate.radius != radius ||
        oldDelegate.strokeWidth != strokeWidth;
  }
}
