package com.omninest.modules.video.repository;

import com.omninest.modules.file.domain.SpaceType;
import com.omninest.modules.video.domain.MediaTvSeries;
import java.util.Collection;
import java.util.List;
import java.util.Optional;
import java.util.UUID;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

public interface MediaTvSeriesRepository extends JpaRepository<MediaTvSeries, UUID> {
    long countByOwnerUserId(UUID ownerUserId);

    List<MediaTvSeries> findByOwnerUserIdOrderByUpdatedAtDesc(UUID ownerUserId);

    /**
     * 查询当前用户可访问且至少包含一个活动剧集文件的系列。
     *
     * <p>条目按来源二分：本地媒体库来源认库可见性，网盘文件来源认本人文件或共享空间可浏览。</p>
     *
     * @param requesterUserId 请求用户 ID
     * @param sharedSpaceReadable 请求者是否可浏览共享空间
     * @param sharedSpaceType 共享空间类型常量，与 {@code sharedSpaceReadable} 同用
     * @param librarySourceIds 请求者可读的媒体库来源 ID
     * @return 活动系列
     */
    @Query("""
            select distinct series from MediaTvSeries series
            join MediaVideoItem item on item.seriesId = series.id
            join FileNode file on item.fileNodeId = file.id
            where file.deleted = false
              and ((series.librarySourceId is null
                     and (series.ownerUserId = :requesterUserId
                          or (:sharedSpaceReadable = true and file.spaceType = :sharedSpaceType)))
                   or series.librarySourceId in :librarySourceIds)
            order by series.updatedAt desc
            """)
    List<MediaTvSeries> findActiveReadable(
            @Param("requesterUserId") UUID requesterUserId,
            @Param("sharedSpaceReadable") boolean sharedSpaceReadable,
            @Param("sharedSpaceType") SpaceType sharedSpaceType,
            @Param("librarySourceIds") Collection<UUID> librarySourceIds
    );

    Optional<MediaTvSeries> findByIdAndOwnerUserId(UUID id, UUID ownerUserId);

    Optional<MediaTvSeries> findByTmdbIdAndOwnerUserId(Integer tmdbId, UUID ownerUserId);

    Optional<MediaTvSeries> findByOwnerUserIdAndTitle(UUID ownerUserId, String title);

    Optional<MediaTvSeries> findByOwnerUserIdAndLibrarySourceIdAndTitleIgnoreCase(
            UUID ownerUserId, UUID librarySourceId, String title);

    List<MediaTvSeries> findByOwnerUserIdAndSeriesTypeOrderByUpdatedAtDesc(UUID ownerUserId, String seriesType);

    /**
     * 按类型查询当前用户可访问且至少包含一个活动剧集文件的系列。
     *
     * @param requesterUserId 请求用户 ID
     * @param sharedSpaceReadable 请求者是否可浏览共享空间
     * @param sharedSpaceType 共享空间类型常量，与 {@code sharedSpaceReadable} 同用
     * @param librarySourceIds 请求者可读的媒体库来源 ID
     * @param seriesType 系列类型
     * @return 活动系列
     */
    @Query("""
            select distinct series from MediaTvSeries series
            join MediaVideoItem item on item.seriesId = series.id
            join FileNode file on item.fileNodeId = file.id
            where series.seriesType = :seriesType
              and file.deleted = false
              and ((series.librarySourceId is null
                     and (series.ownerUserId = :requesterUserId
                          or (:sharedSpaceReadable = true and file.spaceType = :sharedSpaceType)))
                   or series.librarySourceId in :librarySourceIds)
            order by series.updatedAt desc
            """)
    List<MediaTvSeries> findActiveReadableBySeriesType(
            @Param("requesterUserId") UUID requesterUserId,
            @Param("sharedSpaceReadable") boolean sharedSpaceReadable,
            @Param("sharedSpaceType") SpaceType sharedSpaceType,
            @Param("librarySourceIds") Collection<UUID> librarySourceIds,
            @Param("seriesType") String seriesType
    );

    /**
     * 分页查询当前用户可访问且仍有活动剧集文件的指定类型系列，按更新时间倒序，
     * 供系列网格滚动加载与全库关键词检索。
     *
     * @param titlePattern 标题模糊匹配串（小写 {@code %关键词%}），为空时不参与过滤
     */
    @Query(
            value = """
            select distinct series from MediaTvSeries series
            join MediaVideoItem item on item.seriesId = series.id
            join FileNode file on item.fileNodeId = file.id
            where series.seriesType = :seriesType
              and file.deleted = false
              and (:titlePattern is null or lower(series.title) like :titlePattern escape '\\')
              and ((series.librarySourceId is null
                     and (series.ownerUserId = :requesterUserId
                          or (:sharedSpaceReadable = true and file.spaceType = :sharedSpaceType)))
                   or series.librarySourceId in :librarySourceIds)
            order by series.updatedAt desc
            """,
            countQuery = """
            select count(distinct series.id) from MediaTvSeries series
            join MediaVideoItem item on item.seriesId = series.id
            join FileNode file on item.fileNodeId = file.id
            where series.seriesType = :seriesType
              and file.deleted = false
              and (:titlePattern is null or lower(series.title) like :titlePattern escape '\\')
              and ((series.librarySourceId is null
                     and (series.ownerUserId = :requesterUserId
                          or (:sharedSpaceReadable = true and file.spaceType = :sharedSpaceType)))
                   or series.librarySourceId in :librarySourceIds)
            """)
    Page<MediaTvSeries> findPageByActiveReadableAndSeriesType(
            @Param("requesterUserId") UUID requesterUserId,
            @Param("sharedSpaceReadable") boolean sharedSpaceReadable,
            @Param("sharedSpaceType") SpaceType sharedSpaceType,
            @Param("librarySourceIds") Collection<UUID> librarySourceIds,
            @Param("seriesType") String seriesType,
            @Param("titlePattern") String titlePattern,
            Pageable pageable
    );

    /**
     * 查询当前用户可访问且至少包含一个活动剧集文件的系列详情。
     *
     * @param id 系列 ID
     * @param requesterUserId 请求用户 ID
     * @param sharedSpaceReadable 请求者是否可浏览共享空间
     * @param sharedSpaceType 共享空间类型常量，与 {@code sharedSpaceReadable} 同用
     * @param librarySourceIds 请求者可读的媒体库来源 ID
     * @return 活动系列
     */
    @Query("""
            select distinct series from MediaTvSeries series
            join MediaVideoItem item on item.seriesId = series.id
            join FileNode file on item.fileNodeId = file.id
            where series.id = :id
              and file.deleted = false
              and ((series.librarySourceId is null
                     and (series.ownerUserId = :requesterUserId
                          or (:sharedSpaceReadable = true and file.spaceType = :sharedSpaceType)))
                   or series.librarySourceId in :librarySourceIds)
            """)
    Optional<MediaTvSeries> findActiveReadableById(
            @Param("id") UUID id,
            @Param("requesterUserId") UUID requesterUserId,
            @Param("sharedSpaceReadable") boolean sharedSpaceReadable,
            @Param("sharedSpaceType") SpaceType sharedSpaceType,
            @Param("librarySourceIds") Collection<UUID> librarySourceIds
    );

    /**
     * 按系列 ID 集合批量查询当前用户可访问且至少包含一个活动剧集文件的系列。
     *
     * @param ids 系列 ID 集合
     * @param requesterUserId 请求者用户 ID
     * @param sharedSpaceReadable 请求者是否可浏览共享空间
     * @param sharedSpaceType 共享空间类型常量，与 {@code sharedSpaceReadable} 同用
     * @param librarySourceIds 可访问的库来源 ID 集合
     * @return 活动系列列表
     */
    @Query("""
            select distinct series from MediaTvSeries series
            join MediaVideoItem item on item.seriesId = series.id
            join FileNode file on item.fileNodeId = file.id
            where series.id in :ids
              and file.deleted = false
              and ((series.librarySourceId is null
                     and (series.ownerUserId = :requesterUserId
                          or (:sharedSpaceReadable = true and file.spaceType = :sharedSpaceType)))
                   or series.librarySourceId in :librarySourceIds)
            """)
    List<MediaTvSeries> findActiveReadableByIdIn(
            @Param("ids") Collection<UUID> ids,
            @Param("requesterUserId") UUID requesterUserId,
            @Param("sharedSpaceReadable") boolean sharedSpaceReadable,
            @Param("sharedSpaceType") SpaceType sharedSpaceType,
            @Param("librarySourceIds") Collection<UUID> librarySourceIds
    );

    List<MediaTvSeries> findAllByIdInAndOwnerUserId(Collection<UUID> ids, UUID ownerUserId);

    void deleteByOwnerUserIdAndIdIn(UUID ownerUserId, Collection<UUID> ids);

    List<MediaTvSeries> findByOwnerUserIdAndPosterFileIdIn(UUID ownerUserId, Collection<UUID> fileIds);

    List<MediaTvSeries> findByOwnerUserIdAndBackdropFileIdIn(UUID ownerUserId, Collection<UUID> fileIds);

    List<MediaTvSeries> findByPosterFileIdIn(Collection<UUID> fileIds);

    List<MediaTvSeries> findByBackdropFileIdIn(Collection<UUID> fileIds);
}
