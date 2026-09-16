package com.omninest.modules.file.repository;

import com.omninest.modules.file.domain.FileIngressItem;
import com.omninest.modules.file.domain.FileIngressStatus;
import java.time.Instant;
import java.util.List;
import java.util.Optional;
import java.util.UUID;
import org.springframework.data.jpa.repository.JpaRepository;

/**
 * 文件安全入库状态仓储。
 *
 * @author OmniNest
 */
public interface FileIngressItemRepository extends JpaRepository<FileIngressItem, UUID> {

    /**
     * 按上传会话查询入库状态。
     *
     * @param uploadSessionId 上传会话标识
     * @return 入库状态
     */
    Optional<FileIngressItem> findByUploadSessionId(UUID uploadSessionId);

    /**
     * 查询指定状态下、更新时间早于截止时间的入库记录，供保留期回收使用。
     *
     * @param statuses 状态集合
     * @param cutoff 截止时间
     * @return 入库记录列表
     */
    List<FileIngressItem> findByStatusInAndUpdatedAtBefore(List<FileIngressStatus> statuses, Instant cutoff);
}
