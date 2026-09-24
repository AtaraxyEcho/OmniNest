import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/app_theme.dart';
import 'package:omninest/features/admin/presentation/widgets/admin_common_widgets.dart';
import 'package:omninest/features/admin/presentation/widgets/admin_redesign_components.dart';

/// 用与页面相同的定高配方渲染卡片，验证最大字号档位下是否溢出。
Future<void> _pump(
  WidgetTester tester, {
  required Widget Function(BuildContext, BoxConstraints) grid,
  required Size viewport,
  required double textScale,
}) async {
  tester.view.physicalSize = viewport;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('zh'),
      theme: OmniNestTheme.dark(),
      home: Scaffold(
        body: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
          child: LayoutBuilder(
            builder: (context, constraints) => grid(context, constraints),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// admin_users_page 的指标卡配方：列数阈值 980，定高 = 宽/1.9 随字号放大。
Widget _metricGrid(BuildContext context, BoxConstraints constraints) {
  final columns = constraints.maxWidth >= 980 ? 4 : 2;
  final tileWidth = (constraints.maxWidth - (columns - 1) * 16) / columns;
  final textScale =
      MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 1.6).toDouble();
  return GridView.count(
    crossAxisCount: columns,
    crossAxisSpacing: 16,
    mainAxisSpacing: 16,
    mainAxisExtent: tileWidth / 1.9 * textScale,
    shrinkWrap: true,
    physics: const NeverScrollableScrollPhysics(),
    children: const [
      AdminMetricCard(
        title: '超级管理员',
        value: '1',
        detail: '系统最高权限，可执行全部维护操作',
        icon: Icons.workspace_premium_outlined,
      ),
      AdminMetricCard(
        title: '普通用户',
        value: '128',
        detail: '数据库账号总数统计',
        icon: Icons.group_outlined,
      ),
      AdminMetricCard(
        title: '存储配额',
        value: '2.4 TB',
        detail: '已用 68%，接近告警阈值区间',
        icon: Icons.cloud_outlined,
      ),
      AdminMetricCard(
        title: '待处理任务',
        value: '1,024',
        detail: '队列与重试中的任务',
        icon: Icons.admin_panel_settings_outlined,
      ),
    ],
  );
}

/// admin_overview_page 健康状态瓦片配方：定高 72 随字号放大。
Widget _healthGrid(BuildContext context, BoxConstraints constraints) {
  final columns = constraints.maxWidth >= 1320 ? 2 : 1;
  final textScale =
      MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 1.6).toDouble();
  return GridView.count(
    crossAxisCount: columns,
    crossAxisSpacing: 12,
    mainAxisSpacing: 12,
    mainAxisExtent: 72 * textScale,
    shrinkWrap: true,
    physics: const NeverScrollableScrollPhysics(),
    children: const [
      AdminServiceTile(name: 'PostgreSQL', status: 'UP', detail: '连接池 8/32'),
      AdminServiceTile(name: 'MinIO', status: 'WARN', detail: '副本延迟 12 秒'),
      AdminServiceTile(name: 'RabbitMQ', status: 'DOWN', detail: '节点不可达'),
      AdminServiceTile(name: '图像分析侧车', status: 'UP', detail: '模型已就绪'),
    ],
  );
}

void main() {
  const sizes = <String, Size>{
    '平板 768': Size(768, 900),
    '小平板 600': Size(600, 900),
    '桌面 1440': Size(1440, 900),
  };

  for (final entry in sizes.entries) {
    testWidgets('${entry.key} 字号 1.6 下指标卡不溢出', (tester) async {
      await _pump(
        tester,
        grid: _metricGrid,
        viewport: entry.value,
        textScale: 1.6,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('${entry.key} 字号 1.6 下健康瓦片不溢出', (tester) async {
      await _pump(
        tester,
        grid: _healthGrid,
        viewport: entry.value,
        textScale: 1.6,
      );
      expect(tester.takeException(), isNull);
    });
  }
}
