package com.omninest.modules.user.domain;

import static org.assertj.core.api.Assertions.assertThat;

import java.util.UUID;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

class AuthUserEqualsTest {

    @Test
    @DisplayName("两个不同 ID 的 AuthUser 不相等")
    void differentIdentitiesAreNotEqual() {
        AuthUser user1 = new AuthUser();
        user1.setId(UUID.randomUUID());

        AuthUser user2 = new AuthUser();
        user2.setId(UUID.randomUUID());

        assertThat(user1).isNotEqualTo(user2);
    }

    @Test
    @DisplayName("相同 ID 的 AuthUser 相等，即使其他字段不同")
    void sameIdentitiesAreEqualRegardlessOfOtherFields() {
        UUID id = UUID.randomUUID();

        AuthUser user1 = new AuthUser();
        user1.setId(id);
        user1.setUsername("alice");

        AuthUser user2 = new AuthUser();
        user2.setId(id);
        user2.setUsername("bob");

        assertThat(user1).isEqualTo(user2);
        assertThat(user1.hashCode()).isEqualTo(user2.hashCode());
    }
}
