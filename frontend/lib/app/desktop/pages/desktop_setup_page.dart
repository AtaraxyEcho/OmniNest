import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'package:omninest/app/desktop/desktop_icons.dart';
import 'package:omninest/app/desktop/desktop_brand.dart';
import 'package:omninest/app/desktop/desktop_toast.dart';
import 'package:omninest/app/desktop/desktop_shell.dart' show DesktopFormSwitch;
import 'package:omninest/app/desktop/widgets/desktop_controls.dart';
import 'package:omninest/app/desktop/widgets/desktop_select.dart';
import 'package:omninest/app/desktop/widgets/desktop_fields.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/appearance/application/appearance_controller.dart';
import 'package:omninest/app/locale/application/locale_controller.dart';
import 'package:omninest/app/theme/desktop/desktop_palette.dart';
import 'package:omninest/app/theme/desktop/desktop_skin.dart';
import 'package:omninest/app/theme/desktop/desktop_type.dart';
import 'package:omninest/core/auth/auth_controller.dart';
import 'package:omninest/core/auth/auth_models.dart';
import 'package:omninest/core/errors/app_exception.dart';
import 'package:omninest/core/theme/motion_token.dart';
import 'package:omninest/core/errors/error_message.dart';
import 'package:omninest/core/utils/clipboard_writer.dart';
import 'package:omninest/core/utils/platform_helper.dart';
import 'package:omninest/features/setup/application/initial_setup_controller.dart';
import 'package:omninest/features/setup/presentation/pages/initial_setup_page.dart'
    show InitialSetupPage;
import 'package:omninest/app/desktop/setup_timezone.dart';

part 'desktop_setup_support.dart';

String _setupLocaleForLanguage(String language) =>
    language == 'en' ? 'en-US' : 'zh-CN';

/// 桌面首启向导（样例 `Setup.tsx`）：左侧品牌条 + 右侧表单卡。
///
/// 表单规则与服务端一致（安装口令、实例名、账户、密码长度/字节上限、
/// 二次验证），提交走同一个 `initialSetupProvider`，只是换了一套桌面排版。
class DesktopSetupPage extends ConsumerStatefulWidget {
  const DesktopSetupPage({super.key});

  @override
  ConsumerState<DesktopSetupPage> createState() => _DesktopSetupPageState();
}

class _DesktopSetupPageState extends ConsumerState<DesktopSetupPage> {
  final TextEditingController _token = TextEditingController();
  final TextEditingController _instance = TextEditingController(
    text: 'OmniNest',
  );
  final TextEditingController _username = TextEditingController(text: 'root');
  final TextEditingController _displayName = TextEditingController();
  final TextEditingController _email = TextEditingController();
  final TextEditingController _password = TextEditingController();
  final TextEditingController _confirm = TextEditingController();
  final TextEditingController _totpCode = TextEditingController();

  String _timezone = defaultSetupTimezone();
  late final List<DesktopSelectOption<String>> _timezoneOptions = [
    for (final zone in availableSetupTimezones())
      DesktopSelectOption(
        value: zone,
        label: zone.replaceAll('_', ' '),
        hint: setupTimezoneOffset(zone),
      ),
  ];
  bool _obscure = true;
  bool _submitting = false;
  String? _okNote;
  bool _totpLoading = false;
  String? _error;

  // 逐字段校验（样例 `.sf.bad` / `.sf-err`）：错误挂在字段上，提交时一次性
  // 标出并把焦点送到第一个出错项，而不是只回一条整体错误。
  final FocusNode _tokenFocus = FocusNode();
  final FocusNode _instanceFocus = FocusNode();
  final FocusNode _usernameFocus = FocusNode();
  final FocusNode _displayNameFocus = FocusNode();
  final FocusNode _emailFocus = FocusNode();
  final FocusNode _passwordFocus = FocusNode();
  final FocusNode _confirmFocus = FocusNode();
  final FocusNode _codeFocus = FocusNode();
  String? _tokenError;
  String? _instanceError;
  String? _usernameError;
  String? _displayNameError;
  String? _emailError;
  String? _passwordError;
  String? _confirmError;
  String? _codeError;

  TwoFactorSetupData? _totp;
  List<String>? _backupCodes;

  bool get _twoFactorRequired =>
      ref.read(initialSetupProvider).value?.twoFactorRequired ?? false;

  @override
  void dispose() {
    _token.dispose();
    _instance.dispose();
    _username.dispose();
    _displayName.dispose();
    _email.dispose();
    _password.dispose();
    _confirm.dispose();
    _totpCode.dispose();
    _tokenFocus.dispose();
    _instanceFocus.dispose();
    _usernameFocus.dispose();
    _displayNameFocus.dispose();
    _emailFocus.dispose();
    _passwordFocus.dispose();
    _confirmFocus.dispose();
    _codeFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final skin = DesktopSkin.of(context);
    final setup = ref.watch(initialSetupProvider);
    return Scaffold(
      backgroundColor: skin.bg,
      body: setup.when(
        loading:
            () => Center(
              child: SizedBox(
                width: 120,
                child: LinearProgressIndicator(
                  minHeight: 2,
                  backgroundColor: skin.raise,
                  color: skin.accent,
                ),
              ),
            ),
        error:
            (error, _) => _CenteredCard(
              title: AppLocalizations.of(context).setupStatusErrorTitle,
              body: errorReason(error, AppLocalizations.of(context)),
              actionLabel: AppLocalizations.of(context).commonRetry,
              onAction: () => ref.read(initialSetupProvider.notifier).refresh(),
            ),
        data: (status) {
          if (_backupCodes != null) {
            return _BackupCodesPanel(
              codes: _backupCodes!,
              onFinish: _finishAfterBackupCodes,
            );
          }
          if (!status.setupAvailable) {
            return _CenteredCard(
              title: AppLocalizations.of(context).setupUnavailableTitle,
              body: AppLocalizations.of(context).setupUnavailableMessage,
              actionLabel: AppLocalizations.of(context).commonRetry,
              onAction: () => ref.read(initialSetupProvider.notifier).refresh(),
            );
          }
          return _form(context);
        },
      ),
    );
  }

  Widget _form(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final skin = DesktopSkin.of(context);
    final themeMode = ref.watch(appearanceControllerProvider);
    final isDark =
        themeMode == ThemeMode.dark ||
        (themeMode == ThemeMode.system &&
            MediaQuery.platformBrightnessOf(context) == Brightness.dark);
    return Stack(
      fit: StackFit.expand,
      children: [
        Positioned.fill(
          child: LayoutBuilder(
            builder: (context, viewport) {
              final viewportWidth = viewport.maxWidth;
              final horizontalInset =
                  (viewportWidth * 0.05).clamp(24.0, 64.0).toDouble();
              final compact = viewportWidth <= 900;
              return ScrollConfiguration(
                behavior: ScrollConfiguration.of(
                  context,
                ).copyWith(scrollbars: false),
                child: SingleChildScrollView(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(minHeight: viewport.maxHeight),
                    child: Center(
                      child: Container(
                        width: double.infinity,
                        constraints: const BoxConstraints(maxWidth: 1120),
                        // 原型 max-width 包含横向 padding；内层栅格因此在 4K
                        // 桌面也不会意外撑到 1200px 以上。
                        padding: EdgeInsets.fromLTRB(
                          horizontalInset,
                          72,
                          horizontalInset,
                          64,
                        ),
                        child: LayoutBuilder(
                          builder: (context, constraints) {
                            final gap =
                                (viewportWidth * 0.06)
                                    .clamp(32.0, 96.0)
                                    .toDouble();
                            final brandWidth =
                                compact
                                    ? 0.0
                                    : math.min(380.0, constraints.maxWidth);
                            final cardWidth = math.min(
                              620.0,
                              compact
                                  ? constraints.maxWidth
                                  : constraints.maxWidth - gap - brandWidth,
                            );
                            return Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                if (!compact)
                                  SizedBox(
                                    width: brandWidth,
                                    child: _BrandAside(),
                                  ),
                                if (!compact) SizedBox(width: gap),
                                SizedBox(
                                  width: cardWidth,
                                  child: _card(
                                    context,
                                    l10n,
                                    skin,
                                    compact: compact,
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        Positioned(
          top:
              isDesktopPlatform ? (DesktopMetrics.titleBarHeight - 32) / 2 : 16,
          right: isDesktopPlatform ? 166 : 28,
          child: Semantics(
            button: true,
            label: l10n.desktopToggleTheme,
            child: DesktopIconButton(
              icon: isDark ? DesktopIcons.sun : DesktopIcons.moon,
              iconSize: 17,
              onPressed:
                  () => ref
                      .read(appearanceControllerProvider.notifier)
                      .setThemeMode(isDark ? ThemeMode.light : ThemeMode.dark),
            ),
          ),
        ),
      ],
    );
  }

  Widget _card(
    BuildContext context,
    AppLocalizations l10n,
    DesktopSkin skin, {
    required bool compact,
  }) {
    return Container(
      // 样例 `setup.css:7`：卡片内距 22/24。
      padding: const EdgeInsets.fromLTRB(24, 22, 24, 22),
      decoration: BoxDecoration(
        // `--raise` 是半透明色，但 Setup 页面底色固定且不带壁纸；先在该底色
        // 上合成成不透明颜色，避免窗口透明/系统合成时把表单变成毛玻璃。
        color: Color.alphaBlend(skin.raise, skin.bg),
        borderRadius: BorderRadius.circular(DesktopMetrics.radiusLarge),
        border: Border.all(color: skin.line2),
        boxShadow: const [
          BoxShadow(
            color: Color(0x66000000),
            blurRadius: 70,
            spreadRadius: -40,
            offset: Offset(0, 30),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 样例 `setup.css:8`：`h2` 26。
          Text(
            l10n.desktopSetupTitle,
            style: DesktopType.crumbTitle(skin.text),
          ),
          const SizedBox(height: 6),
          Text(l10n.desktopSetupSubtitle, style: DesktopType.dense(skin.text2)),
          const _SetupSectionTitle(titleKey: _SetupSection.instance),
          DesktopTextField(
            keyName: 'setup-token',
            controller: _token,
            focusNode: _tokenFocus,
            label: l10n.setupTokenLabel,
            labelIcon: DesktopIcons.key,
            hint: l10n.setupTokenHint,
            error: _tokenError,
            obscure: true,
            height: 36,
            tone: DesktopFieldTone.page,
            onSubmitted: _submitFromKeyboard,
            onChanged: (_) {
              _clearFieldError(_tokenError, () => _tokenError = null);
              _invalidateTotpSetup();
            },
          ),
          const SizedBox(height: 12),
          DesktopTextField(
            keyName: 'setup-instance',
            controller: _instance,
            focusNode: _instanceFocus,
            label: l10n.setupInstanceName,
            labelIcon: DesktopIcons.home,
            error: _instanceError,
            maxLength: 48,
            height: 36,
            tone: DesktopFieldTone.page,
            onSubmitted: _submitFromKeyboard,
            onChanged:
                (_) => _clearFieldError(
                  _instanceError,
                  () => _instanceError = null,
                ),
          ),
          const SizedBox(height: 12),
          _setupPair(
            compact: compact,
            first: _SetupChoiceField(
              icon: DesktopIcons.language,
              label: l10n.setupDefaultLocale,
              child: DesktopSelect<String>(
                keyName: 'setupDefaultLanguage',
                value: _setupLocaleForLanguage(
                  ref.watch(localeControllerProvider),
                ),
                variant: DesktopSelectVariant.field,
                search: false,
                options: [
                  DesktopSelectOption(
                    value: 'zh-CN',
                    label: l10n.setupLanguageChineseSimplified,
                  ),
                  DesktopSelectOption(
                    value: 'en-US',
                    label: l10n.settingsLanguageEnglish,
                  ),
                ],
                onChanged:
                    (value) => ref
                        .read(localeControllerProvider.notifier)
                        .setLanguage(value == 'en-US' ? 'en' : 'zh'),
              ),
            ),
            second: _SetupChoiceField(
              icon: DesktopIcons.clock,
              label: l10n.setupDefaultTimezone,
              child: _TimezoneSelect(
                value: _timezone,
                options: _timezoneOptions,
                onChanged: (value) => setState(() => _timezone = value),
              ),
            ),
          ),
          const _SetupSectionTitle(titleKey: _SetupSection.admin),
          _setupPair(
            compact: compact,
            first: DesktopTextField(
              keyName: 'setup-username',
              controller: _username,
              focusNode: _usernameFocus,
              label: l10n.loginUsername,
              labelIcon: DesktopIcons.user,
              error: _usernameError,
              maxLength: 32,
              height: 36,
              tone: DesktopFieldTone.page,
              onSubmitted: _submitFromKeyboard,
              onChanged: (value) {
                final normalized = value.toLowerCase();
                if (normalized != value) {
                  _username.value = TextEditingValue(
                    text: normalized,
                    selection: TextSelection.collapsed(
                      offset: normalized.length,
                    ),
                  );
                }
                _clearFieldError(_usernameError, () => _usernameError = null);
                _invalidateTotpSetup();
              },
            ),
            second: DesktopTextField(
              keyName: 'setup-display-name',
              controller: _displayName,
              focusNode: _displayNameFocus,
              label: l10n.setupDisplayName,
              labelIcon: DesktopIcons.users,
              error: _displayNameError,
              maxLength: 48,
              height: 36,
              tone: DesktopFieldTone.page,
              onSubmitted: _submitFromKeyboard,
              onChanged:
                  (_) => _clearFieldError(
                    _displayNameError,
                    () => _displayNameError = null,
                  ),
            ),
          ),
          const SizedBox(height: 12),
          DesktopTextField(
            keyName: 'setup-email',
            controller: _email,
            focusNode: _emailFocus,
            label: l10n.setupEmail,
            labelIcon: DesktopIcons.bell,
            error: _emailError,
            height: 36,
            tone: DesktopFieldTone.page,
            onSubmitted: _submitFromKeyboard,
            onChanged:
                (_) => _clearFieldError(_emailError, () => _emailError = null),
          ),
          const SizedBox(height: 12),
          _setupPair(
            compact: compact,
            first: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                DesktopTextField(
                  keyName: 'setup-password',
                  controller: _password,
                  focusNode: _passwordFocus,
                  label: l10n.loginPassword,
                  labelIcon: DesktopIcons.lock,
                  error: _passwordError,
                  obscure: _obscure,
                  height: 36,
                  tone: DesktopFieldTone.page,
                  onSubmitted: _submitFromKeyboard,
                  onChanged:
                      (_) => setState(() {
                        _passwordError = null;
                        _confirmError = null;
                      }),
                  trailing: Semantics(
                    tooltip:
                        _obscure
                            ? l10n.loginShowPassword
                            : l10n.loginHidePassword,
                    child: IconButton(
                      tooltip: null,
                      icon: Icon(
                        _obscure ? DesktopIcons.eye : DesktopIcons.eyeOff,
                        size: 16,
                        color: skin.text3,
                      ),
                      onPressed: () => setState(() => _obscure = !_obscure),
                    ),
                  ),
                ),
                if (_password.text.isNotEmpty)
                  _PasswordMeter(password: _password.text),
              ],
            ),
            second: DesktopTextField(
              keyName: 'setup-confirm',
              controller: _confirm,
              focusNode: _confirmFocus,
              label: l10n.setupConfirmPassword,
              labelIcon: DesktopIcons.lock,
              error: _confirmError,
              obscure: _obscure,
              height: 36,
              tone: DesktopFieldTone.page,
              onSubmitted: _submitFromKeyboard,
              onChanged:
                  (_) => _clearFieldError(
                    _confirmError,
                    () => _confirmError = null,
                  ),
            ),
          ),
          ..._twoFactorSection(context, l10n, skin, compact: compact),
          if (_hasFieldError) ...[
            const SizedBox(height: 12),
            Text(
              l10n.setupFixHighlightedFields,
              style: DesktopType.fieldHint(DesktopPalette.bad),
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: DesktopType.caption(DesktopPalette.bad)),
          ],
          if (_okNote != null) ...[
            const SizedBox(height: 14),
            _OkNoteBar(message: _okNote!),
          ],
          const SizedBox(height: 18),
          DesktopButton(
            label: l10n.setupCreateAdmin,
            icon: DesktopIcons.bolt,
            variant: DesktopButtonVariant.primary,
            large: true,
            fullWidth: true,
            busy: _submitting,
            onPressed: _submitting ? null : _submit,
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(DesktopIcons.shield, size: 15, color: skin.text3),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  l10n.setupSecureNotice,
                  style: DesktopType.caption(skin.text3),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _setupPair({
    required bool compact,
    required Widget first,
    required Widget second,
  }) {
    if (compact) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [first, const SizedBox(height: 12), second],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: first),
        const SizedBox(width: 12),
        Expanded(child: second),
      ],
    );
  }

  List<Widget> _twoFactorSection(
    BuildContext context,
    AppLocalizations l10n,
    DesktopSkin skin, {
    required bool compact,
  }) {
    final setup = _totp;
    return [
      _SetupSectionTitle(
        titleKey: _SetupSection.twoFactor,
        badge:
            _twoFactorRequired
                ? l10n.setupTwoFactorRequired
                : l10n.setupTwoFactorOptional,
      ),
      Text(
        _twoFactorRequired
            ? l10n.setupTwoFactorHint
            : l10n.setupTwoFactorOptionalHint,
        style: DesktopType.caption(skin.text2),
      ),
      const SizedBox(height: 12),
      if (setup == null)
        DesktopButton(
          label: l10n.setupTwoFactorGenerate,
          icon: DesktopIcons.grid,
          variant: DesktopButtonVariant.primary,
          large: true,
          fullWidth: true,
          busy: _totpLoading,
          onPressed: _totpLoading ? null : _fetchTotpSecret,
        )
      else
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: skin.bg,
            border: Border.all(color: skin.line2),
            borderRadius: BorderRadius.circular(14),
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final qr = Container(
                width: 112,
                height: 112,
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: QrImageView(
                  key: const Key('setupTwoFactorQr'),
                  data: setup.otpauthUri,
                  size: 100,
                  backgroundColor: Colors.white,
                ),
              );
              final details = Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    l10n.twoFactorEnrollScanHint,
                    style: DesktopType.fieldHint(skin.text3),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: SelectableText(
                          setup.secret.replaceAllMapped(
                            RegExp(r'(.{4})(?=.)'),
                            (match) => '${match[1]} ',
                          ),
                          style: DesktopType.mono(skin.text),
                        ),
                      ),
                      Semantics(
                        tooltip: l10n.twoFactorEnrollSecretLabel,
                        child: IconButton(
                          tooltip: null,
                          visualDensity: VisualDensity.compact,
                          icon: Icon(
                            DesktopIcons.copy,
                            size: 15,
                            color: skin.text3,
                          ),
                          onPressed: () async {
                            final copied = await copyTextToClipboard(
                              setup.secret,
                            );
                            if (!context.mounted) {
                              return;
                            }
                            showDesktopToast(
                              context,
                              copied
                                  ? l10n.twoFactorCopied
                                  : l10n.clipboardCopyFailed,
                              kind:
                                  copied
                                      ? DesktopToastKind.success
                                      : DesktopToastKind.error,
                              icon:
                                  copied
                                      ? DesktopIcons.check
                                      : DesktopIcons.info,
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                  DesktopTextField(
                    keyName: 'setup-totp-code',
                    controller: _totpCode,
                    focusNode: _codeFocus,
                    hint: '000000',
                    error: _codeError,
                    height: 38,
                    tone: DesktopFieldTone.panel,
                    maxLength: 6,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    onSubmitted: _submitFromKeyboard,
                    onChanged: (value) {
                      _clearFieldError(_codeError, () => _codeError = null);
                      if (value.length == 6) {
                        FocusScope.of(context).unfocus();
                      }
                    },
                  ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: DesktopButton(
                      label: l10n.setupTwoFactorRegenerate,
                      icon: DesktopIcons.retry,
                      variant: DesktopButtonVariant.ghost,
                      busy: _totpLoading,
                      onPressed: _totpLoading ? null : _fetchTotpSecret,
                    ),
                  ),
                ],
              );
              if (compact || constraints.maxWidth < 360) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(child: qr),
                    const SizedBox(height: 12),
                    details,
                  ],
                );
              }
              return Row(
                children: [
                  qr,
                  const SizedBox(width: 16),
                  Expanded(child: details),
                ],
              );
            },
          ),
        ),
    ];
  }

  Future<void> _fetchTotpSecret() async {
    if (_totpLoading) {
      return;
    }
    setState(() {
      _totpLoading = true;
      _error = null;
    });
    try {
      final setup = await ref
          .read(initialSetupProvider.notifier)
          .newTwoFactorSecret(
            setupToken: _token.text.trim(),
            username: _username.text.trim(),
          );
      if (!mounted) {
        return;
      }
      setState(() {
        _totp = setup;
        _totpCode.clear();
      });
    } on Object catch (error) {
      if (mounted) {
        setState(
          () => _error = errorReason(error, AppLocalizations.of(context)),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _totpLoading = false);
      }
    }
  }

  void _invalidateTotpSetup() {
    if (_totp == null) {
      return;
    }
    setState(() {
      _totp = null;
      _totpCode.clear();
    });
  }

  /// 样例 `Setup.tsx:77-95`：提交时一次性算全部字段错误、把焦点送到第一个
  /// 出错项并中止；之后改哪个字段就清哪个（`clear(k)`）。
  void _clearFieldError(String? current, VoidCallback clear) {
    if (current != null) {
      setState(clear);
    }
  }

  bool get _hasFieldError =>
      _tokenError != null ||
      _instanceError != null ||
      _usernameError != null ||
      _displayNameError != null ||
      _emailError != null ||
      _passwordError != null ||
      _confirmError != null ||
      _codeError != null;

  static bool _looksLikeEmail(String value) =>
      RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(value);

  /// 备份码确认后刷新首启状态并回到登录页。
  Future<void> _finishAfterBackupCodes() async {
    setState(() => _submitting = true);
    try {
      await ref.read(initialSetupProvider.notifier).refresh();
      if (mounted) {
        context.go('/login');
      }
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }

  /// `<form onSubmit>` 的等价物：单个输入框回车即提交。
  void _submitFromKeyboard(String _) {
    if (_submitting) {
      return;
    }
    _submit();
  }

  Future<void> _submit() async {
    final l10n = AppLocalizations.of(context);
    final password = _password.text;
    final email = _email.text.trim();
    final tokenError =
        _token.text.trim().isEmpty ? l10n.setupTokenRequired : null;
    final instanceError =
        _instance.text.trim().isEmpty ? l10n.setupInstanceNameRequired : null;
    final username = _username.text.trim();
    final usernameError =
        RegExp(r'^[a-z][a-z0-9_.-]{2,31}$').hasMatch(username)
            ? null
            : l10n.setupUsernameInvalid;
    final displayNameError =
        _displayName.text.trim().isEmpty ? l10n.setupDisplayNameRequired : null;
    final emailError =
        email.isNotEmpty && !_looksLikeEmail(email)
            ? l10n.setupEmailInvalid
            : null;
    final passwordError =
        password.length < 8 ||
                password.length > 64 ||
                utf8.encode(password).length > 72
            ? l10n.setupPasswordLength
            : null;
    final confirmError =
        _confirm.text != password ? l10n.setupPasswordMismatch : null;
    final codeError =
        (_twoFactorRequired || _totp != null) &&
                _totpCode.text.trim().length != 6
            ? l10n.loginTwoFactorCodeHint
            : null;
    setState(() {
      _tokenError = tokenError;
      _instanceError = instanceError;
      _usernameError = usernameError;
      _displayNameError = displayNameError;
      _emailError = emailError;
      _passwordError = passwordError;
      _confirmError = confirmError;
      _codeError = codeError;
      _error = null;
    });
    final firstInvalid =
        <(String?, FocusNode)>[
          (tokenError, _tokenFocus),
          (instanceError, _instanceFocus),
          (usernameError, _usernameFocus),
          (displayNameError, _displayNameFocus),
          (emailError, _emailFocus),
          (passwordError, _passwordFocus),
          (confirmError, _confirmFocus),
          (codeError, _codeFocus),
        ].where((entry) => entry.$1 != null).toList();
    if (firstInvalid.isNotEmpty) {
      firstInvalid.first.$2.requestFocus();
      return;
    }
    if (_twoFactorRequired && _totp == null) {
      setState(() => _error = l10n.setupTwoFactorGenerateFirst);
      return;
    }
    setState(() => _submitting = true);
    try {
      final backupCodes = await ref
          .read(initialSetupProvider.notifier)
          .createSuperAdmin(
            setupToken: _token.text.trim(),
            username: username,
            displayName: _displayName.text.trim(),
            email: email,
            password: password,
            instanceName: _instance.text.trim(),
            defaultLocale: _setupLocaleForLanguage(
              ref.read(localeControllerProvider),
            ),
            defaultTimezone: _timezone,
            totpSecret: _totp?.secret,
            totpCode: _totp == null ? null : _totpCode.text.trim(),
          );
      if (!mounted) {
        return;
      }
      // 样例 `setup.css:28`：成功后先在卡里给一条绿色 `.ok-note`，
      // 自动登录期间也看得见。
      setState(() => _okNote = l10n.setupAdminCreated);
      if (backupCodes != null && backupCodes.isNotEmpty) {
        setState(() => _backupCodes = backupCodes);
        return;
      }
      try {
        await ref
            .read(authSessionProvider.notifier)
            .signInWithCredentials(username: username, password: password);
        if (!mounted) {
          return;
        }
        await ref.read(initialSetupProvider.notifier).refresh();
      } on Object catch (error) {
        if (!mounted) {
          return;
        }
        showDesktopToast(
          context,
          failureToast(l10n, l10n.setupAutoLoginFailed, error),
          kind: DesktopToastKind.error,
          icon: DesktopIcons.info,
        );
        context.go('/login');
      }
    } on AppException catch (error) {
      if (mounted) {
        setState(() => _error = error.message);
      }
    } on Object {
      if (mounted) {
        setState(() => _error = l10n.setupCreateFailed);
      }
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }
}

/// 首启分支：桌面形态给双栏向导，移动形态保留原单列向导。
class DesktopSetupSwitch extends StatelessWidget {
  const DesktopSetupSwitch({super.key});

  @override
  Widget build(BuildContext context) {
    return const DesktopFormSwitch(
      desktop: DesktopSetupPage(),
      mobile: InitialSetupPage(),
    );
  }
}
