package com.omninest.modules.music.repository;

import com.omninest.modules.music.domain.MusicArtist;
import java.util.Collection;
import java.util.List;
import java.util.Optional;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import java.util.UUID;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

public interface MusicArtistRepository extends JpaRepository<MusicArtist, UUID> {
    List<MusicArtist> findByOwnerUserIdOrderByNameAsc(UUID ownerUserId);

    /**
     * 查询至少包含一个活动曲目的艺术家。
     *
     * @param ownerUserId 所有者用户 ID
     * @return 活动艺术家
     */
    @Query("""
            select distinct artist from MusicArtist artist
            join MusicTrack track on track.artistId = artist.id
            join FileNode file on track.fileNodeId = file.id
            where artist.ownerUserId = :ownerUserId and file.deleted = false
            """)
    Page<MusicArtist> findActiveByOwnerUserId(
            @Param("ownerUserId") UUID ownerUserId,
            Pageable pageable);

    Optional<MusicArtist> findByIdAndOwnerUserId(UUID id, UUID ownerUserId);

    Optional<MusicArtist> findByOwnerUserIdAndNameIgnoreCase(UUID ownerUserId, String name);

    @Query(value = """
            select id, owner_user_id, name, avatar_file_id, bio, track_count,
                   album_count, external_ids, provider_metadata, created_at, updated_at, version
            from omni.music_artists
            where owner_user_id = :ownerUserId
              and external_ids ->> 'musicbrainzArtistId' = :musicBrainzArtistId
            limit 1
            """, nativeQuery = true)
    Optional<MusicArtist> findByOwnerUserIdAndMusicBrainzArtistId(
            @Param("ownerUserId") UUID ownerUserId,
            @Param("musicBrainzArtistId") String musicBrainzArtistId
    );

    List<MusicArtist> findTop12ByOwnerUserIdOrderByTrackCountDescUpdatedAtDesc(UUID ownerUserId);

    /**
     * 查询近期活动艺术家。
     *
     * @param ownerUserId 所有者用户 ID
     * @return 最多十二个活动艺术家
     */
    @Query("""
            select distinct artist from MusicArtist artist
            join MusicTrack track on track.artistId = artist.id
            join FileNode file on track.fileNodeId = file.id
            where artist.ownerUserId = :ownerUserId and file.deleted = false
            order by artist.trackCount desc, artist.updatedAt desc
            limit 12
            """)
    List<MusicArtist> findTop12ActiveByOwnerUserId(@Param("ownerUserId") UUID ownerUserId);

    List<MusicArtist> findTop10ByOwnerUserIdAndNameContainingIgnoreCaseOrderByNameAsc(UUID ownerUserId, String keyword);

    /**
     * 搜索至少包含一个活动曲目的艺术家。
     *
     * @param ownerUserId 所有者用户 ID
     * @param keyword 名称关键词
     * @return 最多十个活动艺术家
     */
    @Query("""
            select distinct artist from MusicArtist artist
            join MusicTrack track on track.artistId = artist.id
            join FileNode file on track.fileNodeId = file.id
            where artist.ownerUserId = :ownerUserId
              and file.deleted = false
              and lower(artist.name) like lower(concat('%', :keyword, '%'))
            order by artist.name asc
            limit 10
            """)
    List<MusicArtist> searchActiveByOwnerUserId(
            @Param("ownerUserId") UUID ownerUserId,
            @Param("keyword") String keyword
    );

    long countByOwnerUserId(UUID ownerUserId);

    /**
     * 统计至少包含一个活动曲目的艺术家。
     *
     * @param ownerUserId 所有者用户 ID
     * @return 活动艺术家数量
     */
    @Query("""
            select count(distinct artist.id) from MusicArtist artist
            join MusicTrack track on track.artistId = artist.id
            join FileNode file on track.fileNodeId = file.id
            where artist.ownerUserId = :ownerUserId and file.deleted = false
            """)
    long countActiveByOwnerUserId(@Param("ownerUserId") UUID ownerUserId);

    List<MusicArtist> findAllByIdInAndOwnerUserId(Collection<UUID> ids, UUID ownerUserId);

    void deleteByOwnerUserIdAndIdIn(UUID ownerUserId, Collection<UUID> ids);

    List<MusicArtist> findByOwnerUserIdAndAvatarFileIdIn(UUID ownerUserId, Collection<UUID> fileIds);

    /**
     * 按头像文件批量查询全部艺术家。
     *
     * @param fileIds 文件节点 ID
     * @return 艺术家
     */
    List<MusicArtist> findByAvatarFileIdIn(Collection<UUID> fileIds);
}
