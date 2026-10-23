package com.omninest.modules.video.service;

import com.omninest.modules.file.dto.FileProcessInput;
import com.omninest.modules.file.service.FileQueryService;
import java.util.UUID;
import org.springframework.stereotype.Service;

/**
 * 将统一文件内容输入转换为 FFmpeg 容器可读取的地址。
 *
 * <p>地址改签由 File 模块的容器视角端口完成（对象存储实现内部选择容器网络端点），
 * 本模块不再接触 S3 签名器或解析预签名 URL 结构。
 *
 * @author OmniNest
 */
@Service
public class VideoSourceInputResolver {

    private final FileQueryService fileQueryService;

    public VideoSourceInputResolver(FileQueryService fileQueryService) {
        this.fileQueryService = fileQueryService;
    }

    /**
     * 解析指定文件的 FFmpeg 容器输入。
     *
     * @param ownerUserId 所有者用户 ID
     * @param fileNodeId 文件节点 ID
     * @return 容器网络可达的 MinIO 预签名 URL 或本地只读容器路径
     */
    public String resolveDockerInput(UUID ownerUserId, UUID fileNodeId) {
        FileProcessInput input = fileQueryService.createOwnedContainerProcessInput(ownerUserId, fileNodeId);
        return input.input();
    }

    /**
     * 解析在后端本机运行的 FFmpeg 输入。
     *
     * <p>对象存储内容使用容器网络端点（生产后端容器内可解析 {@code minio}）；
     * LOCAL_FILESYSTEM 内容使用 File 模块暴露的本机进程路径，避免把 ffmpeg 容器
     * 专用的挂载路径交给宿主机/后端容器外的进程。</p>
     *
     * @param ownerUserId 所有者用户 ID
     * @param fileNodeId 文件节点 ID
     * @return 本机进程可读取的地址或路径
     */
    public String resolveLocalInput(UUID ownerUserId, UUID fileNodeId) {
        FileProcessInput localInput = fileQueryService.createOwnedProcessInput(ownerUserId, fileNodeId);
        if ("LOCAL_FILESYSTEM".equals(localInput.providerType())) {
            return localInput.input();
        }
        return fileQueryService.createOwnedContainerProcessInput(ownerUserId, fileNodeId).input();
    }
}
