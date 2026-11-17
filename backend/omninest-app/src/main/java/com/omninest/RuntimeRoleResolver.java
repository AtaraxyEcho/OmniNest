package com.omninest;

import com.omninest.common.runtime.RuntimeRole;
import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.Optional;
import java.util.stream.Stream;

/**
 * 解析应用启动前必须确定的运行角色。
 *
 * <p>优先级与 Spring 配置约定一致：JVM 系统属性、进程环境变量、当前工作目录的 `.env`，最后使用 API。
 *
 * @author OmniNest
 */
final class RuntimeRoleResolver {

    private static final String ROLE_KEY = "OMNINEST_ROLE";

    private RuntimeRoleResolver() {
    }

    /**
     * 读取当前进程的运行角色。
     *
     * @return 运行角色
     */
    static RuntimeRole resolve() {
        return resolve(
                System.getProperty("omninest.runtime.role"),
                System.getenv(ROLE_KEY),
                Path.of(".env")
        );
    }

    static RuntimeRole resolve(String systemProperty, String environmentValue, Path dotenvPath) {
        return firstPresent(systemProperty)
                .or(() -> firstPresent(environmentValue))
                .or(() -> readDotenvValue(dotenvPath))
                .map(RuntimeRole::from)
                .orElse(RuntimeRole.API);
    }

    private static Optional<String> firstPresent(String value) {
        if (value == null || value.isBlank()) {
            return Optional.empty();
        }
        return Optional.of(value.trim());
    }

    private static Optional<String> readDotenvValue(Path dotenvPath) {
        if (!Files.isRegularFile(dotenvPath)) {
            return Optional.empty();
        }
        try (Stream<String> lines = Files.lines(dotenvPath, StandardCharsets.UTF_8)) {
            return lines.map(String::trim)
                    .filter(line -> !line.isEmpty() && !line.startsWith("#"))
                    .map(RuntimeRoleResolver::removeExportPrefix)
                    .filter(line -> line.startsWith(ROLE_KEY + "="))
                    .map(line -> unquote(line.substring(ROLE_KEY.length() + 1).trim()))
                    .filter(value -> !value.isBlank())
                    .findFirst();
        } catch (IOException exception) {
            throw new IllegalStateException("无法读取后端 .env 文件", exception);
        }
    }

    private static String removeExportPrefix(String line) {
        if (line.startsWith("export ")) {
            return line.substring("export ".length()).trim();
        }
        return line;
    }

    private static String unquote(String value) {
        if (value.length() >= 2
                && ((value.startsWith("\"") && value.endsWith("\""))
                || (value.startsWith("'") && value.endsWith("'")))) {
            return value.substring(1, value.length() - 1).trim();
        }
        // 未加引号的值允许行尾注释（OMNINEST_ROLE=worker # 后台角色），
        // 只有空白后的 # 才算注释起点，避免误伤值内的 #。
        for (int index = 1; index < value.length(); index++) {
            if (value.charAt(index) == '#' && Character.isWhitespace(value.charAt(index - 1))) {
                return value.substring(0, index).trim();
            }
        }
        return value;
    }
}
