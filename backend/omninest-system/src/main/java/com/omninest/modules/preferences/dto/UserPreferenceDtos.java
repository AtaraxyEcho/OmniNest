package com.omninest.modules.preferences.dto;

import io.swagger.v3.oas.annotations.media.Schema;
import java.time.Instant;
import java.util.List;
import java.util.Map;

/**
 * 用户偏好设置 DTO。
 *
 * @author Notask Flow Team
 */
@Schema(description = "用户偏好设置 DTO 集合")
public final class UserPreferenceDtos {
    private UserPreferenceDtos() {
    }

    @Schema(description = "用户偏好设置")
    public record UserPreferenceDto(
            @Schema(description = "偏好范围", example = "theme") String scope,
            @Schema(description = "偏好键值对") Map<String, Object> preferences,
            @Schema(description = "创建时间") Instant createdAt,
            @Schema(description = "更新时间") Instant updatedAt,
            @Schema(description = "乐观锁版本") Long version
    ) {
        /**
         * 构造不包含审计版本的兼容响应。
         *
         * @param scope 偏好作用域
         * @param preferences 偏好键值对
         * @param updatedAt 更新时间
         */
        public UserPreferenceDto(String scope, Map<String, Object> preferences, Instant updatedAt) {
            this(scope, preferences, null, updatedAt, null);
        }
    }

    @Schema(description = "用户偏好增量更新请求")
    public record UserPreferencePatchRequest(
            @Schema(description = "客户端读取到的版本，首次创建时为空") Long baseVersion,
            @Schema(description = "待新增或替换的顶层键值对") Map<String, Object> changes,
            @Schema(description = "待删除的顶层键") List<String> removeKeys
    ) {
    }
}
