package com.omninest.modules.file.repository;

import com.omninest.modules.file.domain.StorageRemoteMetadataCache;
import java.util.List;
import java.util.Optional;
import java.util.UUID;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.transaction.annotation.Transactional;

/**
 * 外部存储元数据缓存仓储。
 */
public interface StorageRemoteMetadataCacheRepository extends JpaRepository<StorageRemoteMetadataCache, UUID> {

    /**
     * 查询指定账户和路径的缓存记录。
     */
    List<StorageRemoteMetadataCache> findByExternalAccountIdAndRemotePath(UUID externalAccountId, String remotePath);

    /**
     * 查询指定账户和路径最近写入的缓存快照。
     *
     * @param externalAccountId 外部存储账户标识
     * @param remotePath 远程目录路径
     * @return 最近的缓存记录
     */
    Optional<StorageRemoteMetadataCache> findFirstByExternalAccountIdAndRemotePathOrderByCachedAtDesc(
            UUID externalAccountId,
            String remotePath);

    /**
     * 删除指定账户和路径的所有缓存记录。
     */
    @Transactional
    void deleteByExternalAccountIdAndRemotePath(UUID externalAccountId, String remotePath);

    /**
     * 删除指定账户的所有缓存记录。
     */
    @Transactional
    void deleteByExternalAccountId(UUID externalAccountId);
}
