import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/core/widgets/workstation_controls.dart';
import 'package:omninest/features/admin/domain/admin_operations.dart';
import 'package:omninest/features/admin/presentation/widgets/admin_permission_tree.dart';

const _permissions = [
  AdminPermissionDetail(
    code: 'file:read',
    name: '读取文件',
    module: 'file',
    description: '',
    enabled: true,
  ),
  AdminPermissionDetail(
    code: 'file:write',
    name: '写入文件',
    module: 'file',
    description: '',
    enabled: true,
  ),
  AdminPermissionDetail(
    code: 'file:legacy',
    name: '废弃能力',
    module: 'file',
    description: '',
    enabled: false,
  ),
  AdminPermissionDetail(
    code: 'task:admin',
    name: '任务管理',
    module: 'task',
    description: '',
    enabled: true,
  ),
];

/// 受控树选择器外壳：持有扁平 code 集合，模拟弹窗保存前的状态演进。
class _TreeHarness extends StatefulWidget {
  const _TreeHarness({required this.initialSelected});

  final Set<String> initialSelected;

  @override
  State<_TreeHarness> createState() => _TreeHarnessState();
}

class _TreeHarnessState extends State<_TreeHarness> {
  late final Set<String> selected = widget.initialSelected.toSet();

  void _toggleModule(String module) {
    final codes =
        _permissions
            .where((item) => item.module == module && item.enabled)
            .map((item) => item.code)
            .toList();
    if (codes.every(selected.contains)) {
      selected.removeAll(codes);
    } else {
      selected.addAll(codes);
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return AdminPermissionTreePicker(
      permissions: _permissions,
      selected: selected,
      onTogglePermission:
          (permission) => setState(() {
            if (!selected.remove(permission.code)) {
              selected.add(permission.code);
            }
          }),
      onToggleModule: _toggleModule,
    );
  }
}

Future<void> _pumpHarness(WidgetTester tester, Set<String> initial) {
  return tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('zh'),
      home: Scaffold(
        body: SingleChildScrollView(
          child: _TreeHarness(initialSelected: initial),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('默认全展开：模块行 + 缩进子权限行 + code mono 同时渲染', (tester) async {
    await _pumpHarness(tester, const <String>{});
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('admin-permission-module-file')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('admin-permission-module-task')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('admin-permission-row-file:read')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('admin-permission-row-task:admin')),
      findsOneWidget,
    );
    // 禁用权限行仍渲染（只读），初始未勾选。
    expect(find.text('✔'), findsNothing);
    expect(find.text('file:legacy'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('模块三态勾选联动子项：全选→✔ 全组，再点→清空', (tester) async {
    await _pumpHarness(tester, const <String>{});
    await tester.pumpAndSettle();

    final moduleCheck = find.descendant(
      of: find.byKey(const ValueKey('admin-permission-module-file')),
      matching: find.byType(WorkstationCheckMark),
    );
    await tester.tap(moduleCheck);
    await tester.pumpAndSettle();
    // 模块勾选 + 2 个启用子项全勾（禁用项保持未勾选），模块计数 2/3。
    expect(find.text('✔'), findsNWidgets(3));
    expect(find.text('2/3'), findsOneWidget);

    await tester.tap(moduleCheck);
    await tester.pumpAndSettle();
    expect(find.text('✔'), findsNothing);
    expect(find.text('0/3'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('单项勾选：模块勾选呈半选态，不显示 ✔', (tester) async {
    await _pumpHarness(tester, const <String>{});
    await tester.pumpAndSettle();

    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey('admin-permission-row-file:read')),
        matching: find.byType(WorkstationCheckMark),
      ),
    );
    await tester.pumpAndSettle();

    // 仅子项一个 ✔；模块勾选保持半选（无第二个 ✔），计数 1/3。
    expect(find.text('✔'), findsOneWidget);
    expect(find.text('1/3'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('展开收起：点击模块行隐藏/恢复子权限行', (tester) async {
    await _pumpHarness(tester, const <String>{});
    await tester.pumpAndSettle();

    // 点击模块名（整行切换展开）收起 file 组。
    await tester.tap(find.text('文件'));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('admin-permission-row-file:read')),
      findsNothing,
    );
    // task 组不受影响。
    expect(
      find.byKey(const ValueKey('admin-permission-row-task:admin')),
      findsOneWidget,
    );

    await tester.tap(find.text('文件'));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('admin-permission-row-file:read')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}
