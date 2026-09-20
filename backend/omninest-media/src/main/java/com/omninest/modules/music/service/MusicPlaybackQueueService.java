package com.omninest.modules.music.service;

import com.omninest.modules.music.dto.MusicDtos.MusicPlaybackQueueDto;
import com.omninest.modules.music.dto.MusicDtos.MusicPlaybackQueueItemDto;
import com.omninest.modules.music.dto.MusicDtos.MusicQueueSourceDto;
import com.omninest.modules.music.dto.MusicDtos.SaveMusicPlaybackQueueRequest;
import java.time.Instant;
import java.util.List;
import java.util.Set;
import java.util.UUID;
import java.util.regex.Pattern;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;

/**
 * 校验并管理用户可重建的播放队列快照。
 *
 * @author OmniNest
 */
@Service
@RequiredArgsConstructor
public class MusicPlaybackQueueService {

    private static final long MAX_QUEUE_SIZE = 100L;
    private static final Pattern LOCAL_KEY = Pattern.compile("local:[0-9a-fA-F-]{36}");
    private static final Pattern ONLINE_KEY = Pattern.compile("online:(netease|qq):[A-Za-z0-9_-]{1,128}");
    private static final Set<String> REPEAT_MODES = Set.of("off", "all", "one");
    private static final Set<String> SOURCE_KINDS = Set.of("library", "playlist", "album", "artist", "transient");

    private final MusicPlaybackQueueStore queueStore;

    /**
     * 获取用户上次保存的播放队列。
     *
     * @param ownerUserId 当前用户标识
     * @return 可重建播放队列，不存在时返回空队列
     */
    public MusicPlaybackQueueDto load(UUID ownerUserId) {
        return queueStore.find(ownerUserId)
                .map(this::normalize)
                .orElseGet(this::emptySnapshot);
    }

    /**
     * 校验并保存用户播放队列的稳定引用和展示快照。
     *
     * <p>非法播放键按 load 侧同策略软过滤（队列是可重建派生态），结构性错误仍由
     * bean validation 拒绝。
     *
     * @param ownerUserId 当前用户标识
     * @param request 队列保存请求
     * @return 已规范化的队列快照
     */
    public MusicPlaybackQueueDto save(UUID ownerUserId, SaveMusicPlaybackQueueRequest request) {
        List<MusicPlaybackQueueItemDto> items = request.items().stream()
                .filter(this::isSupportedItem)
                .limit(MAX_QUEUE_SIZE)
                .toList();
        int currentIndex = normalizeIndex(request.currentIndex(), items.size());
        MusicPlaybackQueueDto snapshot = new MusicPlaybackQueueDto(
                List.copyOf(items),
                currentIndex,
                normalizeRepeatMode(request.repeatMode()),
                request.shuffleEnabled(),
                normalizeSource(request.source()),
                Boolean.TRUE.equals(request.truncated()),
                Instant.now()
        );
        queueStore.save(ownerUserId, snapshot);
        return snapshot;
    }

    private MusicPlaybackQueueDto normalize(MusicPlaybackQueueDto snapshot) {
        if (snapshot == null || snapshot.items() == null) {
            return emptySnapshot();
        }
        List<MusicPlaybackQueueItemDto> items = snapshot.items().stream()
                .filter(this::isSupportedItem)
                .limit(MAX_QUEUE_SIZE)
                .toList();
        return new MusicPlaybackQueueDto(
                items,
                normalizeIndex(snapshot.currentIndex(), items.size()),
                normalizeRepeatMode(snapshot.repeatMode()),
                snapshot.shuffleEnabled(),
                normalizeSource(snapshot.source()),
                snapshot.truncated(),
                snapshot.updatedAt() == null ? Instant.now() : snapshot.updatedAt()
        );
    }

    private boolean isSupportedItem(MusicPlaybackQueueItemDto item) {
        if (item == null || item.playableKey() == null) {
            return false;
        }
        return LOCAL_KEY.matcher(item.playableKey()).matches()
                || ONLINE_KEY.matcher(item.playableKey()).matches();
    }

    private int normalizeIndex(Integer currentIndex, int size) {
        if (size == 0) {
            return -1;
        }
        int index = currentIndex == null ? 0 : currentIndex;
        return Math.max(0, Math.min(index, size - 1));
    }

    private String normalizeRepeatMode(String repeatMode) {
        return REPEAT_MODES.contains(repeatMode) ? repeatMode : "off";
    }

    /**
     * 规范化队列来源：非法或 transient 视为无来源；platforms 仅在 library 来源保留。
     *
     * @param source 待规范化的来源
     * @return 规范化后的来源，无有效来源时返回 null
     */
    private MusicQueueSourceDto normalizeSource(MusicQueueSourceDto source) {
        if (source == null || !SOURCE_KINDS.contains(source.kind())) {
            return null;
        }
        if ("transient".equals(source.kind())) {
            return null;
        }
        List<String> platforms = "library".equals(source.kind())
                ? source.platforms()
                : null;
        return new MusicQueueSourceDto(source.kind(), source.id(), source.title(), platforms);
    }

    private MusicPlaybackQueueDto emptySnapshot() {
        return new MusicPlaybackQueueDto(List.of(), -1, "off", false, null, false, Instant.EPOCH);
    }
}
