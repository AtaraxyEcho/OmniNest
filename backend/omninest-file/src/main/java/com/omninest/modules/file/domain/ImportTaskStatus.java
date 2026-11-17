package com.omninest.modules.file.domain;

import lombok.AllArgsConstructor;
import lombok.Getter;

/**
 * 外部存储导入任务状态。
 *
 * @author OmniNest
 */
@Getter
@AllArgsConstructor
public enum ImportTaskStatus {
    QUEUED("QUEUED"),
    SCANNING("SCANNING"),
    TRANSFERRING("TRANSFERRING"),
    IMPORTING("IMPORTING"),
    RUNNING("RUNNING"),
    COMPLETED("COMPLETED"),
    FAILED("FAILED"),
    CANCELLED("CANCELLED");

    private final String value;

    /**
     * 根据持久化值解析任务状态。
     *
     * @param value 持久化值
     * @return 任务状态
     */
    public static ImportTaskStatus fromValue(String value) {
        for (ImportTaskStatus status : values()) {
            if (status.value.equalsIgnoreCase(value)) {
                return status;
            }
        }
        throw new IllegalArgumentException("未知的导入任务状态: " + value);
    }
}
