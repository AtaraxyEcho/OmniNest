part of 'initial_setup_page.dart';

/// 顶部工具行：右上角界面语言切换器，安装期间无需登录即可切换语言。
class _SetupTopBar extends ConsumerWidget {
  const _SetupTopBar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 14, 24, 0),
      child: Align(alignment: Alignment.centerRight, child: _LanguageSwitch()),
    );
  }
}

/// 紧凑语言切换：文字按钮 + 菜单，体量小于表单字段，避免喧宾夺主。
class _LanguageSwitch extends ConsumerStatefulWidget {
  const _LanguageSwitch();

  @override
  ConsumerState<_LanguageSwitch> createState() => _LanguageSwitchState();
}

class _LanguageSwitchState extends ConsumerState<_LanguageSwitch> {
  final MenuController _menu = MenuController();

  static const _languageCodes = <String>['zh', 'en'];

  String _languageLabel(AppLocalizations l10n, String code) {
    return code == 'zh'
        ? l10n.settingsLanguageChinese
        : l10n.settingsLanguageEnglish;
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context);
    final language = ref.watch(localeControllerProvider);
    final currentLabel = _languageLabel(l10n, language);
    return MenuAnchor(
      controller: _menu,
      useRootOverlay: true,
      alignmentOffset: const Offset(0, 6),
      style: MenuStyle(
        backgroundColor: WidgetStatePropertyAll(colors.surfaceContainerHigh),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: colors.outlineVariant),
          ),
        ),
        elevation: const WidgetStatePropertyAll(8),
        padding: const WidgetStatePropertyAll(
          EdgeInsets.symmetric(vertical: 6),
        ),
        minimumSize: const WidgetStatePropertyAll(Size(120, 0)),
      ),
      menuChildren: [
        for (final code in _languageCodes)
          MenuItemButton(
            onPressed: () {
              _menu.close();
              if (code != language) {
                unawaited(
                  ref.read(localeControllerProvider.notifier).setLanguage(code),
                );
              }
            },
            style: ButtonStyle(
              padding: const WidgetStatePropertyAll(
                EdgeInsets.symmetric(horizontal: 12),
              ),
              minimumSize: WidgetStatePropertyAll(
                Size.fromHeight(AppControlTokens.menuItemHeight),
              ),
              shape: WidgetStatePropertyAll(
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              backgroundColor: WidgetStateProperty.resolveWith(
                (states) =>
                    states.contains(WidgetState.hovered)
                        ? colors.onSurface.withValues(alpha: 0.06)
                        : Colors.transparent,
              ),
              foregroundColor: WidgetStatePropertyAll(colors.onSurface),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _languageLabel(l10n, code),
                  style: TextStyle(
                    color: code == language ? colors.primary : colors.onSurface,
                    fontWeight:
                        code == language ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
                if (code == language)
                  Icon(Icons.check_rounded, size: 16, color: colors.primary),
              ],
            ),
          ),
      ],
      builder: (context, controller, child) {
        return TextButton(
          onPressed:
              () => controller.isOpen ? controller.close() : controller.open(),
          style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            minimumSize: Size(0, AppControlTokens.buttonHeight),
            foregroundColor: colors.onSurface,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.language_rounded,
                size: 18,
                color: colors.onSurfaceVariant,
              ),
              const SizedBox(width: 6),
              Text(
                currentLabel,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600),
              ),
              AnimatedRotation(
                turns: controller.isOpen ? 0.5 : 0,
                duration: const Duration(milliseconds: 150),
                child: Icon(
                  Icons.keyboard_arrow_down_rounded,
                  size: 18,
                  color: colors.onSurfaceVariant,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// 概览面板：品牌标识 + 定位描述 + 能力特性摘要。
class _SetupSummary extends StatelessWidget {
  const _SetupSummary();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final features = <(IconData, String)>[
      (Icons.folder_outlined, l10n.setupFeatureFiles),
      (Icons.movie_outlined, l10n.setupFeatureMedia),
      (Icons.auto_stories_outlined, l10n.setupFeatureReader),
    ];
    return Padding(
      padding: const EdgeInsets.only(top: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const BrandLogo(size: 72, radius: 20),
          const SizedBox(height: 24),
          Text(
            'OmniNest',
            style: Theme.of(context).textTheme.displayLarge?.copyWith(
              fontSize: AppTypography.displayLarge,
            ),
          ),
          const SizedBox(height: 16),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Text(
              l10n.setupSubtitle,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: scheme.onSurfaceVariant,
                height: 1.55,
              ),
            ),
          ),
          const SizedBox(height: 28),
          for (final (icon, label) in features)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: scheme.surfaceContainerHigh,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(icon, size: 18, color: scheme.primary),
                  ),
                  const SizedBox(width: 10),
                  Flexible(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _SetupUnavailable extends StatelessWidget {
  const _SetupUnavailable({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return _SetupCenteredMessage(
      icon: Icons.key_off_outlined,
      title: l10n.setupUnavailableTitle,
      message: l10n.setupUnavailableMessage,
      actionLabel: l10n.setupRetryStatus,
      onAction: onRetry,
    );
  }
}

class _SetupStatusError extends StatelessWidget {
  const _SetupStatusError({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return _SetupCenteredMessage(
      icon: Icons.cloud_off_outlined,
      title: l10n.setupStatusFailed,
      message: l10n.loginConnectionError,
      actionLabel: l10n.setupRetryStatus,
      onAction: onRetry,
    );
  }
}

class _SetupCenteredMessage extends StatelessWidget {
  const _SetupCenteredMessage({
    required this.icon,
    required this.title,
    required this.message,
    required this.actionLabel,
    required this.onAction,
  });

  final IconData icon;
  final String title;
  final String message;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: WorkbenchPanel(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 40),
                const SizedBox(height: 18),
                Text(
                  title,
                  style: Theme.of(context).textTheme.headlineMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 10),
                Text(message, textAlign: TextAlign.center),
                const SizedBox(height: 22),
                FilledButton.tonal(
                  onPressed: onAction,
                  child: Text(actionLabel),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
