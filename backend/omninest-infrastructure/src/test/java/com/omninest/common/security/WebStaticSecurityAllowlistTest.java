package com.omninest.common.security;

import static org.assertj.core.api.Assertions.assertThat;

import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.regex.Matcher;
import java.util.regex.Pattern;
import org.junit.jupiter.api.Test;

/**
 * 校验托管 SPA 静态资源在 SecurityConfig 中匿名可达。
 *
 * <p>CSP 禁止 script-src unsafe-inline 后，web/js 与 web/css 必须 permitAll，
 * 否则脚本被 401 JSON 拦截并因 MIME 失败，页面无法启动。</p>
 *
 * @author OmniNest
 */
class WebStaticSecurityAllowlistTest {

    private static final Pattern PERMIT_ALL_LITERAL = Pattern.compile(
            "requestMatchers\\(([^)]*)\\)\\.permitAll\\(\\)",
            Pattern.DOTALL
    );

    @Test
    void securityConfigPermitsWebJsAndCss() throws IOException {
        Path config = resolveSecurityConfig();
        String source = Files.readString(config, StandardCharsets.UTF_8);
        Matcher matcher = PERMIT_ALL_LITERAL.matcher(source);
        StringBuilder permitted = new StringBuilder();
        while (matcher.find()) {
            permitted.append(matcher.group(1)).append('\n');
        }
        String block = permitted.toString();
        assertThat(block).contains("\"/js/**\"");
        assertThat(block).contains("\"/css/**\"");
        assertThat(block).contains("\"/flutter_bootstrap.js\"");
        assertThat(block).contains("\"/main.dart.js\"");
    }

    private Path resolveSecurityConfig() {
        Path current = Path.of("").toAbsolutePath();
        while (current != null) {
            Path candidate = current.resolve(
                    "omninest-infrastructure/src/main/java/com/omninest/common/security/SecurityConfig.java");
            if (Files.isRegularFile(candidate)) {
                return candidate;
            }
            current = current.getParent();
        }
        throw new IllegalStateException("未找到 SecurityConfig.java");
    }
}
