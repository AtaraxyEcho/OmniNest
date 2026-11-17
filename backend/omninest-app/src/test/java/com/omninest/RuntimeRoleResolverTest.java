package com.omninest;

import static org.assertj.core.api.Assertions.assertThat;

import com.omninest.common.runtime.RuntimeRole;
import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import org.junit.jupiter.api.Test;

/**
 * 验证启动阶段运行角色的配置优先级和 `.env` 读取行为。
 *
 * @author OmniNest
 */
class RuntimeRoleResolverTest {

    @Test
    void systemPropertyHasHighestPriority() throws IOException {
        Path dotenv = writeDotenv("OMNINEST_ROLE=scheduler");

        assertThat(RuntimeRoleResolver.resolve("worker", "api", dotenv))
                .isEqualTo(RuntimeRole.WORKER);
    }

    @Test
    void environmentValueHasPriorityOverDotenv() throws IOException {
        Path dotenv = writeDotenv("OMNINEST_ROLE=scheduler");

        assertThat(RuntimeRoleResolver.resolve(null, "worker", dotenv))
                .isEqualTo(RuntimeRole.WORKER);
    }

    @Test
    void dotenvSupportsExportAndQuotedValue() throws IOException {
        Path dotenv = writeDotenv("export OMNINEST_ROLE=\"scheduler\"");

        assertThat(RuntimeRoleResolver.resolve(null, null, dotenv))
                .isEqualTo(RuntimeRole.SCHEDULER);
    }

    @Test
    void missingValuesDefaultToApi() {
        assertThat(RuntimeRoleResolver.resolve(null, null, Path.of("missing.env")))
                .isEqualTo(RuntimeRole.API);
    }

    private Path writeDotenv(String content) throws IOException {
        Path dotenv = Files.createTempFile("omninest-role", ".env");
        Files.writeString(dotenv, content, StandardCharsets.UTF_8);
        return dotenv;
    }
}
