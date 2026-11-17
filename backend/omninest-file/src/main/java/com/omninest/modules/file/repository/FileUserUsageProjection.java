package com.omninest.modules.file.repository;

import java.util.UUID;

/**
 * 按用户聚合的文件存储用量投影。
 *
 * @author OmniNest
 */
public interface FileUserUsageProjection {

    /**
     * 返回文件所有者用户 ID。
     *
     * @return 用户 ID
     */
    UUID getUserId();

    /**
     * 返回用户实际占用字节数。
     *
     * @return 占用字节数
     */
    long getTotalBytes();
}
