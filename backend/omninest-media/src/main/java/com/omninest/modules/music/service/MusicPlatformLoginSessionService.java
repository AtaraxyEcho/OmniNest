package com.omninest.modules.music.service;

import com.omninest.common.enums.ErrorCode;
import com.omninest.common.error.BusinessException;
import com.omninest.common.security.ExpiringOwnershipRegistry;
import com.omninest.modules.music.service.platform.MusicPlatform;
import java.time.Duration;
import java.util.UUID;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;

/**
 * 管理绑定用户的平台登录会话。
 *
 * @author OmniNest
 */
@Service
@RequiredArgsConstructor
public class MusicPlatformLoginSessionService {
    private static final Duration LOGIN_SESSION_TTL = Duration.ofMinutes(5);
    private static final String KEY_PREFIX = "omninest:integration:music:login:";

    /**
     * 确认标记的有效期：略长于登录会话，覆盖"确认响应丢失后前端重入轮询"的窗口。
     */
    private static final Duration CONFIRMED_MARK_TTL = Duration.ofMinutes(10);
    private static final String CONFIRMED_KEY_PREFIX = "omninest:integration:music:login:confirmed:";

    /**
     * 主动断开标记的有效期：长于确认标记，覆盖"旧会话在断开后才被确认"的最晚时点。
     */
    private static final Duration DISCONNECTED_MARK_TTL = Duration.ofMinutes(15);
    private static final String DISCONNECTED_KEY_PREFIX = "omninest:integration:music:disconnected:";

    private final ExpiringOwnershipRegistry ownershipRegistry;

    /**
     * 登记用户的平台登录会话。
     *
     * <p>登记新会话意味着用户重新发起了登录，因此同时清除主动断开标记，
     * 否则新会话的确认会被误判为"迟到的旧确认"。</p>
     *
     * @param ownerUserId 所属用户 ID
     * @param platform 平台
     * @param sessionId 平台登录会话 ID
     */
    public void register(UUID ownerUserId, MusicPlatform platform, String sessionId) {
        ownershipRegistry.register(key(platform, sessionId), ownerUserId, LOGIN_SESSION_TTL);
        ownershipRegistry.remove(disconnectedKey(platform, ownerUserId));
    }

    /**
     * 校验登录会话归属。
     *
     * @param ownerUserId 当前用户 ID
     * @param platform 平台
     * @param sessionId 平台登录会话 ID
     * @throws BusinessException 会话不存在或不属于当前用户时抛出
     */
    public void requireOwner(UUID ownerUserId, MusicPlatform platform, String sessionId) {
        UUID storedOwner = ownershipRegistry.findOwner(key(platform, sessionId)).orElse(null);
        if (storedOwner == null) {
            throw new BusinessException(ErrorCode.NOT_FOUND, "平台登录会话不存在或已过期");
        }
        if (!ownerUserId.equals(storedOwner)) {
            throw new BusinessException(ErrorCode.FORBIDDEN, "无权访问该平台登录会话");
        }
    }

    /**
     * 记录登录会话已被平台确认成功。
     *
     * <p>扫码确认成功后不立即结束会话：平台会消费一次性密钥，后续轮询同一密钥只能
     * 拿到 800（已失效）。写入确认标记后，检查接口可把这种"先成功、后失效"的轮询
     * 幂等回退为成功，避免前端误报"二维码已失效"。</p>
     *
     * @param ownerUserId 所属用户 ID
     * @param platform 平台
     * @param sessionId 平台登录会话 ID
     */
    public void markConfirmed(UUID ownerUserId, MusicPlatform platform, String sessionId) {
        ownershipRegistry.register(
                confirmedKey(platform, sessionId),
                ownerUserId,
                CONFIRMED_MARK_TTL
        );
    }

    /**
     * 判断登录会话是否曾被平台确认成功。
     *
     * @param platform 平台
     * @param sessionId 平台登录会话 ID
     * @return 存在有效确认标记时返回 true
     */
    public boolean wasConfirmed(MusicPlatform platform, String sessionId) {
        return ownershipRegistry.findOwner(confirmedKey(platform, sessionId)).isPresent();
    }

    /**
     * 结束登录会话。
     *
     * @param platform 平台
     * @param sessionId 平台登录会话 ID
     */
    public void complete(MusicPlatform platform, String sessionId) {
        ownershipRegistry.remove(key(platform, sessionId));
        ownershipRegistry.remove(confirmedKey(platform, sessionId));
    }

    /**
     * 标记用户已主动断开该平台。
     *
     * <p>用途是堵住一个时序漏洞：断开瞬间可能仍有未完成的扫码会话，若用户随后在手机上
     * 完成确认，平台会返回 803，凭据会被重新写回，"退出登录"实际失效。写入该标记后，
     * 检查接口会拒绝处理旧会话的确认，直到用户重新发起登录（{@link #register} 清除标记）。</p>
     *
     * <p>未采用"按用户遍历并删除会话键"的方案：{@link ExpiringOwnershipRegistry} 只有
     * 键到用户的单向查询，没有按用户反查键的能力，且会话本身 5 分钟即自然过期。</p>
     *
     * @param ownerUserId 所属用户 ID
     * @param platform 平台
     */
    public void markDisconnected(UUID ownerUserId, MusicPlatform platform) {
        ownershipRegistry.register(
                disconnectedKey(platform, ownerUserId),
                ownerUserId,
                DISCONNECTED_MARK_TTL
        );
    }

    /**
     * 判断用户是否处于"已主动断开该平台"的窗口内。
     *
     * @param ownerUserId 所属用户 ID
     * @param platform 平台
     * @return 存在有效断开标记时返回 true
     */
    public boolean isDisconnected(UUID ownerUserId, MusicPlatform platform) {
        return ownershipRegistry.findOwner(disconnectedKey(platform, ownerUserId)).isPresent();
    }

    private String key(MusicPlatform platform, String sessionId) {
        return KEY_PREFIX + platform.apiValue() + ":" + sessionId;
    }

    private String confirmedKey(MusicPlatform platform, String sessionId) {
        return CONFIRMED_KEY_PREFIX + platform.apiValue() + ":" + sessionId;
    }

    private String disconnectedKey(MusicPlatform platform, UUID ownerUserId) {
        return DISCONNECTED_KEY_PREFIX + platform.apiValue() + ":" + ownerUserId;
    }
}
