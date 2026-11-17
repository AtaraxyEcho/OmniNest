package com.omninest.modules.file.domain;

/**
 * 文件安全入库状态。
 *
 * @author OmniNest
 */
public enum FileIngressStatus {
    PENDING_SCAN,
    SCANNING,
    CLEAN,
    AVAILABLE,
    REJECTED,
    FAILED
}
