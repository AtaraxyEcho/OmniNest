package com.omninest.modules.music.repository;

import com.omninest.modules.file.domain.SpaceType;
import com.omninest.modules.music.domain.MusicTrack;
import java.util.Collection;
import java.util.List;
import java.util.Optional;
import java.util.UUID;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

/**
 * 音乐曲目仓储。
 *
 * @author OmniNest
 */
public interface MusicTrackRepository extends JpaRepository<MusicTrack, UUID> {
    @Query("""
            select track from MusicTrack track
            join FileNode file on track.fileNodeId = file.id
            where track.ownerUserId = :ownerUserId and file.deleted = false
            order by track.updatedAt desc
            """)
    List<MusicTrack> findByOwnerUserIdOrderByUpdatedAtDesc(@Param("ownerUserId") UUID ownerUserId);

    @Query("""
            select count(track) from MusicTrack track
            join FileNode file on track.fileNodeId = file.id
            where track.ownerUserId = :ownerUserId and file.deleted = false
            """)
    long countVisibleByOwnerUserId(@Param("ownerUserId") UUID ownerUserId);

    @Query("""
            select track from MusicTrack track
            join FileNode file on track.fileNodeId = file.id
            where track.ownerUserId = :ownerUserId
              and file.deleted = false
              and track.id > :afterId
            order by track.id
            """)
    List<MusicTrack> findScrapePageAfter(
            @Param("ownerUserId") UUID ownerUserId,
            @Param("afterId") UUID afterId,
            Pageable pageable);

    @Query("""
            select track from MusicTrack track
            join FileNode file on track.fileNodeId = file.id
            where track.ownerUserId = :ownerUserId and file.deleted = false
            order by track.updatedAt desc
            limit 12
            """)
    List<MusicTrack> findTop12ByOwnerUserIdOrderByUpdatedAtDesc(@Param("ownerUserId") UUID ownerUserId);

    @Query("""
            select track from MusicTrack track
            join FileNode file on track.fileNodeId = file.id
            where track.id = :id and track.ownerUserId = :ownerUserId and file.deleted = false
            """)
    Optional<MusicTrack> findByIdAndOwnerUserId(
            @Param("id") UUID id,
            @Param("ownerUserId") UUID ownerUserId
    );

    Optional<MusicTrack> findByOwnerUserIdAndFileNodeId(UUID ownerUserId, UUID fileNodeId);

    List<MusicTrack> findByOwnerUserIdAndFileNodeIdIn(UUID ownerUserId, Collection<UUID> fileNodeIds);

    /**
     * 按 fileNodeId 查询所有音乐条目（不限 ownerUserId，共享空间清理用）。
     */
    List<MusicTrack> findByFileNodeIdIn(Collection<UUID> fileNodeIds);

    @Query("""
            select track from MusicTrack track
            join FileNode file on track.fileNodeId = file.id
            where track.ownerUserId = :ownerUserId and track.id in :ids and file.deleted = false
            """)
    List<MusicTrack> findByOwnerUserIdAndIdIn(
            @Param("ownerUserId") UUID ownerUserId,
            @Param("ids") List<UUID> ids
    );

    /**
     * 按歌名、歌手或专辑搜索用户曲目。
     *
     * @param ownerUserId 所属用户 ID
     * @param keyword 搜索关键词
     * @param pageable 分页限制
     * @return 匹配曲目
     */
    @Query("""
            select t from MusicTrack t
            join FileNode file on t.fileNodeId = file.id
            where t.ownerUserId = :ownerUserId
              and file.deleted = false
              and (
                lower(coalesce(t.title, '')) like lower(concat('%', :keyword, '%'))
                or lower(coalesce(t.artistName, '')) like lower(concat('%', :keyword, '%'))
                or lower(coalesce(t.albumTitle, '')) like lower(concat('%', :keyword, '%'))
              )
            order by t.updatedAt desc
            """)
    List<MusicTrack> searchByOwnerUserId(
            @Param("ownerUserId") UUID ownerUserId,
            @Param("keyword") String keyword,
            Pageable pageable
    );

    @Query("""
            select count(track) from MusicTrack track
            join FileNode file on track.fileNodeId = file.id
            where track.ownerUserId = :ownerUserId and file.deleted = false
            """)
    long countByOwnerUserId(@Param("ownerUserId") UUID ownerUserId);

    long countByOwnerUserIdAndAlbumId(UUID ownerUserId, UUID albumId);

    long countByOwnerUserIdAndArtistId(UUID ownerUserId, UUID artistId);

    /**
     * 批量查询有曲目的 albumId 集合（避免孤立清理 N+1）。
     */
    @Query("SELECT DISTINCT t.albumId FROM MusicTrack t WHERE t.ownerUserId = :ownerUserId AND t.albumId IN :albumIds")
    List<UUID> findAlbumIdsWithTracks(@Param("ownerUserId") UUID ownerUserId, @Param("albumIds") Collection<UUID> albumIds);

    /**
     * 批量查询有曲目的 artistId 集合（避免孤立清理 N+1）。
     */
    @Query("SELECT DISTINCT t.artistId FROM MusicTrack t WHERE t.ownerUserId = :ownerUserId AND t.artistId IN :artistIds")
    List<UUID> findArtistIdsWithTracks(@Param("ownerUserId") UUID ownerUserId, @Param("artistIds") Collection<UUID> artistIds);

    List<MusicTrack> findByOwnerUserIdAndCoverFileIdIn(UUID ownerUserId, Collection<UUID> coverFileIds);

    /**
     * 按封面文件批量查询全部曲目。
     *
     * @param coverFileIds 文件节点 ID
     * @return 曲目
     */
    List<MusicTrack> findByCoverFileIdIn(Collection<UUID> coverFileIds);

    long countByOwnerUserIdAndAlbumIdAndIdNotIn(
            UUID ownerUserId,
            UUID albumId,
            Collection<UUID> excludedTrackIds
    );

    long countByOwnerUserIdAndArtistIdAndIdNotIn(
            UUID ownerUserId,
            UUID artistId,
            Collection<UUID> excludedTrackIds
    );

    @Query("""
            select coalesce(sum(t.durationSeconds), 0)
            from MusicTrack t
            where t.ownerUserId = :ownerUserId and t.albumId = :albumId
            """)
    long sumDurationSecondsByOwnerUserIdAndAlbumId(@Param("ownerUserId") UUID ownerUserId, @Param("albumId") UUID albumId);

    @Query("""
            select count(distinct t.albumId)
            from MusicTrack t
            where t.ownerUserId = :ownerUserId and t.artistId = :artistId and t.albumId is not null
            """)
    long countDistinctAlbumIdsByOwnerUserIdAndArtistId(@Param("ownerUserId") UUID ownerUserId, @Param("artistId") UUID artistId);

    /**
     * 分页查询用户可见的所有音乐（个人 + 共享合并），排序由调用方白名单约束。
     */
    @Query("""
            SELECT DISTINCT t FROM MusicTrack t
            JOIN FileNode f ON t.fileNodeId = f.id
            WHERE f.deleted = false
            AND (
                t.ownerUserId = :userId
                OR f.spaceType = :sharedType
            )
            """)
    Page<MusicTrack> findTracksVisibleToUser(
            @Param("userId") UUID userId,
            @Param("sharedType") SpaceType sharedType,
            Pageable pageable);
}
