part of 'share_link_sheet.dart';

/// 分享面板的移动壳层形态：原型 `ShareLinksSheet` 的 `.notif-group-label`
/// 眉标 + `.notif-toggle-row` 开关行 + `.field-input` 字段 + `.segmented`
/// 分段 + `.accent-square-btn` 主行动。
///
/// 原型还画了「Allow downloads」开关行，但分享创建契约
/// （CreateShareLinkRequest / FileShareLink）没有该字段，因此不实现，
/// 避免做出无效控件。
class _HostedCreateSection extends StatelessWidget {
  const _HostedCreateSection({
    required this.enablePassword,
    required this.onPasswordChanged,
    required this.passwordMode,
    required this.onPasswordModeChanged,
    required this.passwordController,
    required this.expiryPreset,
    required this.onExpiryPresetChanged,
    required this.optionsExpanded,
    required this.onToggleOptions,
    required this.maxAccessController,
    required this.busy,
    required this.onSubmit,
    required this.errorMessage,
  });

  final bool enablePassword;
  final ValueChanged<bool> onPasswordChanged;
  final _PasswordMode passwordMode;
  final ValueChanged<_PasswordMode> onPasswordModeChanged;
  final TextEditingController passwordController;
  final _ShareExpiryPreset expiryPreset;
  final ValueChanged<_ShareExpiryPreset> onExpiryPresetChanged;
  final bool optionsExpanded;
  final VoidCallback onToggleOptions;
  final TextEditingController maxAccessController;
  final bool busy;
  final VoidCallback onSubmit;

  /// 创建失败摘要；为空时不渲染错误行。
  final String? errorMessage;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _HostedToggleRow(
          icon: Icons.key_outlined,
          title: l10n.filesSetPassword,
          subtitle:
              enablePassword
                  ? l10n.filesPasswordRequired
                  : l10n.filesNoPasswordAnyone,
          value: enablePassword,
          onChanged: onPasswordChanged,
        ),
        if (enablePassword) ...[
          _HostedGroupLabel(label: l10n.filesShareExtract),
          Align(
            alignment: Alignment.centerLeft,
            child: MobileSegmentedControl<_PasswordMode>(
              values: const [_PasswordMode.random, _PasswordMode.custom],
              selected: passwordMode,
              labelBuilder:
                  (mode) => switch (mode) {
                    _PasswordMode.random => l10n.filesRandomGenerate,
                    _PasswordMode.custom => l10n.filesCustomPassword,
                  },
              onSelected: onPasswordModeChanged,
            ),
          ),
          if (passwordMode == _PasswordMode.custom) ...[
            const SizedBox(height: 12),
            TextField(
              controller: passwordController,
              obscureText: true,
              enableSuggestions: false,
              autocorrect: false,
              textInputAction: TextInputAction.done,
              style: const TextStyle(
                fontSize: 13, // ignore: font_size_whitelist
                color: MobileEnvColors.ink,
              ),
              decoration: _hostedFieldDecoration(
                label: l10n.filesCustomPassword,
                hint: l10n.filesEnterPassword,
              ),
            ),
          ],
        ],
        _HostedGroupLabel(label: l10n.filesExpiryTime),
        Align(
          alignment: Alignment.centerLeft,
          child: MobileSegmentedControl<_ShareExpiryPreset>(
            values: _ShareExpiryPreset.values,
            selected: expiryPreset,
            labelBuilder:
                (preset) => switch (preset) {
                  _ShareExpiryPreset.permanent => l10n.filesSharePermanent,
                  _ShareExpiryPreset.days7 => l10n.filesShareExpiryDays(7),
                  _ShareExpiryPreset.days30 => l10n.filesShareExpiryDays(30),
                },
            onSelected: onExpiryPresetChanged,
          ),
        ),
        _HostedOptionsToggle(expanded: optionsExpanded, onTap: onToggleOptions),
        if (optionsExpanded) ...[
          const SizedBox(height: 10),
          TextField(
            controller: maxAccessController,
            keyboardType: TextInputType.number,
            style: const TextStyle(
              fontSize: 13, // ignore: font_size_whitelist
              color: MobileEnvColors.ink,
            ),
            decoration: _hostedFieldDecoration(
              label: l10n.filesMaxAccessCount,
              hint: l10n.filesNoLimit,
            ),
          ),
        ],
        const SizedBox(height: 16),
        _HostedAccentButton(
          icon: OmniIcons.plus,
          label: l10n.filesCreateShareLink,
          busy: busy,
          onPressed: busy ? null : onSubmit,
        ),
        if (errorMessage != null) ...[
          const SizedBox(height: 8),
          Text(
            '${l10n.filesCreateFailed}：$errorMessage',
            style: const TextStyle(
              fontSize: 9, // ignore: font_size_whitelist
              height: 1.5,
              color: Color(0xFFE69696),
            ),
          ),
        ],
      ],
    );
  }
}

/// 原型 `.field-input`：46 高、r14、白 7.5% 实底 + 白 10% 描边。
InputDecoration _hostedFieldDecoration({required String label, String? hint}) {
  const border = OutlineInputBorder(
    borderRadius: BorderRadius.all(Radius.circular(14)),
    borderSide: BorderSide(color: MobileEnvColors.line10),
    gapPadding: 0,
  );
  return InputDecoration(
    labelText: label,
    hintText: hint,
    filled: true,
    fillColor: const Color(0x13FFFFFF),
    isDense: true,
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    labelStyle: const TextStyle(
      fontSize: 9, // ignore: font_size_whitelist
      color: MobileEnvColors.inkMuted,
    ),
    hintStyle: const TextStyle(
      fontSize: 13, // ignore: font_size_whitelist
      color: MobileEnvColors.white46,
    ),
    enabledBorder: border,
    focusedBorder: border.copyWith(
      borderSide: const BorderSide(color: MobileEnvColors.line15),
    ),
    border: border,
  );
}

/// 原型 `.notif-group-label`：弱化大写眉标（字号按稿保留，容器自撑）。
class _HostedGroupLabel extends StatelessWidget {
  const _HostedGroupLabel({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 6),
      child: Text(
        label.toUpperCase(),
        style: const TextStyle(
          fontSize: 9, // ignore: font_size_whitelist
          letterSpacing: 1.4,
          fontWeight: FontWeight.w700,
          color: MobileEnvColors.inkFaint,
        ),
      ),
    );
  }
}

/// 原型 `.notif-toggle-row.as-link`：42 图标舱 + 标题/说明 + 环境开关；
/// 与稿子一致，仅开关本体接收点击。
class _HostedToggleRow extends StatelessWidget {
  const _HostedToggleRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 60),
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: MobileEnvColors.accent.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(13),
            ),
            child: Icon(icon, size: 18, color: MobileEnvColors.accent),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11, // ignore: font_size_whitelist
                    fontWeight: FontWeight.w600,
                    color: MobileEnvColors.ink,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 9, // ignore: font_size_whitelist
                    height: 1.35,
                    color: MobileEnvColors.inkMuted,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          MobileEnvSwitch(value: value, onChanged: onChanged),
        ],
      ),
    );
  }
}

/// 高级选项展开钮：仅承载后端真实存在的最大访问次数。
class _HostedOptionsToggle extends StatelessWidget {
  const _HostedOptionsToggle({required this.expanded, required this.onTap});

  final bool expanded;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: InkWell(
        onTap: onTap,
        child: Row(
          children: [
            Icon(
              expanded ? Icons.expand_less : Icons.expand_more,
              size: 18,
              color: MobileEnvColors.inkMuted,
            ),
            const SizedBox(width: 4),
            Text(
              l10n.filesAdvancedOptions,
              style: const TextStyle(
                fontSize: 10, // ignore: font_size_whitelist
                color: MobileEnvColors.inkMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 原型 `.accent-square-btn.sheet-cta`：整宽酸绿主行动钮（46 高 r14）。
class _HostedAccentButton extends StatelessWidget {
  const _HostedAccentButton({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.busy = false,
  });

  final OmniIconsData icon;
  final String label;
  final VoidCallback? onPressed;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return MobilePressable(
      semanticLabel: label,
      onTap: onPressed,
      child: Container(
        constraints: const BoxConstraints(minHeight: 46),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color:
              onPressed == null
                  ? MobileEnvColors.accent.withValues(alpha: 0.4)
                  : MobileEnvColors.accent,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (busy)
              const SizedBox.square(
                dimension: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: MobileEnvColors.onAccent,
                ),
              )
            else
              OmniIcon(icon: icon, size: 17, color: MobileEnvColors.onAccent),
            const SizedBox(width: 7),
            Text(
              label,
              style: const TextStyle(
                fontSize: 11, // ignore: font_size_whitelist
                fontWeight: FontWeight.w700,
                color: MobileEnvColors.onAccent,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
