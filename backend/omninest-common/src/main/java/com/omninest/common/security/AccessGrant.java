package com.omninest.common.security;

import java.util.UUID;

/**
 * 已完成校验的访问凭证所还原出的请求者身份。
 *
 * <p>实现方必须是一份真实凭证解析的结果：播放会话、内容令牌或分享链接会话。
 * 业务服务不得为了让参数类型通过而临时匿名实现本接口——那等于把资源记录的
 * 所有者当作请求者传入。</p>
 *
 * @author OmniNest
 */
@FunctionalInterface
public interface AccessGrant {

    /**
     * 凭证所属的请求者标识。
     *
     * @return 请求者用户 ID
     */
    UUID requesterUserId();
}
