import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/core/widgets/responsive_breakpoints.dart';

void main() {
  group('ResponsiveBreakpoints', () {
    test('isMobile returns true below 600', () {
      expect(ResponsiveBreakpoints.isMobile(375), isTrue);
      expect(ResponsiveBreakpoints.isMobile(599), isTrue);
      expect(ResponsiveBreakpoints.isMobile(600), isFalse);
    });

    test('isTablet returns true between 600 and 900', () {
      expect(ResponsiveBreakpoints.isTablet(600), isTrue);
      expect(ResponsiveBreakpoints.isTablet(899), isTrue);
      expect(ResponsiveBreakpoints.isTablet(900), isFalse);
      expect(ResponsiveBreakpoints.isTablet(375), isFalse);
    });

    test('isDesktop returns true at 900 and above', () {
      expect(ResponsiveBreakpoints.isDesktop(900), isTrue);
      expect(ResponsiveBreakpoints.isDesktop(1200), isTrue);
      expect(ResponsiveBreakpoints.isDesktop(899), isFalse);
    });

    test('isWide returns true at 1200 and above', () {
      expect(ResponsiveBreakpoints.isWide(1200), isTrue);
      expect(ResponsiveBreakpoints.isWide(1199), isFalse);
    });
  });
}
