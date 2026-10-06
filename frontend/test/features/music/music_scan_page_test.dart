// 本地音乐库扫描页回归：托管工具页只给真实可得的数（状态/进度/已扫描），
// 不摆稿子里算不出来的 REMAINING / ESTIMATED 摘要格；扫描与重刮都要二次确认。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/app_theme.dart';
import 'package:omninest/app/theme/app_theme_palette.dart';
import 'package:omninest/core/widgets/env_empty_state.dart';
import 'package:omninest/core/widgets/mobile_shell_scope.dart';
import 'package:omninest/core/widgets/mobile_status_kit.dart';
import 'package:omninest/core/widgets/mobile_ui.dart';
import 'package:omninest/features/music/application/music_controller.dart';
import 'package:omninest/features/music/application/music_scan_job_controller.dart';
import 'package:omninest/features/music/domain/music_models.dart';
import 'package:omninest/features/music/presentation/pages/music_scan_page.dart';

class _FakeMusicCenter extends MusicCenterController {
  _FakeMusicCenter(this._state);

  final MusicCenterState _state;

  @override
  Future<MusicCenterState> build() async => _state;

  @override
  Future<void> refresh() async {}
}

class _FakeScanJob extends MusicScanJobController {
  _FakeScanJob(this._state);

  final MusicScanJobState _state;

  int startCalls = 0;

  @override
  MusicScanJobState build() => _state;

  @override
  Future<void> startScan() async {
    startCalls++;
  }
}

MusicCenterState _center({MusicScanJob? lastScanJob}) {
  return MusicCenterState(
    dashboard: MusicDashboard.empty(),
    tracks: const [],
    albums: const [],
    artists: const [],
    playlists: const [],
    lastScanJob: lastScanJob,
  );
}

Future<_FakeScanJob> _pump(
  WidgetTester tester, {
  MusicScanJob? job,
  bool polling = false,
}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final scan = _FakeScanJob(MusicScanJobState(job: job, polling: polling));
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        musicCenterControllerProvider.overrideWith(
          () => _FakeMusicCenter(_center(lastScanJob: job)),
        ),
        musicScanJobControllerProvider.overrideWith(() => scan),
      ],
      child: MaterialApp(
        theme: OmniNestTheme.from(AppThemePalette.dark),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('zh'),
        home: const MobileShellScope(
          hosted: true,
          child: Scaffold(body: MusicScanPage()),
        ),
      ),
    ),
  );
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 120));
  }
  return scan;
}

void main() {
  testWidgets('没有扫描记录时给空态而不是假摘要', (tester) async {
    await _pump(tester);

    expect(find.byType(MobilePageSurface), findsOneWidget);
    expect(find.text('本地资源'), findsOneWidget);
    expect(find.byType(EnvEmptyState), findsOneWidget);
    expect(find.text('还没有扫描记录。'), findsOneWidget);
    expect(find.byType(MobileTransferRow), findsNothing);
    expect(find.byTooltip('扫描存储'), findsOneWidget);
    expect(find.byTooltip('全库重刮'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('进行中的任务用传输行展示状态与进度', (tester) async {
    await _pump(
      tester,
      polling: true,
      job: const MusicScanJob(
        id: 'job-1',
        status: 'RUNNING',
        progress: 40,
        scannedFiles: 120,
      ),
    );

    final row = find.byType(MobileTransferRow);
    expect(row, findsOneWidget);
    expect(find.text('RUNNING'), findsOneWidget);
    expect(find.text('已扫描 120 个文件'), findsOneWidget);
    expect(find.text('40%'), findsOneWidget);
    // 轮询中的任务标为警示色，终态回平静色。
    final transfer = tester.widget<MobileTransferRow>(row);
    expect(transfer.tone, MobileStatusTone.warning);
    expect(find.byType(EnvEmptyState), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('扫描要先确认，取消不触发任务', (tester) async {
    final scan = await _pump(tester);

    await tester.tap(find.byTooltip('扫描存储'));
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 120));
    }
    expect(find.text('将重新扫描本地音乐目录并更新曲库。'), findsOneWidget);

    await tester.tap(find.text('取消'));
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 120));
    }
    expect(scan.startCalls, 0);
    expect(tester.takeException(), isNull);
  });
}
