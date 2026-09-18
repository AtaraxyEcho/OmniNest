import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/app_theme.dart';
import 'package:omninest/features/photos/application/photo_backup_albums.dart';
import 'package:omninest/features/photos/application/photo_backup_preferences.dart';
import 'package:omninest/features/profile/presentation/widgets/profile_backup_panel.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _fakeAlbums = [
  PhotoBackupAlbumOption(id: 'album-1', name: '相机', assetCount: 120),
  PhotoBackupAlbumOption(id: 'album-2', name: '截图', assetCount: 30),
];

Future<void> _pumpPanel(WidgetTester tester) async {
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('zh'),
        theme: OmniNestTheme.dark(),
        home: Scaffold(body: ListView(children: [const ProfileBackupPanel()])),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  PhotoBackupAlbumLoader? savedLoader;
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    savedLoader = photoBackupAlbumLoader;
    photoBackupAlbumLoader = () async => _fakeAlbums;
  });
  tearDown(() {
    photoBackupAlbumLoader = savedLoader!;
  });

  testWidgets('默认关闭且范围显示全部相册，打开开关先弹二次确认', (tester) async {
    await _pumpPanel(tester);

    expect(find.text('当前范围：全部相册'), findsOneWidget);
    final toggle = tester.widget<SwitchListTile>(find.byType(SwitchListTile));
    expect(toggle.value, isFalse);

    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();

    expect(find.text('开启自动备份？'), findsOneWidget);
    expect(find.text('全部相册'), findsOneWidget);
    expect(find.text('自选相册'), findsOneWidget);
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));

  testWidgets('取消确认则不开启', (tester) async {
    await _pumpPanel(tester);

    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();

    expect(find.text('开启自动备份？'), findsNothing);
    final toggle = tester.widget<SwitchListTile>(find.byType(SwitchListTile));
    expect(toggle.value, isFalse);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool(photoBackupBackgroundEnabledKey), isNull);
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));

  testWidgets('选择全部相册并确认后直接开启', (tester) async {
    await _pumpPanel(tester);

    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    await tester.tap(find.text('开启'));
    await tester.pumpAndSettle();

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool(photoBackupBackgroundEnabledKey), isTrue);
    expect(prefs.getString(photoBackupScopeKey), 'all');
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));

  testWidgets('自选相册空集确认被拦截，勾选后按集合开启', (tester) async {
    await _pumpPanel(tester);

    // 第一步：确认弹窗选择自选相册。
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    await tester.tap(find.text('自选相册'));
    await tester.pump();
    await tester.tap(find.text('开启'));
    await tester.pumpAndSettle();

    // 相册选择器出现；未勾选直接确认 → 拦截提示并关闭流程，不开启。
    expect(find.text('选择要备份的相册'), findsOneWidget);
    await tester.tap(find.text('确认'));
    await tester.pump();
    expect(find.text('请至少选择一个相册'), findsOneWidget);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool(photoBackupBackgroundEnabledKey), isNull);
    await tester.pump(const Duration(seconds: 4));

    // 第二轮：重新开启并勾选「相机」后确认 → 按自选集合开启。
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    await tester.tap(find.text('自选相册'));
    await tester.pump();
    await tester.tap(find.text('开启'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('相机'));
    await tester.pump();
    await tester.tap(find.text('确认'));
    await tester.pumpAndSettle();

    expect(prefs.getBool(photoBackupBackgroundEnabledKey), isTrue);
    expect(prefs.getString(photoBackupScopeKey), 'selected');
    expect(prefs.getStringList(photoBackupSelectedAlbumIdsKey), ['album-1']);
    expect(find.text('当前范围：已选 1 个相册'), findsOneWidget);
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));

  testWidgets('关闭无需确认直接生效', (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      photoBackupBackgroundEnabledKey: true,
      photoBackupScopeKey: 'selected',
      photoBackupSelectedAlbumIdsKey: ['album-2'],
    });
    await _pumpPanel(tester);

    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();

    expect(find.text('开启自动备份？'), findsNothing);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool(photoBackupBackgroundEnabledKey), isFalse);
    // 范围偏好保留。
    expect(prefs.getString(photoBackupScopeKey), 'selected');
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));

  testWidgets('非 Android 平台开关禁用', (tester) async {
    await _pumpPanel(tester);

    final toggle = tester.widget<SwitchListTile>(find.byType(SwitchListTile));
    expect(toggle.onChanged, isNull);
  }, variant: TargetPlatformVariant.only(TargetPlatform.windows));
}
