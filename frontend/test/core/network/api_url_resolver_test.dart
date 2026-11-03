import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/core/network/api_url_resolver.dart';

/// 服务端相对资源地址解析测试。
///
/// 子路径部署（`OMNINEST_WEB_BASE_HREF=/omninest/`）下 `apiBaseUrl` 是
/// `https://host/omninest/api/v1`，后端下发的根相对路径必须保留 `/omninest`
/// 前缀；按 origin 直接拼接会丢前缀，导致播放、字幕与封面全部 404。
void main() {
  group('resolveApiSiteRoot', () {
    test('子路径部署剥掉 /api/v1 但保留前缀', () {
      expect(
        resolveApiSiteRoot('https://host/omninest/api/v1'),
        'https://host/omninest',
      );
    });

    test('根部署只剩协议与主机', () {
      expect(resolveApiSiteRoot('https://host/api/v1'), 'https://host');
    });

    test('端口不属于要剥离的后缀', () {
      expect(
        resolveApiSiteRoot('https://host:8443/omninest/api/v1'),
        'https://host:8443/omninest',
      );
    });

    test('尾斜杠不影响推导结果', () {
      expect(
        resolveApiSiteRoot('https://host/omninest/api/v1/'),
        'https://host/omninest',
      );
    });

    test('多级子路径同样只剥掉 /api/v1', () {
      expect(
        resolveApiSiteRoot('https://host/nas/omninest/api/v1'),
        'https://host/nas/omninest',
      );
    });

    test('路径不以 /api/v1 结尾时原样保留', () {
      expect(
        resolveApiSiteRoot('https://host/gateway'),
        'https://host/gateway',
      );
    });

    test('非绝对地址按去尾斜杠后的原值返回', () {
      expect(resolveApiSiteRoot('/api/v1'), '/api/v1');
      expect(resolveApiSiteRoot('/api/v1/'), '/api/v1');
      expect(resolveApiSiteRoot(''), '');
    });
  });

  group('resolveServerApiUrl', () {
    test('子路径部署的 /api/ 根相对路径保留前缀', () {
      expect(
        resolveServerApiUrl('https://host/omninest/api/v1', '/api/v1/x'),
        'https://host/omninest/api/v1/x',
      );
    });

    test('根部署的 /api/ 根相对路径回到站点根', () {
      expect(
        resolveServerApiUrl('https://host/api/v1', '/api/v1/x'),
        'https://host/api/v1/x',
      );
    });

    test('基址带尾斜杠时结果与不带斜杠一致', () {
      expect(
        resolveServerApiUrl('https://host/omninest/api/v1/', '/api/v1/x'),
        resolveServerApiUrl('https://host/omninest/api/v1', '/api/v1/x'),
      );
      expect(
        resolveServerApiUrl('https://host/omninest/api/v1/', '/api/v1/x'),
        'https://host/omninest/api/v1/x',
      );
    });

    test('影视流转地址保留子路径前缀与查询串', () {
      expect(
        resolveServerApiUrl(
          'https://host/omninest/api/v1',
          '/api/v1/public/video/items/item-1/stream?token=abc',
        ),
        'https://host/omninest/api/v1/public/video/items/item-1/stream?token=abc',
      );
    });

    test('预签名地址原样返回，编码字符不改写', () {
      const presigned =
          'https://minio:9000/bucket/key?X-Amz-Signature=abc%2Fdef&X-Amz-Expires=900';
      expect(
        resolveServerApiUrl('https://host/omninest/api/v1', presigned),
        presigned,
      );
    });

    test('带 scheme 的 CDN 直链原样返回', () {
      expect(
        resolveServerApiUrl(
          'https://host/omninest/api/v1',
          'http://cdn.example.com/cover/a.jpg',
        ),
        'http://cdn.example.com/cover/a.jpg',
      );
    });

    test('非 /api/ 的根相对路径按实现约定挂到 API 基址后', () {
      // 解析器把这类路径视为相对 API 基址（基址已含 /api/v1），不是站点根。
      expect(
        resolveServerApiUrl('https://host/omninest/api/v1', '/uploads/a.jpg'),
        'https://host/omninest/api/v1/uploads/a.jpg',
      );
      expect(
        resolveServerApiUrl('https://host/api/v1', '/music/stream/1'),
        'https://host/api/v1/music/stream/1',
      );
    });

    test('不带前导斜杠的路径追加到 API 基址后', () {
      expect(
        resolveServerApiUrl('https://host/omninest/api/v1', 'covers/a.png'),
        'https://host/omninest/api/v1/covers/a.png',
      );
    });

    test('空地址原样返回空串', () {
      expect(resolveServerApiUrl('https://host/api/v1', ''), '');
      expect(resolveServerApiUrl('https://host/api/v1/', ''), '');
    });

    test('基址不是绝对地址时原样返回待解析地址', () {
      // 无法定位站点根，交由调用方按失败处理，不得凭猜测拼出绝对地址。
      expect(resolveServerApiUrl('/api/v1', '/api/v1/x'), '/api/v1/x');
      expect(resolveServerApiUrl('not-a-base', '/api/v1/x'), '/api/v1/x');
      expect(resolveServerApiUrl('https://', '/api/v1/x'), '/api/v1/x');
    });

    test('待解析地址无法识别时按相对 API 基址处理', () {
      // 无 scheme 且无前导斜杠，落到拼接分支；原样保留待解析文本。
      expect(
        resolveServerApiUrl('https://host/api/v1', 'not a url'),
        'https://host/api/v1/not a url',
      );
    });
  });
}
