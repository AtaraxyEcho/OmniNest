import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/features/photos/domain/photo.dart';

void main() {
  test('照片详情源图使用稳定缓存键', () {
    final photo = PhotoItem.fromJson(<String, dynamic>{
      'id': 'photo-source',
      'fileNodeId': 'file-source',
      'title': 'source.jpg',
      'sourceUrl': 'https://example.test/files/source.jpg?signature=temporary',
    });

    expect(photo.sourceUrl, contains('/files/source.jpg'));
    expect(photo.sourceCacheKey, 'photo-source:photo-source');
  });

  test('照片详情只暴露稳定图像分析分类并兼容旧结构', () {
    final photo = PhotoItem.fromJson(<String, dynamic>{
      'id': 'photo-1',
      'fileNodeId': 'file-1',
      'title': 'photo.jpg',
      'providerMetadata': <String, dynamic>{
        'sceneLabels': <Object>[
          'Cat',
          <String, dynamic>{'name': 'Nature', 'confidence': 0.9},
          '',
          'Cat',
        ],
        'rawSceneLabels': <Object>[
          <String, dynamic>{'name': 'veterinarians office', 'confidence': 0.8},
        ],
      },
    });

    expect(photo.sceneLabels, <String>['Cat', 'Nature']);
    expect(photo.sceneLabels, isNot(contains('veterinarians office')));
  });

  test('照片详情按命名空间读取图像分析标签', () {
    final photo = PhotoItem.fromJson(<String, dynamic>{
      'id': 'photo-2',
      'fileNodeId': 'file-2',
      'title': 'cat.jpg',
      'contentAnalysis': <String, dynamic>{
        'status': 'SUCCEEDED',
        'pipelineVersion': 'content-analysis-v2',
        'labels': <Object>[
          <String, dynamic>{
            'id': 'label-1',
            'namespace': 'SUBJECT',
            'code': 'cat',
            'confidence': 0.91,
            'source': 'coco',
            'state': 'AUTO',
            'boxes': <Object>[],
          },
          <String, dynamic>{
            'id': 'label-2',
            'namespace': 'SCENE',
            'code': 'office',
            'confidence': 0.88,
            'source': 'places365',
            'state': 'AUTO',
            'boxes': <Object>[],
          },
        ],
      },
    });

    expect(photo.contentAnalysis, isNotNull);
    expect(
      photo.contentAnalysis!.labelsByNamespace['SUBJECT']!.single.code,
      'cat',
    );
    expect(
      photo.contentAnalysis!.labelsByNamespace['SCENE']!.single.code,
      'office',
    );
  });

  test('照片详情按国家省市区生成可读地点', () {
    final photo = PhotoItem(
      id: 'photo-1',
      fileNodeId: 'file-1',
      title: 'photo.jpg',
      format: 'jpg',
      fileSize: 1,
      metadataStatus: 'MATCHED',
      favorite: false,
      createdAt: DateTime(2026),
      gpsLocation: const <String, dynamic>{
        'country': '中国',
        'state': '上海市',
        'city': '上海市',
        'district': '浦东新区',
      },
    );

    expect(photo.locationDisplay(), '中国 · 上海市 · 浦东新区');
    expect(photo.locationDisplay(preferZh: true), '中国 · 上海市 · 浦东新区');
  });

  test('位置显示按语言优先取中英文字段并逐项回退', () {
    final photo = PhotoItem(
      id: 'photo-1',
      fileNodeId: 'file-1',
      title: 'photo.jpg',
      format: 'jpg',
      fileSize: 1,
      metadataStatus: 'MATCHED',
      favorite: false,
      createdAt: DateTime(2026),
      gpsLocation: const <String, dynamic>{
        'country': 'Switzerland',
        'countryZh': '瑞士',
        'state': 'Bern',
        'city': 'Bern',
        'cityZh': '伯尔尼',
      },
    );

    expect(photo.locationDisplay(), 'Switzerland · Bern');
    // 省级中文名缺失时按字段回退英文，其余字段仍用中文。
    expect(photo.locationDisplay(preferZh: true), '瑞士 · Bern · 伯尔尼');
  });

  test('中文字段缺失时回退英文字段与显示名', () {
    final noZh = PhotoItem(
      id: 'photo-1',
      fileNodeId: 'file-1',
      title: 'photo.jpg',
      format: 'jpg',
      fileSize: 1,
      metadataStatus: 'MATCHED',
      favorite: false,
      createdAt: DateTime(2026),
      gpsLocation: const <String, dynamic>{
        'country': 'Switzerland',
        'city': 'Bern',
      },
    );
    expect(noZh.locationDisplay(preferZh: true), 'Switzerland · Bern');

    final displayNameOnly = PhotoItem(
      id: 'photo-2',
      fileNodeId: 'file-2',
      title: 'photo.jpg',
      format: 'jpg',
      fileSize: 1,
      metadataStatus: 'MATCHED',
      favorite: false,
      createdAt: DateTime(2026),
      gpsLocation: const <String, dynamic>{
        'displayName': 'Lauterbrunnen, Switzerland',
        'displayNameZh': '劳特布龙嫩，瑞士',
      },
    );
    expect(displayNameOnly.locationDisplay(), 'Lauterbrunnen, Switzerland');
    expect(displayNameOnly.locationDisplay(preferZh: true), '劳特布龙嫩，瑞士');
  });

  test('缩略图缓存键忽略预签名查询参数', () {
    final first = PhotoItem(
      id: 'photo-1',
      fileNodeId: 'file-1',
      title: 'photo.jpg',
      format: 'jpg',
      fileSize: 1,
      metadataStatus: 'MATCHED',
      favorite: false,
      createdAt: DateTime(2026),
      coverUrl: 'http://minio.local/photos/thumb.jpg?token=first',
    );
    final renewed = PhotoItem(
      id: 'photo-1',
      fileNodeId: 'file-1',
      title: 'photo.jpg',
      format: 'jpg',
      fileSize: 1,
      metadataStatus: 'MATCHED',
      favorite: false,
      createdAt: DateTime(2026),
      coverUrl: 'http://minio.local/photos/thumb.jpg?token=second',
    );

    expect(first.coverCacheKey, renewed.coverCacheKey);
  });

  test('下载文件名在标题缺扩展名时按格式补全', () {
    PhotoItem buildPhoto(String title, String format) {
      return PhotoItem(
        id: 'photo-1',
        fileNodeId: 'file-1',
        title: title,
        format: format,
        fileSize: 1,
        metadataStatus: 'MATCHED',
        favorite: false,
        createdAt: DateTime(2026),
      );
    }

    expect(buildPhoto('Summer', 'JPEG').downloadFileName, 'Summer.jpeg');
    expect(buildPhoto('Summer.jpg', 'JPEG').downloadFileName, 'Summer.jpg');
    expect(buildPhoto('Summer.HEIC', 'HEIC').downloadFileName, 'Summer.HEIC');
    expect(buildPhoto('Summer', '').downloadFileName, 'Summer');
  });
}
