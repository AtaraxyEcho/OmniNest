import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/feature/music_backdrop_theme.dart';
import 'package:omninest/core/errors/error_message.dart';
import 'package:omninest/core/errors/user_facing_error_l10n.dart';
import 'package:omninest/core/widgets/mobile_shell_scope.dart';
import 'package:omninest/features/backdrop/application/app_backdrop_controller.dart';
import 'package:omninest/features/backdrop/domain/app_backdrop_policy.dart';
import 'package:omninest/features/backdrop/backdrop_ui.dart';
import 'package:omninest/features/music/application/music_controller.dart';
import 'package:omninest/features/music/application/music_playback_session.dart';
import 'package:omninest/features/music/presentation/deck/music_deck_shell.dart';

/// Music 模块自适应 Deck 入口。
class MusicCenterPage extends ConsumerStatefulWidget {
  const MusicCenterPage({super.key});

  @override
  ConsumerState<MusicCenterPage> createState() => _MusicCenterPageState();
}

class _MusicCenterPageState extends ConsumerState<MusicCenterPage> {
  late final MusicPlaybackSessionController _playbackSessionController;
  bool _syncScheduled = false;
  int _syncGeneration = 0;

  @override
  void initState() {
    super.initState();
    _playbackSessionController = ref.read(
      musicPlaybackSessionProvider.notifier,
    );
    _schedulePlaybackSync();
  }

  @override
  void dispose() {
    _syncGeneration++;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(musicCenterControllerProvider, (previous, next) {
      _schedulePlaybackSync();
      final previousError = previous?.asData?.value.errorMessage;
      final nextError = next.asData?.value.errorMessage;
      if (nextError != null && nextError != previousError) {
        _showError(nextError);
        ref.read(musicCenterControllerProvider.notifier).clearError();
      }
    });
    ref.listen(musicPlaybackSessionProvider, (previous, next) {
      final previousError = previous?.lastError;
      if (next.lastError != null && next.lastError != previousError) {
        _showError(AppLocalizations.of(context).musicPlaybackError);
        ref.read(musicPlaybackSessionProvider.notifier).clearError();
      }
    });
    final state = ref.watch(musicCenterControllerProvider);
    final backdrop = ref.watch(appBackdropControllerProvider).asData?.value;
    final backdropActive = backdrop?.hasActiveBackdrop == true;
    final content = Theme(
      data: MusicBackdropTheme.resolve(
        Theme.of(context),
        backdropActive: backdropActive,
      ),
      child: Builder(
        builder:
            (context) => PopScope(
              canPop: false,
              onPopInvokedWithResult: (didPop, result) {
                if (!didPop) {
                  context.go('/portal');
                }
              },
              child: Scaffold(
                backgroundColor: Colors.transparent,
                body: state.when(
                  data: (music) => const MusicDeckShell(),
                  loading: () => const _MusicDeckLoading(),
                  error:
                      (error, stackTrace) => _MusicDeckError(
                        message: describeUserFacingError(error).displayMessage,
                        onRetry:
                            () => ref.invalidate(musicCenterControllerProvider),
                      ),
                ),
              ),
            ),
      ),
    );
    if (MobileShellScope.isHosted(context)) {
      return content;
    }
    return AppBackdropSceneScope(
      owner: 'music.center',
      policy: AppBackdropPolicy.musicDeck,
      child: content,
    );
  }

  void _schedulePlaybackSync() {
    if (_syncScheduled) {
      return;
    }
    _syncScheduled = true;
    final generation = ++_syncGeneration;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      _syncScheduled = false;
      if (!mounted || generation != _syncGeneration) {
        return;
      }
      await _playbackSessionController.syncFromCenterState();
    });
  }

  void _showError(String message) {
    if (!mounted) {
      return;
    }
    final localized = AppLocalizations.of(context).localizeStoredError(message);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(localized),
        action: SnackBarAction(
          label: AppLocalizations.of(context).musicGotIt,
          onPressed: () => ScaffoldMessenger.of(context).hideCurrentSnackBar(),
        ),
      ),
    );
  }
}

class _MusicDeckLoading extends StatelessWidget {
  const _MusicDeckLoading();

  @override
  Widget build(BuildContext context) {
    return const Center(child: CircularProgressIndicator());
  }
}

class _MusicDeckError extends StatelessWidget {
  const _MusicDeckError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline_rounded, size: 42),
            const SizedBox(height: 14),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: Text(AppLocalizations.of(context).musicDeckRetry),
            ),
          ],
        ),
      ),
    );
  }
}
