import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/app_theme.dart';
import 'package:omninest/features/admin/presentation/widgets/admin_common_widgets.dart';
import 'package:omninest/features/admin/presentation/widgets/admin_redesign_components.dart';

/// 紧凑指标卡回归：网格定高 132 与固定 132 高容器两种场景下，
/// plain / supporting / progress / footer / supporting+progress 各形态
/// 在字号 1.0 / 1.3 / 1.45 档位均不抛布局异常（超出按裁剪降级）。
Future<void> _pump(
  WidgetTester tester, {
  required Widget child,
  required double textScale,
  required Size viewport,
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
          child: child,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// 覆盖页面全部用到的卡片形态，含最重的 supporting + progress 组合。
List<Widget> _cardForms() {
  return <Widget>[
    const AdminMetricCard(
      title: '待处理任务',
      value: '1,024',
      detail: '队列与重试中的任务',
      icon: Icons.admin_panel_settings_outlined,
    ),
    AdminMetricCard(
      title: '普通用户',
      value: '128',
      detail: '数据库账号总数统计',
      icon: Icons.group_outlined,
      supporting: const [
        AdminMetricMiniStat(label: '活跃', value: '96'),
        AdminMetricMiniStat(label: '禁用', value: '32'),
        AdminTrendBadge(current: 128, previous: 120),
      ],
    ),
    const AdminMetricCard(
      title: '系统 CPU',
      value: '62%',
      detail: '运行正常',
      icon: Icons.memory_outlined,
      progress: 0.62,
    ),
    const AdminMetricCard(
      title: '存储配额',
      value: '2.4 TB',
      detail: '已用 68%，接近告警阈值区间',
      icon: Icons.cloud_outlined,
      footer: AdminTrendBadge(current: 2.4, previous: 2.2, invertGood: true),
    ),
    const AdminMetricCard(
      title: '系统负载',
      value: 'CPU 18%',
      detail: '运行正常',
      icon: Icons.memory_outlined,
      progress: 0.18,
      supporting: [
        AdminMetricMiniStat(label: '内存', value: '26%'),
        AdminMetricMiniStat(label: '磁盘', value: '41%'),
        AdminMetricMiniStat(label: 'JVM', value: '36%'),
      ],
    ),
  ];
}

/// admin_users_page 的健康状态瓦片配方：定高 72 随字号放大。
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

/// 卡片子树内不得存在任何 Scrollable：桌面端指针悬停于 Scrollable 时
/// ScrollConfiguration 会浮现卡片级滚动条，与页面级滚动条叠加。
void _expectNoScrollableInCards() {
  final card = find.byType(AdminMetricCard);
  expect(
    find.descendant(of: card, matching: find.byType(Scrollable)),
    findsNothing,
  );
  expect(
    find.descendant(of: card, matching: find.byType(SingleChildScrollView)),
    findsNothing,
  );
}

void main() {
  const scales = <double>[1.0, 1.3, 1.45];
  const sizes = <String, Size>{
    '平板 768': Size(768, 900),
    '桌面 1440': Size(1440, 900),
  };

  for (final scale in scales) {
    testWidgets('指标网格定高 132 下各形态卡字号 $scale 不溢出', (tester) async {
      await _pump(
        tester,
        textScale: scale,
        viewport: const Size(1440, 900),
        child: SingleChildScrollView(
          child: AdminResponsiveMetricGrid(children: _cardForms()),
        ),
      );
      expect(find.byType(AdminMetricCard), findsNWidgets(5));
      expect(tester.takeException(), isNull);
      _expectNoScrollableInCards();
    });

    testWidgets('固定 132 高容器下各形态卡字号 $scale 不抛布局异常', (tester) async {
      await _pump(
        tester,
        textScale: scale,
        viewport: const Size(1440, 900),
        child: Align(
          alignment: Alignment.topLeft,
          child: Wrap(
            spacing: 16,
            runSpacing: 16,
            children: [
              for (final card in _cardForms())
                SizedBox(width: 300, height: 132, child: card),
            ],
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      _expectNoScrollableInCards();
    });
  }

  testWidgets('supporting 单行 + progress 卡 132 高字号 1.0 内容天然放得下', (tester) async {
    // 系统负载卡形态：supporting 保持单行（真实字体下三枚 MiniStat 一行；
    // 测试字体较宽，用两枚短标签保证单行）+ 3px 进度槽收尾。
    await _pump(
      tester,
      textScale: 1.0,
      viewport: const Size(1440, 900),
      child: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: 300,
          height: 132,
          child: AdminMetricCard(
            title: '系统负载',
            value: 'CPU 18%',
            detail: '运行正常',
            icon: Icons.memory_outlined,
            progress: 0.18,
            supporting: const [
              AdminMetricMiniStat(label: '内存', value: '26%'),
              AdminMetricMiniStat(label: '磁盘', value: '41%'),
            ],
          ),
        ),
      ),
    );
    final card = find.byType(AdminMetricCard);
    // 进度槽为卡内最后一段内容：其底边不超过内容盒底缘（卡底 12px 内边距）
    // 即证明未触发裁剪降级，supporting+progress 组合天然放得下。
    final track = find.descendant(
      of: card,
      matching: find.byType(FractionallySizedBox),
    );
    expect(
      tester.getBottomRight(track).dy,
      lessThanOrEqualTo(tester.getBottomRight(card).dy - 12),
    );
    _expectNoScrollableInCards();
  });

  for (final entry in sizes.entries) {
    testWidgets('${entry.key} 字号 1.6 下健康瓦片不溢出', (tester) async {
      await _pump(
        tester,
        textScale: 1.6,
        viewport: entry.value,
        child: LayoutBuilder(
          builder: (context, constraints) => _healthGrid(context, constraints),
        ),
      );
      expect(tester.takeException(), isNull);
    });
  }
}
