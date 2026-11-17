part of 'desktop_setup_page.dart';

/// 左栏品牌条（样例 `.setup-brand`）：图标 + 名称 + 三条能力说明。
///
/// 从主库拆出，避免向导越过 800 行源码棘轮；依赖仍走主库 import。
class _BrandAside extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final skin = DesktopSkin.of(context);
    final items = <(IconData, String)>[
      (DesktopIcons.folder, l10n.setupBrandFiles),
      (DesktopIcons.film, l10n.setupBrandMedia),
      (DesktopIcons.book, l10n.setupBrandReading),
    ];
    return Padding(
      padding: const EdgeInsets.only(top: 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const DesktopBrandMark(height: 44),
          const SizedBox(height: 22),
          Text(l10n.appName, style: DesktopType.displayXl(skin.text, 1200)),
          const SizedBox(height: 10),
          Text(l10n.setupSubtitle, style: DesktopType.body(skin.text2)),
          const SizedBox(height: 26),
          for (final (icon, label) in items)
            Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: skin.accentWash(0.14),
                      borderRadius: BorderRadius.circular(11),
                    ),
                    child: Icon(icon, size: 18, color: skin.accent),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(label, style: DesktopType.body(skin.text2)),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// 安装状态异常时的居中提示卡（不可用 / 状态读取失败）。
class _CenteredCard extends StatelessWidget {
  const _CenteredCard({
    required this.title,
    required this.body,
    required this.actionLabel,
    required this.onAction,
  });

  final String title;
  final String body;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    final skin = DesktopSkin.of(context);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Container(
          padding: const EdgeInsets.all(26),
          decoration: BoxDecoration(
            color: skin.raise,
            borderRadius: BorderRadius.circular(DesktopMetrics.radiusLarge),
            border: Border.all(color: skin.line2),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: DesktopType.displaySm(skin.text)),
              const SizedBox(height: 8),
              Text(body, style: DesktopType.dense(skin.text3)),
              const SizedBox(height: 18),
              DesktopButton(
                label: actionLabel,
                icon: DesktopIcons.retry,
                variant: DesktopButtonVariant.soft,
                onPressed: onAction,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 首启向导的分节标题（样例 `setup.css:9` 的 `h3`：13px + 下边框）。
enum _SetupSection { instance, admin, twoFactor }

class _SetupSectionTitle extends StatelessWidget {
  const _SetupSectionTitle({required this.titleKey, this.badge});

  final _SetupSection titleKey;
  final String? badge;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final skin = DesktopSkin.of(context);
    final (title, icon) = switch (titleKey) {
      _SetupSection.instance => (
        l10n.setupSectionInstance,
        DesktopIcons.server,
      ),
      _SetupSection.admin => (l10n.setupSectionAdmin, DesktopIcons.users),
      _SetupSection.twoFactor => (
        l10n.setupTwoFactorSection,
        DesktopIcons.shield,
      ),
    };
    return Padding(
      padding: const EdgeInsets.only(top: 20, bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(icon, size: 15, color: skin.accent),
              const SizedBox(width: 8),
              Expanded(
                child: Text(title, style: DesktopType.bodyStrong(skin.text)),
              ),
              if (badge != null)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: skin.bg,
                    border: Border.all(color: skin.line2),
                    borderRadius: BorderRadius.circular(
                      DesktopMetrics.radiusCapsule,
                    ),
                  ),
                  child: Text(badge!, style: DesktopType.fieldHint(skin.text3)),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Container(height: 1, color: skin.line),
          const SizedBox(height: 10),
        ],
      ),
    );
  }
}

/// 密码强度计（样例 `.sf-meter`：4 段 `height:4`、`r2`，s1~s4 分色）。
class _PasswordMeter extends StatelessWidget {
  const _PasswordMeter({required this.password});

  final String password;

  /// 0 段表示还没开始输入；1~4 按长度与字符种类累计。
  int get _score {
    if (password.isEmpty) {
      return 0;
    }
    var score = 0;
    if (password.length >= 8) {
      score++;
    }
    if (password.length >= 12) {
      score++;
    }
    if (RegExp(r'[0-9]').hasMatch(password)) {
      score++;
    }
    if (RegExp(r'[^A-Za-z0-9]').hasMatch(password)) {
      score++;
    }
    if (RegExp(r'[a-z]').hasMatch(password) &&
        RegExp(r'[A-Z]').hasMatch(password)) {
      score++;
    }
    if (password.length < 8) {
      score--;
    }
    return score.clamp(1, 4);
  }

  @override
  Widget build(BuildContext context) {
    final skin = DesktopSkin.of(context);
    final l10n = AppLocalizations.of(context);
    final score = _score;
    final tone = switch (score) {
      0 => skin.line,
      1 => DesktopPalette.bad,
      2 => DesktopPalette.warn,
      3 => DesktopPalette.ok,
      _ => skin.accent,
    };
    final strengthLabel = switch (score) {
      1 => l10n.setupPasswordStrengthWeak,
      2 => l10n.setupPasswordStrengthFair,
      3 => l10n.setupPasswordStrengthGood,
      _ => l10n.setupPasswordStrengthStrong,
    };
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Row(
        children: [
          for (var i = 0; i < 4; i++) ...[
            if (i > 0) const SizedBox(width: 4),
            Expanded(
              child: AnimatedContainer(
                duration: MotionToken.reduced(context, MotionToken.fast),
                curve: MotionToken.curve,
                height: 4,
                decoration: BoxDecoration(
                  color: i < score ? tone : skin.line,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
          ],
          const SizedBox(width: 8),
          SizedBox(
            width: 56,
            child: Text(
              strengthLabel,
              textAlign: TextAlign.right,
              style: DesktopType.fieldHint(skin.text3),
            ),
          ),
        ],
      ),
    );
  }
}

/// 成功提示条（样例 `setup.css:28` 的 `.ok-note`：accent 12% 底 / 9·12 / r10）。
class _OkNoteBar extends StatelessWidget {
  const _OkNoteBar({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final skin = DesktopSkin.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: skin.accentWash(0.12),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(DesktopIcons.check, size: 14, color: skin.accent),
          const SizedBox(width: 8),
          Expanded(child: Text(message, style: DesktopType.caption(skin.text))),
        ],
      ),
    );
  }
}

/// 首启向导的时区下拉（样例 `.sf select`）。
class _TimezoneSelect extends StatelessWidget {
  const _TimezoneSelect({
    required this.value,
    required this.options,
    required this.onChanged,
  });

  final String value;
  final List<DesktopSelectOption<String>> options;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: DesktopSelect<String>(
        value: value,
        variant: DesktopSelectVariant.field,
        keyName: 'setupTimezone',
        options: options,
        onChanged: onChanged,
      ),
    );
  }
}

/// 表单下拉字段的图标和标签与文本字段共用同一排版。
class _SetupChoiceField extends StatelessWidget {
  const _SetupChoiceField({
    required this.icon,
    required this.label,
    required this.child,
  });

  final IconData icon;
  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final skin = DesktopSkin.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(icon, size: 14, color: skin.text2),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: DesktopType.fieldLabel(skin.text2),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        child,
      ],
    );
  }
}

/// 首启成功后的备份码面板（样例 `.codes`）。
class _BackupCodesPanel extends StatelessWidget {
  const _BackupCodesPanel({required this.codes, required this.onFinish});

  final List<String> codes;
  final Future<void> Function() onFinish;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final skin = DesktopSkin.of(context);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(40),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Container(
            padding: const EdgeInsets.all(28),
            decoration: BoxDecoration(
              color: skin.raise,
              borderRadius: BorderRadius.circular(DesktopMetrics.radiusLarge),
              border: Border.all(color: skin.line2),
              boxShadow: skin.shadow,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  l10n.twoFactorEnrollBackupTitle,
                  style: DesktopType.displaySm(skin.text),
                ),
                const SizedBox(height: 8),
                Text(
                  l10n.twoFactorEnrollBackupHint,
                  style: DesktopType.caption(skin.text3),
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    for (final code in codes)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: skin.raise2,
                          borderRadius: BorderRadius.circular(
                            DesktopMetrics.radiusSmall,
                          ),
                        ),
                        child: SelectableText(
                          code,
                          style: DesktopType.mono(skin.text),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    DesktopButton(
                      label: l10n.twoFactorEnrollCopyAll,
                      icon: DesktopIcons.copy,
                      variant: DesktopButtonVariant.ghost,
                      onPressed: () async {
                        final copied = await copyTextToClipboard(
                          codes.join('\n'),
                        );
                        if (!context.mounted) {
                          return;
                        }
                        showDesktopToast(
                          context,
                          copied
                              ? l10n.twoFactorCopied
                              : l10n.clipboardCopyFailed,
                          icon: DesktopIcons.copy,
                        );
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                Align(
                  alignment: Alignment.centerRight,
                  child: DesktopButton(
                    label: l10n.twoFactorEnrollSavedAndFinish,
                    variant: DesktopButtonVariant.primary,
                    onPressed: onFinish,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
