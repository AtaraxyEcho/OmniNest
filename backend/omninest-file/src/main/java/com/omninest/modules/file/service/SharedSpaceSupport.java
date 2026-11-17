package com.omninest.modules.file.service;

import com.omninest.common.enums.ErrorCode;
import com.omninest.common.error.BusinessException;

/**
 * 共享空间名称与统计值的纯函数辅助方法。
 *
 * @author OmniNest
 */
final class SharedSpaceSupport {

    private SharedSpaceSupport() {
    }

    static long toLong(Object value) {
        return value instanceof Number number ? number.longValue() : 0L;
    }

    static String normalizeNodeName(String name) {
        String normalized = name == null ? "" : name.trim();
        if (normalized.isEmpty() || ".".equals(normalized) || "..".equals(normalized)
                || normalized.contains("/") || normalized.contains("\\")
                || normalized.indexOf('\0') >= 0) {
            throw new BusinessException(ErrorCode.PARAM_ERROR, "文件名称不合法");
        }
        return normalized;
    }
}
