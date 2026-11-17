package com.omninest.modules.file.service;

import com.omninest.common.enums.ErrorCode;
import com.omninest.common.error.BusinessException;
import com.omninest.modules.file.domain.FileNode;
import com.omninest.modules.file.repository.FileNodeRepository;
import java.util.Optional;
import java.util.UUID;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;

/**
 * 为媒体探测提供受控本地输入。
 *
 * <p>从 {@link FileQueryService} 拆出：探测暂存不参与文件树查询，单独成服务可避免
 * 媒体模块依赖庞大的文件查询门面，也把首尾窗口策略的调用入口收在一处。</p>
 *
 * @author OmniNest
 */
@Service
@RequiredArgsConstructor
public class FileProbeSourceService {

    private final FileNodeRepository fileNodeRepository;
    private final MediaProbeSourceStager mediaProbeSourceStager;

    /**
     * 为探测准备当前用户拥有的本地输入。
     *
     * <p>不加事务：首尾窗口复制是网络与磁盘 I/O，事务会长时间占住连接池名额。</p>
     *
     * @param ownerUserId 所有者用户 ID
     * @param fileId 文件节点 ID
     * @return 本地探测输入；提供者无法读取时为空
     */
    public Optional<MediaProbeSourceStager.StagedSource> stageOwned(UUID ownerUserId, UUID fileId) {
        return mediaProbeSourceStager.stage(findActiveNode(ownerUserId, fileId));
    }

    /**
     * 首尾窗口与放大尾窗都失败时，按大小上限整文件暂存一次。
     *
     * @param ownerUserId 所有者用户 ID
     * @param fileId 文件节点 ID
     * @return 完整本地探测输入；超限或读取失败时为空
     */
    public Optional<MediaProbeSourceStager.StagedSource> stageOwnedFull(UUID ownerUserId, UUID fileId) {
        return mediaProbeSourceStager.stageFull(findActiveNode(ownerUserId, fileId));
    }

    /**
     * 按指定尾窗为探测准备本地输入，供索引超出默认窗口时放大重试。
     *
     * @param ownerUserId 所有者用户 ID
     * @param fileId 文件节点 ID
     * @param tailBytes 尾窗字节上限
     * @return 本地探测输入；提供者无法读取时为空
     */
    public Optional<MediaProbeSourceStager.StagedSource> stageOwned(
            UUID ownerUserId, UUID fileId, long tailBytes) {
        return mediaProbeSourceStager.stage(findActiveNode(ownerUserId, fileId), tailBytes);
    }

    private FileNode findActiveNode(UUID ownerUserId, UUID fileId) {
        return fileNodeRepository.findByIdAndOwnerUserIdAndDeletedFalse(fileId, ownerUserId)
                .orElseThrow(() -> new BusinessException(ErrorCode.FILE_NOT_FOUND, "文件不存在"));
    }
}
