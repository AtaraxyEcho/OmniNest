package com.omninest.modules.video.repository;

import com.omninest.modules.file.domain.SpaceType;
import com.omninest.modules.video.domain.MediaVideoItem;
import java.time.Instant;
import java.util.Collection;
import java.util.List;
import java.util.Optional;
import java.util.UUID;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

public interface MediaVideoItemRepository extends JpaRepository<MediaVideoItem, UUID> {
    long countByLibrarySourceId(UUID librarySourceId);

    @Query("""
            select count(i) from MediaVideoItem i
            join FileNode file on i.fileNodeId = file.id
            where i.ownerUserId = :ownerUserId and i.mediaType = :mediaType
              and i.sourceVideoItemId is null and file.deleted = false
            """)
    long countByOwnerUserIdAndMediaType(@Param("ownerUserId") UUID ownerUserId, @Param("mediaType") String mediaType);

    @Query("""
            select count(i) from MediaVideoItem i
            join FileNode file on i.fileNodeId = file.id
            where i.ownerUserId = :ownerUserId and i.metadataStatus = :metadataStatus
              and i.sourceVideoItemId is null and file.deleted = false
            """)
    long countByOwnerUserIdAndMetadataStatus(@Param("ownerUserId") UUID ownerUserId, @Param("metadataStatus") String metadataStatus);

    // 库列表查询：排除派生版本（sourceVideoItemId IS NULL = 仅原始条目）

    @Query("""
            select i from MediaVideoItem i
            join FileNode file on i.fileNodeId = file.id
            where i.ownerUserId = :ownerUserId and i.sourceVideoItemId is null and file.deleted = false
            order by i.updatedAt desc
            """)
    List<MediaVideoItem> findTop12ByOwnerUserIdOrderByUpdatedAtDesc(@Param("ownerUserId") UUID ownerUserId);

    @Query("""
            select i from MediaVideoItem i
            join FileNode file on i.fileNodeId = file.id
            where i.ownerUserId = :ownerUserId and i.mediaType = :mediaType
              and i.sourceVideoItemId is null and file.deleted = false
            order by i.updatedAt desc
            """)
    List<MediaVideoItem> findByOwnerUserIdAndMediaTypeOrderByUpdatedAtDesc(@Param("ownerUserId") UUID ownerUserId, @Param("mediaType") String mediaType);

    @Query("""
            select i from MediaVideoItem i
            join FileNode file on i.fileNodeId = file.id
            where i.ownerUserId = :ownerUserId and i.updatedAt > :updatedAt
              and i.sourceVideoItemId is null and file.deleted = false
            order by i.updatedAt desc
            """)
    List<MediaVideoItem> findByOwnerUserIdAndUpdatedAtAfterOrderByUpdatedAtDesc(@Param("ownerUserId") UUID ownerUserId, @Param("updatedAt") Instant updatedAt);

    @Query("""
            select i from MediaVideoItem i
            join FileNode file on i.fileNodeId = file.id
            where i.mediaType = :mediaType
              and i.sourceVideoItemId is null
              and file.deleted = false
              and ((i.librarySourceId is null and i.ownerUserId = :requesterUserId)
                   or i.librarySourceId in :librarySourceIds)
            order by i.updatedAt desc
            """)
    List<MediaVideoItem> findReadableOriginalsByMediaType(
            @Param("requesterUserId") UUID requesterUserId,
            @Param("librarySourceIds") Collection<UUID> librarySourceIds,
            @Param("mediaType") String mediaType
    );

    @Query("""
            select i from MediaVideoItem i
            join FileNode file on i.fileNodeId = file.id
            where i.mediaType = :mediaType
              and i.sourceVideoItemId is null
              and file.deleted = false
              and (:metadataStatus is null or i.metadataStatus = :metadataStatus)
              and ((i.librarySourceId is null and i.ownerUserId = :requesterUserId)
                   or i.librarySourceId in :librarySourceIds)
            """)
    Page<MediaVideoItem> findReadableOriginalsByMediaType(
            @Param("requesterUserId") UUID requesterUserId,
            @Param("librarySourceIds") Collection<UUID> librarySourceIds,
            @Param("mediaType") String mediaType,
            @Param("metadataStatus") String metadataStatus,
            Pageable pageable
    );

    /**
     * 分页检索可读的原始视频条目，按标题模糊匹配。
     *
     * <p>库内搜索必须覆盖全库而不是已加载分页，故关键词在 SQL 侧过滤：
     * {@code titlePattern} 由调用方归一化为小写 {@code %关键词%}，为空时不参与过滤。
     * 标题取元数据标题（影片 → 分集 → 文件名），与 {@code VideoItemDtoConverter}
     * 及不可用媒体投影的 {@code coalesce} 口径一致，未识别元数据的条目仍可按文件名搜到。
     *
     * @param requesterUserId 请求用户 ID
     * @param librarySourceIds 用户可读的服务器媒体库 ID
     * @param mediaType 媒体类型
     * @param metadataStatus 元数据状态过滤，可为空
     * @param titlePattern 标题模糊匹配串，可为空
     * @param pageable 分页参数
     * @return 匹配的视频条目分页
     */
    @Query("""
            select i from MediaVideoItem i
            join FileNode file on i.fileNodeId = file.id
            left join MediaMovie movie on i.movieId = movie.id
            left join MediaTvEpisode episode on i.episodeId = episode.id
            where i.mediaType = :mediaType
              and i.sourceVideoItemId is null
              and file.deleted = false
              and (:metadataStatus is null or i.metadataStatus = :metadataStatus)
              and (:titlePattern is null
                   or lower(coalesce(movie.title, episode.title, file.name)) like :titlePattern)
              and ((i.librarySourceId is null and i.ownerUserId = :requesterUserId)
                   or i.librarySourceId in :librarySourceIds)
            """)
    Page<MediaVideoItem> searchReadableOriginalsByMediaType(
            @Param("requesterUserId") UUID requesterUserId,
            @Param("librarySourceIds") Collection<UUID> librarySourceIds,
            @Param("mediaType") String mediaType,
            @Param("metadataStatus") String metadataStatus,
            @Param("titlePattern") String titlePattern,
            Pageable pageable
    );

    @Query("""
            select i from MediaVideoItem i
            join FileNode file on i.fileNodeId = file.id
            where i.sourceVideoItemId is null
              and file.deleted = false
              and ((i.librarySourceId is null and i.ownerUserId = :requesterUserId)
                   or i.librarySourceId in :librarySourceIds)
            order by i.updatedAt desc
            """)
    List<MediaVideoItem> findReadableOriginals(
            @Param("requesterUserId") UUID requesterUserId,
            @Param("librarySourceIds") Collection<UUID> librarySourceIds
    );

    @Query("""
            select i from MediaVideoItem i
            join FileNode file on i.fileNodeId = file.id
            where i.sourceVideoItemId is null
              and file.deleted = false
              and ((i.librarySourceId is null and i.ownerUserId = :requesterUserId)
                   or i.librarySourceId in :librarySourceIds)
            """)
    Page<MediaVideoItem> findReadableOriginals(
            @Param("requesterUserId") UUID requesterUserId,
            @Param("librarySourceIds") Collection<UUID> librarySourceIds,
            Pageable pageable
    );

    @Query("""
            select count(i) from MediaVideoItem i
            join FileNode file on i.fileNodeId = file.id
            where i.mediaType = :mediaType
              and i.sourceVideoItemId is null
              and file.deleted = false
              and ((i.librarySourceId is null and i.ownerUserId = :requesterUserId)
                   or i.librarySourceId in :librarySourceIds)
            """)
    long countReadableOriginalsByMediaType(
            @Param("requesterUserId") UUID requesterUserId,
            @Param("librarySourceIds") Collection<UUID> librarySourceIds,
            @Param("mediaType") String mediaType
    );

    @Query("""
            select count(i) from MediaVideoItem i
            join FileNode file on i.fileNodeId = file.id
            where i.metadataStatus = :metadataStatus
              and i.sourceVideoItemId is null
              and file.deleted = false
              and ((i.librarySourceId is null and i.ownerUserId = :requesterUserId)
                   or i.librarySourceId in :librarySourceIds)
            """)
    long countReadableOriginalsByMetadataStatus(
            @Param("requesterUserId") UUID requesterUserId,
            @Param("librarySourceIds") Collection<UUID> librarySourceIds,
            @Param("metadataStatus") String metadataStatus
    );

    @Query("""
            select count(distinct i.seriesId) from MediaVideoItem i
            join FileNode file on i.fileNodeId = file.id
            where i.seriesId is not null
              and i.sourceVideoItemId is null
              and file.deleted = false
              and ((i.librarySourceId is null and i.ownerUserId = :requesterUserId)
                   or i.librarySourceId in :librarySourceIds)
            """)
    long countReadableOriginalSeries(
            @Param("requesterUserId") UUID requesterUserId,
            @Param("librarySourceIds") Collection<UUID> librarySourceIds
    );

    @Query("""
            select i from MediaVideoItem i
            join FileNode file on i.fileNodeId = file.id
            where i.updatedAt > :updatedAt
              and i.sourceVideoItemId is null
              and file.deleted = false
              and ((i.librarySourceId is null and i.ownerUserId = :requesterUserId)
                   or i.librarySourceId in :librarySourceIds)
            order by i.updatedAt desc
            """)
    List<MediaVideoItem> findReadableOriginalsUpdatedAfter(
            @Param("requesterUserId") UUID requesterUserId,
            @Param("librarySourceIds") Collection<UUID> librarySourceIds,
            @Param("updatedAt") Instant updatedAt
    );

    @Query("""
            select i from MediaVideoItem i
            join FileNode file on i.fileNodeId = file.id
            where i.ownerUserId = :ownerUserId and i.seriesId = :seriesId
              and i.sourceVideoItemId is null and file.deleted = false
            order by i.seasonNumber asc, i.episodeNumber asc
            """)
    List<MediaVideoItem> findByOwnerUserIdAndSeriesIdOrderBySeasonNumberAscEpisodeNumberAsc(@Param("ownerUserId") UUID ownerUserId, @Param("seriesId") UUID seriesId);

    @Query("""
            select i from MediaVideoItem i
            join FileNode file on i.fileNodeId = file.id
            where i.seriesId = :seriesId
              and i.sourceVideoItemId is null
              and file.deleted = false
              and ((i.librarySourceId is null and i.ownerUserId = :requesterUserId)
                   or i.librarySourceId in :librarySourceIds)
            order by i.seasonNumber asc, i.episodeNumber asc
            """)
    List<MediaVideoItem> findReadableBySeriesId(
            @Param("requesterUserId") UUID requesterUserId,
            @Param("librarySourceIds") Collection<UUID> librarySourceIds,
            @Param("seriesId") UUID seriesId
    );

    @Query("""
            select i from MediaVideoItem i
            join FileNode file on i.fileNodeId = file.id
            where i.ownerUserId = :ownerUserId and i.seriesId = :seriesId
              and i.seasonNumber = :seasonNumber and i.sourceVideoItemId is null
              and file.deleted = false
            order by i.episodeNumber asc
            """)
    List<MediaVideoItem> findByOwnerUserIdAndSeriesIdAndSeasonNumberOrderByEpisodeNumberAsc(@Param("ownerUserId") UUID ownerUserId, @Param("seriesId") UUID seriesId, @Param("seasonNumber") Integer seasonNumber);

    @Query("""
            select i from MediaVideoItem i
            join FileNode file on i.fileNodeId = file.id
            where i.seriesId = :seriesId
              and i.seasonNumber = :seasonNumber
              and i.sourceVideoItemId is null
              and file.deleted = false
              and ((i.librarySourceId is null and i.ownerUserId = :requesterUserId)
                   or i.librarySourceId in :librarySourceIds)
            order by i.episodeNumber asc
            """)
    List<MediaVideoItem> findReadableBySeriesIdAndSeasonNumber(
            @Param("requesterUserId") UUID requesterUserId,
            @Param("librarySourceIds") Collection<UUID> librarySourceIds,
            @Param("seriesId") UUID seriesId,
            @Param("seasonNumber") Integer seasonNumber
    );

    @Query("""
            select item from MediaVideoItem item
            join FileNode file on item.fileNodeId = file.id
            where item.id = :id and item.ownerUserId = :ownerUserId and file.deleted = false
            """)
    Optional<MediaVideoItem> findByIdAndOwnerUserId(
            @Param("id") UUID id,
            @Param("ownerUserId") UUID ownerUserId
    );

    Optional<MediaVideoItem> findByOwnerUserIdAndFileNodeId(UUID ownerUserId, UUID fileNodeId);

    List<MediaVideoItem> findByOwnerUserIdAndMovieId(UUID ownerUserId, UUID movieId);

    List<MediaVideoItem> findByOwnerUserIdAndEpisodeId(UUID ownerUserId, UUID episodeId);

    // 版本列表查询：仅原始条目（排除派生版本如 AUDIO_ONLY、H265）
    @Query("""
            select i from MediaVideoItem i
            join FileNode file on i.fileNodeId = file.id
            where i.ownerUserId = :ownerUserId and i.movieId = :movieId
              and i.sourceVideoItemId is null and file.deleted = false
            """)
    List<MediaVideoItem> findOriginalsByOwnerUserIdAndMovieId(@Param("ownerUserId") UUID ownerUserId, @Param("movieId") UUID movieId);

    @Query("""
            select i from MediaVideoItem i
            join FileNode file on i.fileNodeId = file.id
            where i.ownerUserId = :ownerUserId and i.episodeId = :episodeId
              and i.sourceVideoItemId is null and file.deleted = false
            """)
    List<MediaVideoItem> findOriginalsByOwnerUserIdAndEpisodeId(@Param("ownerUserId") UUID ownerUserId, @Param("episodeId") UUID episodeId);

    List<MediaVideoItem> findByOwnerUserIdAndFileNodeIdIn(UUID ownerUserId, Collection<UUID> fileNodeIds);

    /**
     * 按 fileNodeId 查询所有视频条目（不限 ownerUserId，共享空间清理用）。
     */
    List<MediaVideoItem> findByFileNodeIdIn(Collection<UUID> fileNodeIds);

    @Query("""
            select i from MediaVideoItem i
            join FileNode file on i.fileNodeId = file.id
            where i.id in :ids and i.ownerUserId = :ownerUserId and file.deleted = false
            """)
    List<MediaVideoItem> findAllByIdInAndOwnerUserId(@Param("ids") Collection<UUID> ids, @Param("ownerUserId") UUID ownerUserId);

    @Query("""
            select i from MediaVideoItem i
            join FileNode file on i.fileNodeId = file.id
            where i.id in :ids
              and file.deleted = false
              and ((i.librarySourceId is null and i.ownerUserId = :requesterUserId)
                   or i.librarySourceId in :librarySourceIds)
            """)
    List<MediaVideoItem> findReadableByIds(
            @Param("requesterUserId") UUID requesterUserId,
            @Param("librarySourceIds") Collection<UUID> librarySourceIds,
            @Param("ids") Collection<UUID> ids
    );

    @Query("select count(i) from MediaVideoItem i where i.ownerUserId = :ownerUserId and i.seriesId = :seriesId and i.seasonNumber = :seasonNumber and i.sourceVideoItemId is null")
    long countByOwnerUserIdAndSeriesIdAndSeasonNumber(@Param("ownerUserId") UUID ownerUserId, @Param("seriesId") UUID seriesId, @Param("seasonNumber") Integer seasonNumber);

    Optional<MediaVideoItem> findByOwnerUserIdAndSourceVideoItemIdAndVideoCodec(UUID ownerUserId, UUID sourceVideoItemId, String videoCodec);

    Optional<MediaVideoItem> findByOwnerUserIdAndSourceVideoItemIdAndAudioCodec(UUID ownerUserId, UUID sourceVideoItemId, String audioCodec);

    Optional<MediaVideoItem> findByOwnerUserIdAndSourceVideoItemIdAndVersionLabel(UUID ownerUserId, UUID sourceVideoItemId, String versionLabel);

    long countByOwnerUserIdAndMovieId(UUID ownerUserId, UUID movieId);

    long countByOwnerUserIdAndEpisodeId(UUID ownerUserId, UUID episodeId);

    long countByOwnerUserIdAndMovieIdAndIdNotIn(
            UUID ownerUserId,
            UUID movieId,
            Collection<UUID> excludedVideoItemIds
    );

    long countByOwnerUserIdAndEpisodeIdAndIdNotIn(
            UUID ownerUserId,
            UUID episodeId,
            Collection<UUID> excludedVideoItemIds
    );

    long countByOwnerUserIdAndSeriesIdAndIdNotIn(
            UUID ownerUserId,
            UUID seriesId,
            Collection<UUID> excludedVideoItemIds
    );

    @Query("""
            select count(item) from MediaVideoItem item
            where item.ownerUserId = :ownerUserId
              and item.seriesId = :seriesId
              and item.seasonNumber = :seasonNumber
              and item.id not in :excludedVideoItemIds
            """)
    long countSeasonItemsOutsideTarget(
            @Param("ownerUserId") UUID ownerUserId,
            @Param("seriesId") UUID seriesId,
            @Param("seasonNumber") Integer seasonNumber,
            @Param("excludedVideoItemIds") Collection<UUID> excludedVideoItemIds
    );

    /**
     * 批量查询有视频条目的 movieId 集合（避免孤立清理 N+1）。
     */
    @Query("SELECT DISTINCT i.movieId FROM MediaVideoItem i WHERE i.ownerUserId = :ownerUserId AND i.movieId IN :movieIds")
    List<UUID> findMovieIdsWithItems(@Param("ownerUserId") UUID ownerUserId, @Param("movieIds") Collection<UUID> movieIds);

    /**
     * 批量查询有视频条目的 episodeId 集合（避免孤立清理 N+1）。
     */
    @Query("SELECT DISTINCT i.episodeId FROM MediaVideoItem i WHERE i.ownerUserId = :ownerUserId AND i.episodeId IN :episodeIds")
    List<UUID> findEpisodeIdsWithItems(@Param("ownerUserId") UUID ownerUserId, @Param("episodeIds") Collection<UUID> episodeIds);

    /**
     * 批量查询有视频条目的 seriesId 集合（避免孤立清理 N+1）。
     */
    @Query("SELECT DISTINCT i.seriesId FROM MediaVideoItem i WHERE i.ownerUserId = :ownerUserId AND i.seriesId IN :seriesIds")
    List<UUID> findSeriesIdsWithItems(@Param("ownerUserId") UUID ownerUserId, @Param("seriesIds") Collection<UUID> seriesIds);

    @Query("select count(i) from MediaVideoItem i where i.ownerUserId = :ownerUserId and i.seriesId = :seriesId and i.sourceVideoItemId is null")
    long countByOwnerUserIdAndSeriesId(@Param("ownerUserId") UUID ownerUserId, @Param("seriesId") UUID seriesId);

    /**
     * 查询某部电影的所有可用版本（个人 + 共享）。
     */
    @Query("""
            SELECT vi FROM MediaVideoItem vi
            JOIN FileNode f ON vi.fileNodeId = f.id
            WHERE vi.movieId = :movieId
            AND f.deleted = false
            AND (
                vi.ownerUserId = :userId
                OR f.spaceType = :sharedType
            )
            ORDER BY vi.resolutionHeight DESC
            """)
    List<MediaVideoItem> findVideoVersionsForMovie(@Param("movieId") UUID movieId, @Param("userId") UUID userId, @Param("sharedType") SpaceType sharedType);

    @Query("""
            select item.id as videoItemId,
                   item.fileNodeId as fileNodeId,
                   item.librarySourceId as librarySourceId,
                   coalesce(movie.title, episode.title, file.name) as title,
                   ref.availabilityStatus as availabilityStatus,
                   ref.missingSince as missingSince,
                   ref.missingConfirmations as missingConfirmations
              from MediaVideoItem item
              join FileNode file on item.fileNodeId = file.id
              join FileContentRef ref on item.fileNodeId = ref.fileNodeId
              left join MediaMovie movie on item.movieId = movie.id
              left join MediaTvEpisode episode on item.episodeId = episode.id
             where item.ownerUserId = :ownerUserId
               and item.librarySourceId is not null
               and file.deleted = false
               and ref.availabilityStatus <> 'AVAILABLE'
             order by ref.missingSince desc, item.updatedAt desc
            """)
    Page<UnavailableMediaProjection> findUnavailableLocalMedia(
            @Param("ownerUserId") UUID ownerUserId,
            Pageable pageable
    );

    @Query("""
            select item.id as videoItemId,
                   item.fileNodeId as fileNodeId,
                   item.librarySourceId as librarySourceId,
                   coalesce(movie.title, episode.title, file.name) as title,
                   ref.availabilityStatus as availabilityStatus,
                   ref.missingSince as missingSince,
                   ref.missingConfirmations as missingConfirmations
              from MediaVideoItem item
              join FileNode file on item.fileNodeId = file.id
              join FileContentRef ref on item.fileNodeId = ref.fileNodeId
              left join MediaMovie movie on item.movieId = movie.id
              left join MediaTvEpisode episode on item.episodeId = episode.id
             where item.librarySourceId in :librarySourceIds
               and file.deleted = false
               and ref.availabilityStatus <> 'AVAILABLE'
             order by ref.missingSince desc, item.updatedAt desc
            """)
    Page<UnavailableMediaProjection> findUnavailableLocalMediaByLibrarySourceIds(
            @Param("librarySourceIds") Collection<UUID> librarySourceIds,
            Pageable pageable
    );

    /** 不可用本地媒体列表投影。 */
    interface UnavailableMediaProjection {
        UUID getVideoItemId();

        UUID getFileNodeId();

        UUID getLibrarySourceId();

        String getTitle();

        String getAvailabilityStatus();

        Instant getMissingSince();

        int getMissingConfirmations();
    }
}
