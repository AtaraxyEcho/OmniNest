package com.omninest.modules.file.domain;

/**
 * 文件永久删除生命周期状态。
 *
 * @author OmniNest
 */
public enum FilePurgeState {
    NONE,
    QUEUED,
    RUNNING,
    RETRY_WAIT,
    FAILED
}
