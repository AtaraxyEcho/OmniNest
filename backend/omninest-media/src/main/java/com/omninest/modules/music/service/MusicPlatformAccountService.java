package com.omninest.modules.music.service;

import com.omninest.common.enums.ErrorCode;
import com.omninest.common.error.BusinessException;
import com.omninest.common.sync.SyncScope;
import com.omninest.modules.media.service.MediaSyncEventService;
import java.util.Map;
import com.omninest.modules.music.dto.OnlineMusicDtos.MusicPlatformStatusDto;
import com.omninest.modules.music.dto.OnlineMusicDtos.PlatformUserInfo;
import com.omninest.modules.music.dto.OnlineMusicDtos.QrLoginSession;
import com.omninest.modules.music.dto.OnlineMusicDtos.QrLoginStatus;
import com.omninest.modules.music.service.platform.MusicPlatform;
import com.omninest.modules.music.service.platform.MusicPlatformProvider;
import com.omninest.modules.music.service.platform.NeteaseMusicProxy;
import com.omninest.modules.music.service.platform.QQMusicApi;
import java.util.Comparator;
import java.util.List;
import java.util.UUID;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;

/**
 * 编排在线音乐平台连接、登录会话和脱敏账号状态。
 *
 * @author OmniNest
 */
@Slf4j
@Service
@RequiredArgsConstructor
public class MusicPlatformAccountService {
    private final List<MusicPlatformProvider> providers;
    private final NeteaseMusicProxy neteaseMusicProxy;
    private final QQMusicApi qqMusicApi;
    private final MusicRuntimeConfigService configService;
    private final MusicPlatformLoginSessionService loginSessionService;
    private final MusicPlatformCredentialService credentialService;
    private final MediaSyncEventService mediaSyncEventService;

    /**
     * 获取当前用户的全部平台连接状态。
     *
     * @param ownerUserId 当前用户 ID
     * @return 平台状态列表
     */
    public List<MusicPlatformStatusDto> platforms(UUID ownerUserId) {
        return providers.stream()
                .sorted(Comparator.comparing(provider -> provider.platform().apiValue()))
                .map(provider -> toStatus(ownerUserId, provider))
                .toList();
    }

    /**
     * 获取当前用户在指定平台的资料。
     *
     * @param ownerUserId 当前用户 ID
     * @param platformValue 平台 API 标识
     * @return 平台用户资料
     */
    public PlatformUserInfo getUserInfo(UUID ownerUserId, String platformValue) {
        return provider(MusicPlatform.fromApiValue(platformValue)).getUserInfo(ownerUserId);
    }

    /**
     * 创建绑定当前用户的网易云二维码登录会话。
     *
     * @param ownerUserId 当前用户 ID
     * @return 二维码登录会话
     */
    public QrLoginSession createNeteaseQrLogin(UUID ownerUserId) {
        requireEnabled(MusicPlatform.NETEASE);
        QrLoginSession session = neteaseMusicProxy.createQrLogin();
        if (session == null || session.loginKey() == null || session.loginKey().isBlank()) {
            throw new BusinessException(ErrorCode.INTERNAL_ERROR, "创建网易云二维码登录会话失败");
        }
        loginSessionService.register(ownerUserId, MusicPlatform.NETEASE, session.loginKey());
        return session;
    }

    /**
     * 检查绑定当前用户的网易云二维码登录状态。
     *
     * @param ownerUserId 当前用户 ID
     * @param loginKey 平台登录会话 ID
     * @return 二维码登录状态
     */
    public QrLoginStatus checkNeteaseQrLogin(UUID ownerUserId, String loginKey) {
        requireEnabled(MusicPlatform.NETEASE);
        loginSessionService.requireOwner(ownerUserId, MusicPlatform.NETEASE, loginKey);
        QrLoginStatus status = neteaseMusicProxy.checkQrLogin(ownerUserId, loginKey);
        if ("confirmed".equals(status.status())) {
            publishPlatformChanged(ownerUserId);
        }
        if ("confirmed".equals(status.status()) || "expired".equals(status.status())) {
            loginSessionService.complete(MusicPlatform.NETEASE, loginKey);
        }
        return status;
    }

    /**
     * 保存当前用户的 QQ 音乐 Cookie。
     *
     * @param ownerUserId 当前用户 ID
     * @param cookie QQ 音乐 Cookie
     * @return 平台用户资料
     */
    public PlatformUserInfo applyQqCookie(UUID ownerUserId, String cookie) {
        requireEnabled(MusicPlatform.QQ);
        PlatformUserInfo userInfo = qqMusicApi.applyCookie(ownerUserId, cookie);
        publishPlatformChanged(ownerUserId);
        return userInfo;
    }

    /**
     * 删除当前用户的平台连接。
     *
     * @param ownerUserId 当前用户 ID
     * @param platformValue 平台 API 标识
     */
    public void disconnect(UUID ownerUserId, String platformValue) {
        MusicPlatformProvider provider = provider(MusicPlatform.fromApiValue(platformValue));
        provider.clearLogin(ownerUserId);
        publishPlatformChanged(ownerUserId);
        log.info(
                "音乐平台连接已删除: userId={}, platform={}",
                ownerUserId,
                provider.platform().apiValue()
        );
    }

    /**
     * 广播平台连接变更：同账号其他端收到 MUSIC 失效后刷新平台曲库，
     * 而非依赖各端手动刷新。
     */
    private void publishPlatformChanged(UUID ownerUserId) {
        mediaSyncEventService.invalidate(
                ownerUserId,
                SyncScope.MUSIC,
                "MUSIC_PLATFORM",
                Map.of("scope", "platform-library")
        );
    }

    private MusicPlatformStatusDto toStatus(UUID ownerUserId, MusicPlatformProvider provider) {
        MusicPlatform platform = provider.platform();
        var credential = credentialService.find(ownerUserId, platform);
        boolean connected = credential.isPresent();
        PlatformUserInfo userInfo = credential.map(value -> value.userInfo()).orElse(null);
        return new MusicPlatformStatusDto(
                platform.apiValue(),
                platform.displayName(),
                enabled(platform),
                connected,
                userInfo,
                provider.capabilities(),
                credential.map(value -> value.lastVerifiedAt()).orElse(null),
                List.of()
        );
    }

    private MusicPlatformProvider provider(MusicPlatform platform) {
        return providers.stream()
                .filter(candidate -> candidate.platform() == platform)
                .findFirst()
                .orElseThrow(() -> new BusinessException(
                        ErrorCode.NOT_FOUND,
                        "音乐平台未注册: " + platform.apiValue()
                ));
    }

    private void requireEnabled(MusicPlatform platform) {
        if (!enabled(platform)) {
            throw new BusinessException(ErrorCode.BAD_REQUEST, platform.displayName() + "平台未启用");
        }
    }

    private boolean enabled(MusicPlatform platform) {
        if (!configService.onlineEnabled()) {
            return false;
        }
        return switch (platform) {
            case NETEASE -> configService.neteaseEnabled();
            case QQ -> configService.qqMusicEnabled();
        };
    }
}
