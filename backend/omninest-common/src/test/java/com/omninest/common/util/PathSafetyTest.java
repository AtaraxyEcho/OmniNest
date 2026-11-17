package com.omninest.common.util;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import java.nio.file.Path;
import org.junit.jupiter.api.Test;

class PathSafetyTest {

    @Test
    void normalizesPathUnderBaseDirectory() {
        Path baseDirectory = Path.of("target", "path-safety").toAbsolutePath().normalize();

        Path resolved = PathSafety.normalizeUnderBase(baseDirectory, "users/alice/file.txt");

        assertThat(resolved).isEqualTo(baseDirectory.resolve("users/alice/file.txt").normalize());
    }

    @Test
    void rejectsPathTraversalOutsideBaseDirectory() {
        Path baseDirectory = Path.of("target", "path-safety").toAbsolutePath().normalize();

        assertThatThrownBy(() -> PathSafety.normalizeUnderBase(baseDirectory, "../etc/passwd"))
                .isInstanceOf(IllegalArgumentException.class)
                .hasMessageContaining("escapes base");
    }
}
