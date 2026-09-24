package com.omninest.modules.music.service;

import com.omninest.modules.file.service.DerivedAssetStorageService;
import com.omninest.modules.music.repository.MusicAlbumRepository;
import com.omninest.modules.music.repository.MusicArtistRepository;
import com.omninest.modules.music.repository.MusicPlaylistRepository;
import com.omninest.modules.music.repository.MusicTrackRepository;
import java.util.Collection;
import java.util.HashSet;
import java.util.LinkedHashSet;
import java.util.Set;
import java.util.UUID;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * 负责回收不再被引用的音乐封面资产。
 *
 * <p>封面既不会在替换时消失，也不随曲目、专辑、歌手或歌单删除而消失：业务行删掉后，
 * 它指向的封面节点与按需派生的缩略图仍留在对象存储里，长期累积成无人引用也无入口
 * 可见的资产。回收必须保守，同一张封面可能被多行共用（例如刮削同时写曲目与专辑），
 * 只要还有任何业务行引用就整体保留。</p>
 *
 * <p>调用时机是被替换或被删除的引用已经落库之后、同一事务内：引用检查依赖持久化上下文
 * 在查询前自动刷新，因此刚改写或刚批量删除的行不会再命中旧标识。</p>
 *
 * @author OmniNest
 */
@Slf4j
@Service
@RequiredArgsConstructor
public class MusicCoverRetentionService {

    private final MusicTrackRepository trackRepository;
    private final MusicAlbumRepository albumRepository;
    private final MusicArtistRepository artistRepository;
    private final MusicPlaylistRepository playlistRepository;
    private final MusicCoverThumbnailService coverThumbnailService;
    private final DerivedAssetStorageService derivedAssetStorageService;

    /**
     * 回收单张被替换掉的封面。
     *
     * @param ownerUserId 所有者用户 ID
     * @param coverFileId 被替换掉的封面文件标识，空值不处理
     */
    @Transactional
    public void releaseUnreferenced(UUID ownerUserId, UUID coverFileId) {
        if (coverFileId == null) {
            return;
        }
        releaseUnreferenced(ownerUserId, Set.of(coverFileId));
    }

    /**
     * 回收一批封面标识：仍被任何业务行引用的跳过，其余连同各自缩略图一起删除。
     *
     * @param ownerUserId 所有者用户 ID
     * @param coverFileIds 被替换或被删除的封面文件标识集合，空值项忽略
     */
    @Transactional
    public void releaseUnreferenced(UUID ownerUserId, Collection<UUID> coverFileIds) {
        if (ownerUserId == null || coverFileIds == null || coverFileIds.isEmpty()) {
            return;
        }
        Set<UUID> candidates = new LinkedHashSet<>(coverFileIds);
        candidates.remove(null);
        if (candidates.isEmpty()) {
            return;
        }
        Set<UUID> staleFileIds = new LinkedHashSet<>();
        Set<UUID> referenced = filterReferenced(ownerUserId, candidates);
        for (UUID coverFileId : candidates) {
            if (referenced.contains(coverFileId)) {
                continue;
            }
            // 缩略图与封面本体放进同一批删除，避免中途失败留下无主的缩略图。
            coverThumbnailService.findThumbnailFileId(ownerUserId, coverFileId).ifPresent(staleFileIds::add);
            staleFileIds.add(coverFileId);
        }
        if (staleFileIds.isEmpty()) {
            return;
        }
        int deleted = derivedAssetStorageService.deleteOwnedBatch(ownerUserId, staleFileIds);
        log.info("已回收失效音乐封面资产: userId={}, candidates={}, deleted={}",
                ownerUserId, candidates.size(), deleted);
    }

    /**
     * 筛出仍被业务行引用的封面标识。
     *
     * <p>四张业务表的引用面只在这里定义一次，回收与对账共用同一判据，避免两处漂移。</p>
     *
     * @param ownerUserId 所有者用户 ID
     * @param coverFileIds 待判定的封面标识集合
     * @return 仍被曲目、专辑、歌手或歌单引用的封面标识
     */
    @Transactional(readOnly = true)
    public Set<UUID> filterReferenced(UUID ownerUserId, Collection<UUID> coverFileIds) {
        if (ownerUserId == null || coverFileIds == null || coverFileIds.isEmpty()) {
            return Set.of();
        }
        Collection<UUID> requested = new LinkedHashSet<>(coverFileIds);
        Set<UUID> referenced = new HashSet<>();
        trackRepository.findByOwnerUserIdAndCoverFileIdIn(ownerUserId, requested)
                .forEach(track -> referenced.add(track.getCoverFileId()));
        albumRepository.findByOwnerUserIdAndCoverFileIdIn(ownerUserId, requested)
                .forEach(album -> referenced.add(album.getCoverFileId()));
        playlistRepository.findByOwnerUserIdAndCoverFileIdIn(ownerUserId, requested)
                .forEach(playlist -> referenced.add(playlist.getCoverFileId()));
        artistRepository.findByOwnerUserIdAndAvatarFileIdIn(ownerUserId, requested)
                .forEach(artist -> referenced.add(artist.getAvatarFileId()));
        referenced.remove(null);
        return referenced;
    }
}
