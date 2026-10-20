package com.omninest.common.user;

import java.util.Collection;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.UUID;

/**
 * 用户账户跨模块只读查询端口。
 *
 * @author OmniNest
 */
public interface UserAccountQuery {

    /**
     * 查询用户账户摘要。
     *
     * @param userId 用户 ID
     * @return 用户摘要，不存在时返回空
     */
    Optional<UserAccountSummary> findById(UUID userId);

    /**
     * 查询用户账户详情。
     *
     * @param userId 用户 ID
     * @return 用户详情，不存在时返回空
     */
    Optional<UserAccountDetails> findDetailsById(UUID userId);

    /**
     * 查询单个用户名。
     *
     * @param userId 用户 ID
     * @return 用户名，不存在时返回空
     */
    Optional<String> findUsername(UUID userId);

    /**
     * 查询可用于外部投递的邮箱：仅当账户处于启用状态且邮箱非空时返回。
     *
     * <p>账户状态归认证模块所有，外部通道不应为了判断"这个账户还能不能用"而反向依赖它，
     * 因此判定放在这里，调用方只拿到可投递或不可投递两种结果。</p>
     *
     * @param userId 用户 ID
     * @return 可投递邮箱，账户停用、删除或未填邮箱时返回空
     */
    Optional<String> findDeliverableEmail(UUID userId);

    /**
     * 批量查询用户名。
     *
     * @param userIds 用户 ID 集合
     * @return 以用户 ID 为键的用户名映射
     */
    Map<UUID, String> findUsernames(Collection<UUID> userIds);

    /**
     * 按用户标识游标查询一批账户标识。
     *
     * @param exclusiveCursor 排他游标，首次查询传 null
     * @param limit 最大返回数量
     * @return 按用户标识升序排列的账户标识
     */
    List<UUID> findIdsAfter(UUID exclusiveCursor, int limit);
}
