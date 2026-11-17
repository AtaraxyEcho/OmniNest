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

    /**
     * 按连接器编码查询配置，不限制启用状态。
     *
     * <p>更新已禁用配置时必须命中存量行，否则会走 INSERT 撞唯一索引。</p>
     *
     * @param connectorCode 连接器编码
     * @return 配置记录
     */
    Optional<StorageConnectorOAuthApp> findFirstByConnectorCode(String connectorCode);
}
