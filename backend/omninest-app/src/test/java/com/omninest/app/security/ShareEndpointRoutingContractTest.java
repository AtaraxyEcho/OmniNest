package com.omninest.app.security;

import static org.assertj.core.api.Assertions.assertThat;

import com.omninest.modules.file.controller.FileController;
import java.io.IOException;
import java.lang.reflect.Method;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.List;
import java.util.Set;
import java.util.TreeSet;
import java.util.regex.Matcher;
import java.util.regex.Pattern;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestMapping;

/**
 * 分享端点路由契约测试。
 *
 * <p>公开过滤链（SecurityConfig.publicContentFilterChain）以显式枚举匹配匿名分享端点：
 * 单段 token、{@code /authorize}、{@code /preview}、{@code /children}；{@code /accept}
 * 因需要登录用户身份必须留在鉴权链。本测试锁定 /api/v1/s/ 下的全部子路径集合——新增分享子端点时
 * 必须同步更新公开链枚举与本契约，防止新端点被默认吞进错误的链。
 *
 * @author OmniNest
 */
class ShareEndpointRoutingContractTest {

    private static final String SECURITY_CONFIG_SOURCE =
            "omninest-infrastructure/src/main/java/com/omninest/common/security/SecurityConfig.java";
    private static final Pattern SHARE_PATH_LITERAL = Pattern.compile("\"(/api/v1/s/[^\"]*)\"");

    @Test
    @DisplayName("FileController 的分享子路径集合保持已知五项")
    void shareSubRoutesAreTheKnownSet() {
        Set<String> subPaths = new TreeSet<>();
        for (Method method : FileController.class.getDeclaredMethods()) {
            for (String path : mappingPaths(method)) {
                if (path.startsWith("/api/v1/s/")) {
                    subPaths.add(path.substring("/api/v1/s/".length())
                            .replace("{token}", ""));
                }
            }
        }
        // ""（单段 token 预览）、"/authorize"、"/preview"、"/children" 属公开链；"/accept" 必须经鉴权链
        assertThat(subPaths).containsExactly("", "/accept", "/authorize", "/children", "/preview");
    }

    /**
     * 公开链枚举与控制器匿名分享路由必须一一对应。
     *
     * <p>只锁控制器路由集是不够的：新端点加了控制器却没加进 {@code securityMatcher}，
     * 它会静默落进主鉴权链，对未登录访客永远 401——用例照样绿。本契约把两边集合直接对齐，
     * 并把 {@code /accept} 反向钉成"不得出现在公开链"。</p>
     */
    @Test
    @DisplayName("匿名分享路由与公开过滤链枚举逐项一致")
    void anonymousShareRoutesMatchThePublicFilterChain() throws IOException {
        Set<String> anonymousRoutes = shareRoutes().stream()
                .filter(path -> !path.endsWith("/accept"))
                .collect(java.util.stream.Collectors.toCollection(TreeSet::new));
        Set<String> chainRoutes = publicChainShareRoutes();

        assertThat(chainRoutes).containsExactlyElementsOf(anonymousRoutes);
        assertThat(chainRoutes).doesNotContain("/api/v1/s/*/accept");
    }

    private static Set<String> shareRoutes() {
        Set<String> paths = new TreeSet<>();
        for (Method method : FileController.class.getDeclaredMethods()) {
            for (String path : mappingPaths(method)) {
                if (path.startsWith("/api/v1/s/")) {
                    paths.add(path.replace("{token}", "*"));
                }
            }
        }
        return paths;
    }

    private static Set<String> publicChainShareRoutes() throws IOException {
        Path source = findBackendRoot().resolve(SECURITY_CONFIG_SOURCE);
        assertThat(source).as("公开过滤链源文件必须存在，否则本契约失去意义").isRegularFile();
        Set<String> literals = new TreeSet<>();
        Matcher matcher = SHARE_PATH_LITERAL.matcher(Files.readString(source));
        while (matcher.find()) {
            literals.add(matcher.group(1));
        }
        return literals;
    }

    private static Path findBackendRoot() {
        Path current = Path.of("").toAbsolutePath();
        while (current != null) {
            if (Files.isDirectory(current.resolve("omninest-file"))
                    && Files.isRegularFile(current.resolve("pom.xml"))) {
                return current;
            }
            current = current.getParent();
        }
        throw new IllegalStateException("未找到 backend 根目录");
    }

    private static Set<String> mappingPaths(Method method) {
        Set<String> paths = new TreeSet<>();
        RequestMapping requestMapping = method.getAnnotation(RequestMapping.class);
        if (requestMapping != null) {
            paths.addAll(List.of(requestMapping.value()));
        }
        GetMapping getMapping = method.getAnnotation(GetMapping.class);
        if (getMapping != null) {
            paths.addAll(List.of(getMapping.value()));
        }
        PostMapping postMapping = method.getAnnotation(PostMapping.class);
        if (postMapping != null) {
            paths.addAll(List.of(postMapping.value()));
        }
        return paths;
    }
}
