package com.omninest.modules.reader.service;

import java.util.Collection;
import java.util.Set;
import org.springframework.stereotype.Service;

/**
 * 漫画页面资产引用查询实现。
 *
 * <p>页面资产的物理对象经 DerivedAssetStorageService 写入 FileObject，
 * 孤儿扫描的 FileObject 引用查询已保护这些对象键。此处返回空集，
 * 仅在业务侧出现“无 FileObject 但仍被页面资产引用”的历史数据时才需要扩展。</p>
 *
 * @author OmniNest
 */
@Service
public class ReaderPageAssetReferenceQueryService implements ReaderPageAssetReferenceQuery {

    /**
     * {@inheritDoc}
     */
    @Override
    public Set<String> findReferencedObjectKeys(String bucketName, Collection<String> objectKeys) {
        return Set.of();
    }
}
