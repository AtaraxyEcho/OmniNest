import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:omninest/app/environment.dart';
import 'package:omninest/app/environment_providers.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/app_theme.dart';
import 'package:omninest/features/photos/application/photo_controller.dart';
import 'package:omninest/features/photos/domain/photo.dart';
import 'package:omninest/features/photos/domain/photo_repository.dart';
import 'package:omninest/features/photos/domain/photo_share_link.dart';
import 'package:omninest/features/photos/presentation/widgets/photo_share_panel.dart';
import 'package:qr_flutter/qr_flutter.dart';

class _MockPhotoRepository extends Mock implements PhotoRepository {}

/// 选中态胶囊：面板把选中状态挂在 Semantics.selected 上，测试据此断言
/// 写回失败后档位是否回滚到服务端状态，而不是比对颜色常量。
final _selectedChip = find.byWidgetPredicate(
  (widget) => widget is Semantics && widget.properties.selected == true,
);

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

PhotoShareLink _link({
  String id = 'share-1',
  String token = 'tok-1',
  int accessCount = 0,
  DateTime? createdAt,
  DateTime? expiresAt,
  bool passwordProtected = false,
  bool includeLocation = true,
  bool originalQuality = true,
}) {
  return PhotoShareLink(
    id: id,
    token: token,
    resourceType: 'PHOTO_ITEM',
    resourceId: 'photo-1',
    accessCount: accessCount,
    createdAt: createdAt ?? DateTime(2024, 11, 12),
    expiresAt: expiresAt,
    passwordProtected: passwordProtected,
    includeLocation: includeLocation,
    originalQuality: originalQuality,
  );
}

/// 创建桩与面板调用点的命名参数集合保持一致，避免 mocktail 命名参数静默失配。
void _stubCreate(
  PhotoRepository repository,
  PhotoShareLink Function(Invocation invocation) response, {
  List<Invocation>? requests,
}) {
  when(
    () => repository.createPhotoShare(
      any(),
      password: any(named: 'password'),
      expiresAt: any(named: 'expiresAt'),
      includeLocation: any(named: 'includeLocation'),
      originalQuality: any(named: 'originalQuality'),
    ),
  ).thenAnswer((invocation) async {
    requests?.add(invocation);
    return response(invocation);
  });
}

/// 写回桩：默认把请求参数回显成服务端状态，摘要与档位才反映"已生效"。
void _stubUpdate(
  PhotoRepository repository, {
  PhotoShareLink Function(Invocation invocation)? response,
  List<Invocation>? requests,
}) {
  when(
    () => repository.updatePhotoShare(
      any(),
      password: any(named: 'password'),
      expiresAt: any(named: 'expiresAt'),
      maxAccessCount: any(named: 'maxAccessCount'),
      includeLocation: any(named: 'includeLocation'),
      originalQuality: any(named: 'originalQuality'),
    ),
  ).thenAnswer((invocation) async {
    requests?.add(invocation);
    if (response != null) return response(invocation);
    final args = invocation.namedArguments;
    return _link(
      id: 'share-9',
      token: 'tok-9',
      passwordProtected: (args[#password] as String?)?.isNotEmpty ?? false,
      expiresAt: args[#expiresAt] as DateTime?,
      includeLocation: args[#includeLocation] as bool? ?? true,
      originalQuality: args[#originalQuality] as bool? ?? true,
    );
  });
}

void _failUpdate(PhotoRepository repository) {
  when(
    () => repository.updatePhotoShare(
      any(),
      password: any(named: 'password'),
      expiresAt: any(named: 'expiresAt'),
      maxAccessCount: any(named: 'maxAccessCount'),
      includeLocation: any(named: 'includeLocation'),
      originalQuality: any(named: 'originalQuality'),
    ),
  ).thenThrow(Exception('boom'));
}

void _verifyNeverCreate(PhotoRepository repository) {
  verifyNever(
    () => repository.createPhotoShare(
      any(),
      password: any(named: 'password'),
      expiresAt: any(named: 'expiresAt'),
      includeLocation: any(named: 'includeLocation'),
      originalQuality: any(named: 'originalQuality'),
    ),
  );
}

void _verifyNeverUpdate(PhotoRepository repository) {
  verifyNever(
    () => repository.updatePhotoShare(
      any(),
      password: any(named: 'password'),
      expiresAt: any(named: 'expiresAt'),
      maxAccessCount: any(named: 'maxAccessCount'),
      includeLocation: any(named: 'includeLocation'),
      originalQuality: any(named: 'originalQuality'),
    ),
  );
}

Future<void> _pumpPanel(WidgetTester tester, PhotoRepository repository) async {
  tester.view.physicalSize = const Size(1280, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        photoRepositoryProvider.overrideWithValue(repository),
        presetAppEnvironmentProvider.overrideWithValue(
          const AppEnvironment(
            apiBaseUrl: 'http://localhost:8080/api/v1',
            wsBaseUrl: 'ws://localhost:8080/ws',
          ),
        ),
      ],
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

Future<void> _scrollTo(WidgetTester tester, Finder target) async {
  await tester.dragUntilVisible(
    target,
    find.byType(Scrollable).first,
    const Offset(0, -120),
  );
  await tester.pumpAndSettle();
}

Future<void> _confirmPrompt(WidgetTester tester, String password) async {
  await tester.enterText(find.byType(TextField), password);
  await tester.tap(find.text('确认'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

/// 有效期档位距当前时刻的天数容差：面板与断言各自取 now，允许跨秒误差。
bool _isWithinDays(DateTime? moment, int days) {
  if (moment == null) return false;
  final diff = moment.difference(DateTime.now()).inDays;
  return (diff - days).abs() <= 1;
}

void main() {
  setUp(() {
    // 测试环境 mock 剪贴板平台通道，保证复制链路立即完成。
    TestWidgetsFlutterBinding.ensureInitialized();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          SystemChannels.platform,
          (call) async => null,
        );
    // mock share_plus 插件通道：fake-async 挂起真实引擎响应；返回 null 会被
    // share_plus 归一为 unavailable 状态，从而确定性覆盖降级复制路径。
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('dev.fluttercommunity.plus/share'),
          (call) async => null,
        );
  });

  testWidgets('打开分享侧栏创建链接并展示复制/宫格/开关（桌面形态）', (tester) async {
    final repository = _MockPhotoRepository();
    when(() => repository.listPhotoShares(any())).thenAnswer((_) async => []);
    when(() => repository.revokeAlbumShare(any())).thenAnswer((_) async {});
    _stubCreate(repository, (invocation) => _link());

    await _pumpPanel(tester, repository);
    await tester.pump();
    await tester.pump();

    // 打开面板不创建链接：无链接时字段显示占位文案，点创建才生成。
    expect(find.text('尚未创建链接'), findsOneWidget);
    expect(find.text('永久链接'), findsNothing);
    expect(find.text('限时链接'), findsNothing);
    // 只有一条链接时不需要管理入口：撤销就在摘要行里。
    expect(find.text('管理已有链接'), findsNothing);
    await tester.tap(find.text('创建链接'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // 眉题与预览卡标题、地点角标（预览卡与设置副标签各一处）。
    expect(find.text('分享'), findsOneWidget);
    expect(find.text('Motion Shot'), findsOneWidget);
    expect(find.text('Bern'), findsNWidgets(2));
    // 链接基于前端站点地址（默认退化 origin），而非 API 地址；复制为手动操作。
    expect(
      find.text('http://localhost:8080/#/shared/photos/item/tok-1'),
      findsOneWidget,
    );
    expect(find.text('复制'), findsWidgets);
    expect(find.text('✓ 已复制'), findsNothing);
    await tester.tap(find.text('复制').first);
    await tester.pump();
    await tester.pump();
    expect(find.text('✓ 已复制'), findsOneWidget);
    // 渠道宫格（桌面：系统分享隐藏、二维码展示）与链接设置。
    expect(find.text('分享至'), findsOneWidget);
    expect(find.text('微信'), findsNothing);
    expect(find.text('二维码'), findsOneWidget);
    expect(find.text('更多'), findsNothing);
    expect(find.text('链接设置'), findsOneWidget);
    expect(find.text('选项'), findsNothing);
    expect(find.text('有效期'), findsOneWidget);
    expect(find.text('密码保护'), findsOneWidget);
    expect(find.text('包含位置信息'), findsOneWidget);
    // 四档有效期平铺为胶囊：不再有下拉，也不再有两个创建入口。
    expect(find.text('1天'), findsOneWidget);
    expect(find.text('7天'), findsOneWidget);
    expect(find.text('30天'), findsOneWidget);
    expect(find.text('永不过期'), findsOneWidget);
    expect(find.byType(PopupMenuButton<String>), findsNothing);
    expect(find.text('更新链接'), findsNothing);
    // 默认档位 30 天。
    expect(
      find.ancestor(of: find.text('30天'), matching: _selectedChip),
      findsOneWidget,
    );
  }, variant: TargetPlatformVariant.only(TargetPlatform.windows));

  testWidgets('移动端展示微信入口且系统分享不可用时降级复制', (tester) async {
    final repository = _MockPhotoRepository();
    when(() => repository.listPhotoShares(any())).thenAnswer((_) async => []);
    when(() => repository.revokeAlbumShare(any())).thenAnswer((_) async {});
    _stubCreate(repository, (invocation) => _link());

    await _pumpPanel(tester, repository);
    await tester.pump();
    await tester.pump();

    // 链接需显式创建后才可用于渠道分享。
    await tester.tap(find.text('创建链接'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('微信'), findsOneWidget);
    expect(find.text('二维码'), findsNothing);

    // 测试环境无 share_plus 插件实现：点击微信入口应降级复制并提示。
    await tester.tap(find.text('微信'));
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    expect(find.text('✓ 已复制'), findsOneWidget);
    expect(find.text('已复制链接，请粘贴到微信发送'), findsOneWidget);
    await tester.pump(const Duration(seconds: 10));
    await tester.pumpAndSettle();
  });

  testWidgets('桌面端点击二维码弹出真实二维码弹层', (tester) async {
    final repository = _MockPhotoRepository();
    when(() => repository.listPhotoShares(any())).thenAnswer((_) async => []);
    when(() => repository.revokeAlbumShare(any())).thenAnswer((_) async {});
    _stubCreate(repository, (invocation) => _link());

    await _pumpPanel(tester, repository);
    await tester.pump();
    await tester.pump();

    await tester.tap(find.text('创建链接'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    await tester.tap(find.text('二维码'));
    await tester.pumpAndSettle();
    expect(find.byType(QrImageView), findsOneWidget);
    expect(
      find.text('http://localhost:8080/#/shared/photos/item/tok-1'),
      findsWidgets,
    );
  }, variant: TargetPlatformVariant.only(TargetPlatform.windows));

  testWidgets('已有链接时改设置走原地写回，不撤销也不重建', (tester) async {
    final repository = _MockPhotoRepository();
    final requests = <Invocation>[];
    final existing = _link(
      id: 'share-9',
      token: 'tok-9',
      accessCount: 3,
      expiresAt: DateTime.now().add(const Duration(days: 30)),
    );
    when(
      () => repository.listPhotoShares(any()),
    ).thenAnswer((_) async => [existing]);
    _stubUpdate(repository, requests: requests);

    await _pumpPanel(tester, repository);
    await tester.pump();
    await tester.pump();

    expect(
      find.text('http://localhost:8080/#/shared/photos/item/tok-9'),
      findsOneWidget,
    );
    expect(find.text('创建链接'), findsNothing);
    // 摘要行直接给出访问量，不必打开管理也能读到状态。
    expect(find.textContaining('访问 3 次'), findsOneWidget);

    await _scrollTo(tester, find.text('包含位置信息'));
    await tester.tap(find.text('包含位置信息'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    final args = requests.single.namedArguments;
    expect(args[#includeLocation], isFalse);
    // 未改口令时必须传 null：服务端只存哈希，跟着全量提交会抹掉提取码。
    expect(args[#password], isNull);
    // 面板不编辑访问次数，按链接现值回填，不能被"整体替换"清零。
    expect(args[#maxAccessCount], isNull);
    _verifyNeverCreate(repository);
    verifyNever(() => repository.revokeAlbumShare(any()));
  });

  testWidgets('切换有效期档位原地写回新时限且地址保持不变', (tester) async {
    final repository = _MockPhotoRepository();
    final requests = <Invocation>[];
    final existing = _link(
      id: 'share-9',
      token: 'tok-9',
      expiresAt: DateTime.now().add(const Duration(days: 30)),
    );
    when(
      () => repository.listPhotoShares(any()),
    ).thenAnswer((_) async => [existing]);
    _stubUpdate(repository, requests: requests);

    await _pumpPanel(tester, repository);
    await tester.pump();
    await tester.pump();

    await _scrollTo(tester, find.text('7天'));
    await tester.tap(find.text('7天'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(
      _isWithinDays(requests.single.namedArguments[#expiresAt], 7),
      isTrue,
    );
    // 改档位只换属性，不换令牌：已经发出去的地址仍然可用。
    expect(
      find.text('http://localhost:8080/#/shared/photos/item/tok-9'),
      findsOneWidget,
    );
    expect(
      find.ancestor(of: find.text('7天'), matching: _selectedChip),
      findsOneWidget,
    );
    _verifyNeverCreate(repository);
    verifyNever(() => repository.revokeAlbumShare(any()));
  });

  testWidgets('切到永不过期原地清除过期时间', (tester) async {
    final repository = _MockPhotoRepository();
    final requests = <Invocation>[];
    final existing = _link(
      id: 'share-9',
      token: 'tok-9',
      expiresAt: DateTime.now().add(const Duration(days: 30)),
    );
    when(
      () => repository.listPhotoShares(any()),
    ).thenAnswer((_) async => [existing]);
    _stubUpdate(repository, requests: requests);

    await _pumpPanel(tester, repository);
    await tester.pump();
    await tester.pump();

    await _scrollTo(tester, find.text('永不过期'));
    await tester.tap(find.text('永不过期'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(requests.single.namedArguments[#expiresAt], isNull);
    // 服务端记录已改成永久：摘要行同步显示"永不过期"。
    expect(find.textContaining('· 访问 0 次'), findsOneWidget);
  });

  testWidgets('已有链接时开启密码保护原地写回口令', (tester) async {
    final repository = _MockPhotoRepository();
    final requests = <Invocation>[];
    final existing = _link(
      id: 'share-9',
      token: 'tok-9',
      expiresAt: DateTime.now().add(const Duration(days: 30)),
    );
    when(
      () => repository.listPhotoShares(any()),
    ).thenAnswer((_) async => [existing]);
    _stubUpdate(repository, requests: requests);

    await _pumpPanel(tester, repository);
    await tester.pump();
    await tester.pump();

    await _scrollTo(tester, find.text('密码保护'));
    await tester.tap(find.text('密码保护'));
    await tester.pumpAndSettle();
    await _confirmPrompt(tester, 'secret123');

    expect(requests.single.namedArguments[#password], 'secret123');
    expect(find.text('已启用'), findsOneWidget);
    // 摘要出现密码状态，不点开也读得到这条链接受口令保护。
    expect(find.textContaining('已设密码'), findsOneWidget);
    _verifyNeverCreate(repository);
  });

  testWidgets('已有链接时关闭密码保护提交空串表示清除', (tester) async {
    final repository = _MockPhotoRepository();
    final requests = <Invocation>[];
    final existing = _link(
      id: 'share-9',
      token: 'tok-9',
      passwordProtected: true,
      expiresAt: DateTime.now().add(const Duration(days: 30)),
    );
    when(
      () => repository.listPhotoShares(any()),
    ).thenAnswer((_) async => [existing]);
    _stubUpdate(repository, requests: requests);

    await _pumpPanel(tester, repository);
    await tester.pump();
    await tester.pump();

    expect(find.text('已启用'), findsOneWidget);
    expect(find.textContaining('已设密码'), findsOneWidget);

    await _scrollTo(tester, find.text('密码保护'));
    await tester.tap(find.text('密码保护'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(requests.single.namedArguments[#password], isEmpty);
    expect(find.text('未设置'), findsOneWidget);
  });

  testWidgets('尚未创建链接时设置只暂存，创建时随请求提交', (tester) async {
    final repository = _MockPhotoRepository();
    final requests = <Invocation>[];
    when(() => repository.listPhotoShares(any())).thenAnswer((_) async => []);
    _stubCreate(
      repository,
      (invocation) => _link(passwordProtected: true),
      requests: requests,
    );

    await _pumpPanel(tester, repository);
    await tester.pump();
    await tester.pump();

    await _scrollTo(tester, find.text('密码保护'));
    await tester.tap(find.text('密码保护'));
    await tester.pumpAndSettle();
    await _confirmPrompt(tester, 'secret123');
    _verifyNeverUpdate(repository);

    await _scrollTo(tester, find.text('包含位置信息'));
    await tester.tap(find.text('包含位置信息'));
    await tester.pump();
    _verifyNeverUpdate(repository);

    await tester.tap(find.text('创建链接'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    final args = requests.single.namedArguments;
    expect(args[#password], 'secret123');
    expect(args[#includeLocation], isFalse);
    expect(find.text('已启用'), findsOneWidget);
  });

  testWidgets('打开面板复用已有有效链接，不重复创建', (tester) async {
    final repository = _MockPhotoRepository();
    when(
      () => repository.listPhotoShares(any()),
    ).thenAnswer((_) async => [_link(id: 'share-9', token: 'tok-9')]);

    await _pumpPanel(tester, repository);
    await tester.pump();
    await tester.pump();

    // 已有有效链接直接展示（令牌由后端解密回传），且不得再创建新链接。
    expect(
      find.text('http://localhost:8080/#/shared/photos/item/tok-9'),
      findsOneWidget,
    );
    expect(find.text('创建链接'), findsNothing);
    _verifyNeverCreate(repository);
  });

  testWidgets('多条链接时面板固定编辑最新一条，其余只计数不隐身', (tester) async {
    final repository = _MockPhotoRepository();
    final requests = <Invocation>[];
    final older = _link(id: 'share-old', token: 'tok-old');
    final newest = _link(
      id: 'share-new',
      token: 'tok-new',
      createdAt: DateTime(2024, 11, 13),
      expiresAt: DateTime.now().add(const Duration(days: 30)),
    );
    when(
      () => repository.listPhotoShares(any()),
    ).thenAnswer((_) async => [older, newest]);
    _stubUpdate(
      repository,
      requests: requests,
      response:
          (invocation) => _link(
            id: 'share-new',
            token: 'tok-new',
            createdAt: DateTime(2024, 11, 13),
            expiresAt: DateTime.now().add(const Duration(days: 30)),
          ),
    );

    await _pumpPanel(tester, repository);
    await tester.pump();
    await tester.pump();

    expect(
      find.text('http://localhost:8080/#/shared/photos/item/tok-new'),
      findsOneWidget,
    );
    expect(
      find.text('http://localhost:8080/#/shared/photos/item/tok-old'),
      findsNothing,
    );
    expect(find.textContaining('另有 1 条链接'), findsOneWidget);
    expect(find.text('管理已有链接'), findsOneWidget);

    // 改档位作用于当前这条链接：地址不切换，其余链接不被撤销。
    await _scrollTo(tester, find.text('永不过期'));
    await tester.tap(find.text('永不过期'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(requests.single.positionalArguments.single, 'share-new');
    expect(
      find.text('http://localhost:8080/#/shared/photos/item/tok-new'),
      findsOneWidget,
    );
    expect(
      find.text('http://localhost:8080/#/shared/photos/item/tok-old'),
      findsNothing,
    );
    _verifyNeverCreate(repository);
    verifyNever(() => repository.revokeAlbumShare(any()));
  });

  testWidgets('撤销当前链接后其余有效链接顶上编辑位', (tester) async {
    final repository = _MockPhotoRepository();
    final older = _link(
      id: 'share-old',
      token: 'tok-old',
      expiresAt: DateTime.now().add(const Duration(days: 30)),
    );
    final newest = _link(
      id: 'share-new',
      token: 'tok-new',
      createdAt: DateTime(2024, 11, 13),
      expiresAt: DateTime.now().add(const Duration(days: 30)),
    );
    var listCalls = 0;
    when(() => repository.listPhotoShares(any())).thenAnswer((_) async {
      listCalls++;
      return listCalls == 1 ? [older, newest] : [older];
    });
    when(() => repository.revokeAlbumShare(any())).thenAnswer((_) async {});

    await _pumpPanel(tester, repository);
    await tester.pump();
    await tester.pump();

    expect(find.text('管理已有链接'), findsOneWidget);
    await _scrollTo(tester, find.text('删除'));
    await tester.tap(find.text('删除'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(
      find.text('http://localhost:8080/#/shared/photos/item/tok-old'),
      findsOneWidget,
    );
    expect(
      find.text('http://localhost:8080/#/shared/photos/item/tok-new'),
      findsNothing,
    );
    // 只剩一条链接：管理入口随计数归零而收起。
    expect(find.text('管理已有链接'), findsNothing);
    verify(() => repository.revokeAlbumShare('share-new')).called(1);
    expect(listCalls, 2);
  });

  testWidgets('链接创建失败时在链接框下方展示错误', (tester) async {
    final repository = _MockPhotoRepository();
    when(() => repository.listPhotoShares(any())).thenAnswer((_) async => []);
    when(() => repository.revokeAlbumShare(any())).thenAnswer((_) async {});
    when(
      () => repository.createPhotoShare(
        any(),
        password: any(named: 'password'),
        expiresAt: any(named: 'expiresAt'),
        includeLocation: any(named: 'includeLocation'),
        originalQuality: any(named: 'originalQuality'),
      ),
    ).thenThrow(Exception('boom'));

    await _pumpPanel(tester, repository);
    await tester.tap(find.text('创建链接'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('创建分享链接失败'), findsOneWidget);
  });

  testWidgets('原地写回失败时档位回滚到服务端状态并报更新失败', (tester) async {
    final repository = _MockPhotoRepository();
    final existing = _link(
      id: 'share-9',
      token: 'tok-9',
      expiresAt: DateTime.now().add(const Duration(days: 30)),
    );
    when(
      () => repository.listPhotoShares(any()),
    ).thenAnswer((_) async => [existing]);
    _failUpdate(repository);

    await _pumpPanel(tester, repository);
    await tester.pump();
    await tester.pump();

    await _scrollTo(tester, find.text('7天'));
    await tester.tap(find.text('7天'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('更新分享链接失败'), findsOneWidget);
    // 写回没生效，选中态必须回到服务端记录的 30 天，否则界面在骗人。
    expect(
      find.ancestor(of: find.text('30天'), matching: _selectedChip),
      findsOneWidget,
    );
    expect(
      find.ancestor(of: find.text('7天'), matching: _selectedChip),
      findsNothing,
    );
  });
}
