import 'package:omninest/features/photos/domain/photo.dart';
import 'package:omninest/features/photos/domain/photo_album.dart';
import 'package:omninest/features/photos/domain/photo_group.dart';
import 'package:omninest/features/photos/domain/photo_relation.dart';
import 'package:omninest/features/photos/domain/photo_timeline.dart';

// -- 状态管理 --

/// 图库数据源芯片。
enum PhotoTab { all, favorites }

/// 图库内容形态：按日/按月网格、时间线、分组浏览。
enum PhotoLibraryView { gridDay, gridMonth, timeline, groups }

/// Frame 设计稿中的图库视图：全部照片、时间线、地点、标签、影集、收藏、回收站。
enum FrameView { grid, timeline, locations, tags, albums, favorites, trash }

/// 导入流程提示类型；文案由界面层按语言映射。
enum PhotoImportNotice { completedNotVisible, stillProcessing, backendFailed }

/// 照片中心状态
class PhotoCenterState {
  const PhotoCenterState({
    required this.dashboard,
    required this.photos,
    required this.favorites,
    required this.albums,
    required this.tab,
    this.libraryView = PhotoLibraryView.gridDay,
    this.frameView = FrameView.grid,
    this.searchQuery = '',
    this.timeline,
    this.groups,
    this.groupBy = GroupBy.date,
    this.selectedPhotoIds = const {},
    this.isSelectionMode = false,
    this.relationGraph = PhotoRelationGraph.empty,
    this.isLoadingRelationGraph = false,
    this.relationGraphError,
    this.photoPage = 0,
    this.favoritePage = 0,
    this.photoTotalElements = 0,
    this.favoriteTotalElements = 0,
    this.isLoadingMorePhotos = false,
    this.isLoadingMoreFavorites = false,
    this.photoRefreshVersion = 0,
    this.favoriteRefreshVersion = 0,
    this.photoPageError,
    this.favoritePageError,
    this.timelinePage = 0,
    this.timelineTotalElements = 0,
    this.isLoadingMoreTimeline = false,
    this.timelinePageError,
    this.groupPage = 0,
    this.groupTotalElements = 0,
    this.isLoadingGroups = false,
    this.isLoadingMoreGroups = false,
    this.groupPageError,
    this.trashPhotos = const [],
    this.trashPage = 0,
    this.trashTotalElements = 0,
    this.isLoadingTrash = false,
    this.isLoadingMoreTrash = false,
    this.trashPageError,
    this.albumsHasMore = false,
    this.albumsPage = 0,
    this.isLoadingMoreAlbums = false,
    this.errorMessage,
  });

  factory PhotoCenterState.empty() {
    return PhotoCenterState(
      dashboard: PhotoDashboard.empty(),
      photos: const [],
      favorites: const [],
      albums: const [],
      tab: PhotoTab.all,
    );
  }

  final PhotoDashboard dashboard;
  final List<PhotoItem> photos;
  final List<PhotoItem> favorites;
  final List<PhotoAlbum> albums;
  final PhotoTab tab;
  final PhotoLibraryView libraryView;
  final FrameView frameView;
  final String searchQuery;
  final PhotoTimeline? timeline;
  final List<PhotoGroup>? groups;
  final GroupBy groupBy;
  final Set<String> selectedPhotoIds;
  final bool isSelectionMode;
  final PhotoRelationGraph relationGraph;
  final bool isLoadingRelationGraph;
  final String? relationGraphError;
  final int photoPage;
  final int favoritePage;
  final int photoTotalElements;
  final int favoriteTotalElements;
  final bool isLoadingMorePhotos;
  final bool isLoadingMoreFavorites;
  final int photoRefreshVersion;
  final int favoriteRefreshVersion;
  final String? photoPageError;
  final String? favoritePageError;
  final int timelinePage;
  final int timelineTotalElements;
  final bool isLoadingMoreTimeline;
  final String? timelinePageError;
  final int groupPage;
  final int groupTotalElements;
  final bool isLoadingGroups;
  final bool isLoadingMoreGroups;
  final String? groupPageError;
  final List<PhotoItem> trashPhotos;
  final int trashPage;
  final int trashTotalElements;
  final bool isLoadingTrash;
  final bool isLoadingMoreTrash;
  final String? trashPageError;
  final bool albumsHasMore;
  final int albumsPage;
  final bool isLoadingMoreAlbums;
  final String? errorMessage;

  bool get hasMoreTrash => trashPhotos.length < trashTotalElements;

  bool get hasMorePhotos => photos.length < photoTotalElements;

  bool get hasMoreFavorites => favorites.length < favoriteTotalElements;

  bool get hasMoreTimeline =>
      timeline != null && timeline!.monthCount < timelineTotalElements;

  bool get hasMoreGroups =>
      groups != null && groups!.length < groupTotalElements;

  bool get hasMoreVisiblePhotos => switch (tab) {
    PhotoTab.all => hasMorePhotos,
    PhotoTab.favorites => hasMoreFavorites,
  };

  bool get isLoadingMoreVisiblePhotos => switch (tab) {
    PhotoTab.all => isLoadingMorePhotos,
    PhotoTab.favorites => isLoadingMoreFavorites,
  };

  int get visiblePhotoTotalElements => switch (tab) {
    PhotoTab.all => photoTotalElements,
    PhotoTab.favorites => favoriteTotalElements,
  };

  /// 当前数据源下可见的照片
  List<PhotoItem> get visiblePhotos {
    final source = switch (tab) {
      PhotoTab.all => photos,
      PhotoTab.favorites => favorites,
    };
    final query = searchQuery.trim().toLowerCase();
    if (query.isEmpty) return source;
    return source
        .where(
          (photo) =>
              photo.title.toLowerCase().contains(query) ||
              (photo.description ?? '').toLowerCase().contains(query),
        )
        .toList();
  }

  PhotoCenterState copyWith({
    PhotoDashboard? dashboard,
    List<PhotoItem>? photos,
    List<PhotoItem>? favorites,
    List<PhotoAlbum>? albums,
    PhotoTab? tab,
    PhotoLibraryView? libraryView,
    FrameView? frameView,
    String? searchQuery,
    PhotoTimeline? timeline,
    List<PhotoGroup>? groups,
    GroupBy? groupBy,
    Set<String>? selectedPhotoIds,
    bool? isSelectionMode,
    PhotoRelationGraph? relationGraph,
    bool? isLoadingRelationGraph,
    String? relationGraphError,
    bool clearRelationGraphError = false,
    int? photoPage,
    int? favoritePage,
    int? photoTotalElements,
    int? favoriteTotalElements,
    bool? isLoadingMorePhotos,
    bool? isLoadingMoreFavorites,
    int? photoRefreshVersion,
    int? favoriteRefreshVersion,
    String? photoPageError,
    String? favoritePageError,
    int? timelinePage,
    int? timelineTotalElements,
    bool? isLoadingMoreTimeline,
    String? timelinePageError,
    int? groupPage,
    int? groupTotalElements,
    bool? isLoadingGroups,
    bool? isLoadingMoreGroups,
    String? groupPageError,
    bool clearPhotoPageError = false,
    bool clearFavoritePageError = false,
    bool clearTimelinePageError = false,
    bool clearGroupPageError = false,
    List<PhotoItem>? trashPhotos,
    int? trashPage,
    int? trashTotalElements,
    bool? isLoadingTrash,
    bool? isLoadingMoreTrash,
    String? trashPageError,
    bool clearTrashPageError = false,
    bool? albumsHasMore,
    int? albumsPage,
    bool? isLoadingMoreAlbums,
    String? errorMessage,
    bool clearError = false,
  }) {
    return PhotoCenterState(
      dashboard: dashboard ?? this.dashboard,
      photos: photos ?? this.photos,
      favorites: favorites ?? this.favorites,
      albums: albums ?? this.albums,
      tab: tab ?? this.tab,
      libraryView: libraryView ?? this.libraryView,
      frameView: frameView ?? this.frameView,
      searchQuery: searchQuery ?? this.searchQuery,
      timeline: timeline ?? this.timeline,
      groups: groups ?? this.groups,
      groupBy: groupBy ?? this.groupBy,
      selectedPhotoIds: selectedPhotoIds ?? this.selectedPhotoIds,
      isSelectionMode: isSelectionMode ?? this.isSelectionMode,
      relationGraph: relationGraph ?? this.relationGraph,
      isLoadingRelationGraph:
          isLoadingRelationGraph ?? this.isLoadingRelationGraph,
      relationGraphError:
          clearRelationGraphError
              ? null
              : (relationGraphError ?? this.relationGraphError),
      photoPage: photoPage ?? this.photoPage,
      favoritePage: favoritePage ?? this.favoritePage,
      photoTotalElements: photoTotalElements ?? this.photoTotalElements,
      favoriteTotalElements:
          favoriteTotalElements ?? this.favoriteTotalElements,
      isLoadingMorePhotos: isLoadingMorePhotos ?? this.isLoadingMorePhotos,
      isLoadingMoreFavorites:
          isLoadingMoreFavorites ?? this.isLoadingMoreFavorites,
      photoRefreshVersion: photoRefreshVersion ?? this.photoRefreshVersion,
      favoriteRefreshVersion:
          favoriteRefreshVersion ?? this.favoriteRefreshVersion,
      photoPageError:
          clearPhotoPageError ? null : (photoPageError ?? this.photoPageError),
      favoritePageError:
          clearFavoritePageError
              ? null
              : (favoritePageError ?? this.favoritePageError),
      timelinePage: timelinePage ?? this.timelinePage,
      timelineTotalElements:
          timelineTotalElements ?? this.timelineTotalElements,
      isLoadingMoreTimeline:
          isLoadingMoreTimeline ?? this.isLoadingMoreTimeline,
      timelinePageError:
          clearTimelinePageError
              ? null
              : (timelinePageError ?? this.timelinePageError),
      groupPage: groupPage ?? this.groupPage,
      groupTotalElements: groupTotalElements ?? this.groupTotalElements,
      isLoadingGroups: isLoadingGroups ?? this.isLoadingGroups,
      isLoadingMoreGroups: isLoadingMoreGroups ?? this.isLoadingMoreGroups,
      groupPageError:
          clearGroupPageError ? null : (groupPageError ?? this.groupPageError),
      trashPhotos: trashPhotos ?? this.trashPhotos,
      trashPage: trashPage ?? this.trashPage,
      trashTotalElements: trashTotalElements ?? this.trashTotalElements,
      isLoadingTrash: isLoadingTrash ?? this.isLoadingTrash,
      isLoadingMoreTrash: isLoadingMoreTrash ?? this.isLoadingMoreTrash,
      trashPageError:
          clearTrashPageError ? null : (trashPageError ?? this.trashPageError),
      albumsHasMore: albumsHasMore ?? this.albumsHasMore,
      albumsPage: albumsPage ?? this.albumsPage,
      isLoadingMoreAlbums: isLoadingMoreAlbums ?? this.isLoadingMoreAlbums,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }
}
