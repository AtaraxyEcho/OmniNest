import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/core/realtime/realtime_models.dart';
import 'package:omninest/core/realtime/realtime_store.dart';
import 'package:omninest/core/storage/local_database.dart';

void main() {
  late LocalDatabase database;
  late RealtimeStore store;

  setUp(() {
    database = LocalDatabase(NativeDatabase.memory());
    store = RealtimeStore(
      database: database,
      serverKey: 'http://server/api/v1',
      userId: 'user-1',
    );
  });

  tearDown(() => database.close());

  test('live event persists invalidation without advancing cursor', () async {
    await store.initializeCursor(cursor: 10, schemaVersion: 1);

    final inserted = await store.ingestLive(event('event-1', 12));

    expect(inserted, isTrue);
    expect((await store.readState())?.cursor, 10);
    final invalidations = await store.pendingInvalidations();
    expect(invalidations, hasLength(1));
    expect(invalidations.single.scope, RealtimeScope.files);
    expect(invalidations.single.revision, 1);
  });

  test(
    'rest page advances cursor atomically and deduplicates live event',
    () async {
      await store.initializeCursor(cursor: 10, schemaVersion: 1);
      final sharedEvent = event('event-2', 12);
      await store.ingestLive(sharedEvent);

      final changed = await store.ingestRestPage(
        [sharedEvent, event('event-3', 14, resourceId: 'node-2')],
        nextCursor: 20,
        schemaVersion: 1,
      );

      expect((await store.readState())?.cursor, 20);
      expect(changed, {RealtimeScope.files});
      final invalidations = await store.pendingInvalidations();
      expect(invalidations, hasLength(2));
      expect(
        invalidations
            .firstWhere((item) => item.resourceId == 'node-1')
            .revision,
        1,
      );
    },
  );

  test(
    'acknowledge preserves revision created during feature refresh',
    () async {
      await store.initializeCursor(cursor: 0, schemaVersion: 1);
      await store.ingestLive(event('event-4', 1));
      final observed = (await store.pendingInvalidations()).single;
      await store.ingestLive(event('event-5', 2));

      final deleted = await store.acknowledge(observed);

      expect(deleted, 0);
      final pending = await store.pendingInvalidations();
      expect(pending.single.revision, 2);
    },
  );

  test('同一资源的整页事件合并成一次失效，revision 按条数累加', () async {
    await store.initializeCursor(cursor: 0, schemaVersion: 1);

    final changed = await store.ingestRestPage(
      [
        event('event-10', 1),
        event('event-11', 2),
        event('event-12', 3, resourceId: 'node-2'),
      ],
      nextCursor: 3,
      schemaVersion: 1,
    );

    expect(changed, {RealtimeScope.files});
    final invalidations = await store.pendingInvalidations();
    expect(invalidations, hasLength(2));
    expect(
      invalidations.firstWhere((item) => item.resourceId == 'node-1').revision,
      2,
    );
    expect(
      invalidations.firstWhere((item) => item.resourceId == 'node-2').revision,
      1,
    );
  });

  test('整页重复投递同一条事件只记账一次', () async {
    await store.initializeCursor(cursor: 0, schemaVersion: 1);

    await store.ingestRestPage(
      [event('event-20', 1), event('event-20', 1)],
      nextCursor: 1,
      schemaVersion: 1,
    );

    final invalidations = await store.pendingInvalidations();
    expect(invalidations.single.revision, 1);
  });

  test('cursor reset marks every server scope dirty', () async {
    await store.resetToCursor(latestCursor: 50, schemaVersion: 1);

    expect((await store.readState())?.cursor, 50);
    final invalidations = await store.pendingInvalidations();
    expect(invalidations, hasLength(RealtimeScope.values.length));
    expect(
      invalidations.map((item) => item.scope).toSet(),
      RealtimeScope.values.toSet(),
    );
  });

  test('same server keeps user cursors isolated', () async {
    await store.initializeCursor(cursor: 20, schemaVersion: 1);
    final other = RealtimeStore(
      database: database,
      serverKey: store.serverKey,
      userId: 'user-2',
    );
    await other.initializeCursor(cursor: 40, schemaVersion: 1);

    expect((await store.readState())?.cursor, 20);
    expect((await other.readState())?.cursor, 40);
  });
}

RealtimeSyncEvent event(
  String eventId,
  int sequenceNo, {
  String resourceId = 'node-1',
}) {
  return RealtimeSyncEvent(
    schemaVersion: 1,
    eventId: eventId,
    sequenceNo: sequenceNo,
    scope: RealtimeScope.files,
    resourceType: 'FILE_NODE',
    resourceId: resourceId,
    action: RealtimeAction.updated,
    resourceVersion: 1,
    hints: const {},
    occurredAt: DateTime.utc(2026, 7, 17),
  );
}
