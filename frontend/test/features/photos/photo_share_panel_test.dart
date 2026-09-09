import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/app_theme.dart';
import 'package:omninest/features/photos/application/photo_controller.dart';
import 'package:omninest/features/photos/domain/photo.dart';
import 'package:omninest/features/photos/domain/photo_repository.dart';
import 'package:omninest/features/photos/domain/photo_share_link.dart';
import 'package:omninest/features/photos/presentation/widgets/photo_share_panel.dart';

class _MockPhotoRepository extends Mock implements PhotoRepository {}

PhotoItem _photo() {
  return PhotoItem(
    id: 'photo-1',
    fileNodeId: 'file-1',
    title: 'Motion Shot',
    format: 'JPEG',
    fileSize: 1024,
    metadataStatus: 'READY',
    favorite: false,
    createdAt: DateTime(2024, 11, 12),
    coverUrl: 'https://example.com/thumb.jpg',
    gpsLocation: <String, dynamic>{'city': 'Bern'},
  );
}

Future<void> _pumpPanel(WidgetTester tester, PhotoRepository repository) async {
  tester.view.physicalSize = const Size(1280, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [photoRepositoryProvider.overrideWithValue(repository)],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('zh'),
        theme: OmniNestTheme.dark(),
        home: Scaffold(
          body: Stack(
            fit: StackFit.expand,
            children: [
              const ColoredBox(color: Colors.black),
              PhotoSharePanel(visible: true, photo: _photo()),
            ],
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
}

void main() {
  setUp(() {
    // 测试环境 mock 剪贴板平台通道，保证自动复制链路立即完成。
    TestWidgetsFlutterBinding.ensureInitialized();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          SystemChannels.platform,
          (call) async => null,
        );
  });
  testWidgets('打开分享侧栏创建链接并展示复制/宫格/开关', (tester) async {
    final repository = _MockPhotoRepository();
    final link = PhotoShareLink(
      id: 'share-1',
      token: 'tok-1',
      resourceType: 'PHOTO_ITEM',
      resourceId: 'photo-1',
      accessCount: 0,
      createdAt: DateTime(2024, 11, 12),
    );
    when(() => repository.listPhotoShares(any())).thenAnswer((_) async => []);
    when(
      () => repository.createPhotoShare(
        any(),
        password: any(named: 'password'),
        expiresAt: any(named: 'expiresAt'),
        maxAccessCount: any(named: 'maxAccessCount'),
      ),
    ).thenAnswer((_) async => link);
    await _pumpPanel(tester, repository);
    await tester.pump();
    await tester.pump();

    // 眉题与预览卡标题、地点角标（预览卡与 OPTIONS 副标签各一处）。
    expect(find.text('分享'), findsOneWidget);
    expect(find.text('Motion Shot'), findsOneWidget);
    expect(find.text('Bern'), findsNWidgets(2));
    // 链接基于前端站点地址（默认退化 origin），而非 API 地址；复制为手动操作。
    expect(find.text('http://localhost:8080/share/tok-1'), findsOneWidget);
    expect(find.text('复制'), findsOneWidget);
    expect(find.text('✓ 已复制'), findsNothing);
    await tester.tap(find.text('复制'));
    await tester.pump();
    await tester.pump();
    expect(find.text('✓ 已复制'), findsOneWidget);
    // 渠道宫格、OPTIONS 开关与管理入口。
    expect(find.text('分享至'), findsOneWidget);
    expect(find.text('有效期'), findsOneWidget);
    expect(find.text('密码保护'), findsOneWidget);
    expect(find.text('未设置'), findsOneWidget);
    expect(find.text('包含位置信息'), findsOneWidget);
    expect(find.text('原图画质'), findsOneWidget);
    expect(find.text('管理已有链接'), findsOneWidget);
    expect(find.text('完成'), findsOneWidget);
  });

  testWidgets('切换有效期为 7 天后按新时限重建链接并复制', (tester) async {
    final repository = _MockPhotoRepository();
    final link = PhotoShareLink(
      id: 'share-1',
      token: 'tok-1',
      resourceType: 'PHOTO_ITEM',
      resourceId: 'photo-1',
      accessCount: 0,
      createdAt: DateTime(2024, 11, 12),
    );
    when(() => repository.listPhotoShares(any())).thenAnswer((_) async => []);
    when(
      () => repository.createPhotoShare(
        any(),
        password: any(named: 'password'),
        expiresAt: captureAny(named: 'expiresAt'),
        maxAccessCount: any(named: 'maxAccessCount'),
      ),
    ).thenAnswer((_) async => link);

    await _pumpPanel(tester, repository);
    await tester.pump();
    await tester.pump();

    await tester.dragUntilVisible(
      find.text('有效期'),
      find.byType(Scrollable).first,
      const Offset(0, -120),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('有效期'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('7天'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    final captured =
        verify(
          () => repository.createPhotoShare(
            any(),
            password: any(named: 'password'),
            expiresAt: captureAny(named: 'expiresAt'),
            maxAccessCount: any(named: 'maxAccessCount'),
          ),
        ).captured;
    final expiry = captured.last;
    final days = expiry.difference(DateTime.now()).inDays;
    expect(days, inInclusiveRange(6, 7));
  });

  testWidgets('开启密码保护后携带密码重建链接', (tester) async {
    final repository = _MockPhotoRepository();
    final link = PhotoShareLink(
      id: 'share-2',
      token: 'tok-2',
      resourceType: 'PHOTO_ITEM',
      resourceId: 'photo-1',
      accessCount: 0,
      createdAt: DateTime(2024, 11, 12),
    );
    when(() => repository.listPhotoShares(any())).thenAnswer((_) async => []);
    when(
      () => repository.createPhotoShare(
        any(),
        password: captureAny(named: 'password'),
        expiresAt: any(named: 'expiresAt'),
        maxAccessCount: any(named: 'maxAccessCount'),
      ),
    ).thenAnswer((_) async => link);

    await _pumpPanel(tester, repository);
    await tester.pump();
    await tester.pump();

    await tester.dragUntilVisible(
      find.text('密码保护'),
      find.byType(Scrollable).first,
      const Offset(0, -120),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('密码保护'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'secret123');
    await tester.tap(find.text('确认'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    final captured =
        verify(
          () => repository.createPhotoShare(
            any(),
            password: captureAny(named: 'password'),
            expiresAt: any(named: 'expiresAt'),
            maxAccessCount: any(named: 'maxAccessCount'),
          ),
        ).captured;
    expect(captured.last, 'secret123');
    expect(find.text('已启用'), findsOneWidget);
  });

  testWidgets('链接创建失败时在链接框内展示错误', (tester) async {
    final repository = _MockPhotoRepository();
    when(() => repository.listPhotoShares(any())).thenAnswer((_) async => []);
    when(
      () => repository.createPhotoShare(
        any(),
        password: any(named: 'password'),
        expiresAt: any(named: 'expiresAt'),
        maxAccessCount: any(named: 'maxAccessCount'),
      ),
    ).thenThrow(Exception('boom'));

    await _pumpPanel(tester, repository);

    expect(find.text('创建分享链接失败'), findsOneWidget);
  });
}
