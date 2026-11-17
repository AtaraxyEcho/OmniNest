package com.omninest.common.storage;

/**
 * 本地外部存储容器路径对应的宿主机设置。
 *
 * @author OmniNest
 */
public interface LocalExternalStorageSettings {

    /**
     * 获取本地外部存储在宿主机上的根路径。
     *
     * @return 宿主机根路径
     */
    String localHostRoot();

    /**
     * 获取 rclone 导入暂存目录在宿主机上的路径。
     *
     * @return 宿主机暂存目录
     */
    String importHostRoot();

    /**
     * 获取 rclone 导入暂存目录在容器内的路径。
     *
     * @return 容器暂存目录
     */
    String importContainerRoot();
}
