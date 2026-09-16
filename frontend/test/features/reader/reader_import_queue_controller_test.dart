import 'dart:async';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/app/environment.dart';
import 'package:omninest/app/providers.dart';
import 'package:omninest/core/network/api_client.dart';
import 'package:omninest/features/files/application/media_import_service.dart';
import 'package:omninest/features/files/data/file_api.dart';
import 'package:omninest/features/files/domain/file_manager_models.dart';
import 'package:omninest/features/reader/application/reader_controller.dart';
import 'package:omninest/features/reader/application/reader_import_queue_controller.dart';
import 'package:omninest/features/reader/data/reader_api.dart';
import 'package:omninest/features/reader/domain/reader_models.dart';
import 'package:omninest/features/tasks/data/task_api.dart';

void main() {
  test('空文件集合不会创建导入任务', () {
    final container = _container(
      mediaService: _ImmediateMediaImportService(),
      readerApi: _ReaderApiStub(),
    );
    addTearDown(container.dispose);

    container.read(readerImportQueueProvider.notifier).enqueue(const <XFile>[]);

    expect(container.read(readerImportQueueProvider), isEmpty);
  });

  test('批量选择后立即创建多个任务并并发上传', () async {
    final mediaService = _QueuedMediaImportService();
    final readerApi = _ReaderApiStub();
    final container = _container(
      mediaService: mediaService,
      readerApi: readerApi,
    );
    addTearDown(container.dispose);

    final subscription = container.listen(
      readerImportQueueProvider,
      (_, _) {},
      fireImmediately: true,
    );
    addTearDown(subscription.close);
    final controller = container.read(readerImportQueueProvider.notifier);

    controller.enqueue(<XFile>[
      _memoryFile('book.epub'),
      _memoryFile('comic.cbz'),
    ]);

    expect(container.read(readerImportQueueProvider), hasLength(2));
    expect(
      container
          .read(readerImportQueueProvider)
          .every((job) => job.status == ReaderImportJobStatus.uploading),
      isTrue,
    );

    mediaService.directory.complete('reader-folder');
    await mediaService.twoUploadsStarted.future;
    expect(mediaService.ensureDirectoryCalls, 1);
    expect(mediaService.activeUploads, 2);

    mediaService.uploadsMayComplete.complete();
    await readerApi.twoImportsCompleted.future;
    await _waitUntil(() => container.read(readerImportQueueProvider).isEmpty);

    expect(readerApi.importedKinds, containsAll(<String?>[null, 'COMIC']));
    expect(container.read(readerImportQueueProvider), isEmpty);
  });

  test('扩展名等价类映射为漫画、文本和普通图书', () async {
    final readerApi = _ReaderApiStub();
    final container = _container(
      mediaService: _ImmediateMediaImportService(),
      readerApi: readerApi,
    );
    addTearDown(container.dispose);

    container.read(readerImportQueueProvider.notifier).enqueue(<XFile>[
      _memoryFile('first.CBZ'),
      _memoryFile('second.zip'),
      _memoryFile('notes.TXT'),
      _memoryFile('book.epub'),
    ]);
    await _waitUntil(() => container.read(readerImportQueueProvider).isEmpty);

    expect(
      readerApi.importedKinds,
      unorderedEquals(<String?>['COMIC', 'COMIC', 'TEXT', null]),
    );
  });

  test('上传完成后进入登记状态并在登记完成后移除任务', () async {
    final readerApi = _BlockingReaderApiStub();
    final container = _container(
      mediaService: _ImmediateMediaImportService(),
      readerApi: readerApi,
    );
    addTearDown(container.dispose);

    container.read(readerImportQueueProvider.notifier).enqueue(<XFile>[
      _memoryFile('book.epub'),
    ]);
    await readerApi.registrationStarted.future;

    final registeringJob = container.read(readerImportQueueProvider).single;
    expect(registeringJob.status, ReaderImportJobStatus.registering);
    expect(registeringJob.progress, 1);

    readerApi.registrationMayComplete.complete();
    await _waitUntil(() => container.read(readerImportQueueProvider).isEmpty);
  });

  test('失败任务保留错误状态并可重试成功', () async {
    final mediaService = _RetryMediaImportService();
    final container = _container(
      mediaService: mediaService,
      readerApi: _ReaderApiStub(),
    );
    addTearDown(container.dispose);

    final controller = container.read(readerImportQueueProvider.notifier);
    controller.enqueue(<XFile>[_memoryFile('retry.epub')]);
    await _waitUntil(
      () =>
          container.read(readerImportQueueProvider).singleOrNull?.status ==
          ReaderImportJobStatus.failed,
    );

    final failedJob = container.read(readerImportQueueProvider).single;
    expect(failedJob.errorMessage, isNotEmpty);

    final retry = controller.retry(failedJob.id);
    await mediaService.retryStarted.future;
    expect(
      container.read(readerImportQueueProvider).single.status,
      ReaderImportJobStatus.uploading,
    );
    mediaService.retryMayComplete.complete();
    await retry;

    expect(mediaService.importAttempts, 2);
    expect(container.read(readerImportQueueProvider), isEmpty);
  });

  test('取消上传会终止任务且不会调用 Reader 登记接口', () async {
    final mediaService = _CancellableMediaImportService();
    final readerApi = _ReaderApiStub();
    final container = _container(
      mediaService: mediaService,
      readerApi: readerApi,
    );
    addTearDown(container.dispose);

    final controller = container.read(readerImportQueueProvider.notifier);
    controller.enqueue(<XFile>[_memoryFile('cancel.epub')]);
    await mediaService.uploadStarted.future;
    final jobId = container.read(readerImportQueueProvider).single.id;

    await controller.cancel(jobId);

    expect(container.read(readerImportQueueProvider), isEmpty);
    expect(readerApi.importedKinds, isEmpty);
  });
}

ProviderContainer _container({
  required MediaImportService mediaService,
  required ReaderApi readerApi,
}) {
  final container = ProviderContainer(
    overrides: [
      mediaImportServiceProvider.overrideWithValue(mediaService),
      readerApiProvider.overrideWithValue(readerApi),
    ],
  );
  container.listen(readerImportQueueProvider, (_, _) {}, fireImmediately: true);
  return container;
}

XFile _memoryFile(String name) {
  return XFile(
    name,
    name: name,
    mimeType: 'application/octet-stream',
    length: 3,
    bytes: Uint8List.fromList(<int>[1, 2, 3]),
  );
}

Future<void> _waitUntil(bool Function() condition) async {
  for (var i = 0; i < 100; i++) {
    if (condition()) return;
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  fail('condition was not met before timeout');
}

class _QueuedMediaImportService extends MediaImportService {
  _QueuedMediaImportService() : super(_UnusedFileApi(), _UnusedTaskApi());

  final Completer<String?> directory = Completer<String?>();
  final Completer<void> twoUploadsStarted = Completer<void>();
  final Completer<void> uploadsMayComplete = Completer<void>();
  int ensureDirectoryCalls = 0;
  int activeUploads = 0;

  @override
  Future<String?> ensureDefaultDirectory({
    required String directoryName,
    String? spaceType,
  }) {
    ensureDirectoryCalls++;
    return directory.future;
  }

  @override
  Future<ImportedMediaFile> importFile({
    required XFile file,
    required String parentId,
    String? spaceType,
    FileUploadPolicy? policy,
    required bool reuseExistingFiles,
    ImportProgressCallback? onProgress,
    MediaImportCancellationToken? cancellationToken,
  }) async {
    activeUploads++;
    if (activeUploads == 2) twoUploadsStarted.complete();
    await uploadsMayComplete.future;
    cancellationToken?.throwIfCancelled();
    return ImportedMediaFile(
      fileName: file.name,
      fileNodeId: 'node-${file.name}',
    );
  }
}

class _ImmediateMediaImportService extends MediaImportService {
  _ImmediateMediaImportService() : super(_UnusedFileApi(), _UnusedTaskApi());

  @override
  Future<String?> ensureDefaultDirectory({
    required String directoryName,
    String? spaceType,
  }) async => 'reader-folder';

  @override
  Future<ImportedMediaFile> importFile({
    required XFile file,
    required String parentId,
    String? spaceType,
    FileUploadPolicy? policy,
    required bool reuseExistingFiles,
    ImportProgressCallback? onProgress,
    MediaImportCancellationToken? cancellationToken,
  }) async {
    cancellationToken?.throwIfCancelled();
    return ImportedMediaFile(
      fileName: file.name,
      fileNodeId: 'node-${file.name}',
    );
  }
}

class _RetryMediaImportService extends _ImmediateMediaImportService {
  final Completer<void> retryStarted = Completer<void>();
  final Completer<void> retryMayComplete = Completer<void>();
  int importAttempts = 0;

  @override
  Future<ImportedMediaFile> importFile({
    required XFile file,
    required String parentId,
    String? spaceType,
    FileUploadPolicy? policy,
    required bool reuseExistingFiles,
    ImportProgressCallback? onProgress,
    MediaImportCancellationToken? cancellationToken,
  }) async {
    importAttempts++;
    if (importAttempts == 1) throw StateError('temporary upload failure');
    retryStarted.complete();
    await retryMayComplete.future;
    return super.importFile(
      file: file,
      parentId: parentId,
      spaceType: spaceType,
      policy: policy,
      reuseExistingFiles: reuseExistingFiles,
      onProgress: onProgress,
      cancellationToken: cancellationToken,
    );
  }
}

class _CancellableMediaImportService extends _ImmediateMediaImportService {
  final Completer<void> uploadStarted = Completer<void>();

  @override
  Future<ImportedMediaFile> importFile({
    required XFile file,
    required String parentId,
    String? spaceType,
    FileUploadPolicy? policy,
    required bool reuseExistingFiles,
    ImportProgressCallback? onProgress,
    MediaImportCancellationToken? cancellationToken,
  }) async {
    final cancelled = Completer<void>();
    cancellationToken?.addListener(cancelled.complete);
    uploadStarted.complete();
    await cancelled.future;
    cancellationToken?.throwIfCancelled();
    throw StateError('cancellation signal was not propagated');
  }
}

class _ReaderApiStub extends ReaderApi {
  _ReaderApiStub() : super(_apiClient());

  final List<String?> importedKinds = <String?>[];
  final Completer<void> twoImportsCompleted = Completer<void>();

  @override
  Future<ReaderItem> importFile({
    required String fileNodeId,
    bool force = false,
    String? contentKindOverride,
  }) async {
    importedKinds.add(contentKindOverride);
    if (importedKinds.length == 2) twoImportsCompleted.complete();
    return ReaderItem(
      id: fileNodeId,
      title: fileNodeId,
      itemType: 'EPUB',
      updatedAt: DateTime(2026),
    );
  }

  @override
  Future<ReaderDashboard> dashboard() async => ReaderDashboard.empty();

  @override
  Future<List<ReaderItem>> items({String? itemType, String? query}) async {
    return const <ReaderItem>[];
  }
}

class _BlockingReaderApiStub extends _ReaderApiStub {
  final Completer<void> registrationStarted = Completer<void>();
  final Completer<void> registrationMayComplete = Completer<void>();

  @override
  Future<ReaderItem> importFile({
    required String fileNodeId,
    bool force = false,
    String? contentKindOverride,
  }) async {
    registrationStarted.complete();
    await registrationMayComplete.future;
    return super.importFile(
      fileNodeId: fileNodeId,
      force: force,
      contentKindOverride: contentKindOverride,
    );
  }
}

class _UnusedFileApi extends FileApi {
  _UnusedFileApi() : super(_apiClient());
}

class _UnusedTaskApi extends TaskApi {
  _UnusedTaskApi()
    : super(
        ApiClient(
          const AppEnvironment(
            apiBaseUrl: 'http://localhost:8080/api/v1',
            wsBaseUrl: 'ws://localhost:8080/ws',
          ),
        ),
      );
}

ApiClient _apiClient() {
  return ApiClient(
    const AppEnvironment(
      apiBaseUrl: 'http://localhost:8080/api/v1',
      wsBaseUrl: 'ws://localhost:8080/ws',
    ),
  );
}
