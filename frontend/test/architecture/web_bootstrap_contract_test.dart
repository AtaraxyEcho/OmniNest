import 'dart:io';
import 'dart:ui' show Color;

import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/app/preferences/app_bootstrap_data.dart';
import 'package:omninest/app/theme/mobile_env_palette.dart';

void main() {
  test('Web bootstrap only uses supported Flutter template tokens', () {
    final indexSource = File('web/index.html').readAsStringSync();
    final bootstrapSource = File('web/flutter_bootstrap.js').readAsStringSync();
    final tokens = RegExp(r'\{\{([^}]+)\}\}')
        .allMatches('$indexSource\n$bootstrapSource')
        .map((match) => match.group(1));

    expect(
      tokens,
      everyElement(
        isIn(const <String>{
          'flutter_js',
          'flutter_build_config',
          'flutter_service_worker_version',
        }),
      ),
    );
    expect(indexSource, isNot(contains('flutter_bootstrap_config')));
  });

  test(
    'Web bootstrap loads the self-hosted CanvasKit runtime from the page base',
    () {
      final bootstrapSource =
          File('web/flutter_bootstrap.js').readAsStringSync();

      expect(bootstrapSource, contains('{{flutter_js}}'));
      expect(bootstrapSource, contains('{{flutter_build_config}}'));
      // CanvasKit 只允许自托管，且路径跟随 <base href> 以便子路径部署。
      expect(bootstrapSource, contains("document.querySelector('base')"));
      expect(bootstrapSource, contains("baseHref + 'canvaskit/'"));
      expect(
        bootstrapSource,
        isNot(contains("canvasKitBaseUrl: '/canvaskit/'")),
      );
      expect(bootstrapSource, isNot(contains('gstatic')));
    },
  );

  test('启动阶段底色三处同源，首帧脚本不改写页面底色', () {
    final indexSource = File('web/index.html').readAsStringSync();
    final themeBootSource =
        File('web/js/omninest-theme-boot.js').readAsStringSync();
    final shellCss = File('web/css/omninest-shell.css').readAsStringSync();
    final manifestSource = File('web/manifest.json').readAsStringSync();
    String hex(Color color) =>
        '#${(color.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';

    // 后端 CSP 为 script-src 'self'，内联脚本会被浏览器拒绝执行：
    // 启动期脚本一律外链，index.html 里不得再出现带语句体的 <script>。
    expect(indexSource, contains('<script src="js/omninest-theme-boot.js">'));
    expect(indexSource, contains('<script src="js/omninest-engine-noise.js">'));
    expect(
      RegExp(r'<script>\s*[^\n<]', multiLine: true).hasMatch(indexSource),
      isFalse,
      reason: 'index.html 不得保留内联脚本体',
    );

    // Flutter 启动画面、Web 引擎首帧、PWA 启动屏必须同色：三处都是纯色，
    // 任何一处不同都会在冷启动时跳一次。
    final bootColor = hex(MobileEnvPalette.dark.stage);
    expect(
      shellCss,
      contains('var(--omninest-boot-bg, $bootColor)'),
      reason: '引擎首帧底色要和 MobileEnvPalette.dark.stage 同值',
    );
    expect(
      manifestSource,
      contains('"background_color": "$bootColor"'),
      reason: 'PWA 启动屏底色要和启动画面同值',
    );
    expect(themeBootSource, contains("DARK = '$bootColor'"));

    // 首帧脚本只定系统栏取色。改写页面底色会让浅色偏好用户经历
    // 「浅底 → 深色品牌页 → 浅色界面」两次跳色。
    expect(
      themeBootSource,
      isNot(contains("setProperty('--omninest-boot-bg'")),
      reason: '启动画面固定深色，首帧底色不得随主题极性改写',
    );
    expect(
      themeBootSource,
      contains("LIGHT = '${hex(MobileEnvPalette.light.stageSolid)}'"),
      reason: '浅色偏好下的系统栏取色仍要等于 MobileEnvPalette.light.stageSolid',
    );
    expect(indexSource, contains('<meta name="theme-color" content="#0b1110"'));

    // 脚本读的是 SharedPreferences 的 Web 落盘键，前缀 flutter. 由该实现固定。
    expect(themeBootSource, contains("'flutter.$appearanceDeviceModeKey'"));
    expect(themeBootSource, contains("'flutter.$legacyGlobalThemeModeKey'"));

    // 改写目标按 id 定位，id 漂移会让首帧脚本与运行期绑定各写各的。
    expect(indexSource, contains('id="omninest-theme-color"'));
    expect(themeBootSource, contains("getElementById('omninest-theme-color')"));
  });
}
