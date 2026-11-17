import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/features/music/presentation/deck/music_deck_create_playlist_dialog.dart';

void main() {
  testWidgets('关闭新建歌单对话框时输入控制器保持有效', (tester) async {
    MusicDeckPlaylistDraft? submittedDraft;
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: const [Locale('zh'), Locale('en')],
        home: Builder(
          builder: (context) {
            return TextButton(
              onPressed: () async {
                submittedDraft = await showDialog<MusicDeckPlaylistDraft>(
                  context: context,
                  builder: (context) => const MusicDeckCreatePlaylistDialog(),
                );
              },
              child: const Text('open'),
            );
          },
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'Daily Mix');
    await tester.enterText(find.byType(TextField).last, 'Morning tracks');
    await tester.tap(find.byType(FilledButton));

    await tester.pump();
    expect(tester.takeException(), isNull);
    await tester.pumpAndSettle();

    expect(submittedDraft?.name, 'Daily Mix');
    expect(submittedDraft?.description, 'Morning tracks');
    expect(tester.takeException(), isNull);
  });

  testWidgets('编辑歌单对话框不使用黑色文字', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: const [Locale('zh'), Locale('en')],
        home: const Material(
          child: MusicDeckCreatePlaylistDialog(
            initialName: 'Daily Mix',
            initialDescription: 'Morning tracks',
            editing: true,
          ),
        ),
      ),
    );
    await tester.pump();

    final dialog = find.byType(AlertDialog);
    final texts = find.descendant(of: dialog, matching: find.byType(Text));
    expect(texts, findsWidgets);
    for (final element in texts.evaluate()) {
      final text = element.widget as Text;
      final color =
          text.style?.color ?? DefaultTextStyle.of(element).style.color;
      expect(color, isNot(equals(Colors.black)));
      expect(color, isNot(equals(const Color(0xFF000000))));
    }
  });
}
