part of 'movie_management.dart';

class MediaLibraryAccessPanel extends ConsumerWidget {
  const MediaLibraryAccessPanel({required this.source, super.key});

  final VideoLibrarySource source;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final access = ref.watch(mediaLibraryAccessProvider(source.id));
    return access.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error:
          (error, _) => SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: MovieNoticePanel(
              icon: Icons.error_outline_rounded,
              title: l10n.videoLibraryAccessLoadFailed,
              message: movieErrorMessage(error),
            ),
          ),
      data:
          (settings) => _MediaLibraryAccessForm(
            key: ValueKey('${source.id}:${settings.version}'),
            source: source,
            settings: settings,
          ),
    );
  }
}

class _MediaLibraryAccessForm extends ConsumerStatefulWidget {
  const _MediaLibraryAccessForm({
    required this.source,
    required this.settings,
    super.key,
  });

  final VideoLibrarySource source;
  final MediaLibraryAccessSettings settings;

  @override
  ConsumerState<_MediaLibraryAccessForm> createState() =>
      _MediaLibraryAccessFormState();
}

class _MediaLibraryAccessFormState
    extends ConsumerState<_MediaLibraryAccessForm> {
  late MediaLibraryVisibility _visibility;
  late Set<String> _selectedUserIds;
  final TextEditingController _searchController = TextEditingController();
  String _query = '';
  int _page = 0;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _visibility = widget.settings.visibility;
    _selectedUserIds = {...widget.settings.selectedUserIds};
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final users = ref.watch(
      mediaLibraryAccessUsersProvider((query: _query, page: _page)),
    );
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          RadioGroup<MediaLibraryVisibility>(
            groupValue: _visibility,
            onChanged: (value) {
              if (_saving || value == null) {
                return;
              }
              setState(() => _visibility = value);
            },
            child: Column(
              children:
                  MediaLibraryVisibility.values
                      .map(
                        (visibility) => RadioListTile<MediaLibraryVisibility>(
                          contentPadding: EdgeInsets.zero,
                          value: visibility,
                          enabled: !_saving,
                          title: Text(_visibilityLabel(l10n, visibility)),
                          subtitle: Text(_visibilityHint(l10n, visibility)),
                        ),
                      )
                      .toList(),
            ),
          ),
          if (_visibility == MediaLibraryVisibility.selectedUsers) ...[
            const SizedBox(height: 10),
            TextField(
              controller: _searchController,
              enabled: !_saving,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                labelText: l10n.videoLibraryAccessSearch,
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: IconButton(
                  tooltip: l10n.videoLibraryAccessSearch,
                  onPressed:
                      _saving
                          ? null
                          : () => setState(() {
                            _query = _searchController.text.trim();
                            _page = 0;
                          }),
                  icon: const Icon(Icons.arrow_forward_rounded),
                ),
              ),
              onSubmitted:
                  (value) => setState(() {
                    _query = value.trim();
                    _page = 0;
                  }),
            ),
            const SizedBox(height: 8),
            Text(
              l10n.videoLibraryAccessSelectedCount(_selectedUserIds.length),
              style: TextStyle(
                color: context.videoColors.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
            users.when(
              loading: () => const LinearProgressIndicator(),
              error:
                  (error, _) => MovieNoticePanel(
                    icon: Icons.error_outline_rounded,
                    title: l10n.videoLibraryAccessUsersFailed,
                    message: movieErrorMessage(error),
                  ),
              data: (page) {
                final userList =
                    page.items.isEmpty
                        ? <Widget>[
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 20),
                            child: Text(
                              l10n.videoLibraryAccessNoUsers,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: context.videoColors.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ]
                        : page.items.map<Widget>((user) {
                          final selected = _selectedUserIds.contains(user.id);
                          return CheckboxListTile(
                            contentPadding: EdgeInsets.zero,
                            value: selected,
                            onChanged:
                                _saving
                                    ? null
                                    : (value) => setState(() {
                                      final next = {..._selectedUserIds};
                                      if (value == true) {
                                        next.add(user.id);
                                      } else {
                                        next.remove(user.id);
                                      }
                                      _selectedUserIds = next;
                                    }),
                            title: Text(
                              user.displayName.isEmpty
                                  ? user.username
                                  : user.displayName,
                            ),
                            subtitle: Text('@${user.username}'),
                          );
                        }).toList();
                return Column(
                  children: [
                    ...userList,
                    if (page.totalPages > 1)
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          IconButton(
                            tooltip: l10n.corePrevious,
                            onPressed:
                                _saving || page.page <= 0
                                    ? null
                                    : () => setState(() => _page--),
                            icon: const Icon(Icons.chevron_left_rounded),
                          ),
                          Text('${page.page + 1} / ${page.totalPages}'),
                          IconButton(
                            tooltip: l10n.coreNext,
                            onPressed:
                                _saving || page.page + 1 >= page.totalPages
                                    ? null
                                    : () => setState(() => _page++),
                            icon: const Icon(Icons.chevron_right_rounded),
                          ),
                        ],
                      ),
                  ],
                );
              },
            ),
          ],
          const SizedBox(height: 16),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.icon(
              onPressed: _saving ? null : _save,
              icon:
                  _saving
                      ? const SizedBox.square(
                        dimension: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                      : const Icon(Icons.save_outlined),
              label: Text(l10n.videoLibraryAccessSave),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final l10n = AppLocalizations.of(context);
    try {
      await ref
          .read(videoLibrarySourceActionsProvider)
          .updateAccess(
            sourceId: widget.source.id,
            visibility: _visibility,
            userIds:
                _visibility == MediaLibraryVisibility.selectedUsers
                    ? _selectedUserIds
                    : const <String>{},
            expectedVersion: widget.settings.version,
          );
      if (!mounted) {
        return;
      }
      showMovieFeedback(context, l10n.videoLibraryAccessSaved);
    } on Exception catch (error) {
      if (!mounted) {
        return;
      }
      showMovieFeedback(context, movieErrorMessage(error), isError: true);
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }
}

String _visibilityLabel(
  AppLocalizations l10n,
  MediaLibraryVisibility visibility,
) {
  return switch (visibility) {
    MediaLibraryVisibility.private => l10n.videoLibraryVisibilityPrivate,
    MediaLibraryVisibility.selectedUsers => l10n.videoLibraryVisibilitySelected,
    MediaLibraryVisibility.allMembers => l10n.videoLibraryVisibilityMembers,
  };
}

String _visibilityHint(
  AppLocalizations l10n,
  MediaLibraryVisibility visibility,
) {
  return switch (visibility) {
    MediaLibraryVisibility.private => l10n.videoLibraryVisibilityPrivateHint,
    MediaLibraryVisibility.selectedUsers =>
      l10n.videoLibraryVisibilitySelectedHint,
    MediaLibraryVisibility.allMembers => l10n.videoLibraryVisibilityMembersHint,
  };
}
