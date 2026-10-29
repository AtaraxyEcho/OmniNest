package com.omninest.modules.file.service;

import com.omninest.common.security.RequestPrincipal;
import com.omninest.modules.file.dto.FileContentRange;
import com.omninest.modules.file.dto.FileContentStream;
import java.util.Optional;
import java.util.UUID;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * 播放类业务的内容读取入口。
 *
 * <p>音乐等长音频业务需要“服务端按 Range 直接转发原文件字节”，不能再用面向浏览器的
 * 下载地址做容器内回环请求。这里复用下载权限判定（共享空间需 CAN_DOWNLOAD、定向分享需接收关系），
 * 只暴露按节点 ID 读取的能力，不暴露路径、对象键或 Provider。</p>
 *
 * @author OmniNest
 */
@Service
@RequiredArgsConstructor
public class FilePlaybackContentService {

    private final FileDownloadContentService downloadContentService;

    /**
     * 校验当前请求者具备下载权限，供媒体播放在开会话前预检。
     *
     * @param requester 当前请求主体
     * @param fileId 文件节点 ID
     */
    @Transactional(readOnly = true)
    public void requireDownloadable(RequestPrincipal requester, UUID fileId) {
        downloadContentService.requireDownloadable(requester, fileId);
    }

    /**
     * 按下载权限打开完整内容流。
     *
     * @param requester 当前请求主体
     * @param fileId 文件节点 ID
     * @return 内容流
     */
    @Transactional(readOnly = true)
    public FileContentStream openFileContent(RequestPrincipal requester, UUID fileId) {
        return downloadContentService.openDownloadableFileContent(requester, fileId);
    }

    /**
     * 按下载权限打开字节区间。
     *
     * @param requester 当前请求主体
     * @param fileId 文件节点 ID
     * @param offset 起始字节偏移
     * @param length 读取字节数
     * @return 区间句柄；提供者不支持区间读时为空
     */
    @Transactional(readOnly = true)
    public Optional<FileContentRange> openFileRange(
            RequestPrincipal requester, UUID fileId, long offset, long length) {
        return downloadContentService.openDownloadableFileRange(requester, fileId, offset, length);
    }
}
