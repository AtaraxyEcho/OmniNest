package com.omninest.common.security;

import java.util.UUID;

/**
 * 当前认证用户访问端口。
 *
 * @author OmniNest
 */
public interface CurrentUserContext {

    /**
     * 获取当前已认证用户。
     *
     * @return 当前认证用户信息
     */
    CurrentUser requireCurrentUser();

    /**
     * 获取当前已认证用户标识。
     *
     * @return 当前用户标识
     */
    UUID requireCurrentUserId();

    /**
     * 获取当前访问令牌对应的会话标识（sid claim）。
     *
     * @return 当前会话标识；凭证未携带会话信息时返回 null
     */
    UUID currentSessionId();

    /**
     * 获取当前请求的内容访问主体。
     *
     * <p>只有本接口能产出会话请求主体，内容访问 API 借此区分"请求者"与
     * "资源记录的所有者"，避免把 {@code ownerUserId} 当作请求者传入。</p>
     *
     * @return 当前请求主体
     */
    default RequestPrincipal requirePrincipal() {
        return RequestPrincipal.authenticated(requireCurrentUserId());
    }
}
