import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/core/auth/auth_controller.dart';
import 'package:omninest/core/auth/auth_models.dart';
import 'package:omninest/core/auth/login_two_factor_panel.dart';
import 'package:omninest/core/errors/app_exception.dart';
import 'package:omninest/core/widgets/brand_logo.dart';
import 'package:omninest/core/widgets/workbench_panel.dart';

class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key});

  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;
  bool _submitting = false;
  String? _errorMessage;
  AuthChallenge? _challenge;

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    final l10n = AppLocalizations.of(context);

    setState(() {
      _submitting = true;
      _errorMessage = null;
    });

    try {
      final result = await ref
          .read(authSessionProvider.notifier)
          .signInWithCredentials(
            username: _usernameController.text.trim(),
            password: _passwordController.text,
          );

      if (!mounted) {
        return;
      }
      if (result.requiresTwoFactor) {
        setState(() => _challenge = result.challenge);
        return;
      }
      context.go(_redirectLocation() ?? '/portal');
    } on DioException catch (error) {
      setState(() => _errorMessage = _messageFromDio(error, l10n));
    } on AppException catch (error) {
      setState(() => _errorMessage = error.message);
    } catch (_) {
      setState(() => _errorMessage = l10n.loginFailed);
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }

  void _exitChallenge() {
    setState(() => _challenge = null);
  }

  void _onTwoFactorLoginSucceeded() {
    if (!mounted) {
      return;
    }
    context.go(_redirectLocation() ?? '/portal');
  }

  String _messageFromDio(DioException error, AppLocalizations l10n) {
    final data = error.response?.data;
    if (data is Map<String, dynamic>) {
      final message = data['message'];
      if (message != null && message.toString().isNotEmpty) {
        return message.toString();
      }
    }
    if (error.type == DioExceptionType.connectionError) {
      return l10n.loginConnectionError;
    }
    return l10n.loginRequestFailed;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: LayoutBuilder(
        builder: (context, constraints) {
          final isWide = constraints.maxWidth >= 920;
          return Stack(
            children: [
              SafeArea(
                child: Center(
                  child: SingleChildScrollView(
                    padding: EdgeInsets.symmetric(
                      horizontal: isWide ? 56 : 20,
                      vertical: 28,
                    ),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 1180),
                      child:
                          isWide
                              ? Row(
                                children: [
                                  const Expanded(child: _BrandPanel()),
                                  const SizedBox(width: 48),
                                  SizedBox(width: 420, child: _buildAuthCard()),
                                ],
                              )
                              : Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  const _BrandPanel(compact: true),
                                  const SizedBox(height: 28),
                                  _buildAuthCard(),
                                ],
                              ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildAuthCard() {
    final challenge = _challenge;
    if (challenge != null) {
      return LoginTwoFactorPanel(
        challenge: challenge,
        onLoginSucceeded: _onTwoFactorLoginSucceeded,
        onBackToLogin: _exitChallenge,
      );
    }
    return _LoginFormCard(
      formKey: _formKey,
      usernameController: _usernameController,
      passwordController: _passwordController,
      obscurePassword: _obscurePassword,
      submitting: _submitting,
      errorMessage: _errorMessage,
      onTogglePassword: _togglePassword,
      onSubmit: _submit,
    );
  }

  void _togglePassword() {
    setState(() => _obscurePassword = !_obscurePassword);
  }

  String? _redirectLocation() {
    final redirect = GoRouterState.of(context).uri.queryParameters['redirect'];
    if (redirect == null || redirect.isEmpty) {
      return null;
    }
    if (!redirect.startsWith('/') ||
        redirect.startsWith('//') ||
        redirect.startsWith('/login')) {
      return null;
    }
    return redirect;
  }
}

class _BrandPanel extends StatelessWidget {
  const _BrandPanel({this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        const BrandLogo(size: 56, radius: 16),
        SizedBox(height: compact ? 20 : 32),
        Text(
          'OmniNest',
          style: Theme.of(context).textTheme.displayLarge?.copyWith(
            fontSize: compact ? 40 : 56,
            height: 1,
          ),
        ),
        const SizedBox(height: 16),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Text(
            l10n.loginSubtitle,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
              color: scheme.onSurfaceVariant,
              height: 1.55,
            ),
          ),
        ),
        if (!compact) ...[
          const SizedBox(height: 36),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _FeaturePill(
                icon: Icons.movie_creation_outlined,
                label: l10n.loginFeatureMedia,
              ),
              _FeaturePill(
                icon: Icons.menu_book_outlined,
                label: l10n.loginFeatureReader,
              ),
              _FeaturePill(
                icon: Icons.folder_outlined,
                label: l10n.loginFeatureFiles,
              ),
              _FeaturePill(
                icon: Icons.admin_panel_settings_outlined,
                label: l10n.loginFeatureAdmin,
              ),
            ],
          ),
        ],
      ],
    );
  }
}

class _FeaturePill extends StatelessWidget {
  const _FeaturePill({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(
          context,
        ).colorScheme.surfaceContainer.withValues(alpha: 0.62),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: Theme.of(
            context,
          ).colorScheme.outlineVariant.withValues(alpha: 0.35),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: 8),
            Text(label, style: Theme.of(context).textTheme.labelMedium),
          ],
        ),
      ),
    );
  }
}

class _LoginFormCard extends StatelessWidget {
  const _LoginFormCard({
    required this.formKey,
    required this.usernameController,
    required this.passwordController,
    required this.obscurePassword,
    required this.submitting,
    required this.errorMessage,
    required this.onTogglePassword,
    required this.onSubmit,
  });

  final GlobalKey<FormState> formKey;
  final TextEditingController usernameController;
  final TextEditingController passwordController;
  final bool obscurePassword;
  final bool submitting;
  final String? errorMessage;
  final VoidCallback onTogglePassword;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return WorkbenchPanel(
      padding: const EdgeInsets.all(28),
      shadow: true,
      child: Form(
        key: formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              l10n.loginWelcome,
              style: Theme.of(context).textTheme.headlineLarge,
            ),
            const SizedBox(height: 8),
            Text(
              l10n.loginDescription,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 28),
            TextFormField(
              controller: usernameController,
              textInputAction: TextInputAction.next,
              decoration: InputDecoration(
                labelText: l10n.loginUsername,
                prefixIcon: const Icon(Icons.person_outline_rounded),
              ),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return l10n.loginUsernameHint;
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: passwordController,
              obscureText: obscurePassword,
              onFieldSubmitted: (_) => onSubmit(),
              decoration: InputDecoration(
                labelText: l10n.loginPassword,
                prefixIcon: const Icon(Icons.lock_outline_rounded),
                suffixIcon: IconButton(
                  tooltip:
                      obscurePassword
                          ? l10n.loginShowPassword
                          : l10n.loginHidePassword,
                  onPressed: onTogglePassword,
                  icon: Icon(
                    obscurePassword
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                  ),
                ),
              ),
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return l10n.loginPasswordHint;
                }
                return null;
              },
            ),
            if (errorMessage != null) ...[
              const SizedBox(height: 18),
              _ErrorBanner(message: errorMessage!),
            ],
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: submitting ? null : onSubmit,
              icon:
                  submitting
                      ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                      : const Icon(Icons.login_rounded),
              label: Text(submitting ? l10n.loginSigningIn : l10n.loginSignIn),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.error.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Theme.of(context).colorScheme.error.withValues(alpha: 0.34),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.error_outline_rounded,
              color: Theme.of(context).colorScheme.error,
              size: 20,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.error,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
