package com.omninest.modules.music.repository;

import com.omninest.modules.music.domain.MusicPlaylist;
import java.util.Collection;
import java.util.List;
import java.util.Optional;
import java.util.UUID;
import org.springframework.data.jpa.repository.JpaRepository;

public interface MusicPlaylistRepository extends JpaRepository<MusicPlaylist, UUID> {
    List<MusicPlaylist> findByOwnerUserIdOrderByUpdatedAtDesc(UUID ownerUserId);

    Optional<MusicPlaylist> findByIdAndOwnerUserId(UUID id, UUID ownerUserId);

    List<MusicPlaylist> findByOwnerUserIdAndCoverFileIdIn(UUID ownerUserId, Collection<UUID> fileIds);

    /**
     * 按封面文件批量查询全部播放列表。
     *
     * @param fileIds 文件节点 ID
     * @return 播放列表
     */
    List<MusicPlaylist> findByCoverFileIdIn(Collection<UUID> fileIds);
}
