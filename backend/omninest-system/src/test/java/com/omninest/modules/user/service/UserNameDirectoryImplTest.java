package com.omninest.modules.user.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.Mockito.when;

import com.omninest.modules.user.domain.AuthUser;
import com.omninest.modules.user.repository.AuthUserRepository;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import org.junit.jupiter.api.Test;
import org.mockito.Mockito;

/**
 * 用户显示名端口实现测试：优先 displayName，为空回退 username，未知用户缺省。
 *
 * @author OmniNest
 */
class UserNameDirectoryImplTest {

    private final AuthUserRepository userRepository = Mockito.mock(AuthUserRepository.class);
    private final UserNameDirectoryImpl directory = new UserNameDirectoryImpl(userRepository);

    @Test
    void resolvesDisplayNameWithUsernameFallback() {
        UUID withName = UUID.fromString("10000000-0000-0000-0000-000000000001");
        UUID fallback = UUID.fromString("10000000-0000-0000-0000-000000000002");

        AuthUser named = new AuthUser();
        named.setId(withName);
        named.setUsername("alpha");
        named.setDisplayName("阿尔法");

        AuthUser unnamed = new AuthUser();
        unnamed.setId(fallback);
        unnamed.setUsername("beta");
        unnamed.setDisplayName("  ");

        when(userRepository.findAllById(List.of(withName, fallback)))
                .thenReturn(List.of(named, unnamed));

        Map<UUID, String> names = directory.resolveDisplayNames(List.of(withName, fallback));

        assertThat(names).containsEntry(withName, "阿尔法").containsEntry(fallback, "beta");
    }

    @Test
    void unknownUsersAreSilentlyOmitted() {
        UUID unknown = UUID.fromString("10000000-0000-0000-0000-000000000003");
        when(userRepository.findAllById(List.of(unknown))).thenReturn(List.of());

        assertThat(directory.resolveDisplayNames(List.of(unknown))).isEmpty();
        assertThat(directory.resolveDisplayNames(List.of())).isEmpty();
    }
}
