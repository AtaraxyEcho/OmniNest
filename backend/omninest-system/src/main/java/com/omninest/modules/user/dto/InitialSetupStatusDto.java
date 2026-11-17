package com.omninest.modules.user.dto;

import io.swagger.v3.oas.annotations.media.Schema;

/**
 * 首次安装向导状态。
 *
 * @param setupRequired 当前实例是否仍需要完成首次安装
 * @param setupAvailable 服务端是否已配置可用的安装令牌
 * @param persistentStateEnabled 是否使用系统实例状态控制安装向导
 * @param twoFactorRequired 安装向导是否要求完成两步验证注册
 * @author OmniNest
 */
@Schema(description = "首次安装向导状态")
public record InitialSetupStatusDto(
        boolean setupRequired,
        boolean setupAvailable,
        boolean persistentStateEnabled,
        boolean twoFactorRequired
) {
}
