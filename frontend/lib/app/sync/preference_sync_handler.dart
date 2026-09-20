import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:omninest/app/appearance/application/appearance_controller.dart';
import 'package:omninest/app/appearance/application/font_scale_controller.dart';
import 'package:omninest/app/locale/application/locale_controller.dart';
import 'package:omninest/core/realtime/realtime_models.dart';
import 'package:omninest/core/realtime/realtime_scope_handler.dart';
import 'package:omninest/features/music/application/music_visualizer_preset_controller.dart';
import 'package:omninest/features/notifications/application/notification_preferences_controller.dart';
import 'package:omninest/features/portal/application/weather_preferences_controller.dart';
import 'package:omninest/features/reader/application/reader_preferences_controller.dart';

/// 用户偏好作用域实时失效刷新处理器。
///
/// 门户 scope 曾承载沉浸模式偏好并跨端同步，现沉浸已改为本机会话
/// （portalImmersiveSessionProvider），portal scope 不再注册刷新目标。
class PreferenceSyncHandler implements RealtimeScopeHandler {
  PreferenceSyncHandler(this.ref);

  static const _targets = <String>{
    appearancePreferenceScope,
    localePreferenceScope,
    weatherPreferenceScope,
    readerPreferenceScope,
    notificationPreferenceScope,
    musicVisualizerPreferenceScope,
  };

  final Ref ref;
  final Map<String, Set<String>> _completedTargets = <String, Set<String>>{};

  @override
  RealtimeScope get scope => RealtimeScope.preferences;

  @override
  bool appliesTo(RealtimeInvalidation invalidation) => true;

  @override
  Future<bool> refresh(List<RealtimeInvalidation> invalidations) async {
    var allCompleted = true;
    for (final invalidation in invalidations) {
      final requiredTargets =
          invalidation.resourceType == '*'
              ? _targets
              : <String>{
                if (_targets.contains(invalidation.resourceId))
                  invalidation.resourceId!,
              };
      final revisionKey = '${invalidation.key}:${invalidation.revision}';
      final completed = _completedTargets.putIfAbsent(
        revisionKey,
        () => <String>{},
      );
      for (final target in requiredTargets.difference(completed)) {
        if (await _refreshTarget(target)) {
          completed.add(target);
        }
      }
      if (!completed.containsAll(requiredTargets)) {
        allCompleted = false;
      }
    }
    if (allCompleted) {
      for (final invalidation in invalidations) {
        _completedTargets.remove(
          '${invalidation.key}:${invalidation.revision}',
        );
      }
    }
    return allCompleted;
  }

  Future<bool> _refreshTarget(String target) async {
    switch (target) {
      case appearancePreferenceScope:
        await ref
            .read(appearanceControllerProvider.notifier)
            .refreshFromRemote();
        await ref
            .read(fontScaleControllerProvider.notifier)
            .refreshFromRemote();
        return true;
      case localePreferenceScope:
        await ref.read(localeControllerProvider.notifier).refreshFromRemote();
        return true;
      case weatherPreferenceScope:
        if (!ref.exists(weatherLocationProvider)) return false;
        await ref.read(weatherLocationProvider.future);
        await ref.read(weatherLocationProvider.notifier).refreshFromRemote();
        return true;
      case readerPreferenceScope:
        if (!ref.exists(readerPreferencesProvider)) return false;
        await ref.read(readerPreferencesProvider.future);
        await ref.read(readerPreferencesProvider.notifier).refreshFromRemote();
        return true;
      case notificationPreferenceScope:
        if (!ref.exists(notificationPreferencesProvider)) return false;
        await ref.read(notificationPreferencesProvider.future);
        await ref
            .read(notificationPreferencesProvider.notifier)
            .refreshFromRemote();
        return true;
      case musicVisualizerPreferenceScope:
        if (!ref.exists(musicVisualizerPreferencesProvider)) return false;
        await ref.read(musicVisualizerPreferencesProvider.future);
        await ref
            .read(musicVisualizerPreferencesProvider.notifier)
            .refreshFromRemote();
        return true;
      default:
        return true;
    }
  }
}
