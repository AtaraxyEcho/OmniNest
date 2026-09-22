import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/features/music/application/music_controller.dart';
import 'package:omninest/features/music/application/music_scan_job_controller.dart';
import 'package:omninest/features/music/data/music_api.dart';
import 'package:omninest/features/music/domain/music_models.dart';

void main() {
  testWidgets('扫描任务轮询终态停止且记录进度', (tester) async {
    final api = _ScanApiStub();
    final container = ProviderContainer.test(
      overrides: [musicApiProvider.overrideWithValue(api)],
    );
    addTearDown(container.dispose);

    await tester.runAsync(() async {
      // keepAlive：建立监听防止 autoDispose 在无监听时销毁 provider。
      container.listen(musicScanJobControllerProvider, (previous, next) {});
      final notifier = container.read(musicScanJobControllerProvider.notifier);
      await notifier.startScan();
      final afterStart = container.read(musicScanJobControllerProvider);
      expect(afterStart.polling, isTrue);

      // 第一轮轮询返回 RUNNING。
      await Future<void>.delayed(const Duration(milliseconds: 2200));
      final polling = container.read(musicScanJobControllerProvider);
      expect(polling.job?.status, 'RUNNING');

      // 第二轮返回 COMPLETED。
      await Future<void>.delayed(const Duration(milliseconds: 2200));
      final done = container.read(musicScanJobControllerProvider);
      expect(done.job?.status, 'COMPLETED');
      expect(done.polling, isFalse);
      expect(api.statusRequests, hasLength(3));
    });
  });

  testWidgets('容器释放后停止轮询 Timer', (tester) async {
    final api = _ScanApiStub();
    final container = ProviderContainer.test(
      overrides: [musicApiProvider.overrideWithValue(api)],
    );
    await tester.runAsync(() async {
      final notifier = container.read(musicScanJobControllerProvider.notifier);
      await notifier.startScan();
      expect(api.statusRequests, hasLength(1));

      container.dispose();
      final before = api.statusRequests.length;
      await Future<void>.delayed(const Duration(milliseconds: 2300));
      // 释放后不再有新的轮询请求。
      expect(api.statusRequests.length, before);
    });
  });

  testWidgets('扫描轮询到终态后主动刷新曲库中心', (tester) async {
    final api = _ScanApiStub();
    var centerRefreshes = 0;
    final container = ProviderContainer.test(
      overrides: [
        musicApiProvider.overrideWithValue(api),
        musicCenterControllerProvider.overrideWith(
          () => _SpyMusicCenterController(() => centerRefreshes += 1),
        ),
      ],
    );
    addTearDown(container.dispose);

    await tester.runAsync(() async {
      container.listen(musicScanJobControllerProvider, (previous, next) {});
      await container.read(musicCenterControllerProvider.future);
      expect(centerRefreshes, 0);

      final notifier = container.read(musicScanJobControllerProvider.notifier);
      await notifier.startScan();
      await Future<void>.delayed(const Duration(milliseconds: 2200));
      await Future<void>.delayed(const Duration(milliseconds: 2200));

      final done = container.read(musicScanJobControllerProvider);
      expect(done.job?.status, 'COMPLETED');
      expect(done.polling, isFalse);
      expect(centerRefreshes, 1);
    });
  });
}

class _SpyMusicCenterController extends MusicCenterController {
  _SpyMusicCenterController(this.onRefresh);

  final void Function() onRefresh;

  @override
  Future<MusicCenterState> build() async => MusicCenterState(
    dashboard: MusicDashboard.empty(),
    tracks: const <MusicTrack>[],
    albums: const <MusicAlbum>[],
    artists: const <MusicArtist>[],
    playlists: const <MusicPlaylist>[],
  );

  @override
  Future<void> refresh() async {
    onRefresh();
  }
}

class _ScanApiStub implements MusicApi {
  final statusRequests = <String>[];

  @override
  Future<MusicScanJob> createScanJob() async {
    return const MusicScanJob(
      id: 'scan-1',
      status: 'PENDING',
      progress: 0,
      scannedFiles: 0,
    );
  }

  @override
  Future<MusicScanJob> scanJobStatus(String jobId) async {
    statusRequests.add(jobId);
    final count = statusRequests.length;
    return MusicScanJob(
      id: jobId,
      status: count >= 3 ? 'COMPLETED' : 'RUNNING',
      progress: count >= 3 ? 100 : count * 40,
      scannedFiles: count * 10,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
