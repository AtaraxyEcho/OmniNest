package com.omninest.modules.user.dto;

import io.swagger.v3.oas.annotations.media.Schema;
import java.util.List;

/**
 * 首次安装完成结果。
 *
 * @param backupCodes 安装向导启用两步验证时一次性返回的备份码，未启用时为空
 * @author OmniNest
 */
@Schema(description = "首次安装完成结果")
public record InitialSetupResultDto(
        List<String> backupCodes
) {
}
