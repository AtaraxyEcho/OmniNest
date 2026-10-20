import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/features/files/application/file_browser_models.dart';
import 'package:omninest/features/files/domain/file_node.dart';

FileNode _node(String id, String name, String mimeType) {
  return FileNode(
    id: id,
    parentId: null,
    name: name,
    isFolder: false,
    nodeType: 'FILE',
    normalizedPath: '/$name',
    sizeBytes: 10,
    updatedAt: DateTime(2026, 9, 28),
    mimeType: mimeType,
  );
}

void main() {
  final images = [
    _node('a', 'cat.png', 'image/png'),
    _node('b', 'dog.jpg', 'image/jpeg'),
  ];
  final movies = [_node('c', 'trip.mp4', 'video/mp4')];

  test('非全部文件分区按分类就地过滤，分区保持不变', () {
    final state = FileBrowserState(
      files: const [],
      recycleBin: const [],
      favoriteFiles: [...images, ...movies],
      section: FileManagerSection.favorites,
      fileCategory: FileBrowserFileCategory.image,
    );

    expect(state.section, FileManagerSection.favorites);
    expect(state.visibleNodes.map((node) => node.id), ['a', 'b']);
  });

  test('回收站分区同样按分类过滤，不请求全部文件接口', () {
    final state = FileBrowserState(
      files: const [],
      recycleBin: [...images, ...movies],
      section: FileManagerSection.recycleBin,
      fileCategory: FileBrowserFileCategory.video,
    );

    expect(state.visibleNodes.map((node) => node.id), ['c']);
  });

  test('选中某分类后其余胶囊计数不清零', () {
    final state = FileBrowserState(
      files: const [],
      recycleBin: const [],
      favoriteFiles: [...images, ...movies],
      section: FileManagerSection.favorites,
      fileCategory: FileBrowserFileCategory.image,
    );

    // 计数母集是未过滤的分区原始列表：图片 2、视频 1、全部 3。
    expect(state.sectionNodes, hasLength(3));
    expect(
      state.sectionNodes.where((node) => node.name.endsWith('.mp4')),
      hasLength(1),
    );
    expect(state.visibleNodes, hasLength(2));
  });

  test('搜索词与分类叠加过滤', () {
    final state = FileBrowserState(
      files: const [],
      recycleBin: const [],
      favoriteFiles: [...images, ...movies],
      section: FileManagerSection.favorites,
      fileCategory: FileBrowserFileCategory.image,
      searchQuery: 'dog',
    );

    expect(state.visibleNodes.map((node) => node.id), ['b']);
  });

  test('全部分类不做任何过滤', () {
    final state = FileBrowserState(
      files: const [],
      recycleBin: const [],
      favoriteFiles: [...images, ...movies],
      section: FileManagerSection.favorites,
    );

    expect(state.visibleNodes, hasLength(3));
  });
}
