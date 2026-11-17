import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/features/portal/presentation/widgets/portal_hero_ellipsized_title.dart';

void main() {
  const style = TextStyle(fontSize: 24, fontWeight: FontWeight.w700);

  testWidgets('long Hero title uses one line and exposes full tooltip', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Center(
          child: SizedBox(
            width: 140,
            child: PortalHeroEllipsizedTitle(
              'A deliberately long portal hero title',
              style: style,
            ),
          ),
        ),
      ),
    );

    final text = tester.widget<Text>(
      find.text('A deliberately long portal hero title'),
    );
    expect(text.maxLines, 1);
    expect(text.overflow, TextOverflow.ellipsis);
    expect(find.byType(Tooltip), findsOneWidget);
  });

  testWidgets('short Hero title does not create redundant tooltip', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Center(
          child: SizedBox(
            width: 320,
            child: PortalHeroEllipsizedTitle('Music', style: style),
          ),
        ),
      ),
    );

    expect(find.byType(Tooltip), findsNothing);
  });
}
