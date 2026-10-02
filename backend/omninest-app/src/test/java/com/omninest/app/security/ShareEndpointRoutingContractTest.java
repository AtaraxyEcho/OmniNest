package com.omninest.app.security;

import static org.assertj.core.api.Assertions.assertThat;

import com.omninest.modules.file.controller.FileController;
import java.lang.reflect.Method;
import java.util.List;
import java.util.Set;
import java.util.TreeSet;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestMapping;

/**
 * 分享端点路由契约测试。
 *
 * <p>公开过滤链（SecurityConfig.publicContentFilterChain）以显式枚举匹配匿名分享端点：
 * 单段 token、{@code /authorize}、{@code /preview}；{@code /accept} 因需要登录用户
 * 身份必须留在鉴权链。本测试锁定 /api/v1/s/ 下的全部子路径集合——新增分享子端点时
 * 必须同步更新公开链枚举与本契约，防止新端点被默认吞进错误的链。
 *
 * @author OmniNest
 */
class ShareEndpointRoutingContractTest {

    @Test
    @DisplayName("FileController 的分享子路径集合保持已知四项")
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
        // ""（单段 token 预览）、"/authorize"、"/preview" 属公开链；"/accept" 必须经鉴权链
        assertThat(subPaths).containsExactly("", "/accept", "/authorize", "/preview");
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
