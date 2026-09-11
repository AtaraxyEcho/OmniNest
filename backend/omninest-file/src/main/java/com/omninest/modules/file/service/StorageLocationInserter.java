package com.omninest.modules.file.service;

import com.omninest.modules.file.domain.StorageLocation;
import com.omninest.modules.file.repository.StorageLocationRepository;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Propagation;
import org.springframework.transaction.annotation.Transactional;

/**
 * 存储位置独立事务插入器。
 *
 * <p>插入必须在 REQUIRES_NEW 独立事务中执行：唯一键冲突若发生在外层事务提交期，
 * 调用方无法在已中止的事务内回查；独立事务回滚后外层仍可继续查询。
 * 必须经 Spring 代理跨 bean 调用，同 bean 自调用不生效。</p>
 *
 * @author OmniNest
 */
@Slf4j
@Service
@RequiredArgsConstructor
public class StorageLocationInserter {

    private final StorageLocationRepository storageLocationRepository;

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
}
