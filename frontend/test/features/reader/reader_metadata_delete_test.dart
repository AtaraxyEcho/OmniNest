import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/app_theme.dart';
import 'package:omninest/core/errors/app_exception.dart';
import 'package:omninest/core/feedback/omni_feedback.dart';
import 'package:omninest/features/reader/application/reader_controller.dart';
import 'package:omninest/features/reader/domain/reader_models.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_metadata_section.dart';
import 'package:omninest/features/tasks/domain/task_record.dart';
import 'package:toastification/toastification.dart';

/// 记录删除调用的中心控制器桩：只替换删除入口涉及的状态与网络流程。
class _RecordingReaderCenterController extends ReaderCenterController {
  final List<String> deletedItemIds = <String>[];
  final List<bool> deletedCascades = <bool>[];

  /// 非空时删除调用直接抛出该异常，用于校验失败原因是否回显。
  Object? deleteFailure;

  @override
  Future<ReaderCenterState> build() async {
    return ReaderCenterState(
      dashboard: ReaderDashboard.empty(),
      items: const [],
      searchQuery: '',
    );
  }

  @override
  Future<TaskSubmission> deleteItem(
    String itemId, {
    bool cascade = true,
  }) async {
    deletedItemIds.add(itemId);
    deletedCascades.add(cascade);
    final failure = deleteFailure;
    if (failure != null) {
      throw failure;
    }
    return const TaskSubmission(taskId: 'purge-task', status: 'QUEUED');
  }
}

ReaderItem _item({String? fileNodeId = 'file-1'}) {
  return ReaderItem(
    id: 'item-1',
    title: 'Dune',
    itemType: 'EPUB',
    fileNodeId: fileNodeId,
    authorName: 'Frank Herbert',
    metadataStatus: 'MATCHED',
    updatedAt: DateTime.utc(2026, 10, 12),
  );
}

Widget _wrap(Widget child, _RecordingReaderCenterController controller) {
  return ProviderScope(
    overrides: [readerCenterControllerProvider.overrideWith(() => controller)],
    child: ToastificationWrapper(
      config: omniFeedbackToastConfig,
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('en'),
        theme: OmniNestTheme.dark(),
        home: Scaffold(
          body: SizedBox(
            width: 760,
            child: SingleChildScrollView(child: child),
          ),
        ),
      ),
    ),
  );
}

Future<void> _openRowMenu(WidgetTester tester) async {
  await tester.tap(find.byIcon(Icons.more_vert_rounded));
  await tester.pumpAndSettle();
}

/// 提示条有自动消失计时器，用例结束前必须让它走完，否则 pending Timer 断言失败。
Future<void> _drainFeedbackToast(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 10));
  await tester.pump();
}

void main() {
  setUp(() {
    // toastification 是全局单例，跨用例残留会吞掉后续提示条目。
    toastification.managers.clear();
  });

  testWidgets('管理页行菜单提供删除书籍入口', (tester) async {
    final controller = _RecordingReaderCenterController();

    await tester.pumpWidget(
      _wrap(MetadataSection(items: [_item()]), controller),
    );
    await tester.pumpAndSettle();

    await _openRowMenu(tester);

    expect(find.text('Delete Book'), findsOneWidget);
    expect(find.text('Move to Shared Space'), findsOneWidget);
    expect(controller.deletedItemIds, isEmpty);
  });

  testWidgets('确认后按级联删除书籍与源文件', (tester) async {
    final controller = _RecordingReaderCenterController();

    await tester.pumpWidget(
      _wrap(MetadataSection(items: [_item()]), controller),
    );
    await tester.pumpAndSettle();

    await _openRowMenu(tester);
    await tester.tap(find.text('Delete Book'));
    await tester.pumpAndSettle();

    expect(find.text('Confirm Permanent Deletion'), findsOneWidget);
    expect(
      find.textContaining('Both the library entry and the source file'),
      findsOneWidget,
    );

    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle();

    expect(controller.deletedItemIds, <String>['item-1']);
    expect(controller.deletedCascades, <bool>[true]);
    expect(find.textContaining('Deleted'), findsOneWidget);
    await _drainFeedbackToast(tester);
  });

  testWidgets('取消确认不会发起删除', (tester) async {
    final controller = _RecordingReaderCenterController();

    await tester.pumpWidget(
      _wrap(MetadataSection(items: [_item()]), controller),
    );
    await tester.pumpAndSettle();

    await _openRowMenu(tester);
    await tester.tap(find.text('Delete Book'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();

    expect(controller.deletedItemIds, isEmpty);
  });

  testWidgets('缺少源文件节点的条目仍可删除', (tester) async {
    final controller = _RecordingReaderCenterController();

    await tester.pumpWidget(
      _wrap(MetadataSection(items: [_item(fileNodeId: null)]), controller),
    );
    await tester.pumpAndSettle();

    await _openRowMenu(tester);
    expect(find.text('Delete Book'), findsOneWidget);
    expect(find.text('Move to Shared Space'), findsNothing);

    await tester.tap(find.text('Delete Book'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle();

    expect(controller.deletedItemIds, <String>['item-1']);
    await _drainFeedbackToast(tester);
  });

  testWidgets('删除失败时回显服务端原因而不是通用重试提示', (tester) async {
    final controller =
        _RecordingReaderCenterController()
          ..deleteFailure = const AppException(
            code: '6001',
            message: '阅读条目不存在或无权删除',
          );

    await tester.pumpWidget(
      _wrap(MetadataSection(items: [_item()]), controller),
    );
    await tester.pumpAndSettle();

    await _openRowMenu(tester);
    await tester.tap(find.text('Delete Book'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle();

    expect(find.textContaining('阅读条目不存在或无权删除'), findsOneWidget);
    expect(find.textContaining('Delete failed'), findsNothing);
    await _drainFeedbackToast(tester);
  });
}
