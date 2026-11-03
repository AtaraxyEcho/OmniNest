package com.omninest.modules.video.repository;

import com.omninest.modules.video.domain.MediaMovie;
import java.time.LocalDate;
import java.util.Collection;
import java.util.List;
import java.util.Optional;
import java.util.UUID;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

public interface MediaMovieRepository extends JpaRepository<MediaMovie, UUID> {
    /**
     * 按 TMDB ID 匹配电影。
     *
     * <p>{@code (owner_user_id, tmdb_id)} 没有唯一约束，重复刮削可能留下多行；单值查询
     * 必须带确定性排序，否则多行会抛 {@code IncorrectResultSizeDataAccessException}。</p>
     *
     * @param tmdbId TMDB 电影 ID
     * @param ownerUserId 所有者用户 ID
     * @return 最早创建的匹配电影
     */
    Optional<MediaMovie> findFirstByTmdbIdAndOwnerUserIdOrderByCreatedAtAsc(
            Integer tmdbId, UUID ownerUserId);

    Optional<MediaMovie> findByIdAndOwnerUserId(UUID id, UUID ownerUserId);

    /**
     * 按媒体库来源、标题与上映日期匹配电影。
     *
     * <p>同一媒体库下同名同上映日的电影没有唯一约束，单值查询必须带确定性排序。</p>
     *
     * @param ownerUserId 所有者用户 ID
     * @param librarySourceId 媒体库来源 ID
     * @param title 标题
     * @param releaseDate 上映日期
     * @return 最早创建的匹配电影
     */
    Optional<MediaMovie> findFirstByOwnerUserIdAndLibrarySourceIdAndTitleAndReleaseDateOrderByCreatedAtAsc(
            UUID ownerUserId, UUID librarySourceId, String title, LocalDate releaseDate);

    /**
     * 按媒体库来源与标题匹配上映日期为空的电影。
     *
     * @param ownerUserId 所有者用户 ID
     * @param librarySourceId 媒体库来源 ID
     * @param title 标题
     * @return 最早创建的匹配电影
     */
    Optional<MediaMovie> findFirstByOwnerUserIdAndLibrarySourceIdAndTitleAndReleaseDateIsNullOrderByCreatedAtAsc(
            UUID ownerUserId, UUID librarySourceId, String title);

    List<MediaMovie> findAllByIdInAndOwnerUserId(Collection<UUID> ids, UUID ownerUserId);

    void deleteByOwnerUserIdAndIdIn(UUID ownerUserId, Collection<UUID> ids);

    List<MediaMovie> findByOwnerUserIdAndPosterFileIdIn(UUID ownerUserId, Collection<UUID> fileIds);

    List<MediaMovie> findByOwnerUserIdAndBackdropFileIdIn(UUID ownerUserId, Collection<UUID> fileIds);

    List<MediaMovie> findByPosterFileIdIn(Collection<UUID> fileIds);

    List<MediaMovie> findByBackdropFileIdIn(Collection<UUID> fileIds);

}
