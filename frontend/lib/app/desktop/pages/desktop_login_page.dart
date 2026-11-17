import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:omninest/app/desktop/desktop_brand.dart';
import 'package:omninest/app/desktop/desktop_icons.dart';
import 'package:omninest/app/desktop/desktop_routes.dart';
import 'package:omninest/app/desktop/widgets/desktop_controls.dart';
import 'package:omninest/app/desktop/widgets/desktop_surfaces.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/environment_providers.dart';
import 'package:omninest/app/theme/desktop/desktop_motion.dart';
import 'package:omninest/app/theme/desktop/desktop_palette.dart';
import 'package:omninest/app/theme/desktop/desktop_skin.dart';
import 'package:omninest/app/theme/desktop/desktop_type.dart';
import 'package:omninest/core/auth/auth_controller.dart';
import 'package:omninest/core/auth/login_page_controller.dart';
import 'package:omninest/core/auth/login_two_factor_panel.dart';
import 'package:omninest/core/auth/redirect_target.dart';
import 'package:omninest/core/theme/motion_token.dart';
import 'package:omninest/core/widgets/app_loading.dart';

/// 桌面登录（样例 `Auth.tsx`）：左侧环境画幅 + 右侧凭据卡。
///
/// 提交与两步验证复用既有 `LoginPageController` / `AuthSessionNotifier`，
/// 不另写一套认证时序；强制注册（enroll）分支直接交给既有面板，
/// 避免把扫码与备份码流程在这里复制一遍。
class DesktopLoginPage extends ConsumerStatefulWidget {
  const DesktopLoginPage({super.key});

  @override
  ConsumerState<DesktopLoginPage> createState() => _DesktopLoginPageState();
}

class _DesktopLoginPageState extends ConsumerState<DesktopLoginPage> {
  final TextEditingController _username = TextEditingController();
  final TextEditingController _password = TextEditingController();
  bool _obscure = true;

  @override
  void dispose() {
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  String? _redirect() => safeRedirectTarget(
    GoRouterState.of(context).uri.queryParameters['redirect'],
  );

  void _succeeded() {
    if (!mounted) {
      return;
    }
    context.go(_redirect() ?? DesktopRoutes.home);
  }

  Future<void> _submit() async {
    final ok = await ref
        .read(loginPageControllerProvider.notifier)
        .submit(username: _username.text.trim(), password: _password.text);
    if (!mounted) {
      return;
    }
    if (ok) {
      _succeeded();
    }
  }

  @override
  Widget build(BuildContext context) {
    final skin = DesktopSkin.of(context);
    final l10n = AppLocalizations.of(context);
    final state = ref.watch(loginPageControllerProvider);
    final challenge = state.challenge;
    final width = MediaQuery.sizeOf(context).width;
    final wide = width >= 900;

    final card = ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 420),
      child:
          challenge == null
              ? _CredentialsCard(
                username: _username,
                password: _password,
                obscure: _obscure,
                submitting: state.submitting,
                error: _errorText(state.error, l10n),
                onToggleObscure: () => setState(() => _obscure = !_obscure),
                onSubmit: _submit,
              )
              : challenge.isEnrollment
              ? LoginTwoFactorPanel(
                challenge: challenge,
                onLoginSucceeded: _succeeded,
                onBackToLogin:
                    () =>
                        ref
                            .read(loginPageControllerProvider.notifier)
                            .exitChallenge(),
              )
              : _TwoFactorCard(
                challengeToken: challenge.challengeToken,
                onSucceeded: _succeeded,
                onBack:
                    () =>
                        ref
                            .read(loginPageControllerProvider.notifier)
                            .exitChallenge(),
              ),
    );

    // 登录/两步验证是两张卡（样例 `.auth-card` 带 key，切档重播入场）：
    // key 跟着挑战令牌走，进入 2FA 与退回登录都会重新播一遍 rise。
    final animatedCard = DesktopRise(
      key: ValueKey<String>(challenge?.challengeToken ?? 'credentials'),
      child: card,
    );

    // 登录路由不套 Scaffold，输入框需要自己提供 Material 祖先。
    return Material(
      color: skin.bg,
      child:
          wide
              ? Row(
                children: [
                  const Expanded(flex: 5, child: _AuthArt()),
                  SizedBox(
                    width: 560,
                    child: Center(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 40),
                        child: animatedCard,
                      ),
                    ),
                  ),
                ],
              )
              : Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(28),
                  child: animatedCard,
                ),
              ),
    );
  }

  String? _errorText(LoginPageError? error, AppLocalizations l10n) {
    return switch (error) {
      null => null,
      LoginPageMessage(:final text) => text,
      LoginPageConnectionError() => l10n.loginConnectionError,
      LoginPageRequestError() => l10n.loginRequestFailed,
      LoginPageGenericError() => l10n.loginFailed,
    };
  }
}

class _AuthArt extends StatelessWidget {
  const _AuthArt();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final skin = DesktopSkin.of(context);
    return Stack(
      fit: StackFit.expand,
      children: [
        // 画幅不吃照片：样例的左半是一个环境画幅，本应用没有"默认壁纸"这一
        // 概念，用同语言的光场交代纵深，避免登录页与工作区的环境光脱节。
        //
        // 圆心与停靠点照抄 `.root[data-theme="dark"] .auth`：
        // `radial-gradient(circle at 80% 20%, #14201d, #0b0e11 60%)`。
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: Alignment(0.6, -0.6),
              radius: 1.1,
              colors: [DesktopPalette.authAura, DesktopPalette.bgDark],
              stops: [0.0, 0.6],
            ),
          ),
        ),
        const _AuthAura(),
        // 底部压暗保证白色文案在任何强调色下都可读（样例 .art-shade 的第二层）。
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.bottomCenter,
              end: Alignment.topCenter,
              colors: [
                skin.bg.withValues(alpha: 0.80),
                skin.bg.withValues(alpha: 0.10),
                skin.bg.withValues(alpha: 0),
              ],
              stops: const [0.0, 0.42, 0.62],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(56, 40, 56, 48),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const DesktopBrandLockup(color: DesktopPalette.onStage),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  DesktopRise(
                    delay: const Duration(milliseconds: 300),
                    duration: DesktopMotion.authCopy,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 560),
                      child: Text(
                        l10n.desktopAuthArtTitle,
                        style: DesktopType.displayXl(
                          DesktopPalette.onStage,
                          MediaQuery.sizeOf(context).width,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  DesktopRise(
                    delay: const Duration(milliseconds: 500),
                    duration: DesktopMotion.authCopy,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 420),
                      child: Text(
                        l10n.desktopAuthArtSubtitle,
                        style: DesktopType.medium(
                          DesktopPalette.onStage.withValues(alpha: 0.75),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// 登录画幅的两团环境光，与工作区的 `.blob` 同一语言（强调色 + 暖色），
/// 只是不做模糊封面层：没有封面可模糊时再叠一层噪声只会脏画面。
class _AuthAura extends StatefulWidget {
  const _AuthAura();

  @override
  State<_AuthAura> createState() => _AuthAuraState();
}

class _AuthAuraState extends State<_AuthAura>
    with SingleTickerProviderStateMixin {
  late final AnimationController _drift = AnimationController(
    vsync: this,
    duration: DesktopMotion.floatCycle,
  );

  @override
  void initState() {
    super.initState();
    if (!(WidgetsBinding
        .instance
        .platformDispatcher
        .accessibilityFeatures
        .disableAnimations)) {
      _drift.repeat(reverse: true);
    } else {
      _drift.value = 0.4;
    }
  }

  @override
  void dispose() {
    _drift.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final skin = DesktopSkin.of(context);
    return AnimatedBuilder(
      animation: _drift,
      builder: (context, _) {
        final t = _drift.value;
        return Stack(
          fit: StackFit.expand,
          children: [
            Align(
              alignment: Alignment(-0.9 - 0.2 * t, -0.8 + 0.25 * t),
              child: FractionallySizedBox(
                widthFactor: 0.95,
                heightFactor: 0.95,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        skin.accent.withValues(alpha: 0.26),
                        skin.accent.withValues(alpha: 0),
                      ],
                      stops: const [0.0, 0.68],
                    ),
                  ),
                ),
              ),
            ),
            Align(
              alignment: Alignment(0.9 - 0.2 * t, 1.1 - 0.3 * t),
              child: FractionallySizedBox(
                widthFactor: 1.05,
                heightFactor: 1.05,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        skin.warm.withValues(alpha: 0.16),
                        skin.warm.withValues(alpha: 0),
                      ],
                      stops: const [0.0, 0.68],
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _CredentialsCard extends ConsumerWidget {
  const _CredentialsCard({
    required this.username,
    required this.password,
    required this.obscure,
    required this.submitting,
    required this.onToggleObscure,
    required this.onSubmit,
    this.error,
  });

  final TextEditingController username;
  final TextEditingController password;
  final bool obscure;
  final bool submitting;
  final String? error;
  final VoidCallback onToggleObscure;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final skin = DesktopSkin.of(context);
    final l10n = AppLocalizations.of(context);
    final host =
        Uri.tryParse(ref.watch(appEnvironmentProvider)?.apiBaseUrl ?? '')?.host;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        DesktopEyebrow(l10n.desktopWelcomeBack),
        const SizedBox(height: 8),
        Text(l10n.desktopSignIn, style: DesktopType.authTitle(skin.text)),
        const SizedBox(height: 8),
        Text(
          host == null || host.isEmpty ? l10n.desktopNavHome : host,
          style: DesktopType.dense(skin.text2),
        ),
        const SizedBox(height: 28),
        _Field(
          label: l10n.desktopUsername,
          controller: username,
          autofocus: true,
          onSubmitted: onSubmit,
        ),
        const SizedBox(height: 14),
        _Field(
          label: l10n.desktopPassword,
          controller: password,
          obscure: obscure,
          onSubmitted: onSubmit,
          trailing: DesktopIconButton(
            icon: obscure ? DesktopIcons.eye : DesktopIcons.lock,
            size: 28,
            iconSize: 15,
            tooltip: l10n.desktopPassword,
            onPressed: onToggleObscure,
          ),
        ),
        if (error != null) ...[
          const SizedBox(height: 10),
          Text(error!, style: DesktopType.dense(skin.bad)),
        ],
        const SizedBox(height: 16),
        DesktopButton(
          label: l10n.desktopContinue,
          variant: DesktopButtonVariant.primary,
          large: true,
          fullWidth: true,
          busy: submitting,
          onPressed: submitting ? null : onSubmit,
        ),
        const SizedBox(height: 18),
        Center(
          child: DesktopLink(
            label: l10n.desktopSetUpNewServer,
            trailing: false,
            onPressed: () => context.go(DesktopRoutes.serverSetup),
          ),
        ),
      ],
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({
    required this.label,
    required this.controller,
    this.obscure = false,
    this.autofocus = false,
    this.onSubmitted,
    this.trailing,
  });

  final String label;
  final TextEditingController controller;
  final bool obscure;
  final bool autofocus;
  final VoidCallback? onSubmitted;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final skin = DesktopSkin.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: DesktopType.fieldLabel(skin.text2)),
        const SizedBox(height: 6),
        Container(
          height: DesktopMetrics.fieldHeight,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: skin.raise,
            borderRadius: BorderRadius.circular(DesktopMetrics.radiusButton),
            border: Border.all(color: skin.line2),
          ),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: controller,
                  obscureText: obscure,
                  autofocus: autofocus,
                  cursorColor: skin.accent,
                  onSubmitted: (_) => onSubmitted?.call(),
                  style: DesktopType.field(skin.text),
                  decoration: const InputDecoration(
                    isDense: true,
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                  ),
                ),
              ),
              if (trailing != null) trailing!,
            ],
          ),
        ),
      ],
    );
  }
}

class _TwoFactorCard extends ConsumerStatefulWidget {
  const _TwoFactorCard({
    required this.challengeToken,
    required this.onSucceeded,
    required this.onBack,
  });

  final String challengeToken;
  final VoidCallback onSucceeded;
  final VoidCallback onBack;

  @override
  ConsumerState<_TwoFactorCard> createState() => _TwoFactorCardState();
}

class _TwoFactorCardState extends ConsumerState<_TwoFactorCard> {
  final List<TextEditingController> _digits = List.generate(
    6,
    (_) => TextEditingController(),
  );
  final List<FocusNode> _nodes = List.generate(6, (_) => FocusNode());
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _nodes.first.requestFocus();
      }
    });
  }

  @override
  void dispose() {
    for (final controller in _digits) {
      controller.dispose();
    }
    for (final node in _nodes) {
      node.dispose();
    }
    super.dispose();
  }

  Future<void> _verify() async {
    final code = _digits.map((controller) => controller.text).join();
    if (code.length != 6) {
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(authSessionProvider.notifier)
          .signInWithTwoFactor(
            challengeToken: widget.challengeToken,
            code: code,
          );
      if (!mounted) {
        return;
      }
      widget.onSucceeded();
    } on Exception {
      if (!mounted) {
        return;
      }
      setState(() {
        _busy = false;
        _error = AppLocalizations.of(context).loginFailed;
      });
      for (final controller in _digits) {
        controller.clear();
      }
      _nodes.first.requestFocus();
    }
  }

  void _onChanged(int index, String value) {
    final digit = value.replaceAll(RegExp(r'\D'), '');
    if (digit.length > 1) {
      // 粘贴整串验证码：逐位分发后直接校验。
      for (var i = 0; i < 6; i++) {
        _digits[i].text = i < digit.length ? digit[i] : '';
      }
      _nodes.last.requestFocus();
      _verify();
      return;
    }
    _digits[index].text = digit;
    _digits[index].selection = TextSelection.collapsed(offset: digit.length);
    if (digit.isNotEmpty && index < 5) {
      _nodes[index + 1].requestFocus();
    }
    if (_digits.every((controller) => controller.text.isNotEmpty)) {
      _verify();
    }
  }

  @override
  Widget build(BuildContext context) {
    final skin = DesktopSkin.of(context);
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        DesktopEyebrow(l10n.desktopTwoFactor),
        const SizedBox(height: 8),
        Text(
          l10n.desktopEnterYourCode,
          style: DesktopType.authTitle(skin.text),
        ),
        const SizedBox(height: 8),
        Text(l10n.desktopAuthCodeHint, style: DesktopType.dense(skin.text2)),
        const SizedBox(height: 24),
        Row(
          children: [
            for (var index = 0; index < 6; index++)
              Expanded(
                child: Padding(
                  padding: EdgeInsets.only(right: index == 5 ? 0 : 10),
                  child: _OtpBox(
                    controller: _digits[index],
                    focusNode: _nodes[index],
                    onChanged: (value) => _onChanged(index, value),
                    onBackspace:
                        index == 0
                            ? null
                            : () => _nodes[index - 1].requestFocus(),
                  ),
                ),
              ),
          ],
        ),
        if (_error != null) ...[
          const SizedBox(height: 12),
          Text(_error!, style: DesktopType.dense(skin.bad)),
        ],
        if (_busy) ...[
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const AppLoading(),
              const SizedBox(width: 10),
              Text(l10n.desktopVerifying, style: DesktopType.dense(skin.text2)),
            ],
          ),
        ],
        const SizedBox(height: 20),
        Center(
          child: DesktopLink(
            label: l10n.desktopBackToSignIn,
            trailing: false,
            onPressed: widget.onBack,
          ),
        ),
      ],
    );
  }
}

class _OtpBox extends StatelessWidget {
  const _OtpBox({
    required this.controller,
    required this.focusNode,
    required this.onChanged,
    this.onBackspace,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String> onChanged;
  final VoidCallback? onBackspace;

  @override
  Widget build(BuildContext context) {
    final skin = DesktopSkin.of(context);
    return Focus(
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.backspace &&
            controller.text.isEmpty &&
            onBackspace != null) {
          onBackspace!();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: AnimatedBuilder(
        animation: Listenable.merge([focusNode, controller]),
        builder: (context, _) {
          final focused = focusNode.hasFocus;
          final filled = controller.text.isNotEmpty;
          return AnimatedContainer(
            duration: MotionToken.reduced(context, MotionToken.fast),
            curve: MotionToken.curve,
            height: 62,
            decoration: BoxDecoration(
              color: skin.raise,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: focused || filled ? skin.accent : skin.line2,
                width: DesktopMetrics.hairlineStrong,
              ),
              boxShadow:
                  focused
                      ? [
                        BoxShadow(
                          color: skin.accentWash(0.18),
                          blurRadius: 0,
                          spreadRadius: 5,
                        ),
                      ]
                      : null,
            ),
            child: TextField(
              controller: controller,
              focusNode: focusNode,
              textAlign: TextAlign.center,
              keyboardType: TextInputType.number,
              cursorColor: skin.accent,
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9]')),
              ],
              onChanged: onChanged,
              style: DesktopType.displaySm(skin.text),
              decoration: const InputDecoration(
                isDense: true,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                counterText: '',
              ),
            ),
          );
        },
      ),
    );
  }
}
