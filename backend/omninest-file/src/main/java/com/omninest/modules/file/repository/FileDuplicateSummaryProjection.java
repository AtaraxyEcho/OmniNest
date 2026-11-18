package com.omninest.modules.file.repository;

/**
 * 个人空间重复内容聚合查询投影。
 *
 * @author OmniNest
 */
public interface FileDuplicateSummaryProjection {

    long getDuplicateFileCount();

    long getDuplicateGroupCount();

    long getReclaimableBytes();

    long getFilesWithoutVerifiedHash();
}
