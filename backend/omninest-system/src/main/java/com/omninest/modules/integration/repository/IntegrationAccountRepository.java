package com.omninest.modules.integration.repository;

import com.omninest.modules.integration.domain.IntegrationAccount;
import java.util.Optional;
import java.util.UUID;
import org.springframework.data.jpa.repository.JpaRepository;

/**
 * 外部集成账号仓储。
 *
 * @author OmniNest
 */
public interface IntegrationAccountRepository extends JpaRepository<IntegrationAccount, UUID> {

    /**
     * 按用户、集成类型和提供者查询账号。
     *
     * @param ownerUserId 所属用户 ID
     * @param integrationType 集成类型
     * @param provider 提供者
     * @return 匹配账号
     */
    Optional<IntegrationAccount> findByOwnerUserIdAndIntegrationTypeAndProvider(
            UUID ownerUserId,
            String integrationType,
            String provider
    );
}
