package com.omninest.common.storage;

/**
 * 提供业务代码可使用的对象存储桶名称。
 *
 * @author OmniNest
 */
public interface ObjectStorageBuckets {

    /**
     * 获取用户文件存储桶名称。
     *
     * @return 用户文件存储桶名称
     */
    String userFiles();

    /**
     * 获取衍生资源存储桶名称。
     *
     * @return 衍生资源存储桶名称
     */
    String derivedAssets();

    /**
     * 获取文件安全扫描隔离桶名称。
     *
     * @return 隔离桶名称
     */
    String quarantine();

}
