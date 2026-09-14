import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/features/reader/application/reading_runtime/reader_progress_publisher.dart';

void main() {
  group('ReaderVisualProgressPublisher（方案 §49-§50/§106）', () {
    test('publish 钳制到 [0,1] 并更新 lastPublished 与通知器', () {
      final notifier = ValueNotifier<double>(0);
      final publisher = ReaderVisualProgressPublisher(notifier);
      publisher.publish(1.5);
      expect(notifier.value, 1.0);
      expect(publisher.lastPublished, 1.0);
      publisher.publish(-0.2);
      expect(notifier.value, 0.0);
      expect(publisher.lastPublished, 0.0);
      publisher.publish(0.42);
      expect(notifier.value, 0.42);
    });

    test('同值发布不重复通知监听者', () {
      final notifier = ValueNotifier<double>(0);
      var notifications = 0;
      notifier.addListener(() => notifications++);
      final publisher = ReaderVisualProgressPublisher(notifier);
      publisher.publish(0.3);
      expect(notifications, 1);
      publisher.publish(0.3);
      expect(notifications, 1);
      publisher.publish(0.31);
      expect(notifications, 2);
    });
  });
}
