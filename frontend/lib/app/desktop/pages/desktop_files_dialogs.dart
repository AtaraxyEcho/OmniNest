part of 'desktop_files_page.dart';

Future<void> _showRenameDialog(
  BuildContext context,
  FileBrowserController controller,
  FileNode node,
) async {
  final l10n = AppLocalizations.of(context);
  final name = await showDesktopDialog<String>(
    context,
    builder:
        (dialogContext) => _NameDialog(
          eyebrow: l10n.filesRename,
          title: node.name,
          hint: l10n.desktopFilesRenameHint,
          confirmLabel: l10n.desktopFilesSave,
          initial: node.name,
          icon: node.isFolder ? DesktopIcons.folder : DesktopIcons.file,
        ),
  );
  if (name == null || name == node.name) {
    return;
  }
  try {
    await controller.renameFile(node, name);
  } on Object catch (error) {
    if (context.mounted) {
      showDesktopToast(
        context,
        failureToast(l10n, l10n.filesRename, error),
        kind: DesktopToastKind.error,
        icon: DesktopIcons.info,
      );
    }
  }
}

/// 永久删除确认：先算清"会失去什么"，再让用户按下不可撤销的那颗键。
Future<void> _showPurgeDialog(
  BuildContext context,
  FileBrowserController controller,
  List<FileNode> nodes,
) async {
  if (nodes.isEmpty) {
    return;
  }
  final l10n = AppLocalizations.of(context);
  final skin = DesktopSkin.of(context);
  final totalBytes = nodes.fold<int>(
    0,
    (sum, node) => sum + (node.isFolder ? 0 : node.sizeBytes),
  );
  final confirmed = await showDesktopDialog<bool>(
    context,
    builder:
        (dialogContext) => DesktopDialog(
          width: 460,
          eyebrow: l10n.filesRecycleBin,
          title: l10n.desktopFilesDeleteForever,
          lead: Icon(DesktopIcons.trash, size: 20, color: DesktopPalette.bad),
          content: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                l10n.desktopFilesRecycleNoticeBody,
                style: DesktopType.dense(skin.text2),
              ),
              const SizedBox(height: 16),
              DesktopKeyValues(
                entries: [
                  MapEntry(l10n.desktopFilesItemsGroup, '${nodes.length}'),
                  MapEntry(l10n.desktopFilesSize, formatFileSize(totalBytes)),
                ],
              ),
            ],
          ),
          actions: [
            DesktopButton(
              label: l10n.filesCancel,
              onPressed: () => closeDesktopModal(dialogContext, false),
            ),
            DesktopButton(
              label: l10n.desktopFilesDeleteForever,
              icon: DesktopIcons.trash,
              variant: DesktopButtonVariant.danger,
              onPressed: () => closeDesktopModal(dialogContext, true),
            ),
          ],
        ),
  );
  if (confirmed != true) {
    return;
  }
  try {
    if (nodes.length == 1) {
      await controller.purgeFile(nodes.first);
    } else {
      await controller.batchPurgeFiles();
    }
  } on Object catch (error) {
    if (context.mounted) {
      showDesktopToast(
        context,
        failureToast(l10n, l10n.desktopFilesDeleteForever, error),
        kind: DesktopToastKind.error,
        icon: DesktopIcons.info,
      );
    }
  }
}

Future<void> _showShareDialog(
  BuildContext context,
  FileBrowserController controller,
  FileNode node,
) async {
  await showDesktopDialog<void>(
    context,
    builder:
        (dialogContext) => _ShareLinkDialog(controller: controller, node: node),
  );
}

class _NameDialog extends StatefulWidget {
  const _NameDialog({
    required this.eyebrow,
    required this.title,
    required this.hint,
    required this.confirmLabel,
    required this.icon,
    this.initial = '',
  });

  final String eyebrow;
  final String title;
  final String hint;
  final String confirmLabel;
  final IconData icon;
  final String initial;

  @override
  State<_NameDialog> createState() => _NameDialogState();
}

class _NameDialogState extends State<_NameDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initial,
  );
  late final ValueNotifier<bool> _valid = ValueNotifier<bool>(
    widget.initial.trim().isNotEmpty,
  );

  @override
  void dispose() {
    _controller.dispose();
    _valid.dispose();
    super.dispose();
  }

  void _submit() {
    final value = _controller.text.trim();
    if (value.isEmpty) {
      return;
    }
    closeDesktopModal(context, value);
  }

  @override
  Widget build(BuildContext context) {
    return DesktopDialog(
      width: 460,
      eyebrow: widget.eyebrow,
      title: widget.title,
      content: DesktopTextField(
        keyName: 'desktop-files-name-field',
        controller: _controller,
        hint: widget.hint,
        autofocus: true,
        selectAllOnFocus: true,
        height: 40,
        prefixIcon: widget.icon,
        onChanged: (value) => _valid.value = value.trim().isNotEmpty,
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        DesktopButton(
          label: AppLocalizations.of(context).filesCancel,
          onPressed: () => closeDesktopModal(context),
        ),
        ValueListenableBuilder<bool>(
          valueListenable: _valid,
          builder:
              (context, valid, _) => DesktopButton(
                label: widget.confirmLabel,
                variant: DesktopButtonVariant.primary,
                onPressed: valid ? _submit : null,
              ),
        ),
      ],
    );
  }
}

/// 分享链接创建表单与原型访问策略保持一致，设置由服务端保存并同步。
class _ShareLinkDialog extends ConsumerStatefulWidget {
  const _ShareLinkDialog({required this.controller, required this.node});

  final FileBrowserController controller;
  final FileNode node;

  @override
  ConsumerState<_ShareLinkDialog> createState() => _ShareLinkDialogState();
}

class _ShareLinkDialogState extends ConsumerState<_ShareLinkDialog> {
  final List<FileShareLink> _links = <FileShareLink>[];
  final TextEditingController _password = TextEditingController();
  final TextEditingController _recipientQuery = TextEditingController();
  final List<FileShareRecipient> _recipients = <FileShareRecipient>[];
  List<FileShareRecipient> _recipientSuggestions = const [];
  Timer? _recipientSearchTimer;
  int _recipientSearchGeneration = 0;
  bool _busy = false;
  bool _loadingLinks = true;
  String? _baseUrl;
  _ShareAccessMode _accessMode = _ShareAccessMode.anyone;
  int _expiryDays = 7;
  int _maxAccess = 0;
  bool _allowDownloads = true;
  bool _originalQuality = false;
  bool _includeLocation = false;

  bool get _hasMediaPolicies {
    if (widget.node.isFolder) return false;
    final mimeType = widget.node.mimeType?.toLowerCase() ?? '';
    return mimeType.startsWith('image/') || mimeType.startsWith('video/');
  }

  @override
  void initState() {
    super.initState();
    unawaited(_resolveBaseUrl());
    unawaited(_loadExistingLinks());
  }

  @override
  void dispose() {
    _password.dispose();
    _recipientQuery.dispose();
    _recipientSearchTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadExistingLinks() async {
    try {
      final links = await widget.controller.listShareLinksForResource(
        widget.node,
      );
      if (!mounted) return;
      setState(() {
        _links
          ..clear()
          ..addAll(links);
        _loadingLinks = false;
      });
    } on Object {
      if (mounted) setState(() => _loadingLinks = false);
    }
  }

  void _searchRecipients(String query) {
    _recipientSearchTimer?.cancel();
    final needle = query.trim();
    if (needle.length < 2) {
      setState(() => _recipientSuggestions = const []);
      return;
    }
    final generation = ++_recipientSearchGeneration;
    _recipientSearchTimer = Timer(const Duration(milliseconds: 300), () {
      unawaited(() async {
        try {
          final users = await widget.controller.searchShareRecipients(needle);
          if (!mounted || generation != _recipientSearchGeneration) return;
          setState(
            () =>
                _recipientSuggestions = users
                    .where(
                      (user) => !_recipients.any((item) => item.id == user.id),
                    )
                    .toList(growable: false),
          );
        } on Object {
          if (!mounted || generation != _recipientSearchGeneration) return;
          setState(() => _recipientSuggestions = const []);
        }
      }());
    });
  }

  void _addRecipient(FileShareRecipient recipient) {
    if (_recipients.any((item) => item.id == recipient.id)) return;
    setState(() {
      _recipients.add(recipient);
      _recipientSuggestions = const [];
      _recipientQuery.clear();
    });
  }

  Future<void> _resolveBaseUrl() async {
    try {
      final url = await ref.read(webShareBaseUrlResolverProvider).resolve();
      if (mounted) {
        setState(() => _baseUrl = url);
      }
    } on Object {
      // 基址缺失时只是不给复制入口，链接本身仍可创建。
    }
  }

  Future<void> _create() async {
    if (_loadingLinks) return;
    setState(() => _busy = true);
    try {
      if (_accessMode == _ShareAccessMode.off) {
        for (final link in List<FileShareLink>.of(_links)) {
          await widget.controller.revokeShare(link);
        }
        if (!mounted) return;
        setState(_links.clear);
        showDesktopToast(
          context,
          AppLocalizations.of(context).filesSharingDisabled,
          icon: DesktopIcons.close,
        );
        return;
      }
      final link = await widget.controller.createShareLink(
        widget.node,
        password:
            _accessMode == _ShareAccessMode.passcode &&
                    _password.text.trim().isNotEmpty
                ? _password.text.trim()
                : null,
        generatePassword:
            _accessMode == _ShareAccessMode.passcode &&
            _password.text.trim().isEmpty,
        expiresAt:
            _expiryDays <= 0
                ? null
                : () {
                  final now = DateTime.now();
                  return DateTime(now.year, now.month, now.day + _expiryDays);
                }(),
        maxAccessCount: _maxAccess <= 0 ? null : _maxAccess,
        allowDownloads: _allowDownloads,
        originalQuality: _originalQuality,
        includeLocation: _includeLocation,
        recipientUserIds: _recipients.map((user) => user.id).toList(),
      );
      if (!mounted) {
        return;
      }
      setState(() => _links.insert(0, link));
    } on Object catch (error) {
      if (!mounted) {
        return;
      }
      final l10n = AppLocalizations.of(context);
      showDesktopToast(
        context,
        failureToast(l10n, l10n.filesCreateShareLink, error),
        kind: DesktopToastKind.error,
        icon: DesktopIcons.info,
      );
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _revoke(FileShareLink link) async {
    await widget.controller.revokeShare(link);
    if (!mounted) {
      return;
    }
    setState(() => _links.removeWhere((item) => item.id == link.id));
  }

  Future<void> _copy(FileShareLink link) async {
    if (_baseUrl == null || link.shareCode.isEmpty) {
      return;
    }
    final l10n = AppLocalizations.of(context);
    final copied = await copyTextToClipboard('$_baseUrl/#/s/${link.shareCode}');
    if (!mounted) {
      return;
    }
    showDesktopToast(
      context,
      copied ? l10n.desktopFilesLinkCopied : l10n.filesCopyLink,
      icon: DesktopIcons.copy,
      kind: copied ? DesktopToastKind.success : DesktopToastKind.warn,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final skin = DesktopSkin.of(context);
    return DesktopDialog(
      eyebrow: l10n.filesShare,
      title: widget.node.name,
      lead: Icon(DesktopIcons.share, size: 20, color: skin.accent),
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _shareOptionRow(l10n.filesShareAccess, [
            DesktopChipButton(
              label: l10n.filesShareOff,
              selected: _accessMode == _ShareAccessMode.off,
              onTap: () => setState(() => _accessMode = _ShareAccessMode.off),
            ),
            DesktopChipButton(
              label: l10n.filesSharePublic,
              selected: _accessMode == _ShareAccessMode.anyone,
              onTap:
                  () => setState(() => _accessMode = _ShareAccessMode.anyone),
            ),
            DesktopChipButton(
              label: l10n.filesShareExtract,
              selected: _accessMode == _ShareAccessMode.passcode,
              onTap:
                  () => setState(() => _accessMode = _ShareAccessMode.passcode),
            ),
          ], skin),
          if (_accessMode != _ShareAccessMode.off) ...[
            if (_accessMode == _ShareAccessMode.passcode) ...[
              const SizedBox(height: 10),
              DesktopTextField(
                keyName: 'desktop-files-share-passcode',
                controller: _password,
                label: l10n.filesSharePasscode,
                hint: l10n.filesSharePasscodeHint,
                maxLength: 128,
              ),
            ],
            const SizedBox(height: 10),
            DesktopTextField(
              keyName: 'desktop-files-share-recipient-search',
              controller: _recipientQuery,
              label: l10n.filesShareRecipients,
              hint: l10n.filesShareRecipientsHint,
              prefixIcon: DesktopIcons.search,
              onChanged: _searchRecipients,
            ),
            if (_recipients.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final recipient in _recipients)
                      InputChip(
                        label: Text(recipient.label),
                        onDeleted:
                            () => setState(() => _recipients.remove(recipient)),
                      ),
                  ],
                ),
              ),
            if (_recipientSuggestions.isNotEmpty)
              Container(
                margin: const EdgeInsets.only(top: 4),
                decoration: BoxDecoration(
                  color: skin.panelSolid,
                  border: Border.all(color: skin.line),
                  borderRadius: BorderRadius.circular(
                    DesktopMetrics.radiusSmall,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final recipient in _recipientSuggestions)
                      TextButton(
                        onPressed: () => _addRecipient(recipient),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            '${recipient.label} · @${recipient.username}',
                          ),
                        ),
                      ),
                  ],
                ),
              ),
          ],
          const SizedBox(height: 10),
          _shareOptionRow(l10n.filesShareExpires, [
            for (final days in const [1, 7, 30])
              DesktopChipButton(
                label: l10n.filesShareExpiryDays(days),
                selected: _expiryDays == days,
                onTap: () => setState(() => _expiryDays = days),
              ),
            DesktopChipButton(
              label: l10n.filesSharePermanent,
              selected: _expiryDays == 0,
              onTap: () => setState(() => _expiryDays = 0),
            ),
          ], skin),
          const SizedBox(height: 10),
          _shareOptionRow(l10n.filesShareRemaining, [
            DesktopChipButton(
              label: l10n.filesShareUnlimited,
              selected: _maxAccess == 0,
              onTap: () => setState(() => _maxAccess = 0),
            ),
            for (final limit in const [10, 50, 100])
              DesktopChipButton(
                label: '$limit',
                selected: _maxAccess == limit,
                onTap: () => setState(() => _maxAccess = limit),
              ),
          ], skin),
          const SizedBox(height: 10),
          _sharePolicyRow(
            title: l10n.filesAllowDownloads,
            subtitle: l10n.filesAllowDownloadsSubtitle,
            value: _allowDownloads,
            onChanged: (value) => setState(() => _allowDownloads = value),
            skin: skin,
          ),
          if (_hasMediaPolicies) ...[
            _sharePolicyRow(
              title: l10n.filesOriginalQuality,
              subtitle: l10n.filesOriginalQualitySubtitle,
              value: _originalQuality,
              onChanged: (value) => setState(() => _originalQuality = value),
              skin: skin,
            ),
            _sharePolicyRow(
              title: l10n.filesIncludeLocation,
              subtitle: l10n.filesIncludeLocationSubtitle,
              value: _includeLocation,
              onChanged: (value) => setState(() => _includeLocation = value),
              skin: skin,
            ),
          ],
          const SizedBox(height: 16),
          Text(
            l10n.filesSharesEmptyMessage,
            style: DesktopType.caption(skin.text3),
          ),
          if (_links.isNotEmpty) const SizedBox(height: 14),
          for (final link in _links)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: skin.raise,
                  borderRadius: BorderRadius.circular(
                    DesktopMetrics.radiusSmall,
                  ),
                  border: Border.all(color: skin.line),
                ),
                child: Row(
                  children: [
                    Icon(DesktopIcons.link, size: 14, color: skin.accent),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _baseUrl == null
                                ? link.shareCode
                                : '$_baseUrl/#/s/${link.shareCode}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: DesktopType.mono(skin.text2),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            l10n.desktopFilesShareVisits(link.accessCount),
                            style: DesktopType.nano(skin.text3),
                          ),
                          if (link.generatedPassword?.isNotEmpty == true)
                            Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: Text(
                                l10n.filesSharePasswordLabel(
                                  link.generatedPassword!,
                                ),
                                style: DesktopType.nano(skin.accent),
                              ),
                            ),
                        ],
                      ),
                    ),
                    DesktopButton(
                      label: l10n.filesCopyLink,
                      icon: DesktopIcons.copy,
                      variant: DesktopButtonVariant.ghost,
                      onPressed:
                          _baseUrl == null || link.shareCode.isEmpty
                              ? null
                              : () => unawaited(_copy(link)),
                    ),
                    const SizedBox(width: 6),
                    DesktopButton(
                      label: l10n.desktopFilesRevoke,
                      icon: DesktopIcons.close,
                      variant: DesktopButtonVariant.ghost,
                      onPressed: () => unawaited(_revoke(link)),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
      actions: [
        DesktopButton(
          label: l10n.filesClose,
          onPressed: () => closeDesktopModal(context),
        ),
        DesktopButton(
          label:
              _accessMode == _ShareAccessMode.off
                  ? l10n.filesShareOff
                  : l10n.desktopFilesCreateLink,
          icon:
              _accessMode == _ShareAccessMode.off
                  ? DesktopIcons.close
                  : DesktopIcons.link,
          variant:
              _accessMode == _ShareAccessMode.off
                  ? DesktopButtonVariant.danger
                  : DesktopButtonVariant.primary,
          busy: _busy,
          onPressed: _busy || _loadingLinks ? null : () => unawaited(_create()),
        ),
      ],
    );
  }
}

enum _ShareAccessMode { off, anyone, passcode }

Widget _sharePolicyRow({
  required String title,
  required String subtitle,
  required bool value,
  required ValueChanged<bool> onChanged,
  required DesktopSkin skin,
}) {
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 7),
    child: Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: DesktopType.caption(skin.text2)),
              const SizedBox(height: 2),
              Text(subtitle, style: DesktopType.nano(skin.text3)),
            ],
          ),
        ),
        const SizedBox(width: 12),
        DesktopToggle(value: value, onChanged: onChanged, label: title),
      ],
    ),
  );
}

Widget _shareOptionRow(String label, List<Widget> options, DesktopSkin skin) {
  return Row(
    crossAxisAlignment: CrossAxisAlignment.center,
    children: [
      SizedBox(
        width: 96,
        child: Text(label, style: DesktopType.caption(skin.text3)),
      ),
      Expanded(child: Wrap(spacing: 6, runSpacing: 6, children: options)),
    ],
  );
}

/// 详情与历史版本（样例 `DetailsDialog` 的 Versions 页）。
class _DetailsDialog extends StatefulWidget {
  const _DetailsDialog({required this.controller, required this.node});

  final FileBrowserController controller;
  final FileNode node;

  @override
  State<_DetailsDialog> createState() => _DetailsDialogState();
}

class _DetailsDialogState extends State<_DetailsDialog> {
  List<FileVersion>? _versions;
  bool _loading = true;
  Object? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final versions = await widget.controller.listFileVersions(widget.node.id);
      if (!mounted) {
        return;
      }
      setState(() {
        _versions = versions;
        _loading = false;
      });
    } on Object catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = error;
        _loading = false;
      });
    }
  }

  Future<void> _restore(FileVersion version) async {
    final l10n = AppLocalizations.of(context);
    try {
      await widget.controller.restoreFileVersion(widget.node, version.id);
      if (!mounted) {
        return;
      }
      showDesktopToast(context, l10n.filesRestore, icon: DesktopIcons.undo);
      setState(() {
        _loading = true;
        _error = null;
      });
      unawaited(_load());
    } on Object catch (error) {
      if (!mounted) {
        return;
      }
      showDesktopToast(
        context,
        failureToast(l10n, l10n.filesRestore, error),
        kind: DesktopToastKind.error,
        icon: DesktopIcons.info,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final skin = DesktopSkin.of(context);
    return DesktopDialog(
      width: 620,
      eyebrow: l10n.desktopFilesDetails,
      title: widget.node.name,
      lead: Icon(_fileIcon(widget.node), size: 20, color: skin.accent),
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DesktopKeyValues(
            entries: [
              MapEntry(
                l10n.desktopFilesSize,
                formatFileSize(widget.node.sizeBytes),
              ),
              MapEntry(
                l10n.desktopFilesModified,
                _formatDate(widget.node.updatedAt),
              ),
              MapEntry(l10n.filesAccess, widget.node.normalizedPath),
            ],
          ),
          const SizedBox(height: 18),
          Text(
            l10n.desktopFilesVersions.toUpperCase(),
            style: DesktopType.eyebrow(skin.text3),
          ),
          const SizedBox(height: 8),
          if (_loading)
            const SizedBox(height: 40)
          else if (_error != null)
            Text(
              failureToast(l10n, l10n.desktopFilesVersions, _error!),
              style: DesktopType.caption(DesktopPalette.bad),
            )
          else
            for (final version in _versions ?? const <FileVersion>[])
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color:
                            version.isCurrent
                                ? skin.accentWash(0.14)
                                : skin.raise,
                        borderRadius: BorderRadius.circular(
                          DesktopMetrics.radiusPill,
                        ),
                      ),
                      child: Text(
                        'v${version.versionNo}',
                        style: DesktopType.nano(
                          version.isCurrent ? skin.accent : skin.text3,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        '${formatFileSize(version.sizeBytes)} · '
                        '${_formatDate(version.createdAt)}',
                        style: DesktopType.caption(skin.text2),
                      ),
                    ),
                    if (!version.isCurrent)
                      DesktopButton(
                        label: l10n.filesRestore,
                        icon: DesktopIcons.undo,
                        variant: DesktopButtonVariant.ghost,
                        onPressed: () => unawaited(_restore(version)),
                      ),
                  ],
                ),
              ),
        ],
      ),
      actions: [
        DesktopButton(
          label: l10n.filesClose,
          onPressed: () => closeDesktopModal(context),
        ),
      ],
    );
  }
}
