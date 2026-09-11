package com.omninest.modules.file.service;

import com.omninest.modules.file.domain.StorageLocation;
import com.omninest.modules.file.repository.FileContentRefRepository;
import com.omninest.modules.file.repository.StorageLocationRepository;
import java.util.List;
import java.util.UUID;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Propagation;
import org.springframework.transaction.annotation.Transactional;

/**
 * 存储位置独立事务变更器。
 *
 * <p>插入与回滚清理必须在 REQUIRES_NEW 独立事务中执行：唯一键冲突若发生在外层
 * 事务提交期，调用方无法在已中止的事务内回查或删除；独立事务回滚后外层仍可继续。
 * 必须经 Spring 代理跨 bean 调用，同 bean 自调用不生效。</p>
 *
 * @author OmniNest
 */
@Slf4j
@Service
@RequiredArgsConstructor
public class StorageLocationInserter {

    private final StorageLocationRepository storageLocationRepository;
    private final FileContentRefRepository contentRefRepository;
    private final List<StorageLocationUsageInspector> usageInspectors;

    /**
     * 在独立事务中保存并立即刷出存储位置，使唯一键冲突在本方法内抛出。
     *
     * @param location 已完成校验的存储位置
     * @return 已持久化的存储位置
     */
    @Transactional(propagation = Propagation.REQUIRES_NEW, rollbackFor = Exception.class)
    public StorageLocation insert(StorageLocation location) {
        StorageLocation saved = storageLocationRepository.saveAndFlush(location);
        log.info("本地媒体存储位置已自动创建: locationId={}, mountKey={}, scopeType={}",
                saved.getId(), saved.getMountKey(), saved.getScopeType());
        return saved;
    }

    /**
     * 在独立事务中删除无引用的存储位置，用于挂载直达创建失败的回滚清理；
     * 仍被文件内容引用或业务来源引用时跳过删除并返回 false。
     *
     * @param locationId 存储位置 ID
     * @return 实际删除时返回 true
     */
    @Transactional(propagation = Propagation.REQUIRES_NEW, rollbackFor = Exception.class)
    public boolean deleteIfUnreferenced(UUID locationId) {
        if (contentRefRepository.countByStorageLocationId(locationId) > 0) {
            return false;
        }
        if (usageInspectors.stream().anyMatch(inspector -> inspector.isInUse(locationId))) {
            return false;
        }
        storageLocationRepository.deleteById(locationId);
        log.info("挂载直达自动创建的存储位置已回滚清理: locationId={}", locationId);
        return true;
    }
}
