package com.omninest.modules.media.service;

import com.github.benmanes.caffeine.cache.Cache;
import com.github.benmanes.caffeine.cache.Caffeine;
import com.github.benmanes.caffeine.cache.Expiry;
import com.omninest.modules.file.port.MediaCoverDirectory;
import java.time.Duration;
import java.util.ArrayList;
import java.util.Collection;
import java.util.HashMap;
import java.util.HashSet;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.Set;
import java.util.UUID;
import java.util.concurrent.TimeUnit;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * 媒体封面反查端口的 media 模块实现。
 *
 * <p>聚合 music / video / reader 三域的 {@link MediaCoverContributor}，
 * 自身只负责差异化 TTL 缓存：正结果 10 分钟、负结果 60 秒——媒体入库前的
 * "无封面"不被长期缓存，导入完成约一分钟后列表即可解析到新封面。</p>
 *
 * @author OmniNest
 */
@Service
@RequiredArgsConstructor
public class MediaCoverDirectoryImpl implements MediaCoverDirectory {

    private static final Duration POSITIVE_TTL = Duration.ofMinutes(10);
    private static final Duration NEGATIVE_TTL = Duration.ofSeconds(60);

    private final List<MediaCoverContributor> contributors;

    private final Cache<UUID, Optional<UUID>> cache = Caffeine.newBuilder()
            .maximumSize(10_000)
            .expireAfter(new CoverExpiry())
            .build();

    @Override
    @Transactional(readOnly = true)
    public Map<UUID, UUID> resolveCoverFileIds(UUID ownerUserId, Collection<UUID> fileNodeIds) {
        if (ownerUserId == null || fileNodeIds == null || fileNodeIds.isEmpty()) {
            return Map.of();
        }
        Map<UUID, UUID> result = new HashMap<>();
        List<UUID> misses = new ArrayList<>();
        Set<UUID> distinct = new HashSet<>(fileNodeIds);
        for (UUID fileId : distinct) {
            Optional<UUID> cached = cache.getIfPresent(fileId);
            if (cached == null) {
                misses.add(fileId);
            } else {
                cached.ifPresent(coverId -> result.put(fileId, coverId));
            }
        }
        if (misses.isEmpty()) {
            return result;
        }
        Map<UUID, UUID> resolved = resolveUncached(ownerUserId, misses);
        for (UUID fileId : misses) {
            UUID coverId = resolved.get(fileId);
            cache.put(fileId, Optional.ofNullable(coverId));
            if (coverId != null) {
                result.put(fileId, coverId);
            }
        }
        return result;
    }

    /** 无缓存批量解析：各域贡献者依次写入，域间源文件不相交。 */
    private Map<UUID, UUID> resolveUncached(UUID ownerUserId, List<UUID> fileNodeIds) {
        Map<UUID, UUID> covers = new HashMap<>();
        for (MediaCoverContributor contributor : contributors) {
            contributor.contribute(ownerUserId, fileNodeIds, covers);
        }
        return covers;
    }

    /** 差异化过期：有封面长缓存，无封面短缓存。 */
    private static final class CoverExpiry implements Expiry<UUID, Optional<UUID>> {
        @Override
        public long expireAfterCreate(UUID key, Optional<UUID> value, long currentTime) {
            return after(value, currentTime);
        }

        @Override
        public long expireAfterUpdate(UUID key, Optional<UUID> value, long currentTime, long currentDuration) {
            return after(value, currentTime);
        }

        @Override
        public long expireAfterRead(UUID key, Optional<UUID> value, long currentTime, long currentDuration) {
            return currentDuration;
        }

        private long after(Optional<UUID> value, long currentTime) {
            Duration ttl = value.isPresent() ? POSITIVE_TTL : NEGATIVE_TTL;
            return TimeUnit.NANOSECONDS.convert(ttl.toNanos(), TimeUnit.NANOSECONDS);
        }
    }
}
