import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/features/admin/domain/admin_operations.dart';
import 'package:omninest/features/admin/domain/admin_paging.dart';

void main() {
  test('全站分享行解析可空访问上限与过期时间', () {
    final page = AdminPage.fromJson({
      'items': [
        {
          'id': 'share-1',
          'ownerUserId': 'user-1',
          'ownerUsername': 'owner',
          'resourceType': 'FOLDER',
          'resourceId': 'node-1',
          'resourceName': '素材',
          'status': 'ACTIVE',
          'maxAccessCount': 100,
          'accessCount': 5,
          'expiresAt': '2026-12-01T08:00:00Z',
          'createdAt': '2026-11-01T08:00:00Z',
        },
        {
          'id': 'share-2',
          'ownerUsername': 'other',
          'status': 'EXPIRED',
          'accessCount': 0,
        },
      ],
      'page': 0,
      'size': 20,
      'totalElements': 2,
      'totalPages': 1,
    }, AdminFileShareLink.fromJson);

    expect(page.items, hasLength(2));
    final first = page.items.first;
    expect(first.ownerUsername, 'owner');
    expect(first.maxAccessCount, 100);
    expect(first.accessCount, 5);
    expect(first.expiresAt, isNotNull);
    final second = page.items.last;
    expect(second.maxAccessCount, isNull);
    expect(second.expiresAt, isNull);
    expect(second.accessCount, 0);
  });

  test('不可用媒体解析缺失时间与确认次数', () {
    final item = AdminUnavailableMedia.fromJson({
      'videoItemId': 'video-1',
      'fileNodeId': 'file-1',
      'librarySourceId': 'source-1',
      'title': '影片',
      'availabilityStatus': 'MISSING',
      'missingSince': '2026-10-01T00:00:00Z',
      'missingConfirmations': 3,
    });

    expect(item.title, '影片');
    expect(item.availabilityStatus, 'MISSING');
    expect(item.missingSince, isNotNull);
    expect(item.missingConfirmations, 3);
  });

  test('共享空间矩阵只比较能力位', () {
    const base = AdminSharedSpacePermission(
      roleId: 'role-1',
      roleCode: 'MEMBER',
      canBrowse: true,
      canUpload: false,
      canDownload: true,
      canDeleteOwn: false,
      canDeleteAny: false,
      canMoveTo: false,
      canMoveFrom: false,
      canCreateFolder: false,
    );
    final same = base.copyWith(canBrowse: true);
    final changed = base.copyWith(canUpload: true);

    expect(base.sameCapabilities(same), isTrue);
    expect(base.sameCapabilities(changed), isFalse);
    expect(
      changed.enabledCapabilities,
      containsAll(['browse', 'download', 'upload']),
    );
  });

  test('地理维护结果解析任务与复用标记', () {
    final imported = AdminGeoImportResult.fromJson({
      'taskId': 'task-1',
      'datasetId': 'dataset-1',
      'datasetVersion': '2026-01-01',
    });
    final backfill = AdminGeoBackfillResult.fromJson({
      'taskId': 'task-2',
      'reused': true,
    });

    expect(imported.datasetVersion, '2026-01-01');
    expect(backfill.reused, isTrue);
    expect(backfill.taskId, 'task-2');
  });
}
