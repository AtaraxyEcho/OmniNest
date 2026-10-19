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

  test('Web 首帧取色脚本与 Dart 侧的键名和极性值不漂移', () {
    final indexSource = File('web/index.html').readAsStringSync();
    final themeBootSource =
        File('web/js/omninest-theme-boot.js').readAsStringSync();
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

    // 浅色档必须等于托管面的 scaffold 底色，否则首帧与第一帧之间会跳色。
    expect(
      themeBootSource,
      contains("LIGHT = '${hex(MobileEnvPalette.light.stageSolid)}'"),
      reason: '首帧浅色底要和 MobileEnvPalette.light.stageSolid 同值',
    );
    // 深色档沿用既有兜底值：本次只补浅色，不动冷启动深色基线。
    expect(themeBootSource, contains("DARK = '#0b1110'"));
    expect(indexSource, contains('<meta name="theme-color" content="#0b1110"'));

    // 脚本读的是 SharedPreferences 的 Web 落盘键，前缀 flutter. 由该实现固定。
    expect(themeBootSource, contains("'flutter.$appearanceDeviceModeKey'"));
    expect(themeBootSource, contains("'flutter.$legacyGlobalThemeModeKey'"));

    // 改写目标按 id 定位，id 漂移会让首帧脚本与运行期绑定各写各的。
    expect(indexSource, contains('id="omninest-theme-color"'));
    expect(themeBootSource, contains("getElementById('omninest-theme-color')"));

    // 底色由 CSS 变量接管，缺省仍是设计基准的 #09100f（无脚本时保持深色）。
    final shellCss = File('web/css/omninest-shell.css').readAsStringSync();
    expect(shellCss, contains('var(--omninest-boot-bg, #09100f)'));
    expect(themeBootSource, contains("'--omninest-boot-bg'"));
  });
}
