package com.omninest.modules.user.service;

import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.times;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import com.omninest.modules.user.domain.AuthUser;
import com.omninest.modules.user.domain.UserStatus;
import com.omninest.modules.user.repository.AuthUserRepository;
import java.util.List;
import org.junit.jupiter.api.Test;
import org.springframework.data.domain.PageImpl;
import org.springframework.data.domain.Pageable;

/**
 * 用户候选目录查询服务测试。
 *
 * <p>钉住搜索词在进入 LIKE 谓词前按字面量转义：这个入口是管理端的成员候选输入框，
 * 未转义时输入 {@code %} 或 {@code _} 会把条件放宽成近似全表模糊扫描。</p>
 *
 * @author OmniNest
 */
class UserDirectoryQueryServiceTest {

    private final AuthUserRepository userRepository = mock(AuthUserRepository.class);
    private final UserDirectoryQueryService service = new UserDirectoryQueryService(userRepository);

    @Test
    void escapesLikeWildcardsBeforeReachingTheQuery() {
        when(userRepository.searchByStatus(any(), any(), any(Pageable.class)))
                .thenReturn(new PageImpl<>(List.<AuthUser>of()));

        service.findActiveUsers(" 100% _X ", 0, 20);

        // 小写归一在转义之前，转义后的反斜杠不能被 lower() 影响。
        verify(userRepository).searchByStatus(
                eq(UserStatus.ACTIVE.getValue()),
                eq("100\\% \\_x"),
                any(Pageable.class)
        );
    }

    @Test
    void keepsTheEmptyKeywordEmptySoThePredicateShortCircuitStillApplies() {
        when(userRepository.searchByStatus(any(), any(), any(Pageable.class)))
                .thenReturn(new PageImpl<>(List.<AuthUser>of()));

        service.findActiveUsers(null, 0, 20);
        service.findActiveUsers("   ", 0, 20);

        verify(userRepository, times(2)).searchByStatus(
                eq(UserStatus.ACTIVE.getValue()),
                eq(""),
                any(Pageable.class)
        );
    }
}
