package com.omninest.modules.file.repository;

import com.omninest.modules.file.domain.StorageConnectorOAuthApp;
import java.util.Optional;
import java.util.UUID;
import org.springframework.data.jpa.repository.JpaRepository;

/**
 * 连接器 OAuth 应用仓库。
 *
 * @author OmniNest
 */
public interface StorageConnectorOAuthAppRepository extends JpaRepository<StorageConnectorOAuthApp, UUID> {

    Optional<StorageConnectorOAuthApp> findFirstByConnectorCodeAndEnabledTrue(String connectorCode);
}
