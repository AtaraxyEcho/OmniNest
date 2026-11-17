package com.omninest.common.runtime;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import org.junit.jupiter.api.Test;

/**
 * 验证运行角色配置解析行为。
 *
 * @author OmniNest
 */
class RuntimeRoleTest {

    @Test
    void from_blankValue_defaultsToApi() {
        assertThat(RuntimeRole.from(null)).isEqualTo(RuntimeRole.API);
        assertThat(RuntimeRole.from(" ")).isEqualTo(RuntimeRole.API);
    }

    @Test
    void from_isCaseInsensitive() {
        assertThat(RuntimeRole.from("worker")).isEqualTo(RuntimeRole.WORKER);
        assertThat(RuntimeRole.from("SCHEDULER")).isEqualTo(RuntimeRole.SCHEDULER);
    }

    @Test
    void from_unknownValue_rejectsConfiguration() {
        assertThatThrownBy(() -> RuntimeRole.from("combined"))
                .isInstanceOf(IllegalArgumentException.class)
                .hasMessageContaining("combined");
    }
}
