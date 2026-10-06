// 托管态分享面板：原型眉标 + 环境开关行 + 分段 + 酸绿主行动，
// 创建失败必须在面板内给出本地化摘要而不是停在忙碌态。
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/providers.dart';
import 'package:omninest/app/theme/app_theme.dart';
import 'package:omninest/core/errors/app_exception.dart';
import 'package:omninest/core/widgets/mobile_shell_scope.dart';
import 'package:omninest/core/widgets/mobile_ui.dart';
import 'package:omninest/core/widgets/workstation_controls.dart';
import 'package:omninest/features/files/data/file_providers.dart';
import 'package:omninest/features/files/domain/file_manager_models.dart';
import 'package:omninest/features/files/domain/file_node.dart';
import 'package:omninest/features/files/domain/file_repository.dart';
import 'package:omninest/features/files/presentation/widgets/share_link_sheet.dart';

class _MockFileRepository extends Mock implements FileRepository {}

/// 固定分享基址：避免解析流程触达环境与网络。
class _StubShareBaseUrlResolver implements WebShareBaseUrlResolver {
  const _StubShareBaseUrlResolver();

  @override
  Future<String> resolve() async => 'https://share.test';
}

const _seedFile = FileNode(
  id: 'file-1',
  parentId: null,
  name: 'golden-hour.jpg',
  isFolder: false,
  nodeType: 'FILE',
  normalizedPath: '/Photos/golden-hour.jpg',
  sizeBytes: 2048,
  mimeType: 'image/jpeg',
  updatedAt: null,
);

FileShareLink _link({String? generatedPassword}) {
  return FileShareLink(
    id: 'share-1',
    resourceType: 'FILE',
    resourceId: 'file-1',
    resourceName: _seedFile.name,
    shareCode: 'ab12cd',
    status: 'ACTIVE',
    accessCount: 0,
    createdAt: DateTime(2026, 10, 5),
    generatedPassword: generatedPassword,
  );
}

void _stubCreate(
  FileRepository repository, {
  Object? error,
  FileShareLink? link,
}) {
  when(
    () => repository.createShareLink(
      resourceId: any(named: 'resourceId'),
      resourceType: any(named: 'resourceType'),
      password: any(named: 'password'),
      generatePassword: any(named: 'generatePassword'),
      expiresAt: any(named: 'expiresAt'),
      maxAccessCount: any(named: 'maxAccessCount'),
    ),
  ).thenAnswer((_) async {
    if (error != null) {
      throw error;
    }
    return link!;
  });
}

Future<void> _openSheet(WidgetTester tester, FileRepository repository) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(390, 844);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        fileRepositoryProvider.overrideWithValue(repository),
        webShareBaseUrlResolverProvider.overrideWithValue(
          const _StubShareBaseUrlResolver(),
        ),
      ],
      child: MaterialApp(
        theme: OmniNestTheme.dark(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('zh'),
        home: Scaffold(
          body: MobileShellScope(
            hosted: true,
            child: Builder(
              builder:
                  (context) => TextButton(
                    onPressed:
                        () => ShareLinkSheet.show(context, file: _seedFile),
                    child: const Text('打开分享面板'),
                  ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('打开分享面板'));
  await tester.pumpAndSettle();
}

Future<void> _tapCreate(WidgetTester tester) async {
  await tester.tap(find.text('创建分享链接'));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          SystemChannels.platform,
          (call) async => null,
        );
  });

  testWidgets('托管态用原型分段与开关行，不出现工位控件', (tester) async {
    final repository = _MockFileRepository();
    _stubCreate(repository, link: _link());
    await _openSheet(tester, repository);

    expect(tester.takeException(), isNull);
    // 有效期是原型 `.segmented` 三档，而不是桌面日期选择器。
    expect(find.text('过期时间'), findsOneWidget);
    expect(find.text('永久有效'), findsOneWidget);
    expect(find.text('7 天'), findsOneWidget);
    expect(find.text('30 天'), findsOneWidget);
    expect(find.text('高级选项'), findsOneWidget);
    expect(find.text('创建分享链接'), findsOneWidget);
    // 工位形态控件不得混入托管面板：分段走 MobileSegmentedControl，
    // 口令开关走原型 .notif-toggle-row。
    expect(
      find.byWidgetPredicate((widget) => widget is MobileSegmentedControl),
      findsAtLeastNWidgets(1),
    );
    expect(find.byType(MobileEnvSwitch), findsOneWidget);
    expect(
      find.byType(WorkstationToggle),
      findsNothing,
      reason: '托管态口令开关换成原型 .notif-toggle-row',
    );
  });

  testWidgets('开启口令后出现提取码分段与自定义口令字段', (tester) async {
    final repository = _MockFileRepository();
    _stubCreate(repository, link: _link());
    await _openSheet(tester, repository);

    await tester.tap(find.byType(MobileEnvSwitch));
    await tester.pumpAndSettle();
    expect(find.text('提取码'), findsOneWidget);
    expect(find.text('随机生成'), findsOneWidget);
    expect(find.text('自定义密码'), findsOneWidget);

    await tester.tap(find.text('自定义密码'));
    await tester.pumpAndSettle();
    final passwordField = find.widgetWithText(TextField, '自定义密码');
    expect(passwordField, findsOneWidget);
    final field = tester.widget<TextField>(passwordField);
    expect(field.obscureText, isTrue, reason: '口令字段保持掩码');
    expect(field.controller?.text, isEmpty, reason: '切到自定义口令不应残留既有输入');
  });

  testWidgets('创建成功后展示链接与提取码', (tester) async {
    final repository = _MockFileRepository();
    _stubCreate(repository, link: _link(generatedPassword: 'XK3F'));
    await _openSheet(tester, repository);

    await _tapCreate(tester);

    expect(tester.takeException(), isNull);
    expect(
      find.textContaining('https://share.test/#/s/ab12cd'),
      findsOneWidget,
    );
    expect(find.byIcon(Icons.copy), findsWidgets);
    expect(find.textContaining('密码: XK3F'), findsOneWidget);
  });

  testWidgets('创建失败在面板内给出本地化摘要并可重试', (tester) async {
    final repository = _MockFileRepository();
    _stubCreate(
      repository,
      error: const AppException(
        code: 'SHARE_CREATE_FAILED',
        message: '分享域名未配置',
      ),
    );
    await _openSheet(tester, repository);

    await _tapCreate(tester);

    expect(tester.takeException(), isNull);
    // 摘要行取本地化标签，不得把 AppLocalizations 对象插进文案。
    expect(find.text('创建失败：分享域名未配置'), findsOneWidget);
    expect(find.textContaining('AppLocalizations'), findsNothing);
    // 失败后按钮回到可用态，不卡在忙碌指示上。
    expect(find.text('创建分享链接'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    verify(
      () => repository.createShareLink(
        resourceId: any(named: 'resourceId'),
        resourceType: any(named: 'resourceType'),
        password: any(named: 'password'),
        generatePassword: any(named: 'generatePassword'),
        expiresAt: any(named: 'expiresAt'),
        maxAccessCount: any(named: 'maxAccessCount'),
      ),
    ).called(1);
  });
}
