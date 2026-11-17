import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/app/theme/app_theme.dart';
import 'package:omninest/features/music/presentation/deck/music_deck_primitives.dart';

void main() {
  testWidgets('Music Deck 玻璃表面为列表项提供 Material 层', (tester) async {
    var tapped = false;
    await tester.pumpWidget(
      MaterialApp(
        theme: OmniNestTheme.dark(),
        home: Scaffold(
          body: MusicDeckGlass(
            child: ListTile(
              title: const Text('track'),
              onTap: () => tapped = true,
            ),
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    await tester.tap(find.text('track'));
    await tester.pump();

    expect(tapped, isTrue);
    expect(tester.takeException(), isNull);
  });
}
