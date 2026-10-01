part of 'file_browser_page.dart';

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
    final controller = ref.read(fileBrowserControllerProvider.notifier);
    setState(() => _loading = true);
    try {
      final files = await controller.listFolderOptions(parentId);
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
