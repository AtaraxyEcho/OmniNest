package com.omninest.modules.video.domain;

/** 本地媒体候选入库策略。 */
public enum MediaImportPolicy {
    MANUAL_REVIEW,
    AUTO_ADD_CONFIDENT,
    AUTO_ADD_ALL_MATCHED
}
