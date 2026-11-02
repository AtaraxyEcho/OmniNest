package com.omninest.modules.music.repository;

import com.omninest.modules.file.domain.SpaceType;
import com.omninest.modules.music.domain.MusicAlbum;
import java.util.Collection;
import java.util.List;
import java.util.Optional;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import java.util.UUID;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Modifying;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

public interface MusicAlbumRepository extends JpaRepository<MusicAlbum, UUID> {
    List<MusicAlbum> findByOwnerUserIdOrderByUpdatedAtDesc(UUID ownerUserId);

    /**
     * 查询至少包含一个活动曲目的专辑。
     *
     * @param ownerUserId 所有者用户 ID
     * @return 活动专辑
     */
    @Query("""
            select distinct album from MusicAlbum album
            join MusicTrack track on track.albumId = album.id
            join FileNode file on track.fileNodeId = file.id
            where album.ownerUserId = :ownerUserId and file.deleted = false
            """)
    Page<MusicAlbum> findActiveByOwnerUserId(
            @Param("ownerUserId") UUID ownerUserId,
            Pageable pageable);

    /**
     * 查询指定艺术家下至少包含一个活动曲目的专辑。
     *
     * @param ownerUserId 所有者用户 ID
     * @param artistId 艺术家 ID
     * @return 活动专辑，按更新时间倒序
     */
    @Query("""
            select distinct album from MusicAlbum album
            join MusicTrack track on track.albumId = album.id
            join FileNode file on track.fileNodeId = file.id
            where album.ownerUserId = :ownerUserId and track.artistId = :artistId
            and file.deleted = false
            order by album.updatedAt desc
            """)
    List<MusicAlbum> findActiveByOwnerUserIdAndArtistId(
            @Param("ownerUserId") UUID ownerUserId,
            @Param("artistId") UUID artistId);

    /**
     * 查询当前用户可见的活动专辑：本人名下，或含本人可见共享空间曲目。
     */
    @Query("""
            select distinct album from MusicAlbum album
            join MusicTrack track on track.albumId = album.id
            join FileNode file on track.fileNodeId = file.id
            where file.deleted = false
              and (album.ownerUserId = :userId
                   or (:sharedType is not null and file.spaceType = :sharedType))
            """)
    Page<MusicAlbum> findVisibleActiveAlbums(
            @Param("userId") UUID userId,
            @Param("sharedType") SpaceType sharedType,
            Pageable pageable);

    /**
     * 搜索当前用户可见的活动专辑。
     */
    @Query("""
            select distinct album from MusicAlbum album
            join MusicTrack track on track.albumId = album.id
            join FileNode file on track.fileNodeId = file.id
            where file.deleted = false
              and (album.ownerUserId = :userId
                   or (:sharedType is not null and file.spaceType = :sharedType))
              and lower(album.title) like lower(concat('%', :keyword, '%')) escape '\\'
            order by album.updatedAt desc
            limit 10
            """)
    List<MusicAlbum> searchVisibleActiveAlbums(
            @Param("userId") UUID userId,
            @Param("sharedType") SpaceType sharedType,
            @Param("keyword") String keyword);

    /**
     * 查询指定歌手下用户可见的活动专辑。
     */
    @Query("""
            select distinct album from MusicAlbum album
            join MusicTrack track on track.albumId = album.id
            join FileNode file on track.fileNodeId = file.id
            where file.deleted = false and track.artistId = :artistId
              and (album.ownerUserId = :userId
                   or (:sharedType is not null and file.spaceType = :sharedType))
            order by album.updatedAt desc
            """)
    List<MusicAlbum> findVisibleActiveAlbumsByArtist(
            @Param("userId") UUID userId,
            @Param("sharedType") SpaceType sharedType,
            @Param("artistId") UUID artistId);

    Optional<MusicAlbum> findByIdAndOwnerUserId(UUID id, UUID ownerUserId);

    Optional<MusicAlbum> findByOwnerUserIdAndTitleIgnoreCase(UUID ownerUserId, String title);

    /**
     * 按标题与艺术家精确匹配同名专辑，避免不同歌手的同名专辑被合并。
     *
     * @param ownerUserId 所有者用户 ID
     * @param title 专辑标题
     * @param artistName 专辑艺术家
     * @return 匹配到的专辑
     */
    Optional<MusicAlbum> findFirstByOwnerUserIdAndTitleIgnoreCaseAndArtistNameIgnoreCase(
            UUID ownerUserId, String title, String artistName);

    /**
     * 无艺术家信息时仅匹配没有艺术家快照的同名专辑。
     *
     * @param ownerUserId 所有者用户 ID
     * @param title 专辑标题
     * @return 匹配到的专辑
     */
    Optional<MusicAlbum> findFirstByOwnerUserIdAndTitleIgnoreCaseAndArtistNameIsNull(
            UUID ownerUserId, String title);

    /**
     * 批量重算专辑曲目数与总时长，单条 SQL 覆盖一组专辑。
     *
     * @param ownerUserId 所有者用户 ID
     * @param albumIds 专辑 ID 集合
     * @return 更新的行数
     */
    @Modifying(flushAutomatically = true)
    @Query(value = """
            UPDATE omni.music_albums album
            SET track_count = (
                    SELECT COUNT(*)::int FROM omni.music_tracks track
                    WHERE track.owner_user_id = :ownerUserId AND track.album_id = album.id),
                total_duration = COALESCE((
                    SELECT SUM(track.duration_seconds) FROM omni.music_tracks track
                    WHERE track.owner_user_id = :ownerUserId AND track.album_id = album.id), 0)::int,
                updated_at = now()
            WHERE album.owner_user_id = :ownerUserId
              AND album.id IN (:albumIds)
            """, nativeQuery = true)
    int refreshStatisticsBatch(
            @Param("ownerUserId") UUID ownerUserId,
            @Param("albumIds") Collection<UUID> albumIds);

    @Query(value = """
            select id, owner_user_id, title, artist_name, cover_file_id, release_date,
                   total_duration, track_count, external_ids, provider_metadata,
                   created_at, updated_at, version
            from omni.music_albums
            where owner_user_id = :ownerUserId
              and external_ids ->> 'musicbrainzReleaseId' = :musicBrainzReleaseId
            limit 1
            """, nativeQuery = true)
    Optional<MusicAlbum> findByOwnerUserIdAndMusicBrainzReleaseId(
            @Param("ownerUserId") UUID ownerUserId,
            @Param("musicBrainzReleaseId") String musicBrainzReleaseId
    );

    @Query(value = """
            select id, owner_user_id, title, artist_name, cover_file_id, release_date,
                   total_duration, track_count, external_ids, provider_metadata,
                   created_at, updated_at, version
            from omni.music_albums
            where owner_user_id = :ownerUserId
              and external_ids ->> 'musicbrainzReleaseGroupId' = :musicBrainzReleaseGroupId
            limit 1
            """, nativeQuery = true)
    Optional<MusicAlbum> findByOwnerUserIdAndMusicBrainzReleaseGroupId(
            @Param("ownerUserId") UUID ownerUserId,
            @Param("musicBrainzReleaseGroupId") String musicBrainzReleaseGroupId
    );

    List<MusicAlbum> findTop12ByOwnerUserIdOrderByReleaseDateDescUpdatedAtDesc(UUID ownerUserId);

    /**
     * 查询近期活动专辑。
     *
     * @param ownerUserId 所有者用户 ID
     * @return 最多十二个活动专辑
     */
    @Query("""
            select distinct album from MusicAlbum album
            join MusicTrack track on track.albumId = album.id
            join FileNode file on track.fileNodeId = file.id
            where album.ownerUserId = :ownerUserId and file.deleted = false
            order by album.releaseDate desc, album.updatedAt desc
            limit 12
            """)
    List<MusicAlbum> findTop12ActiveByOwnerUserId(@Param("ownerUserId") UUID ownerUserId);

    List<MusicAlbum> findTop10ByOwnerUserIdAndTitleContainingIgnoreCaseOrderByUpdatedAtDesc(UUID ownerUserId, String keyword);

    /**
     * 搜索至少包含一个活动曲目的专辑。
     *
     * @param ownerUserId 所有者用户 ID
     * @param keyword 标题关键词
     * @return 最多十个活动专辑
     */
    @Query("""
            select distinct album from MusicAlbum album
            join MusicTrack track on track.albumId = album.id
            join FileNode file on track.fileNodeId = file.id
            where album.ownerUserId = :ownerUserId
              and file.deleted = false
              and lower(album.title) like lower(concat('%', :keyword, '%')) escape '\\'
            order by album.updatedAt desc
            limit 10
            """)
    List<MusicAlbum> searchActiveByOwnerUserId(
            @Param("ownerUserId") UUID ownerUserId,
            @Param("keyword") String keyword
    );

    long countByOwnerUserId(UUID ownerUserId);

    /**
     * 统计至少包含一个活动曲目的专辑。
     *
     * @param ownerUserId 所有者用户 ID
     * @return 活动专辑数量
     */
    @Query("""
            select count(distinct album.id) from MusicAlbum album
            join MusicTrack track on track.albumId = album.id
            join FileNode file on track.fileNodeId = file.id
            where album.ownerUserId = :ownerUserId and file.deleted = false
            """)
    long countActiveByOwnerUserId(@Param("ownerUserId") UUID ownerUserId);

    List<MusicAlbum> findAllByIdInAndOwnerUserId(Collection<UUID> ids, UUID ownerUserId);

    void deleteByOwnerUserIdAndIdIn(UUID ownerUserId, Collection<UUID> ids);

    List<MusicAlbum> findByOwnerUserIdAndCoverFileIdIn(UUID ownerUserId, Collection<UUID> fileIds);

    /**
     * 按封面文件批量查询全部专辑。
     *
     * @param fileIds 文件节点 ID
     * @return 专辑
     */
    List<MusicAlbum> findByCoverFileIdIn(Collection<UUID> fileIds);
}
