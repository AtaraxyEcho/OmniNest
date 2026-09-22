package com.omninest.modules.music.service;

import com.omninest.common.enums.ErrorCode;
import com.omninest.common.error.BusinessException;
import com.omninest.common.sync.SyncScope;
import com.omninest.modules.media.service.MediaSyncEventService;
import com.omninest.modules.music.dto.OnlineMusicDtos.MusicPlatformStatusDto;
import com.omninest.modules.music.dto.OnlineMusicDtos.PlatformUserInfo;
import com.omninest.modules.music.dto.OnlineMusicDtos.QrLoginSession;
import com.omninest.modules.music.dto.OnlineMusicDtos.QrLoginStatus;
import com.omninest.modules.music.service.platform.MusicPlatform;
import com.omninest.modules.music.service.platform.MusicPlatformCredential;
import com.omninest.modules.music.service.platform.MusicPlatformProvider;
import com.omninest.modules.music.service.platform.NeteaseMusicProxy;
import jakarta.annotation.PostConstruct;
import java.util.Comparator;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.transaction.support.TransactionTemplate;

/**
 * 编排在线音乐平台连接、登录会话和脱敏账号状态。
 *
 * <p>同步事件记录器要求调用方处于活动事务中（{@code Propagation.MANDATORY}），
 * 因此本类所有事件广播都经 {@link TransactionTemplate} 包裹；同时 {@code @Transactional}
 * 只施加在无外部 HTTP 调用的方法上，避免把平台容器延迟传导为数据库连接占用。</p>
 *
 * @author OmniNest
 */
@Slf4j
@Service
@RequiredArgsConstructor
public class MusicPlatformAccountService {
    private final List<MusicPlatformProvider> providers;
    private final NeteaseMusicProxy neteaseMusicProxy;
    private final MusicRuntimeConfigService configService;
    private final MusicPlatformLoginSessionService loginSessionService;
    private final MusicPlatformCredentialService credentialService;
    private final MediaSyncEventService mediaSyncEventService;
    private final MusicPlatformService musicPlatformService;
    private final MusicPlaybackQueueService musicPlaybackQueueService;
    private final PlatformTransactionManager transactionManager;

    private TransactionTemplate transactionTemplate;

    /**
     * 初始化事件广播事务模板。
     *
     * <p>使用默认的 {@code PROPAGATION_REQUIRED}：已有事务（如断开连接）时并入同一事务，
     * 保证"凭据清理 + 事件落库"原子提交；无事务时（如登录成功后广播）自建短事务。
     * 这与 {@code MusicAdminService} 中逐文件独立的 {@code REQUIRES_NEW} 模板用途不同。</p>
     */
    @PostConstruct
    void initTransactionTemplate() {
        this.transactionTemplate = new TransactionTemplate(transactionManager);
    }

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
     * <p>确认成功后不再立即结束会话，而是写入确认标记并保留会话，使确认后的几分钟内
     * 对同一 key 的重复轮询仍能幂等返回 confirmed。原因：803 确认响应丢失后，前端重入
     * 轮询时平台已消费密钥并返回 800，若按 expired 处理会误报"二维码已失效"，
     * 而凭据实际已保存；此时通过确认标记回退为 confirmed 并携带已保存的账号资料。</p>
     *
     * @param ownerUserId 当前用户 ID
     * @param loginKey 平台登录会话 ID
     * @return 二维码登录状态
     */
    public QrLoginStatus checkNeteaseQrLogin(UUID ownerUserId, String loginKey) {
        requireEnabled(MusicPlatform.NETEASE);
        loginSessionService.requireOwner(ownerUserId, MusicPlatform.NETEASE, loginKey);
        if (loginSessionService.isDisconnected(ownerUserId, MusicPlatform.NETEASE)) {
            // 用户已主动断开：拒绝处理旧会话的迟到确认，避免凭据被重新写回。
            log.info("已断开平台，忽略二维码确认: userId={}", ownerUserId);
            return new QrLoginStatus("expired", null);
        }
        QrLoginStatus status = neteaseMusicProxy.checkQrLogin(ownerUserId, loginKey);
        if ("confirmed".equals(status.status())) {
            loginSessionService.markConfirmed(ownerUserId, MusicPlatform.NETEASE, loginKey);
            publishPlatformChanged(ownerUserId);
            return status;
        }
        if ("expired".equals(status.status())) {
            if (loginSessionService.wasConfirmed(MusicPlatform.NETEASE, loginKey)) {
                loginSessionService.complete(MusicPlatform.NETEASE, loginKey);
                PlatformUserInfo userInfo = credentialService
                        .find(ownerUserId, MusicPlatform.NETEASE)
                        .map(MusicPlatformCredential::userInfo)
                        .orElse(null);
                return new QrLoginStatus("confirmed", userInfo);
            }
            loginSessionService.complete(MusicPlatform.NETEASE, loginKey);
        }
        return status;
    }

    /**
     * 删除当前用户的平台连接，并清理该平台派生的本地状态。
     *
     * <p>清理范围覆盖：凭据与凭据缓存、当天的每日推荐缓存、播放队列中该平台的在线曲目、
     * 未完成登录会话的迟到确认，以及向其他端广播平台失效。凭据清理与事件落库在同一事务
     * 内提交，避免出现"凭据已删但其他端不知道"或"事件已记但凭据没删"的偏态。</p>
     *
     * @param ownerUserId 当前用户 ID
     * @param platformValue 平台 API 标识
     */
    @Transactional(rollbackFor = Exception.class)
    public void disconnect(UUID ownerUserId, String platformValue) {
        MusicPlatformProvider provider = provider(MusicPlatform.fromApiValue(platformValue));
        MusicPlatform platform = provider.platform();
        provider.clearLogin(ownerUserId);
        loginSessionService.markDisconnected(ownerUserId, platform);
        musicPlatformService.invalidateDailyRecommendations(ownerUserId, platform.apiValue());
        int removedQueueItems = musicPlaybackQueueService.removePlatformTracks(
                ownerUserId,
                platform.apiValue()
        );
        publishPlatformChanged(ownerUserId);
        log.info(
                "音乐平台连接已删除: userId={}, platform={}, removedQueueItems={}",
                ownerUserId,
                platform.apiValue(),
                removedQueueItems
        );
    }

    /**
     * 广播平台连接变更：同账号其他端收到 MUSIC 失效后刷新平台曲库，
     * 而非依赖各端手动刷新。
     *
     * <p>事件记录器要求活动事务，此处统一用事务模板包裹：断开连接路径会并入其外层事务，
     * 登录/确认路径则自建短事务。历史上该调用缺事务上下文，导致记录器抛
     * {@code IllegalTransactionStateException} 并让接口整体 500。</p>
     */
    private void publishPlatformChanged(UUID ownerUserId) {
        transactionTemplate.executeWithoutResult(status -> mediaSyncEventService.invalidate(
                ownerUserId,
                SyncScope.MUSIC,
                "MUSIC_PLATFORM",
                Map.of("scope", "platform-library")
        ));
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
        };
    }
}
