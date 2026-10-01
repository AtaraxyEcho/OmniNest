import 'package:flutter/material.dart';
import 'package:omninest/core/widgets/workstation_pagination_bar.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/control_tokens.dart';
import 'package:omninest/app/theme/feature/admin_colors.dart';
import 'package:omninest/core/theme/workstation_skin.dart';
import 'package:omninest/core/widgets/workstation_controls.dart';
import 'package:omninest/features/admin/presentation/theme/admin_workstation_theme.dart';
import 'package:omninest/features/admin/presentation/widgets/admin_common_widgets.dart';
import 'package:omninest/features/admin/presentation/widgets/admin_list_components.dart';

Widget _wrap(Widget child, {Brightness brightness = Brightness.dark}) {
  return MaterialApp(
    theme: ThemeData(brightness: brightness, useMaterial3: true),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(body: AdminWorkstationScope(child: child)),
  );
}

void main() {
  group('AdminWorkstationScope', () {
    testWidgets('暗色下注入 Zinc 调色板与工位 ColorScheme', (tester) async {
      late BuildContext captured;
      await tester.pumpWidget(
        _wrap(
          Builder(
            builder: (context) {
              captured = context;
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      final admin = AdminColors.of(captured);
      expect(admin.surface, WorkstationPalette.canvasDark);
      expect(admin.onSurface, WorkstationPalette.textPrimaryDark);
      expect(admin.outlineVariant, WorkstationPalette.lineDark);
      expect(admin.success, WorkstationPalette.emerald);
      expect(admin.error, WorkstationPalette.rose);
      final scheme = Theme.of(captured).colorScheme;
      expect(scheme.surface, WorkstationPalette.canvasDark);
      expect(scheme.brightness, Brightness.dark);
    });

    testWidgets('亮色下注入亮色 Zinc 调色板', (tester) async {
      late BuildContext captured;
      await tester.pumpWidget(
        _wrap(
          Builder(
            builder: (context) {
              captured = context;
              return const SizedBox.shrink();
            },
          ),
          brightness: Brightness.light,
        ),
      );
      final admin = AdminColors.of(captured);
      expect(admin.surface, WorkstationPalette.canvasLight);
      expect(admin.onSurface, WorkstationPalette.textPrimaryLight);
      expect(Theme.of(captured).colorScheme.brightness, Brightness.light);
    });

    testWidgets('弹窗与按钮主题全直角零阴影', (tester) async {
      late BuildContext captured;
      await tester.pumpWidget(
        _wrap(
          Builder(
            builder: (context) {
              captured = context;
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      final theme = Theme.of(captured);
      final dialogShape = theme.dialogTheme.shape as RoundedRectangleBorder?;
      expect(dialogShape?.borderRadius, BorderRadius.zero);
      expect(theme.dialogTheme.elevation, 0);
      final filledShape =
          theme.filledButtonTheme.style?.shape?.resolve({})
              as RoundedRectangleBorder?;
      expect(filledShape?.borderRadius, BorderRadius.zero);
    });
  });

  group('工位基础件直角度量', () {
    testWidgets('状态胶囊/迷你统计为直角细边框', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AdminStatusPill(label: 'RUNNING'),
                AdminMetricMiniStat(label: 'items', value: '12'),
                AdminStatusTag(label: 'ACTIVE', tone: AdminTagTone.success),
              ],
            ),
          ),
        ),
      );
      final decorations =
          tester
              .widgetList<DecoratedBox>(find.byType(DecoratedBox))
              .map((box) => box.decoration)
              .whereType<BoxDecoration>()
              .toList();
      expect(decorations, isNotEmpty);
      // 描边容器一律直角；无描边的圆点（状态指示灯）是规范唯一豁免。
      final bordered = decorations.where(
        (decoration) => decoration.border != null,
      );
      expect(bordered, isNotEmpty);
      for (final decoration in bordered) {
        expect(decoration.borderRadius, isNull);
      }
      expect(
        decorations.any((decoration) => decoration.shape == BoxShape.circle),
        isTrue,
      );
    });

    testWidgets('指标卡进度槽为 1px 细线直角条', (tester) async {
      await tester.pumpWidget(
        _wrap(
          Center(
            child: SizedBox(
              width: 320,
              child: AdminMetricCard(
                title: 'CPU',
                value: '18%',
                detail: 'load',
                icon: Icons.memory,
                progress: 0.5,
              ),
            ),
          ),
        ),
      );
      final bars =
          tester
              .widgetList<DecoratedBox>(find.byType(DecoratedBox))
              .map((box) => box.decoration)
              .whereType<BoxDecoration>()
              .toList();
      final progressTrack = bars.firstWhere(
        (decoration) => decoration.borderRadius == null,
      );
      expect(progressTrack, isNotNull);
    });

    testWidgets('分页页码 chip 直角并保持 44px 触达', (tester) async {
      await tester.pumpWidget(
        _wrap(
          Center(
            child: WorkstationPaginationBar(
              currentPage: 0,
              totalPages: 3,
              totalElements: 25,
              rowsPerPage: 10,
              onPageChanged: (_) {},
              onRowsPerPageChanged: (_) {},
            ),
          ),
        ),
      );
      final pageOne = find.text('1');
      expect(pageOne, findsOneWidget);
      final chip = tester.widget<Container>(
        find.ancestor(of: pageOne, matching: find.byType(Container)).first,
      );
      final decoration = chip.decoration as BoxDecoration?;
      expect(decoration?.borderRadius, isNull);
      expect(chip.constraints?.minHeight, 44);
    });
  });

  group('工位输入框 hairline 默认描边', () {
    /// 在工位 Scope 内构建工作站输入装饰并渲染可聚焦 TextField。
    Future<(InputDecoration, BuildContext)> pumpField(WidgetTester tester) {
      late BuildContext captured;
      final field = Builder(
        builder: (context) {
          captured = context;
          return TextField(
            decoration: workstationInputDecoration(context, hintText: 'search'),
          );
        },
      );
      return tester
          .pumpWidget(_wrap(Center(child: SizedBox(width: 300, child: field))))
          .then(
            (_) => (
              tester.widget<TextField>(find.byType(TextField)).decoration!,
              captured,
            ),
          );
    }

    testWidgets('未聚焦边框为 outlineVariant hairline，聚焦后 1px 升为 onSurface', (
      tester,
    ) async {
      final (decoration, captured) = await pumpField(tester);
      final scheme = Theme.of(captured).colorScheme;

      final enabled = decoration.enabledBorder as OutlineInputBorder;
      expect(enabled.borderRadius, BorderRadius.zero);
      expect(enabled.borderSide.color, scheme.outlineVariant);
      expect(enabled.borderSide.width, 1);

      final focused = decoration.focusedBorder as OutlineInputBorder;
      expect(focused.borderRadius, BorderRadius.zero);
      expect(focused.borderSide.color, scheme.onSurface);
      expect(focused.borderSide.width, 1);

      // 主题侧同步 hairline：inputDecorationTheme 默认描边为 outlineVariant。
      final themeBorder =
          Theme.of(captured).inputDecorationTheme.enabledBorder
              as OutlineInputBorder;
      expect(themeBorder.borderSide.color, scheme.outlineVariant);

      // 实际聚焦后仍为 1px 精准变色（无宽度放大或双描边）。
      await tester.tap(find.byType(TextField));
      await tester.pump();
      final editable = tester.widget<EditableText>(find.byType(EditableText));
      expect(editable.focusNode.hasFocus, isTrue);
    });
  });

  group('AppDropdown 工位直角化', () {
    Widget dropdown() {
      return AppDropdown<String>(
        value: 'a',
        items: const [
          AppDropdownItem(value: 'a', label: 'Alpha'),
          AppDropdownItem(value: 'b', label: 'Beta'),
        ],
        onChanged: (_) {},
      );
    }

    testWidgets('工位 Scope 内：字段直角 hairline，注册工位标记扩展', (tester) async {
      late BuildContext captured;
      await tester.pumpWidget(
        _wrap(
          Center(
            child: SizedBox(
              width: 240,
              child: Builder(
                builder: (context) {
                  captured = context;
                  return dropdown();
                },
              ),
            ),
          ),
        ),
      );
      final scheme = Theme.of(captured).colorScheme;
      expect(Theme.of(captured).extension<WorkstationSurfaceFlag>(), isNotNull);
      final decorator = tester.widget<InputDecorator>(
        find.byType(InputDecorator),
      );
      final enabled = decorator.decoration.enabledBorder as OutlineInputBorder;
      expect(enabled.borderRadius, BorderRadius.zero);
      expect(enabled.borderSide.color, scheme.outlineVariant);
      expect(enabled.borderSide.width, 1);
      final focused = decorator.decoration.focusedBorder as OutlineInputBorder;
      expect(focused.borderRadius, BorderRadius.zero);
      expect(focused.borderSide.color, scheme.onSurface);
      expect(focused.borderSide.width, 1);
    });

    testWidgets('工位 Scope 外：保持全局默认圆角外观不受影响', (tester) async {
      late BuildContext captured;
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(brightness: Brightness.dark, useMaterial3: true),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 240,
                child: Builder(
                  builder: (context) {
                    captured = context;
                    return dropdown();
                  },
                ),
              ),
            ),
          ),
        ),
      );
      expect(Theme.of(captured).extension<WorkstationSurfaceFlag>(), isNull);
      final decorator = tester.widget<InputDecorator>(
        find.byType(InputDecorator),
      );
      final enabled = decorator.decoration.enabledBorder as OutlineInputBorder;
      expect(
        enabled.borderRadius,
        BorderRadius.circular(AppControlTokens.controlRadius),
      );
    });
  });
}
