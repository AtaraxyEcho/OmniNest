import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:omninest/features/reader/data/reader_tts_preference_store.dart';

final readerTtsPreferenceStoreProvider = Provider<ReaderTtsPreferenceStore>(
  (ref) => const ReaderTtsPreferenceStore(),
);

final readerTtsSpeedControllerProvider =
    AsyncNotifierProvider<ReaderTtsSpeedController, double>(
      ReaderTtsSpeedController.new,
    );

/// 管理阅读器语音朗读速度并持久化到当前设备。
class ReaderTtsSpeedController extends AsyncNotifier<double> {
  static const defaultSpeed = ReaderTtsPreferenceStore.defaultSpeed;

  @override
  Future<double> build() {
    return ref.read(readerTtsPreferenceStoreProvider).loadSpeed();
  }

  Future<void> setSpeed(double speed) async {
    final normalized = speed.clamp(0.5, 2.0).toDouble();
    state = AsyncData(normalized);
    await ref.read(readerTtsPreferenceStoreProvider).saveSpeed(normalized);
  }
}
