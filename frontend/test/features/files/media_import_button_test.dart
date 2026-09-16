import 'dart:async';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/app/environment.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/providers.dart';
import 'package:omninest/core/network/api_client.dart';
import 'package:omninest/features/files/application/media_import_service.dart';
import 'package:omninest/features/files/data/file_api.dart';
import 'package:omninest/features/files/presentation/widgets/media_import_button.dart';
import 'package:omninest/features/tasks/data/task_api.dart';

void main() {
  Widget buildButton(
    MediaImportFilePicker picker, {
    MediaImportService? importService,
    FutureOr<void> Function() onImportComplete = _noop,
    List<String> acceptedExtensions = const <String>['jpg', 'png'],
    List<String> unsupportedExtensions = const <String>[],
  }) {
    return ProviderScope(
      overrides: [
        mediaImportFilePickerProvider.overrideWithValue(picker),
        if (importService != null)
          mediaImportServiceProvider.overrideWithValue(importService),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('zh'),
        home: Navigator(
          onGenerateRoute:
              (_) => MaterialPageRoute<void>(
                builder:
                    (_) => Scaffold(
                      body: MediaImportButton(
                        subsystemDirectory: 'Photos',
                        acceptedExtensions: acceptedExtensions,
                        unsupportedExtensions: unsupportedExtensions,
                        onImportComplete: onImportComplete,
                        allowSharedSpace: false,
                        style: ImportButtonStyle.iconButton,
                      ),
                    ),
              ),
        ),
      ),
    );
  }

  testWidgets('文件选择期间禁止重复打开原生选择器', (tester) async {
    final completer = Completer<List<XFile>>();
    var calls = 0;
    List<XTypeGroup>? capturedGroups;
    await tester.pumpWidget(
      buildButton((groups) {
        calls++;
        capturedGroups = groups;
        return completer.future;
      }),
    );

    await tester.tap(find.byTooltip('导入文件'));
    await tester.pump();
    await tester.tap(find.byType(IconButton));
    await tester.pump();

    expect(calls, 1);
    expect(capturedGroups?.single.extensions, <String>['jpg', 'png']);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    completer.complete(const <XFile>[]);
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.cloud_upload_outlined), findsOneWidget);
  });

  testWidgets('原生选择器异常时恢复按钮并显示错误反馈', (tester) async {
    await tester.pumpWidget(
      buildButton((groups) async => throw StateError('picker failed')),
    );

    await tester.tap(find.byTooltip('导入文件'));
    await tester.pumpAndSettle();

    expect(find.text('导入失败'), findsOneWidget);
    expect(find.byIcon(Icons.cloud_upload_outlined), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('选择器返回不支持的格式时显示明确反馈且不启动导入', (tester) async {
    await tester.pumpWidget(
      buildButton(
        (_) async => <XFile>[
          XFile(
            'photo.webp',
            name: 'photo.webp',
            mimeType: 'image/webp',
            length: 3,
            bytes: Uint8List.fromList(<int>[1, 2, 3]),
          ),
        ],
        acceptedExtensions: const <String>['jpg', 'png', 'webp'],
        unsupportedExtensions: const <String>['webp'],
      ),
    );

    await tester.tap(find.byTooltip('导入文件'));
    await tester.pumpAndSettle();

    expect(find.textContaining('不支持以下文件格式'), findsOneWidget);
    expect(find.byType(Dialog), findsNothing);
    expect(find.byType(BottomSheet), findsNothing);
    expect(find.byIcon(Icons.cloud_upload_outlined), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('关闭导入错误弹窗时保留嵌套导航中的业务页面', (tester) async {
    final service = _StubMediaImportService(parentId: null);
    await tester.pumpWidget(
      buildButton(
        (_) async => <XFile>[
          XFile(
            'photo.jpg',
            name: 'photo.jpg',
            mimeType: 'image/jpeg',
            length: 3,
            bytes: Uint8List.fromList(<int>[1, 2, 3]),
          ),
        ],
        importService: service,
      ),
    );

    await tester.tap(find.byTooltip('导入文件'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pump();
    expect(find.text('导入失败'), findsOneWidget);

    await tester.tap(find.text('关闭'));
    await tester.pumpAndSettle();

    expect(find.byType(MediaImportButton), findsOneWidget);
    expect(find.byType(Dialog), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('导入完成后关闭弹窗并且只刷新一次业务页面', (tester) async {
    var refreshCount = 0;
    final service = _StubMediaImportService(parentId: 'photos');
    await tester.pumpWidget(
      buildButton(
        (_) async => <XFile>[
          XFile(
            'photo.jpg',
            name: 'photo.jpg',
            mimeType: 'image/jpeg',
            length: 3,
            bytes: Uint8List.fromList(<int>[1, 2, 3]),
          ),
        ],
        importService: service,
        onImportComplete: () => refreshCount++,
      ),
    );

    await tester.tap(find.byTooltip('导入文件'));
    await tester.pumpAndSettle();

    expect(find.byType(MediaImportButton), findsOneWidget);
    expect(find.byType(Dialog), findsNothing);
    expect(refreshCount, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('导入完成后先关闭进度弹窗再等待页面刷新', (tester) async {
    final refreshCompleter = Completer<void>();
    final service = _StubMediaImportService(parentId: 'photos');
    await tester.pumpWidget(
      buildButton(
        (_) async => <XFile>[
          XFile(
            'photo.jpg',
            name: 'photo.jpg',
            mimeType: 'image/jpeg',
            length: 3,
            bytes: Uint8List.fromList(<int>[1, 2, 3]),
          ),
        ],
        importService: service,
        onImportComplete: () => refreshCompleter.future,
      ),
    );

    await tester.tap(find.byTooltip('导入文件'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.byType(Dialog), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    refreshCompleter.complete();
    await tester.pumpAndSettle();

    expect(find.textContaining('已导入 1 个文件'), findsOneWidget);
    expect(find.byIcon(Icons.cloud_upload_outlined), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('导入完成后的列表刷新失败时显示独立反馈', (tester) async {
    final service = _StubMediaImportService(parentId: 'photos');
    await tester.pumpWidget(
      buildButton(
        (_) async => <XFile>[
          XFile(
            'photo.jpg',
            name: 'photo.jpg',
            mimeType: 'image/jpeg',
            length: 3,
            bytes: Uint8List.fromList(<int>[1, 2, 3]),
          ),
        ],
        importService: service,
        onImportComplete: () => throw StateError('refresh failed'),
      ),
    );

    await tester.tap(find.byTooltip('导入文件'));
    await tester.pumpAndSettle();

    expect(find.text('文件已导入，但列表刷新失败。'), findsOneWidget);
    expect(find.byIcon(Icons.cloud_upload_outlined), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('页面退出会取消仍在进行的媒体导入且不访问已卸载状态', (tester) async {
    final service = _BlockingMediaImportService();
    await tester.pumpWidget(
      buildButton(
        (_) async => <XFile>[
          XFile(
            'photo.jpg',
            name: 'photo.jpg',
            mimeType: 'image/jpeg',
            length: 3,
            bytes: Uint8List.fromList(<int>[1, 2, 3]),
          ),
        ],
        importService: service,
      ),
    );

    await tester.tap(find.byType(IconButton));
    await tester.pump();
    await service.started.future;

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();

    expect(service.cancellationToken?.isCancelled, isTrue);
    expect(tester.takeException(), isNull);
  });
}

void _noop() {}

class _StubMediaImportService extends MediaImportService {
  _StubMediaImportService({required this.parentId})
    : super(_UnusedFileApi(), _UnusedTaskApi());

  final String? parentId;

  @override
  Future<String?> ensureDefaultDirectory({
    required String directoryName,
    String? spaceType,
  }) async {
    return parentId;
  }

  @override
  Future<List<String>> importFiles({
    required List<XFile> files,
    required String parentId,
    String? spaceType,
    bool reuseExistingFiles = false,
    ImportProgressCallback? onProgress,
    MediaImportCancellationToken? cancellationToken,
  }) async {
    return files.map((file) => file.name).toList();
  }

  @override
  Future<MediaImportBatchResult> importFilesDetailed({
    required List<XFile> files,
    required String parentId,
    String? spaceType,
    bool reuseExistingFiles = false,
    ImportProgressCallback? onProgress,
    MediaImportCancellationToken? cancellationToken,
  }) async {
    return MediaImportBatchResult(
      imported: files
          .map((file) => ImportedMediaFile(fileName: file.name, fileNodeId: ''))
          .toList(growable: false),
      failures: const <MediaImportFailure>[],
    );
  }
}

class _UnusedFileApi extends FileApi {
  _UnusedFileApi()
    : super(
        ApiClient(
          const AppEnvironment(
            apiBaseUrl: 'http://localhost:8080/api/v1',
            wsBaseUrl: 'ws://localhost:8080/ws',
          ),
        ),
      );
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

class _BlockingMediaImportService extends MediaImportService {
  _BlockingMediaImportService() : super(_UnusedFileApi(), _UnusedTaskApi());

  final Completer<void> started = Completer<void>();
  MediaImportCancellationToken? cancellationToken;

  @override
  Future<String?> ensureDefaultDirectory({
    required String directoryName,
    String? spaceType,
  }) async {
    return 'photos';
  }

  @override
  Future<List<String>> importFiles({
    required List<XFile> files,
    required String parentId,
    String? spaceType,
    bool reuseExistingFiles = false,
    ImportProgressCallback? onProgress,
    MediaImportCancellationToken? cancellationToken,
  }) async {
    this.cancellationToken = cancellationToken;
    final completer = Completer<List<String>>();
    cancellationToken?.addListener(
      () => completer.completeError(const MediaImportCancelledException()),
    );
    started.complete();
    return completer.future;
  }

  @override
  Future<MediaImportBatchResult> importFilesDetailed({
    required List<XFile> files,
    required String parentId,
    String? spaceType,
    bool reuseExistingFiles = false,
    ImportProgressCallback? onProgress,
    MediaImportCancellationToken? cancellationToken,
  }) async {
    this.cancellationToken = cancellationToken;
    final completer = Completer<MediaImportBatchResult>();
    cancellationToken?.addListener(
      () => completer.completeError(const MediaImportCancelledException()),
    );
    started.complete();
    return completer.future;
  }
}
