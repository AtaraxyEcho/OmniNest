package com.omninest.app.architecture;

import static org.assertj.core.api.Assertions.assertThat;

import com.omninest.common.config.SecurityProperties;
import java.io.IOException;
import java.io.InputStream;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.regex.Matcher;
import java.util.regex.Pattern;
import org.junit.jupiter.api.Test;

/**
 * 浏览器安全响应头策略的一致性测试。
 *
 * <p>同一条 CSP 存在四份副本（后端配置默认值、{@code application.yml}、nginx 两个模板），
 * 任一处单独改动都会造成只在某一环境暴露的失效：dev 由后端下发、prod 由 nginx 覆盖，
 * 而这类差异在功能上表现为"只在生产坏掉"。pdfrx 的 pdfium Worker 被 CSP 拦死就是这么来的。</p>
 *
 * @author OmniNest
 */
class SecurityHeaderPolicyConsistencyTest {

    private static final Pattern YML_POLICY = Pattern.compile(
            "content-security-policy:\\s*\"([^\"]+)\"");

    private static final Pattern NGINX_POLICY = Pattern.compile(
            "add_header\\s+Content-Security-Policy\\s+\"([^\"]+)\"");

    @Test
    void cspCopiesMustStayIdenticalAndAllowBlobWorkers() throws IOException {
        String javaDefault = normalize(new SecurityProperties().getContentSecurityPolicy());
        String applicationYml = normalize(extract(YML_POLICY, readClasspath("application.yml")));
        String httpTemplate = normalize(extract(NGINX_POLICY, readTemplate("http.conf.template")));
        String httpsTemplate = normalize(extract(NGINX_POLICY, readTemplate("https.conf.template")));

        assertThat(applicationYml).isEqualTo(javaDefault);
        assertThat(httpTemplate).isEqualTo(javaDefault);
        assertThat(httpsTemplate).isEqualTo(javaDefault);
        // pdfrx 的 pdfium 客户端从 blob URL 创建 Worker：worker-src 缺失会回落 script-src 并拦截，
        // 表现为 PDF 预览区空白且加载不报错，因此这条是功能必需项而非可选放宽。
        assertThat(javaDefault).contains("worker-src 'self' blob:");
    }

    private String readClasspath(String resourceName) throws IOException {
        try (InputStream input = getClass().getClassLoader().getResourceAsStream(resourceName)) {
            if (input == null) {
                throw new IllegalStateException("缺少类路径资源: " + resourceName);
            }
            return new String(input.readAllBytes(), StandardCharsets.UTF_8);
        }
    }

    private String readTemplate(String fileName) throws IOException {
        Path root = Path.of("").toAbsolutePath();
        while (root != null && !Files.isDirectory(root.resolve("deploy"))) {
            root = root.getParent();
        }
        if (root == null) {
            throw new IllegalStateException("无法定位仓库根目录");
        }
        return Files.readString(
                root.resolve("deploy/prod/nginx/templates").resolve(fileName), StandardCharsets.UTF_8);
    }

    private String extract(Pattern pattern, String text) {
        Matcher matcher = pattern.matcher(text);
        if (!matcher.find()) {
            throw new IllegalStateException("未找到 Content-Security-Policy 定义");
        }
        return matcher.group(1);
    }

    private String normalize(String policy) {
        return policy.replaceAll("\\s+", " ").trim();
    }
}
