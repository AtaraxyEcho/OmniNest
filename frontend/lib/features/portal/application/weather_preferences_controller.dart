import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:omninest/app/providers.dart';
import 'package:omninest/core/auth/auth_controller.dart';

const weatherPreferenceScope = 'weather';

final weatherLocationProvider =
    AsyncNotifierProvider<WeatherLocationController, String?>(
      WeatherLocationController.new,
    );

class WeatherLocationController extends AsyncNotifier<String?> {
  String? _userId;

  @override
  Future<String?> build() async {
    final session = await ref.watch(authSessionProvider.future);
    _userId = session.user?.id;
    final userId = _userId;
    if (userId == null) {
      return null;
    }
    final snapshot = await ref
        .read(preferenceSyncServiceProvider)
        .load(userId: userId, scope: weatherPreferenceScope);
    return _normalize(snapshot.preferences['location']?.toString());
  }

  Future<void> save(String? location) async {
    final normalized = _normalize(location);
    state = AsyncData(normalized);
    final userId = _userId;
    if (userId == null) {
      return;
    }
    final snapshot = await ref
        .read(preferenceSyncServiceProvider)
        .patch(
          userId: userId,
          scope: weatherPreferenceScope,
          changes: normalized == null ? const {} : {'location': normalized},
          removeKeys: normalized == null ? {'location'} : const {},
        );
    state = AsyncData(_normalize(snapshot.preferences['location']?.toString()));
  }

  /// 从远端重新同步天气位置偏好。
  Future<void> refreshFromRemote() async {
    final userId = _userId;
    if (userId == null) return;
    final snapshot = await ref
        .read(preferenceSyncServiceProvider)
        .synchronize(userId: userId, scope: weatherPreferenceScope);
    if (_userId != userId) return;
    state = AsyncData(_normalize(snapshot.preferences['location']?.toString()));
  }

  String? _normalize(String? value) {
    final trimmed = value?.trim() ?? '';
    return trimmed.isEmpty ? null : trimmed;
  }
}
