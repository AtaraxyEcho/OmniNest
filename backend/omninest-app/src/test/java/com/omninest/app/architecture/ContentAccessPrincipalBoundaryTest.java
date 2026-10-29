package com.omninest.app.architecture;

import static org.junit.jupiter.api.Assertions.assertTrue;

import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.List;
import java.util.Set;
import java.util.regex.Pattern;
import java.util.stream.Stream;
import org.junit.jupiter.api.Test;

/**
 * 内容访问请求主体的铸造边界。
 *
 * <p>下载与原片播放的能力判定必须针对出示凭证的一方。只要请求主体还能从任意
 * 用户 ID 构造，"把 {@code item.getOwnerUserId()} 当请求者"就会重新变得可写：
 * 本测试把两类铸造入口钉死——会话主体只允许 {@code CurrentUserContext} 产生，
 * 凭证主体只允许持有真实凭证的解析点还原。</p>
 *
 * @author OmniNest
 */
class ContentAccessPrincipalBoundaryTest {

    /** 允许把已验证凭证还原为请求主体的位置；新增一项等于声明"这里持有真实凭证"。 */
    private static final Set<String> CREDENTIAL_MINT_ALLOWLIST = Set.of(
            "omninest-media/src/main/java/com/omninest/modules/music/service/MusicStreamGatewayService.java"
    );

    /** 会话主体只能在安全包内产生，业务模块不得自行铸造。 */
    private static final Set<String> AUTHENTICATED_MINT_ALLOWLIST = Set.of(
            "omninest-common/src/main/java/com/omninest/common/security/CurrentUserContext.java",
            "omninest-common/src/main/java/com/omninest/common/security/RequestPrincipal.java"
    );

    private static final Pattern CREDENTIAL_MINT_PATTERN =
            Pattern.compile("RequestPrincipal\\s*\\.\\s*credential\\s*\\(");
    private static final Pattern AUTHENTICATED_MINT_PATTERN =
            Pattern.compile("RequestPrincipal\\s*\\.\\s*authenticated\\s*\\(");
    private static final Pattern OWNER_SCOPED_SIGN_PATTERN =
            Pattern.compile("createDownloadUrl(s)?As\\s*\\(");

    @Test
    void credentialPrincipalsComeOnlyFromValidatedCredentials() throws IOException {
        List<String> violations = new ArrayList<>();
        for (Path source : productionSources().toList()) {
            String relative = relativePath(source);
            String content = Files.readString(source);
            if (CREDENTIAL_MINT_PATTERN.matcher(content).find()
                    && !CREDENTIAL_MINT_ALLOWLIST.contains(relative)) {
                violations.add("CREDENTIAL_PRINCIPAL_MINT " + relative);
            }
            if (AUTHENTICATED_MINT_PATTERN.matcher(content).find()
                    && !AUTHENTICATED_MINT_ALLOWLIST.contains(relative)) {
                violations.add("SESSION_PRINCIPAL_MINT " + relative);
            }
        }
        assertTrue(violations.isEmpty(),
                "请求主体只能由会话上下文或已登记凭证解析点产生，违规: " + violations);
    }

    @Test
    void downloadUrlsAreNotIssuedAsAnotherUserFromControllers() throws IOException {
        List<String> violations = new ArrayList<>();
        for (Path source : productionSources().toList()) {
            String relative = relativePath(source);
            if (relative.contains("/controller/")
                    && OWNER_SCOPED_SIGN_PATTERN.matcher(Files.readString(source)).find()) {
                violations.add("CONTROLLER_OWNER_SCOPED_DOWNLOAD_URL " + relative);
            }
        }
        assertTrue(violations.isEmpty(),
                "控制器必须按当前请求者签发下载地址，禁止以其他用户身份签发: " + violations);
    }

    private Stream<Path> productionSources() throws IOException {
        Path backendRoot = findBackendRoot();
        List<Path> sources = new ArrayList<>();
        try (Stream<Path> moduleDirs = Files.list(backendRoot)) {
            for (Path moduleDir : moduleDirs.filter(Files::isDirectory).toList()) {
                Path sourceRoot = moduleDir.resolve("src/main/java");
                if (!Files.isDirectory(sourceRoot)) {
                    continue;
                }
                try (Stream<Path> files = Files.walk(sourceRoot)) {
                    sources.addAll(files
                            .filter(path -> path.getFileName().toString().endsWith(".java"))
                            .toList());
                }
            }
        }
        return sources.stream();
    }

    private String relativePath(Path source) {
        return normalize(findBackendRoot().relativize(source));
    }

    private String normalize(Path path) {
        return path.toString().replace('\\', '/');
    }

    private Path findBackendRoot() {
        Path current = Path.of("").toAbsolutePath();
        while (current != null) {
            if (Files.isDirectory(current.resolve("omninest-app"))
                    && Files.isDirectory(current.resolve("omninest-common"))) {
                return current;
            }
            current = current.getParent();
        }
        throw new IllegalStateException("无法定位后端仓库根目录");
    }
}
