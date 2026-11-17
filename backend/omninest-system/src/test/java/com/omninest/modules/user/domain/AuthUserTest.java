package com.omninest.modules.user.domain;

import static org.assertj.core.api.Assertions.assertThat;

import jakarta.persistence.Table;
import org.junit.jupiter.api.Test;

class AuthUserTest {
    @Test
    void mapsToAuthUsersTable() {
        Table table = AuthUser.class.getAnnotation(Table.class);

        assertThat(table).isNotNull();
        assertThat(table.schema()).isEqualTo("omni");
        assertThat(table.name()).isEqualTo("auth_users");
    }
}
