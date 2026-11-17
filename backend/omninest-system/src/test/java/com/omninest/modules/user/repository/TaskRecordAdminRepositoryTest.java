package com.omninest.modules.user.repository;

import static org.assertj.core.api.Assertions.assertThat;

import jakarta.persistence.EntityManager;
import jakarta.persistence.Query;
import java.util.List;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentMatchers;
import org.mockito.Mockito;

/**
 * 后台任务管理仓库单元测试。
 *
 * @author OmniNest
 */
class TaskRecordAdminRepositoryTest {
    private final EntityManager entityManager = Mockito.mock(EntityManager.class);
    private final Query query = Mockito.mock(Query.class);
    private final TaskRecordAdminRepository repository = new TaskRecordAdminRepository(entityManager);

    @BeforeEach
    void setUp() {
        Mockito.when(entityManager.createNativeQuery(ArgumentMatchers.anyString())).thenReturn(query);
        Mockito.when(query.setMaxResults(ArgumentMatchers.anyInt())).thenReturn(query);
        Mockito.when(query.getResultList()).thenReturn(List.of());
    }

    @Test
    void findRecentAppliesRequestedLimit() {
        repository.findRecent(100);

        Mockito.verify(query).setMaxResults(100);
    }

    @Test
    void findRecentCapsExcessiveLimit() {
        repository.findRecent(1_000);

        Mockito.verify(query).setMaxResults(500);
    }

    @Test
    void findPageAppliesOffsetLimitAndReturnsCount() {
        Query countQuery = Mockito.mock(Query.class);
        Mockito.when(entityManager.createNativeQuery(ArgumentMatchers.anyString()))
                .thenReturn(query, countQuery);
        Mockito.when(query.setFirstResult(ArgumentMatchers.anyInt())).thenReturn(query);
        Mockito.when(countQuery.getSingleResult()).thenReturn(10L);

        TaskRecordAdminRepository.TaskPage result = repository.findPage(
                2,
                25,
                "FAILED",
                "FILE_INDEX",
                "%index%",
                "updated_at",
                false
        );

        Mockito.verify(query).setFirstResult(50);
        Mockito.verify(query).setMaxResults(25);
        Mockito.verify(query).setParameter("status", "FAILED");
        Mockito.verify(countQuery).setParameter("taskType", "FILE_INDEX");
        Mockito.verify(countQuery).setParameter("searchPattern", "%index%");
        assertThat(result.totalElements()).isEqualTo(10);
    }
}
