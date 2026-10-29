package com.omninest.common.security;

import java.util.Objects;
import java.util.UUID;

/**
 * 内容访问请求主体。
 *
 * <p>下载与原文件播放在共享空间里取决于请求者是否持有 {@code CAN_DOWNLOAD}，因此这类
 * 判定必须针对"本次调用出示凭证的一方"。历史实现把请求者写成裸 {@code UUID}，调用点
 * 手里同时有请求者和 {@code item.getOwnerUserId()} 时，传错不会产生任何编译或运行反馈。
 * 本类型把请求者身份从普通用户 ID 中分离出来，且只能由两类来源产生：</p>
 *
 * <ul>
 *   <li>会话请求：{@link CurrentUserContext#requirePrincipal()}；</li>
 *   <li>已验证凭证：{@link #credential(AccessGrant)}，由播放会话、内容令牌或分享链接解析结果实现。</li>
 * </ul>
 *
 * <p>后台任务不持有请求者身份，只能使用按所有者授权的处理入口
 * （{@code FileLifecycleGuard.requireOwnedWritable}、{@code FileContentAccessService.open}），
 * 不得构造本类型。</p>
 *
 * @author OmniNest
 */
public final class RequestPrincipal {

    private final UUID userId;

    private RequestPrincipal(UUID userId) {
        this.userId = userId;
    }

    static RequestPrincipal authenticated(UUID userId) {
        return new RequestPrincipal(Objects.requireNonNull(userId, "userId"));
    }

    /**
     * 由已完成校验的凭证还原请求者身份。
     *
     * @param grant 凭证解析结果
     * @return 请求主体
     */
    public static RequestPrincipal credential(AccessGrant grant) {
        Objects.requireNonNull(grant, "grant");
        return new RequestPrincipal(Objects.requireNonNull(grant.requesterUserId(), "requesterUserId"));
    }

    /**
     * 请求者用户标识。
     *
     * @return 请求者用户 ID
     */
    public UUID userId() {
        return userId;
    }

    @Override
    public boolean equals(Object other) {
        return other instanceof RequestPrincipal principal && userId.equals(principal.userId);
    }

    @Override
    public int hashCode() {
        return userId.hashCode();
    }

    @Override
    public String toString() {
        return "RequestPrincipal[" + userId + "]";
    }
}
