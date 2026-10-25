part of 'file_browser_page.dart';

/// 打开个人空间文件夹选择器。
///
/// 返回 `''` 表示个人空间根目录，`null` 表示用户取消。
Future<String?> showFilesFolderPickerDialog({required BuildContext context}) {
  return showFilesDialog<String>(
    context: context,
    builder: (ctx) => const _FolderPickerDialog(),
  );
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
  final ScrollController _scrollController = ScrollController();
  List<FileNode> _folders = [];
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = true;
  String? _error;
  int _page = 0;
  int _loadGeneration = 0;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _loadFolders(reset: true);
  }

  Future<void> _loadFolders({bool reset = false}) async {
    if (!reset && (_loading || _loadingMore || !_hasMore)) {
      return;
    }
    final generation = ++_loadGeneration;
    final parentId = _currentParentId;
    final page = reset ? 0 : _page + 1;
    final controller = ref.read(fileBrowserControllerProvider.notifier);
    setState(() {
      if (reset) {
        _folders = [];
        _page = 0;
        _hasMore = true;
      }
      _loading = reset;
      _loadingMore = !reset;
      _error = null;
    });
    try {
      final result = await controller.listFolderOptionsPage(
        parentId,
        page: page,
      );
      if (!mounted || generation != _loadGeneration) {
        return;
      }
      setState(() {
        final existingIds = _folders.map((folder) => folder.id).toSet();
        _folders.addAll(
          result.items.where(
            (node) => node.isFolder && !existingIds.contains(node.id),
          ),
        );
        _page = result.page;
        _hasMore = result.hasNextPage;
        _loading = false;
        _loadingMore = false;
      });
      // 当前页只有普通文件时继续向后找目录，不能把“本页没有目录”显示成空文件夹。
      if (_folders.isEmpty && _hasMore) {
        _loadFolders();
      }
    } catch (_) {
      if (!mounted || generation != _loadGeneration) {
        return;
      }
      setState(() {
        _loading = false;
        _loadingMore = false;
        _error = AppLocalizations.of(context).filesLoadFailed('');
      });
    }
  }

  void _onScroll() {
    if (_scrollController.position.extentAfter < 160) {
      _loadFolders();
    }
  }

  Future<void> _createFolder() async {
    final l10n = AppLocalizations.of(context);
    await _showNameDialog(
      context: context,
      title: l10n.filesNewFolder,
      actionLabel: l10n.filesCreate,
      labelText: l10n.filesFolderName,
      initialValue: l10n.filesNewFolderDefault,
      onSubmit: (name) async {
        await ref
            .read(fileBrowserControllerProvider.notifier)
            .createFolderInParent(_currentParentId, name);
        if (!mounted) {
          return;
        }
        await _loadFolders(reset: true);
      },
    );
  }

  @override
  void dispose() {
    _loadGeneration++;
    _scrollController.dispose();
    super.dispose();
  }

  void _enterFolder(FileNode folder) {
    setState(() {
      _breadcrumbs.add(_FolderBreadcrumb(id: folder.id, name: folder.name));
      _currentParentId = folder.id;
    });
    _loadFolders(reset: true);
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
    _loadFolders(reset: true);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final currentName =
        _breadcrumbs.isEmpty ? l10n.filesRootDirectory : _breadcrumbs.last.name;
    return FilesDialogFrame(
      title: l10n.filesSelectTargetFolder,
      body: ConstrainedBox(
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
                    _loading && _folders.isEmpty
                        ? const Center(child: CircularProgressIndicator())
                        : _error != null && _folders.isEmpty
                        ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.cloud_off_outlined,
                                size: 36,
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant
                                    .withValues(alpha: 0.5),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                _error!,
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color:
                                      Theme.of(
                                        context,
                                      ).colorScheme.onSurfaceVariant,
                                ),
                              ),
                              const SizedBox(height: 8),
                              TextButton(
                                onPressed: () => _loadFolders(reset: true),
                                child: Text(l10n.commonRetry),
                              ),
                            ],
                          ),
                        )
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
                          controller: _scrollController,
                          itemCount: _folders.length + (_loadingMore ? 1 : 0),
                          itemBuilder: (context, index) {
                            if (index >= _folders.length) {
                              return const Padding(
                                padding: EdgeInsets.all(12),
                                child: Center(
                                  child: SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  ),
                                ),
                              );
                            }
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
        TextButton.icon(
          onPressed: _createFolder,
          icon: const Icon(Icons.create_new_folder_outlined, size: 18),
          label: Text(l10n.filesNewFolder),
        ),
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
