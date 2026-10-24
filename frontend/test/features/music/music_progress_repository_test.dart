import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:omninest/core/storage/local_database.dart';
import 'package:omninest/core/storage/sync_queue.dart';
import 'package:omninest/features/music/data/music_api.dart';
import 'package:omninest/features/music/data/music_progress_repository.dart';
import 'package:omninest/features/music/domain/music_models.dart';

class _MockMusicApi extends Mock implements MusicApi {}

void main() {
  late LocalDatabase database;
  late SyncQueue syncQueue;
  late _MockMusicApi api;
  late MusicProgressRepository repository;

  setUpAll(() {
    registerFallbackValue(
      MusicPlaybackProgress(
        playableKey: 'local:fallback',
        positionSeconds: 0,
        durationSeconds: 0,
        completed: false,
        updatedAt: DateTime(2026, 7, 10),
      ),
    );
  });

  setUp(() {
    database = LocalDatabase(NativeDatabase.memory());
    syncQueue = SyncQueue(database);
    api = _MockMusicApi();
    repository = MusicProgressRepository(
      database: database,
      syncQueue: syncQueue,
      api: api,
    );
  });

  tearDown(() async {
    await database.close();
  });

  test(
    'local progress is isolated per account and logout keeps other accounts',
    () async {
      final repositoryA = MusicProgressRepository(
        database: database,
        syncQueue: SyncQueue(database, userId: 'user-a'),
        api: api,
        userId: 'user-a',
      );
      final repositoryB = MusicProgressRepository(
        database: database,
        syncQueue: SyncQueue(database, userId: 'user-b'),
        api: api,
        userId: 'user-b',
      );

      await repositoryA.saveLocal(
        playableKey: 'shared:track-1',
        position: const Duration(seconds: 15),
        duration: const Duration(seconds: 180),
        completed: false,
      );
      await repositoryB.saveLocal(
        playableKey: 'shared:track-1',
        position: const Duration(seconds: 90),
        duration: const Duration(seconds: 180),
        completed: false,
      );

      expect(
        (await repositoryA.loadLocal('shared:track-1'))?.positionSeconds,
        15,
      );
      expect(
        (await repositoryB.loadLocal('shared:track-1'))?.positionSeconds,
        90,
      );

      await database.clearUserData('user-a');

      expect(await repositoryA.loadLocal('shared:track-1'), isNull);
      expect(
        (await repositoryB.loadLocal('shared:track-1'))?.positionSeconds,
        90,
      );
    },
  );

  test('saveLocal caches progress and coalesces pending sync', () async {
    await repository.saveLocal(
      playableKey: 'local:track-1',
      position: const Duration(seconds: 15),
      duration: const Duration(seconds: 180),
      completed: false,
    );
    await repository.saveLocal(
      playableKey: 'local:track-1',
      position: const Duration(seconds: 30),
      duration: const Duration(seconds: 180),
      completed: false,
    );

    final progress = await repository.loadLocal('local:track-1');
    final operations = await syncQueue.dequeue();

    expect(progress?.positionSeconds, 30);
    expect(operations, hasLength(1));
    expect(
      operations.single.type,
      MusicProgressRepository.operationType('local:track-1'),
    );
  });

  test('loadForRestore prefers unsynced local progress', () async {
    await repository.saveLocal(
      playableKey: 'online:netease:song-1',
      position: const Duration(seconds: 45),
      duration: const Duration(seconds: 180),
      completed: false,
    );

    final progress = await repository.loadForRestore('online:netease:song-1');

    expect(progress?.positionSeconds, 45);
    verifyNever(() => api.playbackProgress(any()));
  });

  test('loadForRestore fetches remote progress when cache is empty', () async {
    final remote = MusicPlaybackProgress(
      playableKey: 'local:track-1',
      positionSeconds: 60,
      durationSeconds: 180,
      completed: false,
      updatedAt: DateTime(2026, 7, 10),
      version: 3,
    );
    when(
      () => api.playbackProgress('local:track-1'),
    ).thenAnswer((_) async => remote);

    final progress = await repository.loadForRestore('local:track-1');

    expect(progress?.positionSeconds, 60);
    expect((await repository.loadLocal('local:track-1'))?.positionSeconds, 60);
  });
}
