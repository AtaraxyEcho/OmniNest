package com.omninest.modules.user.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import com.omninest.modules.user.repository.AuthUserRepository;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentMatchers;

/**
 * 用户存储写入服务测试。
 *
 * @author OmniNest
 */
class UserStorageCommandServiceTest {

    private static final UUID USER_ID = UUID.fromString("10000000-0000-0000-0000-000000000001");

    private final AuthUserRepository authUserRepository = mock(AuthUserRepository.class);
    private final UserStorageCommandService service = new UserStorageCommandService(authUserRepository);

    /**
     * 验证减少用量时不会产生负数。
     */
    @Test
    void decrementUsageClampsToZero() {
        when(authUserRepository.decrementUsageAtomic(USER_ID, 200)).thenReturn(1);

        service.decrementUsage(USER_ID, 200);

        verify(authUserRepository).decrementUsageAtomic(USER_ID, 200);
    }

    /**
     * 对账只按列写回发生变化的用户：整实体 saveAll 会把对账窗口内的并发改密/改昵称一起覆盖，
     * 并让单个乐观锁冲突拖垮整批事务。
     */
    @Test
    void reconcileUsageUpdatesOnlyChangedUsersColumn() {
        UUID unchangedId = UUID.fromString("10000000-0000-0000-0000-000000000002");
        when(authUserRepository.reconcileUsedBytes(USER_ID, 300L)).thenReturn(1);
        when(authUserRepository.reconcileUsedBytes(unchangedId, 50L)).thenReturn(0);

        List<UUID> result = service.reconcileUsage(Map.of(USER_ID, 300L, unchangedId, 50L));

        assertThat(result).containsExactly(USER_ID);
        verify(authUserRepository).reconcileUsedBytes(USER_ID, 300L);
        verify(authUserRepository).reconcileUsedBytes(unchangedId, 50L);
        verify(authUserRepository, never()).saveAll(ArgumentMatchers.anyCollection());
    }

    @Test
    void reconcileUsageTreatsMissingAggregateAsZero() {
        // 聚合缺失（用户已全部删除）必须写 0 而不是跳过，否则残留用量永久占着配额。
        Map<UUID, Long> actualUsage = new HashMap<>();
        actualUsage.put(USER_ID, null);
        when(authUserRepository.reconcileUsedBytes(USER_ID, 0L)).thenReturn(1);

        List<UUID> result = service.reconcileUsage(actualUsage);

        assertThat(result).containsExactly(USER_ID);
        verify(authUserRepository).reconcileUsedBytes(USER_ID, 0L);
    }
}
