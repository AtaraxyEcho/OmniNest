package com.omninest.modules.file.service;

/**
 * 查询文件模块持有的对象存储引用。
 *
 * <p>覆盖经 {@link DerivedAssetStorageService} 登记的派生资产
 * （Photo 缩略图、Transcode、Backdrop、Music 封面等）。</p>
 *
 * @author OmniNest
 */
public interface FileObjectReferenceQuery extends DerivedObjectReferenceQuery {
}
