package com.omninest.modules.file.service;

import com.omninest.common.storage.ObjectStorageClient;
import com.omninest.common.storage.ObjectStorageKey;
import java.io.InputStream;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;

/**
 * 迁移前遗留派生对象的访问入口。
 *
 * <p>这些对象还没有迁移成 FileNode，只按 bucket + object key 定位。业务模块不得直接依赖
 * 对象存储客户端，因此统一从这里取流或删除；从 {@link DerivedAssetStorageService}
 * 拆出后，存储服务只保留 FileNode 形态的派生资产管理。</p>
 *
 * @author OmniNest
 */
@Service
@RequiredArgsConstructor
public class LegacyObjectAccess {

    private final ObjectStorageClient objectStorageClient;

    /**
     * 删除派生资源引用的物理对象。
     *
     * <p>调用方必须在删除自身元数据前调用此方法。对象存储异常会直接抛出，
     * 由上层事务决定是否回滚，不能在元数据已经删除后再静默记录失败。</p>
     *
     * @param reference 物理对象引用
     */
    public void delete(LegacyObjectReference reference) {
        validate(reference);
        objectStorageClient.removeObject(key(reference));
    }

    /**
     * 打开迁移前遗留派生对象的只读流。
     *
     * <p>调用方拥有关闭返回流的责任。</p>
     *
     * @param reference 遗留对象引用
     * @return 对象内容流
     */
    public InputStream open(LegacyObjectReference reference) {
        validate(reference);
        return objectStorageClient.getObject(key(reference));
    }

    private ObjectStorageKey key(LegacyObjectReference reference) {
        return new ObjectStorageKey(reference.bucketName(), reference.objectKey());
    }

    private void validate(LegacyObjectReference reference) {
        if (reference == null
                || reference.bucketName() == null
                || reference.bucketName().isBlank()
                || reference.objectKey() == null
                || reference.objectKey().isBlank()) {
            throw new IllegalArgumentException("派生资源对象引用不能为空");
        }
    }
}
