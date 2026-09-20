import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/core/server/server_config.dart';

void main() {
  group('tryParse 地址规范化', () {
    test('裸 host:port 默认 http 并补 /api/v1', () {
      final config = ServerConfig.tryParse('192.168.1.10:8080');
      expect(config?.apiBaseUrl, 'http://192.168.1.10:8080/api/v1');
    });

    test('裸 host 默认 http', () {
      final config = ServerConfig.tryParse('example.com');
      expect(config?.apiBaseUrl, 'http://example.com/api/v1');
    });

    test('端口 443 默认 https 且规范化剥默认端口', () {
      final config = ServerConfig.tryParse('example.com:443');
      expect(config?.apiBaseUrl, 'https://example.com/api/v1');
    });

    test('完整 URL 补齐 /api/v1 并剥尾斜杠', () {
      expect(
        ServerConfig.tryParse('https://nest.example.com')?.apiBaseUrl,
        'https://nest.example.com/api/v1',
      );
      expect(
        ServerConfig.tryParse('https://nest.example.com/')?.apiBaseUrl,
        'https://nest.example.com/api/v1',
      );
    });

    test('已含 /api/v1 保持不变', () {
      expect(
        ServerConfig.tryParse('https://nest.example.com/api/v1')?.apiBaseUrl,
        'https://nest.example.com/api/v1',
      );
      expect(
        ServerConfig.tryParse('https://nest.example.com/api/v1/')?.apiBaseUrl,
        'https://nest.example.com/api/v1',
      );
    });

    test('粘贴完整端点 URL 截断至 /api/v1', () {
      expect(
        ServerConfig.tryParse(
          'https://nest.example.com/api/v1/auth/login',
        )?.apiBaseUrl,
        'https://nest.example.com/api/v1',
      );
      expect(
        ServerConfig.tryParse(
          'http://192.168.1.10:9090/sub/api/v1/files',
        )?.apiBaseUrl,
        'http://192.168.1.10:9090/sub/api/v1',
      );
    });

    test('子路径部署追加 /api/v1', () {
      expect(
        ServerConfig.tryParse('http://192.168.1.10:9090/sub')?.apiBaseUrl,
        'http://192.168.1.10:9090/sub/api/v1',
      );
    });

    test('IPv6 字面量需方括号并可解析', () {
      expect(
        ServerConfig.tryParse('[2001:db8::1]:8080')?.apiBaseUrl,
        'http://[2001:db8::1]:8080/api/v1',
      );
    });

    test('空白输入返回 null', () {
      expect(ServerConfig.tryParse(''), isNull);
      expect(ServerConfig.tryParse('   '), isNull);
    });

    test('非法输入返回 null', () {
      expect(ServerConfig.tryParse('ftp://example.com'), isNull);
      expect(ServerConfig.tryParse('https://'), isNull);
      expect(ServerConfig.tryParse('https://host?a=1'), isNull);
      expect(ServerConfig.tryParse('https://host#frag'), isNull);
      expect(ServerConfig.tryParse('http://user:pass@host'), isNull);
      expect(ServerConfig.tryParse('ha st:8080'), isNull);
    });
  });

  group('REQUIRE_HTTPS 构建开关', () {
    test('开启后拒绝 http 地址', () {
      expect(
        ServerConfig.tryParse('http://192.168.1.10:8080', requireHttps: true),
        isNull,
      );
      expect(
        ServerConfig.tryParse('192.168.1.10:8080', requireHttps: true),
        isNull,
      );
    });

    test('开启后 https 地址不受影响', () {
      expect(
        ServerConfig.tryParse(
          'https://nest.example.com',
          requireHttps: true,
        )?.apiBaseUrl,
        'https://nest.example.com/api/v1',
      );
    });

    test('关闭后 http 地址可用', () {
      expect(
        ServerConfig.tryParse(
          'http://192.168.1.10:8080',
          requireHttps: false,
        )?.apiBaseUrl,
        'http://192.168.1.10:8080/api/v1',
      );
    });
  });

  group('可选覆盖地址', () {
    test('ws 覆盖保留且剥尾斜杠', () {
      final config = ServerConfig.tryParse(
        'https://nest.example.com',
        wsBaseUrl: 'wss://rt.example.com/ws/',
      );
      expect(config?.wsBaseUrl, 'wss://rt.example.com/ws');
    });

    test('ws 覆盖非法 scheme 时整体拒绝', () {
      expect(
        ServerConfig.tryParse(
          'https://nest.example.com',
          wsBaseUrl: 'http://rt.example.com',
        ),
        isNull,
      );
    });

    test('ws 空白视为未覆盖', () {
      final config = ServerConfig.tryParse(
        'https://nest.example.com',
        wsBaseUrl: '   ',
      );
      expect(config?.wsBaseUrl, isNull);
    });

    test('web 分享基址覆盖规范化', () {
      final config = ServerConfig.tryParse(
        'https://nest.example.com',
        webBaseUrl: 'https://share.example.com/',
      );
      expect(config?.webBaseUrl, 'https://share.example.com');
    });
  });

  group('环境派生与持久化', () {
    test('未显式覆盖时 WS 由 API 同域推导', () {
      final env =
          ServerConfig.tryParse('https://nest.example.com')!.toAppEnvironment();
      expect(env.apiBaseUrl, 'https://nest.example.com/api/v1');
      expect(env.wsBaseUrl, 'wss://nest.example.com/ws');
    });

    test('显式 ws 覆盖优先于推导', () {
      final env =
          ServerConfig.tryParse(
            'https://nest.example.com',
            wsBaseUrl: 'wss://rt.example.com/ws',
          )!.toAppEnvironment();
      expect(env.wsBaseUrl, 'wss://rt.example.com/ws');
    });

    test('JSON 往返保持字段', () {
      final config =
          ServerConfig.tryParse(
            'https://nest.example.com',
            wsBaseUrl: 'wss://rt.example.com/ws',
            webBaseUrl: 'https://share.example.com',
          )!;
      final restored = ServerConfig.fromJson(config.toJson());
      expect(restored?.apiBaseUrl, config.apiBaseUrl);
      expect(restored?.wsBaseUrl, config.wsBaseUrl);
      expect(restored?.webBaseUrl, config.webBaseUrl);
    });

    test('结构版本不符返回 null', () {
      expect(
        ServerConfig.fromJson({
          'schemaVersion': 99,
          'apiBaseUrl': 'https://nest.example.com/api/v1',
        }),
        isNull,
      );
    });

    test('严格构建读到 http 历史配置视为未配置', () {
      final config =
          ServerConfig.tryParse(
            'http://192.168.1.10:8080',
            requireHttps: false,
          )!;
      final json = config.toJson();
      expect(ServerConfig.fromJson(json), isNotNull);
      // 模拟严格构建：fromJson 走 requireHttpsByBuild（测试未注入 define，为 false），
      // 因此此处直接校验 tryParse 的严格行为。
      expect(
        ServerConfig.tryParse(json['apiBaseUrl'] as String, requireHttps: true),
        isNull,
      );
    });
  });
}
