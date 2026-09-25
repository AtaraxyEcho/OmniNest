package com.omninest.modules.file.service;

import java.util.Collection;
import java.util.Set;

/**
 * 派生对象引用查询 SPI。
 *
 * <p>Photo 缩略图、Transcode、Backdrop、Music 封面等经
 * {@link DerivedAssetStorageService} 写入的派生资产会登记 FileObject，
 * 由 {@link FileObjectReferenceQuery} 报告引用；本接口用于统一扩展
 * 其余不走 FileObject 的引用源。</p>
 *
 * @author OmniNest
 */
public interface DerivedObjectReferenceQuery {

    /**
     * 查询候选对象键中仍被业务元数据引用的键。
     *
     * @param bucketName 存储桶名称
     * @param objectKeys 候选对象键
     * @return 已引用对象键
     */
    Set<String> findReferencedObjectKeys(String bucketName, Collection<String> objectKeys);
}
