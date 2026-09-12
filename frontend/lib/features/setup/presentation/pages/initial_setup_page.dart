import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/locale/application/locale_controller.dart';
import 'package:omninest/app/theme/app_typography.dart';
import 'package:omninest/app/theme/control_tokens.dart';
import 'package:omninest/app/widgets/app_dropdown.dart';
import 'package:omninest/core/auth/auth_controller.dart';
import 'package:omninest/core/errors/app_exception.dart';
import 'package:omninest/core/widgets/brand_logo.dart';
import 'package:omninest/core/widgets/workbench_panel.dart';
import 'package:omninest/features/setup/application/initial_setup_controller.dart';

class InitialSetupPage extends ConsumerStatefulWidget {
  const InitialSetupPage({super.key});

  @override
  ConsumerState<InitialSetupPage> createState() => _InitialSetupPageState();
}

/// 引导表单可选的常用 IANA 时区；时区标识本身与界面语言无关，不做本地化。
const List<String> kCommonSetupTimezones = <String>[
  'UTC',
  'Asia/Shanghai',
  'Asia/Hong_Kong',
  'Asia/Taipei',
  'Asia/Singapore',
  'Asia/Tokyo',
  'Asia/Seoul',
  'Asia/Bangkok',
  'Asia/Jakarta',
  'Asia/Kolkata',
  'Asia/Dubai',
  'Asia/Riyadh',
  'Europe/London',
  'Europe/Paris',
  'Europe/Berlin',
  'Europe/Moscow',
  'America/New_York',
  'America/Toronto',
  'America/Chicago',
  'America/Denver',
  'America/Los_Angeles',
  'America/Sao_Paulo',
  'Australia/Sydney',
  'Pacific/Auckland',
];

class _InitialSetupPageState extends ConsumerState<InitialSetupPage> {
  final _formKey = GlobalKey<FormState>();
  final _setupTokenController = TextEditingController();
  final _instanceNameController = TextEditingController(text: 'OmniNest');
  final _usernameController = TextEditingController(text: 'root');
  final _displayNameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  String _defaultLocale = 'zh-CN';
  String _defaultTimezone = 'Asia/Shanghai';
  bool _obscurePassword = true;
  bool _submitting = false;
  String? _errorMessage;

  @override
  void dispose() {
    _setupTokenController.dispose();
    _instanceNameController.dispose();
    _usernameController.dispose();
    _displayNameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final l10n = AppLocalizations.of(context);
    final setupToken = _setupTokenController.text;
    final username = _usernameController.text.trim();
    final displayName = _displayNameController.text.trim();
    final email = _emailController.text.trim();
    final password = _passwordController.text;
    final instanceName = _instanceNameController.text.trim();
    final defaultLocale = _defaultLocale;
    final defaultTimezone = _defaultTimezone;
    setState(() {
      _submitting = true;
      _errorMessage = null;
    });
    try {
      await ref
          .read(initialSetupProvider.notifier)
          .createSuperAdmin(
            setupToken: setupToken,
            username: username,
            displayName: displayName,
            email: email,
            password: password,
            instanceName: instanceName,
            defaultLocale: defaultLocale,
            defaultTimezone: defaultTimezone,
          );
      if (!mounted) return;
      await ref
          .read(authSessionProvider.notifier)
          .signInWithCredentials(username: username, password: password);
      if (!mounted) return;
      await ref.read(initialSetupProvider.notifier).refresh();
    } on AppException catch (error) {
      if (!mounted) return;
      setState(() => _errorMessage = error.message);
      await ref.read(initialSetupProvider.notifier).refresh();
    } catch (_) {
      if (!mounted) return;
      setState(() => _errorMessage = l10n.setupCreateFailed);
      await ref.read(initialSetupProvider.notifier).refresh();
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final setup = ref.watch(initialSetupProvider);
    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _SetupTopBar(),
            Expanded(
              child: setup.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error:
                    (_, _) => _SetupStatusError(
                      onRetry: ref.read(initialSetupProvider.notifier).refresh,
                    ),
                data: (status) {
                  if (!status.setupAvailable) {
                    return _SetupUnavailable(
                      onRetry: ref.read(initialSetupProvider.notifier).refresh,
                    );
                  }
                  return _buildForm(context);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildForm(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 920;
        return Center(
          child: SingleChildScrollView(
            padding: EdgeInsets.symmetric(
              horizontal: wide ? 48 : 20,
              vertical: 28,
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1040),
              child:
                  wide
                      ? Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Expanded(child: _SetupSummary()),
                          const SizedBox(width: 48),
                          SizedBox(width: 480, child: _formPanel(l10n)),
                        ],
                      )
                      : _formPanel(l10n),
            ),
          ),
        );
      },
    );
  }

  /// 分区标题：引导表单按"实例信息 / 管理员账户"两段组织，降低长表单
  /// 的视觉密度。
  Widget _sectionHeader(BuildContext context, String title, IconData icon) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: colors.primaryContainer.withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(icon, size: 17, color: colors.onPrimaryContainer),
          ),
          const SizedBox(width: 10),
          Flexible(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(
                context,
              ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }

  Widget _formPanel(AppLocalizations l10n) {
    return WorkbenchPanel(
      padding: const EdgeInsets.all(24),
      child: AutofillGroup(
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                l10n.setupTitle,
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 8),
              Text(
                l10n.setupSubtitle,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 20),
              _sectionHeader(
                context,
                l10n.setupSectionInstance,
                Icons.dns_outlined,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _setupTokenController,
                obscureText: true,
                enableSuggestions: false,
                autocorrect: false,
                decoration: InputDecoration(
                  labelText: l10n.setupToken,
                  hintText: l10n.setupTokenHint,
                  prefixIcon: const Icon(Icons.token_rounded),
                ),
                validator:
                    (value) =>
                        value == null || value.isEmpty
                            ? l10n.setupTokenHint
                            : null,
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _instanceNameController,
                decoration: InputDecoration(
                  labelText: l10n.setupInstanceName,
                  prefixIcon: const Icon(Icons.apartment_rounded),
                ),
                validator:
                    (value) =>
                        value == null || value.trim().isEmpty
                            ? l10n.setupInstanceNameRequired
                            : null,
              ),
              const SizedBox(height: 14),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: AppDropdown<String>(
                      value: _defaultLocale,
                      items: const [
                        AppDropdownItem(value: 'zh-CN', label: '中文'),
                        AppDropdownItem(value: 'en-US', label: 'English'),
                      ],
                      onChanged:
                          (value) => setState(() {
                            if (value != null) _defaultLocale = value;
                          }),
                      label: l10n.setupDefaultLocale,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: AppDropdown<String>(
                      value: _defaultTimezone,
                      items: [
                        for (final timezone in kCommonSetupTimezones)
                          AppDropdownItem(value: timezone, label: timezone),
                      ],
                      onChanged:
                          (value) => setState(() {
                            if (value != null) _defaultTimezone = value;
                          }),
                      label: l10n.setupDefaultTimezone,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              _sectionHeader(
                context,
                l10n.setupSectionAdmin,
                Icons.manage_accounts_outlined,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _usernameController,
                autofillHints: const [AutofillHints.newUsername],
                decoration: InputDecoration(
                  labelText: l10n.loginUsername,
                  prefixIcon: const Icon(Icons.person_outline_rounded),
                ),
                validator:
                    (value) =>
                        value == null || value.trim().isEmpty
                            ? l10n.loginUsernameHint
                            : null,
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _displayNameController,
                decoration: InputDecoration(
                  labelText: l10n.setupDisplayName,
                  prefixIcon: const Icon(Icons.badge_outlined),
                ),
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                autofillHints: const [AutofillHints.email],
                decoration: InputDecoration(
                  labelText: l10n.setupEmail,
                  prefixIcon: const Icon(Icons.mail_outline_rounded),
                ),
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _passwordController,
                obscureText: _obscurePassword,
                autofillHints: const [AutofillHints.newPassword],
                decoration: InputDecoration(
                  labelText: l10n.loginPassword,
                  prefixIcon: const Icon(Icons.lock_outline_rounded),
                  suffixIcon: IconButton(
                    tooltip:
                        _obscurePassword
                            ? l10n.loginShowPassword
                            : l10n.loginHidePassword,
                    onPressed:
                        () => setState(
                          () => _obscurePassword = !_obscurePassword,
                        ),
                    icon: Icon(
                      _obscurePassword
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                    ),
                  ),
                ),
                validator: (value) {
                  if (value == null || value.length < 8 || value.length > 24) {
                    return l10n.setupPasswordLength;
                  }
                  return null;
                },
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _confirmPasswordController,
                obscureText: _obscurePassword,
                autofillHints: const [AutofillHints.newPassword],
                decoration: InputDecoration(
                  labelText: l10n.setupConfirmPassword,
                  prefixIcon: const Icon(Icons.lock_reset_rounded),
                ),
                validator:
                    (value) =>
                        value != _passwordController.text
                            ? l10n.setupPasswordMismatch
                            : null,
                onFieldSubmitted: (_) => _submitting ? null : _submit(),
              ),
              if (_errorMessage != null) ...[
                const SizedBox(height: 14),
                Text(
                  _errorMessage!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: _submitting ? null : _submit,
                icon:
                    _submitting
                        ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                        : const Icon(Icons.rocket_launch_rounded),
                label: Text(l10n.setupCreateAdmin),
              ),
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.verified_user_outlined, size: 18),
                  const SizedBox(width: 8),
                  Expanded(child: Text(l10n.setupSecureNotice)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

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

  static const _languageOptions = <(String, String)>[
    ('zh', '中文'),
    ('en', 'English'),
  ];

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final language = ref.watch(localeControllerProvider);
    final currentLabel =
        _languageOptions.firstWhere((option) => option.$1 == language).$2;
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
        for (final (code, label) in _languageOptions)
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
                  label,
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
