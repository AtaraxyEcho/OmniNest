import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:omninest/app/desktop/desktop_brand.dart';
import 'package:omninest/app/desktop/desktop_icons.dart';
import 'package:omninest/app/desktop/desktop_routes.dart';
import 'package:omninest/app/desktop/widgets/desktop_controls.dart';
import 'package:omninest/app/desktop/widgets/desktop_fields.dart';
import 'package:omninest/app/desktop/widgets/desktop_surfaces.dart';
import 'package:omninest/features/backdrop/backdrop_ui.dart';
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
    final wide = width > 900;
    // 对应样例 `grid-template-columns: minmax(0, 1.25fr) minmax(420px, 560px)`：
    // 右栏在 900px 断点以上由 420px 起步，达到 560px 后固定，左画幅只占余量。
    final formPaneWidth = (width / 2.25).clamp(420.0, 560.0);

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
              : challenge.isEnrollment || challenge.isPasswordChange
              ? LoginTwoFactorPanel(
                key: ValueKey<String>(challenge.challengeToken),
                challenge: challenge,
                errorMessage: _errorText(state.error, l10n),
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
                    width: formPaneWidth,
                    child: Center(
                      child: Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: formPaneWidth * 0.07,
                        ),
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
    // 样例 `.auth-art { overflow: hidden }`：推镜只改变图片绘制范围，
    // 裁切在左画幅边界完成，不能覆盖或挤占右侧表单列。
    return ClipRect(
      child: Stack(
        fit: StackFit.expand,
        children: [
          Positioned.fill(
            child: TweenAnimationBuilder<double>(
              tween: Tween<double>(begin: 0, end: 1),
              duration: MotionToken.reduced(
                context,
                DesktopMotion.authKenBurns,
              ),
              curve: DesktopMotion.cssEaseOut,
              builder:
                  (context, progress, child) => Transform.scale(
                    scale: 1 + 0.14 * progress,
                    child: FractionalTranslation(
                      translation: Offset(-0.015 * progress, -0.01 * progress),
                      child: child,
                    ),
                  ),
              // 样例 .auth-art .img 使用 30s kenburns，终态为 1.14 倍并向左上轻移。
              child: const BundledWallpaperPoster(),
            ),
          ),
          // 样例先绘制底部渐暗，再将水平渐暗层绘制在其上方。
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.bottomCenter,
                end: Alignment.topCenter,
                colors: [Color(0xcc05080a), Color(0x0005080a)],
                stops: const [0.0, 0.55],
              ),
            ),
          ),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: [Color(0x8c05080a), Color(0x1a05080a)],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(56, 40, 56, 48),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const DesktopBrandLockup(color: DesktopPalette.onStage),
                Expanded(
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: DesktopRise(
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
                  ),
                ),
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
          ),
        ],
      ),
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
    return DesktopTextField(
      controller: controller,
      label: label,
      obscure: obscure,
      autofocus: autofocus,
      trailing: trailing,
      onSubmitted: (_) => onSubmitted?.call(),
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
