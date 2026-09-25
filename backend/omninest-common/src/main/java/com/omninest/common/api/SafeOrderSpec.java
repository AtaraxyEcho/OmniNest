package com.omninest.common.api;

/**
 * 后台任务列表排序列白名单。
 *
 * <p>拼接 ORDER BY 时只能使用本枚举中的物理列名，禁止调用方传入任意字符串。</p>
 *
 * @author OmniNest
 */
public enum SafeOrderSpec {
    UPDATED_AT("updated_at"),
    CREATED_AT("created_at"),
    PROGRESS("progress"),
    TASK_TYPE("task_type"),
    STATUS("status");

    private final String column;

    SafeOrderSpec(String column) {
        this.column = column;
    }

    public String column() {
        return column;
    }

    /**
     * 解析排序列；未知列回退到 updated_at。
     *
     * @param raw 调用方传入的排序列
     * @return 安全排序列
     */
    public static SafeOrderSpec resolve(String raw) {
        if (raw == null || raw.isBlank()) {
            return UPDATED_AT;
        }
        String normalized = raw.trim().toLowerCase(java.util.Locale.ROOT);
        for (SafeOrderSpec spec : values()) {
            if (spec.column.equals(normalized)) {
                return spec;
            }
        }
        return UPDATED_AT;
    }
}
