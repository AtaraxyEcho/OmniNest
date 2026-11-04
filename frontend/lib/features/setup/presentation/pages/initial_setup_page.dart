import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/locale/application/locale_controller.dart';
import 'package:omninest/app/theme/app_typography.dart';
import 'package:omninest/app/theme/control_tokens.dart';
import 'package:omninest/app/widgets/app_dropdown.dart';
import 'package:omninest/core/auth/auth_controller.dart';
import 'package:omninest/core/auth/auth_models.dart';
import 'package:omninest/core/errors/app_exception.dart';
import 'package:omninest/core/theme/motion_token.dart';
import 'package:omninest/core/widgets/brand_logo.dart';
import 'package:omninest/core/widgets/workbench_panel.dart';
import 'package:omninest/features/setup/application/initial_setup_controller.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:omninest/core/errors/error_message.dart';
import 'package:omninest/core/utils/clipboard_writer.dart';
import 'package:omninest/core/feedback/omni_feedback.dart';
part 'initial_setup_page_widgets.dart';
part 'initial_setup_page_two_factor.dart';

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
  bool _totpLoading = false;
  bool _codesSaved = false;
  TwoFactorSetupData? _totpSetup;
  List<String>? _pendingBackupCodes;
  final _totpCodeController = TextEditingController();

  /// 是否强制两步验证；直接从服务端状态读取，不在 build 内写实例字段。
  bool get _twoFactorRequired =>
      ref.read(initialSetupProvider).value?.twoFactorRequired ?? false;

  @override
  void dispose() {
    _setupTokenController.dispose();
    _instanceNameController.dispose();
    _usernameController.dispose();
    _displayNameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _totpCodeController.dispose();
    super.dispose();
  }

  /// 扩展成员里不能直接调 protected 的 setState，统一经此转接。
  void _updateState(VoidCallback update) => setState(update);

  Future<void> _fetchTotpSecret() async {
    if (_totpLoading) return;
    setState(() {
      _totpLoading = true;
      _errorMessage = null;
    });
    try {
      final setup = await ref
          .read(initialSetupProvider.notifier)
          .newTwoFactorSecret(
            setupToken: _setupTokenController.text.trim(),
            username: _usernameController.text.trim(),
          );
      if (!mounted) return;
      setState(() {
        _totpSetup = setup;
        _totpCodeController.clear();
      });
    } catch (error) {
      if (!mounted) return;
      setState(
        () => _errorMessage = errorReason(error, AppLocalizations.of(context)),
      );
    } finally {
      if (mounted) setState(() => _totpLoading = false);
    }
  }

  /// 用户名或安装口令一改，先前生成的秘钥、二维码与备份码就不再对应本次提交的
  /// 账户（otpauth URI 里写的是旧名，口令也不匹配），必须回到"重新生成"这一步，
  /// 否则扫码器里存下的是一条永远不会被用到的条目。
  void _invalidateTotpSetup() {
    if (_totpSetup == null) {
      return;
    }
    setState(() {
      _totpSetup = null;
      _totpCodeController.clear();
    });
  }

  Future<void> _finishBackupCodes() async {
    setState(() => _submitting = true);
    try {
      await ref.read(initialSetupProvider.notifier).refresh();
      // 两步验证路径无自动登录，路由守卫不会因 auth 变化触发，需显式前往登录页。
      if (mounted) {
        context.go('/login');
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
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
    if (_twoFactorRequired && _totpSetup == null) {
      setState(() => _errorMessage = l10n.setupTwoFactorGenerateFirst);
      return;
    }
    setState(() {
      _submitting = true;
      _errorMessage = null;
    });
    try {
      final backupCodes = await ref
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
            totpSecret: _twoFactorRequired ? _totpSetup!.secret : null,
            totpCode:
                _twoFactorRequired ? _totpCodeController.text.trim() : null,
          );
      if (!mounted) return;
      if (backupCodes != null && backupCodes.isNotEmpty) {
        // 启用两步验证：不自动登录（验证码已被注册消费），确认保存备份码后经登录页进入。
        setState(() => _pendingBackupCodes = backupCodes);
        return;
      }
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
                  // 一次性备份码必须先于「安装不可用」判断：创建管理员后服务端会把
                  // setupAvailable 置为 false，状态重算不能把备份码面板顶掉。
                  final pendingCodes = _pendingBackupCodes;
                  if (pendingCodes != null) {
                    return _backupCodesPanel(context, pendingCodes);
                  }
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

  /// 安装向导两步验证分区：生成秘钥（QR/手输）+ 确认码输入。
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
                onChanged: (_) => _invalidateTotpSetup(),
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
                      items: [
                        AppDropdownItem(
                          value: 'zh-CN',
                          label: l10n.settingsLanguageChinese,
                        ),
                        AppDropdownItem(
                          value: 'en-US',
                          label: l10n.settingsLanguageEnglish,
                        ),
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
                onChanged: (_) => _invalidateTotpSetup(),
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
                  if (value == null ||
                      value.length < 8 ||
                      value.length > 64 ||
                      utf8.encode(value).length > 72) {
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
              if (_twoFactorRequired) ..._twoFactorSection(l10n),
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
