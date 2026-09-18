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

  testWidgets('单弹窗内自选：空集时开启置灰，勾选后按集合开启', (tester) async {
    await _pumpPanel(tester);

    // 打开开关 → 单个确认弹窗；切到自选后内联展开相册清单。
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    await tester.tap(find.text('自选相册'));
    await tester.pumpAndSettle();

    expect(find.text('相机'), findsOneWidget);
    expect(find.text('截图'), findsOneWidget);

    // 未勾选任何相册：「开启」按钮置灰，无法确认。
    FilledButton enableButton() =>
        tester.widget<FilledButton>(find.byType(FilledButton));
    expect(enableButton().onPressed, isNull);

    // 勾选「相机」→ 按钮激活 → 确认后按自选集合开启。
    await tester.tap(find.text('相机'));
    await tester.pump();
    expect(enableButton().onPressed, isNotNull);
    await tester.tap(find.byType(FilledButton));
    await tester.pumpAndSettle();

    final prefs = await SharedPreferences.getInstance();
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
    expect(prefs.getString(photoBackupScopeKey), 'selected');
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));

  testWidgets('确认弹窗内勾选移动数据后按 any 策略开启', (tester) async {
    await _pumpPanel(tester);

    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    await tester.tap(find.text('无 Wi-Fi 时也使用移动数据备份'));
    await tester.pump();
    await tester.tap(find.byType(FilledButton));
    await tester.pumpAndSettle();

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool(photoBackupBackgroundEnabledKey), isTrue);
    expect(prefs.getString(photoBackupScopeKey), 'all');
    expect(prefs.getString(photoBackupNetworkPolicyKey), 'any');
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));

  testWidgets('非 Android 平台开关禁用', (tester) async {
    await _pumpPanel(tester);

    final toggle = tester.widget<SwitchListTile>(find.byType(SwitchListTile));
    expect(toggle.onChanged, isNull);
  }, variant: TargetPlatformVariant.only(TargetPlatform.windows));
}
