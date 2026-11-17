import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/app_theme.dart';
import 'package:omninest/app/theme/app_theme_palette.dart';
import 'package:omninest/features/photos/application/photo_batch_task_monitor.dart';
import 'package:omninest/features/photos/application/photo_controller.dart';
import 'package:omninest/features/photos/domain/photo_batch_task.dart';
import 'package:omninest/features/photos/presentation/widgets/batch_progress_dialog.dart';

class _SpyPhotoCenterController extends PhotoCenterController {
  int refreshCalls = 0;

  @override
  Future<PhotoCenterState> build() async => PhotoCenterState.empty();

  @override
  Future<void> refresh() async {
    refreshCalls += 1;
  }
}

PhotoBatchTask _task(String taskType, String status) {
  return PhotoBatchTask(
    id: 'task-1',
    taskType: taskType,
    status: status,
    totalItems: 2,
    processedItems: 2,
    createdAt: DateTime(2026, 9, 15),
  );
}

Future<int> _pumpAndCountRefreshes(
  WidgetTester tester, {
  required _SpyPhotoCenterController controller,
  required List<PhotoBatchTaskMonitorState> states,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        photoCenterControllerProvider.overrideWith(() => controller),
        photoBatchTaskMonitorProvider.overrideWith(
          (ref, taskId) => Stream.fromIterable(states),
        ),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('zh'),
        theme: OmniNestTheme.from(AppThemePalette.dark),
        home: const Scaffold(body: BatchProgressDialog(taskId: 'task-1')),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return controller.refreshCalls;
}

void main() {
  testWidgets('completed TAG task triggers exactly one refresh', (
    tester,
  ) async {
    final refreshCalls = await _pumpAndCountRefreshes(
      tester,
      controller: _SpyPhotoCenterController(),
      states: [
        PhotoBatchTaskMonitorState(task: _task('TAG', 'RUNNING')),
        PhotoBatchTaskMonitorState(task: _task('TAG', 'COMPLETED')),
      ],
    );

    expect(refreshCalls, 1);
  });

  testWidgets('completed UPDATE_DATE task triggers exactly one refresh', (
    tester,
  ) async {
    final refreshCalls = await _pumpAndCountRefreshes(
      tester,
      controller: _SpyPhotoCenterController(),
      states: [
        PhotoBatchTaskMonitorState(task: _task('UPDATE_DATE', 'RUNNING')),
        PhotoBatchTaskMonitorState(task: _task('UPDATE_DATE', 'COMPLETED')),
      ],
    );

    expect(refreshCalls, 1);
  });

  testWidgets('failed TAG task still refreshes for partial mutations', (
    tester,
  ) async {
    final refreshCalls = await _pumpAndCountRefreshes(
      tester,
      controller: _SpyPhotoCenterController(),
      states: [
        PhotoBatchTaskMonitorState(task: _task('TAG', 'RUNNING')),
        PhotoBatchTaskMonitorState(task: _task('TAG', 'FAILED')),
      ],
    );

    expect(refreshCalls, 1);
  });

  testWidgets('completed DOWNLOAD task does not refresh', (tester) async {
    final refreshCalls = await _pumpAndCountRefreshes(
      tester,
      controller: _SpyPhotoCenterController(),
      states: [
        PhotoBatchTaskMonitorState(task: _task('DOWNLOAD', 'RUNNING')),
        PhotoBatchTaskMonitorState(task: _task('DOWNLOAD', 'COMPLETED')),
      ],
    );

    expect(refreshCalls, 0);
  });

  testWidgets('repeated terminal emissions refresh only once', (tester) async {
    final refreshCalls = await _pumpAndCountRefreshes(
      tester,
      controller: _SpyPhotoCenterController(),
      states: [
        PhotoBatchTaskMonitorState(task: _task('TAG', 'RUNNING')),
        PhotoBatchTaskMonitorState(task: _task('TAG', 'COMPLETED')),
        PhotoBatchTaskMonitorState(task: _task('TAG', 'COMPLETED')),
      ],
    );

    expect(refreshCalls, 1);
  });
}
