package com.omninest.modules.file.service;

import com.omninest.modules.file.domain.FileNode;
import com.omninest.modules.file.domain.FileObject;
import com.omninest.modules.file.dto.FileContentResource;
import com.omninest.modules.file.dto.FileContentStream;
import com.omninest.modules.file.dto.FileDownloadUrlDto;
import com.omninest.modules.file.dto.FileProcessInput;
import java.util.Optional;

/**
 * 文件内容提供者统一契约。
 *
 * @author OmniNest
 */
public interface FileContentProvider {

    /**
     * 返回稳定提供者编码。
     *
     * @return 提供者编码
     */
    String providerType();

    /**
     * 判断提供者是否负责指定文件节点。
     *
     * @param node 文件节点
     * @return 负责时返回 true
     */
    boolean supports(FileNode node);

    /**
     * 打开文件内容流。
     *
     * @param node 文件节点
     * @return 内容流
     */
    FileContentStream open(FileNode node);

    /**
     * 创建短期下载地址。
     *
     * @param node 文件节点
     * @return 下载地址
     */
    FileDownloadUrlDto createDownloadUrl(FileNode node);
    /**
     * 基于已加载的对象元数据创建下载地址，批量场景避免逐节点回查对象记录。
     * 默认退化为单节点查询实现。
     *
     * @param node 文件节点
     * @param object 节点当前对象元数据
     * @return 下载地址
     */
    default FileDownloadUrlDto createDownloadUrl(FileNode node, FileObject object) {
        return createDownloadUrl(node);
    }

    /**
     * 创建受信任媒体进程输入。
     *
     * @param node 文件节点
     * @return 进程输入
     */
    FileProcessInput createProcessInput(FileNode node);

    /**
     * 创建容器/进程网络视角可读取的输入地址。
     * 默认与 {@link #createProcessInput(FileNode)} 一致（本地只读路径本就容器可达）；
     * 对象存储提供者覆写为容器网络端点的签名 URL，业务模块不再自行改签。
     */
    default FileProcessInput createContainerProcessInput(FileNode node) {
        return createProcessInput(node);
    }

    /**
     * 返回可直接处理 Range 的本地资源。
     *
     * @param node 文件节点
     * @return 本地资源，不支持时返回空
     */
    Optional<FileContentResource> findRangeResource(FileNode node);
}
