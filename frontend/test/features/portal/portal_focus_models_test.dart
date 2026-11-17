import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/features/portal/domain/portal_focus_models.dart';

void main() {
  group('PortalFocusModule', () {
    test('包含快捷工作台需要支持的模块', () {
      expect(
        PortalFocusModule.values,
        containsAll(<PortalFocusModule>[
          PortalFocusModule.reader,
          PortalFocusModule.video,
          PortalFocusModule.photos,
          PortalFocusModule.music,
          PortalFocusModule.files,
          PortalFocusModule.weather,
          PortalFocusModule.tasks,
          PortalFocusModule.admin,
        ]),
      );
    });
  });

  group('PortalFocusItem', () {
    test('保存轻量入口所需字段', () {
      const item = PortalFocusItem(
        icon: PortalFocusIcon.reader,
        module: PortalFocusModule.reader,
        title: 'Book',
        subtitle: 'Chapter 1',
        imageUrl: null,
        route: '/reader/items/book',
        actionLabel: 'Open',
        variant: 0,
        heroEyebrow: 'Reading',
        heroBody: 'Chapter 1',
        readerItemId: 'book',
      );
      expect(item.route, '/reader/items/book');
      expect(item.readerItemId, 'book');
      expect(item.module, PortalFocusModule.reader);
      expect(item.heroEyebrow, 'Reading');
      expect(item.heroBody, 'Chapter 1');
    });
  });
}
