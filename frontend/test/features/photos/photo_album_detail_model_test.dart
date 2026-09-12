import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/features/photos/domain/photo.dart';
import 'package:omninest/features/photos/domain/photo_album.dart';

void main() {
  test('PhotoAlbumDetail.fromJson 解析元信息与首页照片', () {
    final detail = PhotoAlbumDetail.fromJson({
      'album': {
        'id': 'album-1',
        'name': 'Trip',
        'description': 'd',
        'photoCount': 120,
      },
      'photos': [
        {'id': 'p1', 'fileNodeId': 'f1', 'title': 'a', 'format': 'JPEG'},
        {'id': 'p2', 'fileNodeId': 'f2', 'title': 'b', 'format': 'JPEG'},
      ],
    });
    expect(detail.album.id, 'album-1');
    expect(detail.album.photoCount, 120);
    expect(detail.photos, hasLength(2));
  });

  test('PhotoPage.fromJson 解析相册照片分页', () {
    final page = PhotoPage.fromJson({
      'items': [
        {'id': 'p1', 'fileNodeId': 'f1', 'title': 'a', 'format': 'JPEG'},
      ],
      'page': 1,
      'size': 50,
      'totalElements': 80,
      'totalPages': 2,
    });
    expect(page.items.single.id, 'p1');
    expect(page.page, 1);
    expect(page.totalElements, 80);
  });
}
