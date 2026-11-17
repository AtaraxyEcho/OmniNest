package com.omninest.modules.file.service;

import com.omninest.modules.file.domain.FileIngressStatus;
import com.omninest.modules.file.repository.FileIngressItemRepository;
import java.util.Collection;
import java.util.List;
import java.util.Set;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * 基于文件安全入库记录实现对象键在途归属查询。
 *
 * @author OmniNest
 */
@Service
@RequiredArgsConstructor
public class FileIngressObjectReferenceQueryService implements FileIngressObjectReferenceQuery {

    /**
     * 仍在扫描或等待晋升的入库状态；这三类状态的目标键归入库流程所有。
     */
    private static final List<FileIngressStatus> IN_FLIGHT_STATUSES = List.of(
            FileIngressStatus.PENDING_SCAN,
            FileIngressStatus.SCANNING,
            FileIngressStatus.CLEAN
    );

    private final FileIngressItemRepository ingressItemRepository;

    /**
     * 查询候选对象键中被在途入库记录持有的键。
     *
     * @param bucketName 存储桶名称
     * @param objectKeys 候选对象键
     * @return 由在途入库记录持有的对象键
     */
    @Override
    @Transactional(readOnly = true)
    public Set<String> findInFlightObjectKeys(String bucketName, Collection<String> objectKeys) {
        if (bucketName == null || bucketName.isBlank() || objectKeys == null || objectKeys.isEmpty()) {
            return Set.of();
        }
        return Set.copyOf(
                ingressItemRepository.findInFlightObjectKeys(bucketName, IN_FLIGHT_STATUSES, objectKeys)
        );
    }
}
