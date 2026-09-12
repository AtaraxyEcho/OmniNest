package com.omninest.modules.music.repository;

import com.omninest.modules.music.domain.MusicAlbum;
import java.util.Collection;
import java.util.List;
import java.util.Optional;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import java.util.UUID;
import org.springframework.data.jpa.repository.JpaRepository;
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

    Optional<MusicAlbum> findByIdAndOwnerUserId(UUID id, UUID ownerUserId);

    Optional<MusicAlbum> findByOwnerUserIdAndTitleIgnoreCase(UUID ownerUserId, String title);

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
              and lower(album.title) like lower(concat('%', :keyword, '%'))
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
