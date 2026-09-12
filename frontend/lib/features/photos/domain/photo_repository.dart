import 'dart:typed_data';
import 'package:omninest/features/photos/domain/photo.dart';
import 'package:omninest/features/photos/domain/photo_album.dart';
import 'package:omninest/features/photos/domain/photo_batch_task.dart';
import 'package:omninest/features/photos/domain/photo_batch_download_ticket.dart';
import 'package:omninest/features/photos/domain/photo_edit_version.dart';
import 'package:omninest/features/photos/domain/photo_group.dart';
import 'package:omninest/features/photos/domain/photo_relation.dart';
import 'package:omninest/features/photos/domain/photo_share_link.dart';
import 'package:omninest/features/photos/domain/photo_timeline.dart';
import 'package:omninest/features/tasks/domain/task_record.dart';

/// 照片仓储抽象接口
abstract interface class PhotoRepository {
  /// 获取仪表盘数据
  Future<PhotoDashboard> dashboard();

  /// 分页获取照片列表。
  Future<PhotoPage> listPhotos({
    String? query,
    int page = 0,
    int size = 50,
    String sort = 'createdAt,desc',
  });

  /// 获取单张照片详情
  Future<PhotoItem> getPhoto(String photoId);

  /// 删除照片
  Future<void> movePhotoToTrash(String photoId);

  /// 批量删除照片并返回统一任务。
  Future<void> movePhotosToTrash(List<String> photoIds);

  /// 分页查询回收站照片。
  Future<PhotoPage> listTrash({int page = 0, int size = 50});

  /// 从回收站恢复照片。
  Future<void> restorePhoto(String photoId);

  /// 为有 GPS 坐标但缺少地名的照片补充逆地理编码。
  Future<void> backfillGeocode(String photoId);

  /// 永久删除回收站中的照片。
  Future<TaskSubmission> purgePhoto(String photoId, {bool cascade = false});

  /// 提交外部编辑器产出的整图字节，保存为新编辑版本。
  Future<PhotoEditVersion> applyEditedImage(String photoId, Uint8List bytes);

  /// 按标签查询照片列表。
  Future<List<PhotoItem>> listByTag(String tag);

  /// 清空回收站。
  Future<TaskSubmission> purgeTrash();

  /// 分页获取收藏照片列表。
  Future<PhotoPage> listFavorites({
    String? query,
    int page = 0,
    int size = 50,
    String sort = 'createdAt,desc',
  });

  /// 分页获取指定年月的照片列表，时间口径与时间线一致。
  Future<PhotoPage> listByPeriod({
    required int year,
    required int month,
    int page = 0,
    int size = 50,
    String sort = 'dateTaken,desc',
  });

  /// 添加收藏
  Future<void> addFavorite(String photoId);

  /// 取消收藏
  Future<void> removeFavorite(String photoId);

  /// 获取相册列表
  Future<List<PhotoAlbum>> listAlbums();

  /// 创建相册
  Future<PhotoAlbum> createAlbum({required String name, String? description});

  /// 获取相册详情
  Future<PhotoAlbumDetail> getAlbumDetail(String albumId);

  /// 分页获取相册内照片。
  Future<PhotoPage> listAlbumPhotos({
    required String albumId,
    int page = 0,
    int size = 50,
  });

  /// 更新相册
  Future<PhotoAlbum> updateAlbum({
    required String albumId,
    String? name,
    String? description,
  });

  /// 删除相册
  Future<void> deleteAlbum(String albumId);

  /// 添加照片到相册
  Future<void> addPhotosToAlbum({
    required String albumId,
    required List<String> photoIds,
  });

  /// 分页获取可加入相册的候选照片，排除已在该相册内的照片。
  Future<PhotoPage> listAlbumCandidates({
    required String albumId,
    int page = 0,
    int size = 50,
  });

  /// 从相册移除照片
  Future<void> removePhotoFromAlbum({
    required String albumId,
    required String photoId,
  });

  /// 触发照片扫描任务
  Future<Map<String, dynamic>> triggerScan();

  /// 查询扫描任务状态
  Future<Map<String, dynamic>> getScanStatus(String jobId);

  /// 重建所有缩略图
  Future<String> regenerateThumbnails();

  /// 分页获取时间线月份数据。
  Future<PhotoTimelinePage> getTimeline({int page = 0, int size = 50});

  /// 按维度分页查询照片分组。
  Future<PhotoGroupPage> getGroups(String by, {int page = 0, int size = 50});

  /// 添加标签
  Future<void> addTag(String photoId, String tag);

  /// 移除标签
  Future<void> removeTag(String photoId, String tag);

  /// 查询所有标签
  Future<List<String>> listTags();

  /// 创建批量任务
  Future<PhotoBatchTask> createBatchTask({
    required String taskType,
    required List<String> photoIds,
    Map<String, dynamic>? params,
  });

  /// 查询批量任务状态
  Future<PhotoBatchTask> getBatchTask(String taskId);

  /// 获取照片批量 ZIP 的下载票据。
  Future<PhotoBatchDownloadTicket> getBatchDownloadTicket(String taskId);

  /// 续传并保存照片批量 ZIP。
  Future<void> downloadBatchArchive(
    PhotoBatchDownloadTicket ticket,
    String destinationPath,
  );

  /// 续传并保存单张照片原片。
  Future<void> downloadPhotoFile({
    required String url,
    required int sizeBytes,
    required String destinationPath,
  });

  /// 应用编辑操作
  Future<PhotoEditVersion> applyEdit(
    String photoId,
    String editType,
    Map<String, dynamic> editParams,
  );

  /// 获取编辑版本列表
  Future<List<PhotoEditVersion>> listVersions(String photoId);

  /// 回滚到指定版本
  Future<void> revertToVersion(String photoId, String versionId);

  /// 创建相册分享链接
  Future<PhotoShareLink> createAlbumShare(
    String albumId, {
    String? password,
    DateTime? expiresAt,
    int? maxAccessCount,
  });

  /// 列出相册分享链接
  Future<List<PhotoShareLink>> listAlbumShares(String albumId);

  /// 撤销分享链接
  Future<void> revokeAlbumShare(String shareId);

  /// 创建单张照片分享链接
  Future<PhotoShareLink> createPhotoShare(
    String photoId, {
    String? password,
    DateTime? expiresAt,
    int? maxAccessCount,
    bool includeLocation = true,
    bool originalQuality = true,
  });

  /// 列出单张照片分享链接
  Future<List<PhotoShareLink>> listPhotoShares(String photoId);

  /// 发起共享单张照片会话
  Future<String> authorizeSharedPhoto(String token, {String? password});

  /// 访问共享单张照片
  Future<PhotoItem> accessSharedPhoto(
    String token, {
    required String sessionToken,
  });

  /// 访问共享相册
  Future<String> authorizeSharedAlbum(String token, {String? password});

  Future<PhotoSharedAlbum> accessSharedAlbum(
    String token, {
    required String sessionToken,
    int page,
    int size,
  });

  // -- 关系图谱 --

  /// 获取关系图谱节点与边。
  Future<PhotoRelationGraph> getRelationGraph();

  /// 提交照片库存量 AI 重分析任务
  Future<String> reanalyzeLibrary();

  // -- 备份状态 --

  /// 获取备份状态
  Future<Map<String, dynamic>> getBackupStatus(String deviceId);

  /// 上报备份进度
  Future<void> reportBackup(String deviceId, int photoCount);

  /// 检查重复文件
  Future<List<String>> checkDuplicate(List<String> contentHashes);
}
