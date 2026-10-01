package com.omninest.common.storage;

import java.io.InputStream;
import java.net.URI;
import java.nio.file.Path;
import java.time.Duration;
import java.util.List;

/**
 * 对象存储访问端口。
 *
 * @author OmniNest
 */
public interface ObjectStorageClient {

    /**
     * 创建对象上传地址。
     *
     * @param key 对象存储键
     * @param ttl 地址有效期
     * @return 上传地址
     */
    URI createUploadUrl(ObjectStorageKey key, Duration ttl);

    /**
     * 创建对象下载地址。
     *
     * @param key 对象存储键
     * @param ttl 地址有效期
     * @return 下载地址
     */
    URI createDownloadUrl(ObjectStorageKey key, Duration ttl);

    /**
     * 创建供容器/进程网络视角读取的下载地址（如转码容器访问对象存储）。
     * 默认与普通下载地址一致；对象存储实现覆写为容器网络可达端点的签名。
     *
     * @param key 对象存储键
     * @param ttl 地址有效期
     * @return 下载地址
     */
    default URI createContainerDownloadUrl(ObjectStorageKey key, Duration ttl) {
        return createDownloadUrl(key, ttl);
    }

    /**
     * 创建对象下载地址，可覆盖响应 Content-Type 与 Content-Disposition。
     * 用于把浏览器会执行的类型（HTML/SVG 等）强制为附件下载。
     *
     * @param key 对象存储键
     * @param ttl 地址有效期
     * @param responseContentType 覆盖的 Content-Type；null 表示不覆盖
     * @param responseContentDisposition 覆盖的 Content-Disposition；null 表示不覆盖
     * @return 下载地址
     */
    default URI createDownloadUrl(
            ObjectStorageKey key,
            Duration ttl,
            String responseContentType,
            String responseContentDisposition
    ) {
        return createDownloadUrl(key, ttl);
    }

    /**
     * 初始化分片上传。
     *
     * @param key 对象存储键
     * @param contentType 内容类型
     * @return 上传标识
     */
    String initiateMultipartUpload(ObjectStorageKey key, String contentType);

    /**
     * 创建分片上传地址。
     *
     * @param key 对象存储键
     * @param uploadId 上传标识
     * @param partNumber 分片编号
     * @param ttl 地址有效期
     * @return 分片上传地址
     */
    URI createMultipartUploadPartUrl(ObjectStorageKey key, String uploadId, int partNumber, Duration ttl);

    /**
     * 完成分片上传。
     *
     * @param key 对象存储键
     * @param uploadId 上传标识
     * @param parts 已完成分片
     */
    void completeMultipartUpload(ObjectStorageKey key, String uploadId, List<ObjectStorageCompletedPart> parts);

    /**
     * 终止分片上传。
     *
     * @param key 对象存储键
     * @param uploadId 上传标识
     */
    void abortMultipartUpload(ObjectStorageKey key, String uploadId);

    /**
     * 上传单个分片。
     *
     * @param key 对象存储键
     * @param uploadId 上传标识
     * @param partNumber 分片编号
     * @param data 分片数据
     * @param size 分片字节数
     * @return 已完成分片
     */
    ObjectStorageCompletedPart uploadPart(
            ObjectStorageKey key, String uploadId, int partNumber,
            InputStream data, long size);

    /**
     * 从本地文件上传对象。
     *
     * @param key 对象存储键
     * @param source 本地文件
     * @param contentType 内容类型
     */
    void putObject(ObjectStorageKey key, Path source, String contentType);

    /**
     * 从输入流上传对象。
     *
     * @param key 对象存储键
     * @param data 输入流
     * @param size 对象字节数
     * @param contentType 内容类型
     */
    void putObject(ObjectStorageKey key, InputStream data, long size, String contentType);

    /**
     * 在对象存储服务端复制对象。
     *
     * @param source 源对象键
     * @param target 目标对象键
     */
    void copyObject(ObjectStorageKey source, ObjectStorageKey target);

    /**
     * 复制对象并以 REPLACE 元数据指令写入目标 Content-Type。
     * 供晋升链把服务端核实的魔数类型固化到对象元数据，
     * 使下载侧的类型判定与存储层直出行为一致。
     *
     * @param source 源对象键
     * @param target 目标对象键
     * @param contentType 目标 Content-Type
     */
    default void copyObject(ObjectStorageKey source, ObjectStorageKey target, String contentType) {
        copyObject(source, target);
    }

    /**
     * 获取对象输入流。
     *
     * @param key 对象存储键
     * @return 对象输入流
     */
    InputStream getObject(ObjectStorageKey key);

    /**
     * 判断对象是否存在。
     *
     * @param key 对象存储键
     * @return 对象存在时返回 true
     */
    boolean objectExists(ObjectStorageKey key);

    /**
     * 删除对象。
     *
     * @param key 对象存储键
     */
    void removeObject(ObjectStorageKey key);

    /**
     * 删除指定对象版本。
     *
     * @param key 对象存储键
     * @param versionId 对象版本 ID
     */
    default void removeObjectVersion(ObjectStorageKey key, String versionId) {
        removeObject(key);
    }

    /**
     * 按前缀分页列出对象。
     *
     * @param bucket 存储桶名称
     * @param prefix 对象键前缀，空字符串表示整个存储桶
     * @param continuationToken 续查标识，首次查询传入 null
     * @param maxKeys 本页最大对象数，范围为 1 至 1000
     * @return 对象分页结果
     */
    ObjectStoragePage listObjects(String bucket, String prefix, String continuationToken, int maxKeys);
}
