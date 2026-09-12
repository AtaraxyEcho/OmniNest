import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:omninest/core/errors/error_message.dart';
import 'package:omninest/features/music/application/music_controller.dart';
import 'package:omninest/features/music/data/music_api.dart';
import 'package:omninest/features/music/domain/music_models.dart';

/// 扫描任务轮询节奏。
const Duration musicScanJobPollInterval = Duration(seconds: 2);

/// 扫描任务最长轮询时长，超时后停止并提示任务可能仍在后台执行。
const Duration musicScanJobPollTimeout = Duration(minutes: 10);

final musicScanJobControllerProvider =
    NotifierProvider.autoDispose<MusicScanJobController, MusicScanJobState>(
      MusicScanJobController.new,
    );

/// 音乐扫描任务的进行时状态：轮询中的最新任务快照。
class MusicScanJobState {
  const MusicScanJobState({
    this.job,
    this.polling = false,
    this.errorMessage,
    this.timedOut = false,
  });

  final MusicScanJob? job;
  final bool polling;
  final String? errorMessage;
  final bool timedOut;

  bool get isTerminal {
    final status = job?.status.toUpperCase();
    return status == 'COMPLETED' || status == 'FAILED' || status == 'CANCELLED';
  }

  MusicScanJobState copyWith({
    MusicScanJob? job,
    bool? polling,
    String? errorMessage,
    bool clearError = false,
    bool? timedOut,
  }) {
    return MusicScanJobState(
      job: job ?? this.job,
      polling: polling ?? this.polling,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      timedOut: timedOut ?? this.timedOut,
    );
  }
}

/// 管理扫描任务轮询的生命周期：autoDispose 时取消 Timer。
class MusicScanJobController extends Notifier<MusicScanJobState> {
  Timer? _timer;
  int _pollGeneration = 0;
  DateTime? _startedAt;

  bool get _disposed => !ref.mounted;

  @override
  MusicScanJobState build() {
    ref.onDispose(_cancelTimer);
    return const MusicScanJobState();
  }

  void _cancelTimer() {
    _timer?.cancel();
    _timer = null;
  }

  /// 提交扫描任务并开始轮询进度。
  Future<void> startScan() async {
    try {
      final job = await _api().createScanJob();
      if (_disposed) {
        return;
      }
      final latest = await _api().scanJobStatus(job.id);
      if (_disposed) {
        return;
      }
      state = MusicScanJobState(job: latest, polling: true);
      _startPolling();
    } on Exception catch (error) {
      if (!_disposed) {
        state = state.copyWith(
          errorMessage: describeUserFacingError(error).message,
        );
      }
    }
  }

  void _startPolling() {
    _cancelTimer();
    _pollGeneration++;
    final generation = _pollGeneration;
    _startedAt = DateTime.now();
    _timer = Timer.periodic(musicScanJobPollInterval, (timer) {
      unawaited(_pollOnce(generation));
    });
  }

  Future<void> _pollOnce(int generation) async {
    if (_disposed || generation != _pollGeneration) {
      return;
    }
    final current = state;
    final jobId = current.job?.id;
    if (jobId == null) {
      _cancelTimer();
      return;
    }
    if (_startedAt != null &&
        DateTime.now().difference(_startedAt!) > musicScanJobPollTimeout) {
      _cancelTimer();
      state = current.copyWith(polling: false, timedOut: true);
      return;
    }
    try {
      final job = await _api().scanJobStatus(jobId);
      if (_disposed || generation != _pollGeneration) {
        return;
      }
      final terminal = MusicScanJobState(job: job).isTerminal;
      state = MusicScanJobState(job: job, polling: !terminal);
      if (terminal) {
        _cancelTimer();
      }
    } on Exception catch (error) {
      if (_disposed || generation != _pollGeneration) {
        return;
      }
      // 轮询失败不打断进行中的任务，仅记录最近一次错误。
      state = current.copyWith(errorMessage: describeUserFacingError(error).message);
    }
  }

  MusicApi _api() => ref.read(musicApiProvider);
}
