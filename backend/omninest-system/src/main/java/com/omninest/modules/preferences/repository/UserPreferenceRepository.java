package com.omninest.modules.preferences.repository;

import com.omninest.modules.preferences.domain.UserPreference;
import java.util.Optional;
import java.util.UUID;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Modifying;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

/**
 * 用户偏好持久化仓库。
 *
 * @author Notask Flow Team
 */
public interface UserPreferenceRepository extends JpaRepository<UserPreference, UUID> {
    /**
     * 按用户和作用域查询偏好。
     *
     * @param ownerUserId 用户 ID
     * @param scope 偏好作用域
     * @return 用户偏好
     */
    Optional<UserPreference> findByOwnerUserIdAndScope(UUID ownerUserId, String scope);

    /**
     * 删除用户全部偏好记录，供管理端物理删除空账户使用。
     *
     * @param userId 用户标识
     * @return 删除数量
     */
    @Modifying
    @Query("delete from UserPreference preference where preference.ownerUserId = :userId")
    int deleteByOwnerUserId(@Param("userId") UUID userId);
}
