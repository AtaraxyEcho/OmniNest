package com.omninest.modules.file.repository;

/**
 * 共享空间用量账本的对账投影。
 *
 * @author OmniNest
 */
public interface SharedSpaceUsageProjection {

    /**
     * 返回共享空间实际占用字节数。
     *
     * @return 占用字节数
     */
    long getTotalBytes();

    /**
     * 返回共享空间实际文件数。
     *
     * @return 文件数
     */
    long getTotalFiles();
}
