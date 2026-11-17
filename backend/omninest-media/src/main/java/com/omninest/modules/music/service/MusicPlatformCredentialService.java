package com.omninest.modules.music.service;

import com.omninest.common.cache.ReadThroughCache;
import com.omninest.modules.integration.service.IntegrationAccountData;
import com.omninest.modules.integration.service.IntegrationAccountService;
import com.omninest.modules.music.dto.OnlineMusicDtos.PlatformUserInfo;
import com.omninest.modules.music.service.platform.MusicPlatform;
import com.omninest.modules.music.service.platform.MusicPlatformCredential;
import java.time.Duration;
import java.util.Map;
import java.util.Optional;
import java.util.UUID;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;

/**
 * 管理音乐平台用户凭据的加密持久化和 Redis 短期缓存。
 *
 * @author OmniNest
 */
@Slf4j
@Service
@RequiredArgsConstructor
public class MusicPlatformCredentialService {
    private static final String INTEGRATION_TYPE = "MUSIC";
    private static final String COOKIE_KEY = "cookie";
    private static final String VIP_KEY = "vip";
    private static final Duration CACHE_TTL = Duration.ofMinutes(15);
    private static final String CACHE_PREFIX = "omninest:integration:music:";

    private final IntegrationAccountService integrationAccountService;
    private final ReadThroughCache readThroughCache;

    /**
     * 查询用户的平台凭据。
     *
     * @param ownerUserId 所属用户 ID
     * @param platform 平台
     * @return 用户级凭据
     */
    public Optional<MusicPlatformCredential> find(UUID ownerUserId, MusicPlatform platform) {
        String cacheKey = cacheKey(ownerUserId, platform);
        MusicPlatformCredential credential = readThroughCache.getOrLoad(
                cacheKey,
                CACHE_TTL,
                () -> integrationAccountService
                        .find(ownerUserId, INTEGRATION_TYPE, platform.apiValue())
                        .map(data -> toCredential(platform, data))
                        .orElse(null),
                MusicPlatformCredential.class
        );
        return Optional.ofNullable(credential);
    }

    /**
     * 保存用户的平台凭据。
     *
     * @param ownerUserId 所属用户 ID
     * @param platform 平台
     * @param cookie 平台 Cookie
     * @param userInfo 平台用户信息
     */
    public void save(
            UUID ownerUserId,
            MusicPlatform platform,
            String cookie,
            PlatformUserInfo userInfo
    ) {
        IntegrationAccountData account = integrationAccountService.save(
                ownerUserId,
                INTEGRATION_TYPE,
                platform.apiValue(),
                userInfo.userId(),
                userInfo.nickname(),
                userInfo.avatarUrl(),
                Map.of(
                        COOKIE_KEY, cookie,
                        VIP_KEY, Boolean.toString(userInfo.vip())
                )
        );
        MusicPlatformCredential credential = new MusicPlatformCredential(
                cookie,
                userInfo.userId(),
                userInfo,
                account.lastVerifiedAt()
        );
        cache(cacheKey(ownerUserId, platform), credential);
        evictLibrary(ownerUserId, platform);
    }

    /**
     * 清除用户的平台连接。
     *
     * @param ownerUserId 所属用户 ID
     * @param platform 平台
     */
    public void clear(UUID ownerUserId, MusicPlatform platform) {
        integrationAccountService.delete(ownerUserId, INTEGRATION_TYPE, platform.apiValue());
        invalidate(cacheKey(ownerUserId, platform), ownerUserId, platform);
        evictLibrary(ownerUserId, platform);
    }

    /**
     * 凭据换绑或解绑后清理该用户在当前平台的只读回源缓存：歌单、歌单曲目、喜欢列表和
     * 当日推荐都按用户归属，不清会让新账号在 TTL 内看到上一账号的内容。
     */
    private void evictLibrary(UUID ownerUserId, MusicPlatform platform) {
        try {
            MusicPlatformLibraryCache.evict(readThroughCache, ownerUserId, platform);
        } catch (RuntimeException exception) {
            log.warn(
                    "清理音乐平台账号内容缓存失败: userId={}, platform={}",
                    ownerUserId,
                    platform.apiValue()
            );
        }
    }

    private void cache(String cacheKey, MusicPlatformCredential credential) {
        try {
            readThroughCache.invalidate(cacheKey);
            readThroughCache.getOrLoad(
                    cacheKey,
                    CACHE_TTL,
                    () -> credential,
                    MusicPlatformCredential.class
            );
        } catch (RuntimeException exception) {
            log.warn("刷新音乐平台凭据缓存失败: key={}", cacheKey);
        }
    }

    private MusicPlatformCredential toCredential(MusicPlatform platform, IntegrationAccountData data) {
        PlatformUserInfo userInfo = new PlatformUserInfo(
                platform.apiValue(),
                valueOrEmpty(data.externalUserId()),
                valueOrEmpty(data.displayName()),
                valueOrEmpty(data.avatarUrl()),
                Boolean.parseBoolean(data.credentials().getOrDefault(VIP_KEY, "false"))
        );
        return new MusicPlatformCredential(
                data.credentials().getOrDefault(COOKIE_KEY, ""),
                valueOrEmpty(data.externalUserId()),
                userInfo,
                data.lastVerifiedAt()
        );
    }

    private void invalidate(String cacheKey, UUID ownerUserId, MusicPlatform platform) {
        try {
            readThroughCache.invalidate(cacheKey);
        } catch (RuntimeException exception) {
            log.warn("清理音乐平台凭据缓存失败: userId={}, platform={}", ownerUserId, platform.apiValue());
        }
    }

    private String cacheKey(UUID ownerUserId, MusicPlatform platform) {
        return CACHE_PREFIX + ownerUserId + ":" + platform.apiValue() + ":account";
    }

    private String valueOrEmpty(String value) {
        return value == null ? "" : value;
    }
}
