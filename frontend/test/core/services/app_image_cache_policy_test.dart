import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/core/services/app_image_cache_policy.dart';

void main() {
  test('不同平台使用独立的图片缓存预算', () {
    final mobile = AppImageCachePolicy.budgetFor(AppImageCacheTarget.mobile);
    final web = AppImageCachePolicy.budgetFor(AppImageCacheTarget.web);
    final desktop = AppImageCachePolicy.budgetFor(AppImageCacheTarget.desktop);

    expect(mobile.maximumEntries, 160);
    expect(mobile.maximumBytes, 64 * 1024 * 1024);
    expect(web.maximumEntries, 220);
    expect(web.maximumBytes, 96 * 1024 * 1024);
    expect(desktop.maximumEntries, 320);
    expect(desktop.maximumBytes, 384 * 1024 * 1024);
  });

  test('配置会同时更新条目数和字节预算', () {
    final cache = ImageCache();

    AppImageCachePolicy.configure(cache, target: AppImageCacheTarget.mobile);

    expect(cache.maximumSize, 160);
    expect(cache.maximumSizeBytes, 64 * 1024 * 1024);
  });
}
