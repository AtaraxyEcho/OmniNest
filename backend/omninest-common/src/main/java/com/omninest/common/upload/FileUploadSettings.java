package com.omninest.common.upload;

import java.time.Duration;

/**
 * 文件上传会话和预签名地址的运行参数。
 *
 * @author OmniNest
 */
public interface FileUploadSettings {

    /**
     * 获取预签名上传地址的有效期。
     *
     * @return 预签名地址有效期
     */
    Duration presignedUrlTtl();

    /**
     * 获取上传会话的有效期。
     *
     * @return 上传会话有效期
     */
    Duration sessionTtl();

    /**
     * 判断是否启用预签名地址签发限速。
     *
     * @return 启用时返回 true
     */
    boolean bandwidthLimitEnabled();

    /**
     * 获取每个用户每秒允许签发的分片地址数量。
     *
     * @return 每秒签发数量
     */
    int maxPresignedPartsPerSecond();

    /**
     * 获取预签名地址签发令牌桶的突发容量。
     *
     * @return 突发容量
     */
    int presignedPartBurstCapacity();
}
