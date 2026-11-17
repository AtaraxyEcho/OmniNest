package com.omninest.common.rclone;

import java.time.Instant;
import java.util.Collections;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

/**
 * 定义业务模块使用的 Rclone 远程存储能力。
 *
 * @author OmniNest
 */
public interface RcloneGateway {

    /**
     * 创建远程存储配置。
     *
     * @param name       远程存储名称
     * @param type       Rclone 存储类型
     * @param parameters 配置参数
     */
    void createRemote(String name, String type, Map<String, String> parameters);

    /**
     * 删除远程存储配置。
     *
     * @param name 远程存储名称
     */
    void deleteRemote(String name);

    /**
     * 查询已配置的远程存储名称。
     *
     * @return 远程存储名称列表
     */
    List<String> listRemoteNames();

    /**
     * 查询远程目录内容。
     *
     * @param fileSystem Rclone 文件系统标识
     * @param remotePath 远程目录路径
     * @param includeHash 是否读取文件哈希
     * @return 目录条目列表
     */
    List<DirectoryEntry> listDirectory(String fileSystem, String remotePath, boolean includeHash);

    /**
     * 查询远程存储空间使用情况。
     *
     * @param fileSystem Rclone 文件系统标识
     * @return 空间使用情况
     */
    SpaceUsage querySpaceUsage(String fileSystem);

    /**
     * 查询远程文件系统能力。
     *
     * @param fileSystem Rclone 文件系统标识
     * @return 只包含普通 Java 类型的能力信息
     */
    Map<String, Object> queryFileSystemInfo(String fileSystem);

    /**
     * 创建远程目录。
     *
     * @param fileSystem Rclone 文件系统标识
     * @param remotePath 远程目录路径
     */
    void createDirectory(String fileSystem, String remotePath);

    /**
     * 删除远程文件。
     *
     * @param fileSystem Rclone 文件系统标识
     * @param remotePath 远程文件路径
     */
    void deleteFile(String fileSystem, String remotePath);

    /**
     * 移动远程文件。
     *
     * @param sourceFileSystem 源文件系统标识
     * @param sourceRemotePath 源文件路径
     * @param targetFileSystem 目标文件系统标识
     * @param targetRemotePath 目标文件路径
     */
    void moveFile(
            String sourceFileSystem,
            String sourceRemotePath,
            String targetFileSystem,
            String targetRemotePath
    );

    /**
     * 异步复制目录。
     *
     * @param sourceFileSystem 源文件系统标识
     * @param targetFileSystem 目标文件系统标识
     * @param group             传输统计分组
     * @return Rclone 作业编号
     */
    int startDirectoryCopy(String sourceFileSystem, String targetFileSystem, String group);

    /**
     * 异步复制单个文件。
     *
     * @param sourceFileSystem 源文件系统标识
     * @param sourceRemotePath 源文件路径
     * @param targetFileSystem 目标文件系统标识
     * @param targetRemotePath 目标文件路径
     * @param group             传输统计分组
     * @return Rclone 作业编号
     */
    int startFileCopy(
            String sourceFileSystem,
            String sourceRemotePath,
            String targetFileSystem,
            String targetRemotePath,
            String group
    );

    /**
     * 查询异步作业状态。
     *
     * @param jobId Rclone 作业编号
     * @return 作业状态
     */
    JobStatus queryJobStatus(int jobId);

    /**
     * 停止异步作业。
     *
     * @param jobId Rclone 作业编号
     */
    void stopJob(int jobId);

    /**
     * 查询传输统计。
     *
     * @param group 传输统计分组
     * @return 传输统计
     */
    TransferStats queryTransferStats(String group);

    /**
     * 远程目录条目。
     *
     * @param name       条目名称
     * @param path       条目相对路径
     * @param directory  是否为目录
     * @param sizeBytes  文件大小
     * @param modifiedAt 修改时间
     * @param mimeType   媒体类型
     * @param hash       文件哈希
     * @param metadata   Rclone 返回的普通 Java 元数据
     * @author OmniNest
     */
    record DirectoryEntry(
            String name,
            String path,
            boolean directory,
            long sizeBytes,
            Instant modifiedAt,
            String mimeType,
            String hash,
            Map<String, Object> metadata
    ) {

        /**
         * 创建不可变目录条目。
         */
        public DirectoryEntry {
            Map<String, Object> values = metadata == null ? Map.of() : new LinkedHashMap<>(metadata);
            metadata = Collections.unmodifiableMap(values);
        }
    }

    /**
     * 远程存储空间使用情况。
     *
     * @param totalBytes   总空间字节数
     * @param usedBytes    已用空间字节数
     * @param freeBytes    可用空间字节数
     * @param trashedBytes 回收站占用字节数
     * @author OmniNest
     */
    record SpaceUsage(long totalBytes, long usedBytes, long freeBytes, long trashedBytes) {
    }

    /**
     * Rclone 异步作业状态。
     *
     * @param finished   是否结束
     * @param successful 是否成功
     * @param error      错误摘要
     * @author OmniNest
     */
    record JobStatus(boolean finished, boolean successful, String error) {
    }

    /**
     * Rclone 传输统计。
     *
     * @param totalBytes       总字节数
     * @param transferredBytes 已传输字节数
     * @param speedBytes       每秒传输字节数
     * @author OmniNest
     */
    record TransferStats(long totalBytes, long transferredBytes, long speedBytes) {
    }
}
