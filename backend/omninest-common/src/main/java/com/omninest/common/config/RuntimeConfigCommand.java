package com.omninest.common.config;

import java.util.UUID;

/**
 * 运行时配置跨模块写入端口。
 *
 * @author OmniNest
 */
public interface RuntimeConfigCommand {

    /**
     * 更新指定运行时配置。
     *
     * @param key 配置键
     * @param value 配置值
     * @param reason 变更原因
     * @param changedBy 操作者用户标识
     */
    void updateValue(String key, String value, String reason, UUID changedBy);
}
