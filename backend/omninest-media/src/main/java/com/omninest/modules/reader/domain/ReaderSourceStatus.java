package com.omninest.modules.reader.domain;

/**
 * 漫画来源解析状态。
 */
public enum ReaderSourceStatus {

    /** 等待解析（任务已入队） */
    PENDING,

    /** 解析中 */
    PARSING,

    /** 解析成功，可阅读 */
    READY,

    /** 解析失败 */
    FAILED
}
