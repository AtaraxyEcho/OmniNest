package com.omninest.modules.video.repository;

import com.omninest.modules.video.domain.MediaTvSeries;
import java.util.Collection;
import java.util.List;
import java.util.Optional;
import java.util.UUID;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

public interface MediaTvSeriesRepository extends JpaRepository<MediaTvSeries, UUID> {
    long countByOwnerUserId(UUID ownerUserId);

    /**
     * 统计至少包含一个活动文件的系列数量。
     *
     * @param ownerUserId 所有者用户 ID
     * @return 活动系列数量
     */
    @Query("""
            select count(distinct series.id) from MediaTvSeries series
            join MediaVideoItem item on item.seriesId = series.id
            join FileNode file on item.fileNodeId = file.id
            where series.ownerUserId = :ownerUserId and file.deleted = false
            """)
    long countActiveByOwnerUserId(@Param("ownerUserId") UUID ownerUserId);

    List<MediaTvSeries> findByOwnerUserIdOrderByUpdatedAtDesc(UUID ownerUserId);

    /**
     * 查询至少包含一个活动剧集文件的系列。
     *
     * @param ownerUserId 所有者用户 ID
     * @return 活动系列
     */
    @Query("""
            select distinct series from MediaTvSeries series
            join MediaVideoItem item on item.seriesId = series.id
            join FileNode file on item.fileNodeId = file.id
            where series.ownerUserId = :ownerUserId and file.deleted = false
            order by series.updatedAt desc
            """)
    List<MediaTvSeries> findActiveByOwnerUserId(@Param("ownerUserId") UUID ownerUserId);

    @Query("""
            select distinct series from MediaTvSeries series
            join MediaVideoItem item on item.seriesId = series.id
            join FileNode file on item.fileNodeId = file.id
            where file.deleted = false
              and ((series.librarySourceId is null and series.ownerUserId = :requesterUserId)
                   or series.librarySourceId in :librarySourceIds)
            order by series.updatedAt desc
            """)
    List<MediaTvSeries> findActiveReadable(
            @Param("requesterUserId") UUID requesterUserId,
            @Param("librarySourceIds") Collection<UUID> librarySourceIds
    );

    Optional<MediaTvSeries> findByIdAndOwnerUserId(UUID id, UUID ownerUserId);

    Optional<MediaTvSeries> findByTmdbIdAndOwnerUserId(Integer tmdbId, UUID ownerUserId);

    Optional<MediaTvSeries> findByOwnerUserIdAndTitle(UUID ownerUserId, String title);

    Optional<MediaTvSeries> findByOwnerUserIdAndLibrarySourceIdAndTitleIgnoreCase(
            UUID ownerUserId, UUID librarySourceId, String title);

    List<MediaTvSeries> findByOwnerUserIdAndSeriesTypeOrderByUpdatedAtDesc(UUID ownerUserId, String seriesType);

    /**
     * 按类型查询至少包含一个活动剧集文件的系列。
     *
     * @param ownerUserId 所有者用户 ID
     * @param seriesType 系列类型
     * @return 活动系列
     */
    @Query("""
            select distinct series from MediaTvSeries series
            join MediaVideoItem item on item.seriesId = series.id
            join FileNode file on item.fileNodeId = file.id
            where series.ownerUserId = :ownerUserId
              and series.seriesType = :seriesType
              and file.deleted = false
            order by series.updatedAt desc
            """)
    List<MediaTvSeries> findActiveByOwnerUserIdAndSeriesType(
            @Param("ownerUserId") UUID ownerUserId,
            @Param("seriesType") String seriesType
    );

    @Query("""
            select distinct series from MediaTvSeries series
            join MediaVideoItem item on item.seriesId = series.id
            join FileNode file on item.fileNodeId = file.id
            where series.seriesType = :seriesType
              and file.deleted = false
              and ((series.librarySourceId is null and series.ownerUserId = :requesterUserId)
                   or series.librarySourceId in :librarySourceIds)
            order by series.updatedAt desc
            """)
    List<MediaTvSeries> findActiveReadableBySeriesType(
            @Param("requesterUserId") UUID requesterUserId,
            @Param("librarySourceIds") Collection<UUID> librarySourceIds,
            @Param("seriesType") String seriesType
    );

    /**
     * 查询当前用户可访问且至少包含一个活动剧集文件的系列详情。
     *
     * @param id 系列 ID
     * @param ownerUserId 所有者用户 ID
     * @return 活动系列
     */
    @Query("""
            select distinct series from MediaTvSeries series
            join MediaVideoItem item on item.seriesId = series.id
            join FileNode file on item.fileNodeId = file.id
            where series.id = :id and series.ownerUserId = :ownerUserId and file.deleted = false
            """)
    Optional<MediaTvSeries> findActiveByIdAndOwnerUserId(
            @Param("id") UUID id,
            @Param("ownerUserId") UUID ownerUserId
    );

    @Query("""
            select distinct series from MediaTvSeries series
            join MediaVideoItem item on item.seriesId = series.id
            join FileNode file on item.fileNodeId = file.id
            where series.id = :id
              and file.deleted = false
              and ((series.librarySourceId is null and series.ownerUserId = :requesterUserId)
                   or series.librarySourceId in :librarySourceIds)
            """)
    Optional<MediaTvSeries> findActiveReadableById(
            @Param("id") UUID id,
            @Param("requesterUserId") UUID requesterUserId,
            @Param("librarySourceIds") Collection<UUID> librarySourceIds
    );

    /**
     * 按系列 ID 集合批量查询当前用户可访问且至少包含一个活动剧集文件的系列。
     *
     * @param ids 系列 ID 集合
     * @param requesterUserId 请求者用户 ID
     * @param librarySourceIds 可访问的库来源 ID 集合
     * @return 活动系列列表
     */
    @Query("""
            select distinct series from MediaTvSeries series
            join MediaVideoItem item on item.seriesId = series.id
            join FileNode file on item.fileNodeId = file.id
            where series.id in :ids
              and file.deleted = false
              and ((series.librarySourceId is null and series.ownerUserId = :requesterUserId)
                   or series.librarySourceId in :librarySourceIds)
            """)
    List<MediaTvSeries> findActiveReadableByIdIn(
            @Param("ids") Collection<UUID> ids,
            @Param("requesterUserId") UUID requesterUserId,
            @Param("librarySourceIds") Collection<UUID> librarySourceIds
    );

    List<MediaTvSeries> findAllByIdInAndOwnerUserId(Collection<UUID> ids, UUID ownerUserId);

    void deleteByOwnerUserIdAndIdIn(UUID ownerUserId, Collection<UUID> ids);

    List<MediaTvSeries> findByOwnerUserIdAndPosterFileIdIn(UUID ownerUserId, Collection<UUID> fileIds);

    List<MediaTvSeries> findByOwnerUserIdAndBackdropFileIdIn(UUID ownerUserId, Collection<UUID> fileIds);

    List<MediaTvSeries> findByPosterFileIdIn(Collection<UUID> fileIds);

    List<MediaTvSeries> findByBackdropFileIdIn(Collection<UUID> fileIds);
}
