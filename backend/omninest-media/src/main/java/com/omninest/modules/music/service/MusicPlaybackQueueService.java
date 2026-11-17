package com.omninest.modules.music.service;

import com.omninest.modules.music.dto.MusicDtos.MusicPlaybackQueueDto;
import com.omninest.modules.music.dto.MusicDtos.MusicPlaybackQueueItemDto;
import com.omninest.modules.music.dto.MusicDtos.MusicQueueSourceDto;
import com.omninest.modules.music.dto.MusicDtos.SaveMusicPlaybackQueueRequest;
import java.time.Instant;
import java.util.ArrayList;
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

    /**
     * 剔除队列中属于指定平台的在线曲目，并回存。
     *
     * <p>用于平台账号断开后清理队列：队列条目没有独立的平台字段，平台信息由
     * {@code playableKey} 的 {@code online:{platform}:{songId}} 前缀承载，因此按前缀判定。
     * 若被剔除的条目原本是当前播放项，则把当前项置为 -1（无当前曲）；库来源的
     * {@code platforms} 清单同步摘除该平台，避免来源标签仍指向已断开平台。</p>
     *
     * @param ownerUserId 当前用户标识
     * @param platformValue 平台 API 标识
     * @return 实际剔除的条目数，队列无变化时返回 0 且不写库
     */
    public int removePlatformTracks(UUID ownerUserId, String platformValue) {
        if (platformValue == null || platformValue.isBlank()) {
            return 0;
        }
        MusicPlaybackQueueDto current = load(ownerUserId);
        if (current.items().isEmpty()) {
            return 0;
        }
        String prefix = "online:" + platformValue + ":";
        List<MusicPlaybackQueueItemDto> remaining = new ArrayList<>(current.items().size());
        int currentIndex = current.currentIndex();
        int removed = 0;
        int removedBeforeCurrent = 0;
        boolean currentRemoved = false;
        for (int index = 0; index < current.items().size(); index++) {
            MusicPlaybackQueueItemDto item = current.items().get(index);
            if (item.playableKey().startsWith(prefix)) {
                removed++;
                if (index < currentIndex) {
                    removedBeforeCurrent++;
                } else if (index == currentIndex) {
                    currentRemoved = true;
                }
                continue;
            }
            remaining.add(item);
        }
        if (removed == 0) {
            return 0;
        }
        queueStore.save(ownerUserId, new MusicPlaybackQueueDto(
                List.copyOf(remaining),
                shiftedIndex(currentIndex, removedBeforeCurrent, currentRemoved, remaining.size()),
                current.repeatMode(),
                current.shuffleEnabled(),
                stripPlatform(current.source(), platformValue),
                current.truncated(),
                Instant.now()
        ));
        return removed;
    }

    /**
     * 计算剔除后的当前项下标：当前项被剔除时返回 -1，其前的条目被剔除时整体前移。
     */
    private int shiftedIndex(
            int currentIndex,
            int removedBeforeCurrent,
            boolean currentRemoved,
            int remainingSize
    ) {
        if (currentIndex < 0 || currentRemoved) {
            return -1;
        }
        int shifted = currentIndex - removedBeforeCurrent;
        if (shifted >= remainingSize) {
            return remainingSize == 0 ? -1 : remainingSize - 1;
        }
        return shifted;
    }

    /**
     * 从库来源的 {@code platforms} 清单中摘除指定平台。
     */
    private MusicQueueSourceDto stripPlatform(MusicQueueSourceDto source, String platformValue) {
        if (source == null || source.platforms() == null) {
            return source;
        }
        List<String> platforms = source.platforms().stream()
                .filter(platform -> !platformValue.equals(platform))
                .toList();
        if (platforms.size() == source.platforms().size()) {
            return source;
        }
        return new MusicQueueSourceDto(source.kind(), source.id(), source.title(), platforms);
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
