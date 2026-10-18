package com.omninest.modules.video.repository;

import com.omninest.modules.video.domain.MediaSubtitleTrack;
import java.util.Collection;
import java.util.List;
import java.util.UUID;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Modifying;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

public interface MediaSubtitleTrackRepository extends JpaRepository<MediaSubtitleTrack, UUID> {
    List<MediaSubtitleTrack> findByOwnerUserIdAndVideoItemIdOrderBySortOrderAsc(UUID ownerUserId, UUID videoItemId);

    void deleteByOwnerUserIdAndVideoItemIdIn(UUID ownerUserId, Collection<UUID> videoItemIds);

    void deleteByOwnerUserIdAndFileNodeIdIn(UUID ownerUserId, Collection<UUID> fileNodeIds);

    /**
     * 按主键集合批量删除字幕轨道，使用 JPQL bulk delete 避免逐条加载。
     *
     * @param ownerUserId 所属用户 ID
     * @param ids 待删除轨道 ID 集合
     */
    @Modifying(clearAutomatically = true, flushAutomatically = true)
    @Query("delete from MediaSubtitleTrack t where t.ownerUserId = :ownerUserId and t.id in :ids")
    void deleteAllByIdIn(@Param("ownerUserId") UUID ownerUserId, @Param("ids") Collection<UUID> ids);

    /**
     * 按字幕文件节点批量查询全部字幕轨道。
     *
     * @param fileNodeIds 文件节点 ID
     * @return 字幕轨道
     */
    List<MediaSubtitleTrack> findByFileNodeIdIn(Collection<UUID> fileNodeIds);

    /**
     * 按字幕文件节点批量删除全部字幕轨道。
     *
     * @param fileNodeIds 文件节点 ID
     */
    void deleteByFileNodeIdIn(Collection<UUID> fileNodeIds);
}
