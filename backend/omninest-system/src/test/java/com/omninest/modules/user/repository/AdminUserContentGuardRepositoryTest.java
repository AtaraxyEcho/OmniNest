package com.omninest.modules.user.repository;

import static org.assertj.core.api.Assertions.assertThat;

import jakarta.persistence.EntityManager;
import jakarta.persistence.Query;
import java.util.UUID;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentMatchers;
import org.mockito.Mockito;

/**
 * 管理端用户内容占用核查仓库单元测试。
 *
 * <p>重点锁定投影列与内容标签的按位对应关系，防止 SQL 追加列后标签错位。</p>
 */
class AdminUserContentGuardRepositoryTest {
    private final EntityManager entityManager = Mockito.mock(EntityManager.class);
    private final Query query = Mockito.mock(Query.class);
    private final AdminUserContentGuardRepository repository = new AdminUserContentGuardRepository(entityManager);

    @BeforeEach
    void setUp() {
        Mockito.when(entityManager.createNativeQuery(ArgumentMatchers.anyString())).thenReturn(query);
        Mockito.when(query.setParameter(ArgumentMatchers.anyString(), ArgumentMatchers.any()))
                .thenReturn(query);
    }

    @Test
    void countOwnedContentReturnsOnlyPositiveColumnsWithLabels() {
        UUID userId = UUID.fromString("10000000-0000-0000-0000-000000000001");
        Mockito.when(query.getSingleResult()).thenReturn(new Object[]{
                2L, 0L, 0L, 1L, 0L, 0L, 0L, 0L, 0L, 0L, 0L, 0L
        });

        var owned = repository.countOwnedContent(userId);

        assertThat(owned).containsOnlyKeys("文件", "阅读库");
        assertThat(owned).containsEntry("文件", 2L).containsEntry("阅读库", 1L);
        Mockito.verify(query).setParameter("userId", userId);
    }

    @Test
    void countOwnedContentReturnsEmptyMapForEmptyAccount() {
        Mockito.when(query.getSingleResult()).thenReturn(new Object[]{
                0L, 0L, 0L, 0L, 0L, 0L, 0L, 0L, 0L, 0L, 0L, 0L
        });

        assertThat(repository.countOwnedContent(UUID.randomUUID())).isEmpty();
    }
}
