package com.omninest.modules.file.repository;

import com.omninest.modules.file.domain.StorageExternalAccount;
import java.util.List;
import java.util.Optional;
import java.util.UUID;
import org.springframework.data.jpa.repository.JpaRepository;

/**
 * 外部存储账户仓库。
 *
 * @author OmniNest
 */
public interface StorageExternalAccountRepository extends JpaRepository<StorageExternalAccount, UUID> {

    /**
     * 按创建时间倒序查询指定用户的外部存储账户。
     *
     * @param ownerUserId 所有者用户标识
     * @return 外部存储账户列表
     */
    List<StorageExternalAccount> findByOwnerUserIdOrderByCreatedAtDesc(UUID ownerUserId);

    /**
     * 查询指定用户拥有的外部存储账户。
     *
     * @param id 账户标识
     * @param ownerUserId 所有者用户标识
     * @return 外部存储账户
     */
    Optional<StorageExternalAccount> findByIdAndOwnerUserId(UUID id, UUID ownerUserId);

    /**
     * 按更新时间倒序查询全部外部存储账户。
     *
     * @return 外部存储账户列表
     */
    List<StorageExternalAccount> findAllByOrderByUpdatedAtDesc();
}
