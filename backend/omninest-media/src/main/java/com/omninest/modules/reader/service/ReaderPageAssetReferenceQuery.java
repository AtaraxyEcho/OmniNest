package com.omninest.modules.reader.service;

import java.util.Collection;
import java.util.Set;

/**
 * 报告仍被漫画页面资产引用的对象键，供派生孤儿扫描排除误删。
 *
 * <p>B2 之后页面资产只持有派生 FileNode ID，物理对象由 File 模块 FileObject 登记；
 * 孤儿扫描的 FileObject 引用查询已覆盖这些对象。本接口保留为业务侧二次确认点，
 * 当前实现恒为空集，避免与 FileObject 引用重复计数。</p>
 *
 * @author OmniNest
 */
public interface ReaderPageAssetReferenceQuery {

    /**
     * 查询候选对象键中仍被漫画页面资产引用的键。
     *
     * @param bucketName 存储桶名称
     * @param objectKeys 候选对象键
     * @return 已引用对象键
     */
    Set<String> findReferencedObjectKeys(String bucketName, Collection<String> objectKeys);
}
