import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/app_theme.dart';
import 'package:omninest/app/theme/control_tokens.dart';
import 'package:omninest/features/files/media_import_ui.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_empty_state.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_import_queue_cards.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_library_import_action.dart';

void main() {
  testWidgets('添加图书使用主题描边按钮尺寸与圆角', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1024, 768);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          locale: const Locale('zh'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: OmniNestTheme.dark(),
          home: const Scaffold(body: ImportFromDeviceButton()),
        ),
      ),
    );
    await tester.pump();

    final material = tester.widget<Material>(
      find.descendant(
        of: find.byType(OutlinedButton),
        matching: find.byType(Material),
      ),
    );
    final shape = material.shape as RoundedRectangleBorder?;
    expect(
      shape?.borderRadius,
      BorderRadius.circular(AppControlTokens.controlRadius),
      reason: '添加图书不得继续使用与主题不一致的直角圆角',
    );
    final size = tester.getSize(find.byType(OutlinedButton));
    expect(
      size.height,
      lessThanOrEqualTo(AppControlTokens.buttonHeight + 4),
      reason: '添加图书高度应收敛到主题控件高度',
    );
  });

  testWidgets('书架空态去书库与导入书籍按钮等高', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1024, 768);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          locale: const Locale('zh'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: OmniNestTheme.dark(),
          home: Scaffold(
            body: ReaderEmptyState(
              title: '书架空空',
              subtitle: '去书库挑书',
              icon: Icons.auto_stories_outlined,
              action: Wrap(
                spacing: 8,
                children: [
                  FilledButton.icon(
                    onPressed: () {},
                    icon: const Icon(
                      Icons.library_books_outlined,
                      size: AppControlTokens.buttonIconSize,
                    ),
                    label: const Text('去书库'),
                  ),
                  const ReaderLibraryImportAction(
                    style: ImportButtonStyle.outlinedButton,
                    label: '导入书籍',
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    final filledSize = tester.getSize(find.byType(FilledButton));
    final outlinedSize = tester.getSize(find.byType(OutlinedButton));
    expect(
      (filledSize.height - outlinedSize.height).abs(),
      lessThan(1),
      reason: '空态主次按钮必须等高，避免并排时视觉错位',
    );
    expect(
      filledSize.height,
      lessThanOrEqualTo(AppControlTokens.buttonHeight + 4),
    );
  });

  testWidgets('书库空态导入书籍填充按钮不是胶囊形', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1024, 768);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          locale: const Locale('zh'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: OmniNestTheme.dark(),
          home: const Scaffold(
            body: ReaderLibraryImportAction(
              style: ImportButtonStyle.filledButton,
              label: '导入书籍',
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    final material = tester.widget<Material>(
      find.descendant(
        of: find.byType(FilledButton),
        matching: find.byType(Material),
      ),
    );
    expect(
      material.shape,
      isNot(isA<StadiumBorder>()),
      reason: '覆盖填充按钮配色时不得丢掉主题圆角，否则会回退成 Material 胶囊形',
    );
    final shape = material.shape as RoundedRectangleBorder?;
    expect(
      shape?.borderRadius,
      BorderRadius.circular(AppControlTokens.controlRadius),
      reason: '书库空态导入书籍应与其它操作按钮共用主题圆角',
    );
  });
}
