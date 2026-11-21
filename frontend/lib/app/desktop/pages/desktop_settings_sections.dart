part of 'desktop_settings_page.dart';

class _ProfileSection extends ConsumerStatefulWidget {
  const _ProfileSection({
    required this.name,
    required this.email,
    required this.role,
    required this.avatarUrl,
    required this.skin,
  });

  final String name;
  final String email;
  final String role;
  final String? avatarUrl;
  final DesktopSkin skin;

  @override
  ConsumerState<_ProfileSection> createState() => _ProfileSectionState();
}

class _ProfileSectionState extends ConsumerState<_ProfileSection> {
  late final TextEditingController _name = TextEditingController(
    text: widget.name,
  );
  late final TextEditingController _email = TextEditingController(
    text: widget.email,
  );
  late String _savedName = widget.name;
  late String _savedEmail = widget.email;
  bool _dirty = false;
  bool _saving = false;
  bool _avatarBusy = false;

  @override
  void didUpdateWidget(_ProfileSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_dirty &&
        (oldWidget.name != widget.name || oldWidget.email != widget.email)) {
      _savedName = widget.name;
      _savedEmail = widget.email;
      _name.text = widget.name;
      _email.text = widget.email;
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final skin = widget.skin;
    final host =
        Uri.tryParse(ref.read(appEnvironmentProvider)?.apiBaseUrl ?? '')?.host;
    final name = _name.text.trim();
    final email = _email.text.trim();
    final invalidName = name.isEmpty || name.length > 40;
    final invalidEmail = !RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email);
    return _Card(
      title: l10n.desktopAccount,
      subtitle: l10n.profileAccountSubtitle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 34,
                backgroundColor: widget.skin.accent,
                backgroundImage:
                    widget.avatarUrl == null || widget.avatarUrl!.isEmpty
                        ? null
                        : NetworkImage(widget.avatarUrl!),
                child:
                    widget.avatarUrl == null || widget.avatarUrl!.isEmpty
                        ? Text(
                          name.isEmpty
                              ? '·'
                              : name.characters.first.toUpperCase(),
                          style: DesktopType.panelTitle(widget.skin.accentInk),
                        )
                        : null,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name, style: DesktopType.panelTitle(widget.skin.text)),
                    const SizedBox(height: 2),
                    Text(
                      email.isEmpty ? '—' : email,
                      style: DesktopType.dense(widget.skin.text3),
                    ),
                  ],
                ),
              ),
              DesktopButton(
                label: l10n.profileChangeAvatar,
                icon: DesktopIcons.upload,
                variant: DesktopButtonVariant.soft,
                busy: _avatarBusy,
                onPressed: _avatarBusy ? null : _pickAvatar,
              ),
              if (widget.avatarUrl?.isNotEmpty == true) ...[
                const SizedBox(width: 8),
                DesktopButton(
                  label: l10n.profileRemoveAvatar,
                  icon: DesktopIcons.trash,
                  variant: DesktopButtonVariant.ghost,
                  busy: _avatarBusy,
                  onPressed: _avatarBusy ? null : _removeAvatar,
                ),
              ],
            ],
          ),
          const SizedBox(height: 18),
          Divider(height: 1, color: skin.line),
          const SizedBox(height: 14),
          DesktopTextField(
            keyName: 'desktop-profile-display-name',
            controller: _name,
            label: l10n.profileDisplayNameField,
            maxLength: 40,
            error: invalidName ? l10n.desktopProfileDisplayNameInvalid : null,
            onChanged: (_) => setState(() => _dirty = true),
          ),
          const SizedBox(height: 14),
          DesktopTextField(
            keyName: 'desktop-profile-email',
            controller: _email,
            label: l10n.profileEmailField,
            error: invalidEmail ? l10n.profileEmailInvalid : null,
            onChanged: (_) => setState(() => _dirty = true),
          ),
          const SizedBox(height: 8),
          _KvRow(
            label: l10n.desktopRole,
            value: widget.role.isEmpty ? '—' : widget.role,
          ),
          _KvRow(
            label: l10n.desktopServer,
            value: (host == null || host.isEmpty) ? '—' : host,
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              DesktopButton(
                label: l10n.profileResetChanges,
                onPressed: _dirty ? _reset : null,
              ),
              const SizedBox(width: 8),
              DesktopButton(
                label: l10n.profileSaveChanges,
                icon: DesktopIcons.check,
                variant: DesktopButtonVariant.primary,
                busy: _saving,
                onPressed:
                    !_dirty || _saving || invalidName || invalidEmail
                        ? null
                        : _save,
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _reset() {
    setState(() {
      _name.text = _savedName;
      _email.text = _savedEmail;
      _dirty = false;
    });
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    final l10n = AppLocalizations.of(context);
    try {
      await ref
          .read(profileCommandServiceProvider)
          .updateProfile(
            displayName: _name.text.trim(),
            email: _email.text.trim(),
          );
      if (!mounted) return;
      await ref.read(authSessionProvider.notifier).reloadProfile();
      if (!mounted) return;
      setState(() {
        _savedName = _name.text.trim();
        _savedEmail = _email.text.trim();
        _dirty = false;
      });
      showDesktopToast(
        context,
        l10n.profileUpdateSuccess,
        icon: DesktopIcons.check,
      );
    } on Object catch (error) {
      if (mounted) {
        showDesktopToast(
          context,
          failureToast(l10n, l10n.profileSaveChanges, error),
          kind: DesktopToastKind.error,
          icon: DesktopIcons.info,
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _pickAvatar() async {
    final l10n = AppLocalizations.of(context);
    try {
      final selected = await FilePick.pickImages(
        dialogTitle: l10n.profileChangeAvatar,
      );
      if (!mounted || selected.isEmpty) return;
      final file = selected.first;
      final length = await file.length();
      if (!mounted) return;
      if (length != null &&
          length > FileSizeThresholds.desktopAvatarUploadMaxBytes) {
        showDesktopToast(
          context,
          l10n.desktopProfileAvatarSizeError,
          kind: DesktopToastKind.error,
        );
        return;
      }
      final extension = file.extension;
      if (extension == null ||
          !['jpg', 'jpeg', 'png', 'webp'].contains(extension)) {
        showDesktopToast(
          context,
          l10n.profileAvatarFormatError,
          kind: DesktopToastKind.error,
        );
        return;
      }
      setState(() => _avatarBusy = true);
      final bytes = await file.readBytes();
      if (!mounted) return;
      if (bytes.isEmpty ||
          bytes.length > FileSizeThresholds.desktopAvatarUploadMaxBytes) {
        showDesktopToast(
          context,
          l10n.desktopProfileAvatarSizeError,
          kind: DesktopToastKind.error,
        );
        return;
      }
      await ref
          .read(profileCommandServiceProvider)
          .uploadAvatar(bytes, file.name);
      if (!mounted) return;
      await ref.read(authSessionProvider.notifier).reloadProfile();
      if (!mounted) return;
      showDesktopToast(
        context,
        l10n.profileAvatarSuccess,
        icon: DesktopIcons.check,
      );
    } on Object catch (error) {
      if (mounted) {
        showDesktopToast(
          context,
          failureToast(l10n, l10n.profileAvatarFailed, error),
          kind: DesktopToastKind.error,
          icon: DesktopIcons.info,
        );
      }
    } finally {
      if (mounted) setState(() => _avatarBusy = false);
    }
  }

  Future<void> _removeAvatar() async {
    if (_avatarBusy) return;
    final l10n = AppLocalizations.of(context);
    final confirmed = await showDesktopDialog<bool>(
      context,
      builder:
          (dialogContext) => DesktopDialog(
            width: 420,
            eyebrow: l10n.desktopAccount,
            title: l10n.profileRemoveAvatar,
            lead: Icon(DesktopIcons.trash, size: 20, color: DesktopPalette.bad),
            content: Text(
              l10n.profileAccountSubtitle,
              style: DesktopType.dense(DesktopSkin.of(context).text2),
            ),
            actions: [
              DesktopButton(
                label: l10n.filesCancel,
                onPressed: () => closeDesktopModal(dialogContext, false),
              ),
              DesktopButton(
                label: l10n.profileRemoveAvatar,
                icon: DesktopIcons.trash,
                variant: DesktopButtonVariant.danger,
                onPressed: () => closeDesktopModal(dialogContext, true),
              ),
            ],
          ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _avatarBusy = true);
    try {
      await ref.read(profileCommandServiceProvider).removeAvatar();
      if (!mounted) return;
      await ref.read(authSessionProvider.notifier).reloadProfile();
      if (!mounted) return;
      showDesktopToast(
        context,
        l10n.profileAvatarRemoved,
        icon: DesktopIcons.trash,
      );
    } on Object catch (error) {
      if (mounted) {
        showDesktopToast(
          context,
          failureToast(l10n, l10n.profileRemoveAvatar, error),
          kind: DesktopToastKind.error,
          icon: DesktopIcons.info,
        );
      }
    } finally {
      if (mounted) setState(() => _avatarBusy = false);
    }
  }
}

class _KvRow extends StatelessWidget {
  const _KvRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final skin = DesktopSkin.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          SizedBox(
            width: 160,
            child: Text(label, style: DesktopType.dense(skin.text3)),
          ),
          Expanded(
            child: Text(value, style: DesktopType.denseStrong(skin.text)),
          ),
        ],
      ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.title, required this.child, this.subtitle});

  final String title;
  final String? subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final skin = DesktopSkin.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: DesktopGlassSurface(
        borderRadius: BorderRadius.circular(DesktopMetrics.radiusCard),
        blur: 24,
        saturation: 1.3,
        child: Container(
          padding: const EdgeInsets.fromLTRB(24, 22, 24, 22),
          decoration: BoxDecoration(
            color: skin.panel,
            borderRadius: BorderRadius.circular(DesktopMetrics.radiusCard),
            border: Border.all(color: skin.line),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title, style: DesktopType.panelTitle(skin.text)),
                        if (subtitle != null) ...[
                          const SizedBox(height: 3),
                          Text(
                            subtitle!,
                            style: DesktopType.caption(skin.text3),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              child,
            ],
          ),
        ),
      ),
    );
  }
}
