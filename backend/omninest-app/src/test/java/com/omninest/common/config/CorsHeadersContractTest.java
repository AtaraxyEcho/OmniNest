package com.omninest.common.config;

import static org.assertj.core.api.Assertions.assertThat;

import java.io.IOException;
import java.lang.reflect.Method;
import java.lang.reflect.Parameter;
import java.util.Locale;
import java.util.Set;
import java.util.TreeSet;
import org.junit.jupiter.api.Test;
import org.springframework.core.io.Resource;
import org.springframework.core.io.support.PathMatchingResourcePatternResolver;
import org.springframework.core.type.AnnotationMetadata;
import org.springframework.core.type.classreading.MetadataReader;
import org.springframework.core.type.classreading.SimpleMetadataReaderFactory;
import org.springframework.web.bind.annotation.RequestHeader;

/**
 * CORS 请求头白名单契约测试。
 *
 * 扫描全部后端控制器方法参数上的 @RequestHeader 消费点，断言每个非
 * CORS 简单头都已登记进 {@link CorsConfig#ALLOWED_HEADERS}。新增自定义
 * 请求头但遗漏 CORS 白名单时（浏览器跨源预检被拒、前端表现为
 * NETWORK_ERROR 的事故形态）本测试直接失败，防止配置漂移静默回归。
 *
 * 局限：只覆盖注解式消费；前端可能发送而后端不读取的头不在本契约内，
 * 需要前端侧约束。
 */
class CorsHeadersContractTest {

    /** CORS 简单头：浏览器预检豁免，无需进入白名单。 */
    private static final Set<String> CORS_SAFE_HEADERS = Set.of(
            "accept",
            "accept-language",
            "content-language",
            "content-type"
    );

    private int controllerCount;

    @Test
    void allControllerConsumedHeadersAreWhitelistedForCors() throws IOException {
        Set<String> consumed = collectRequestHeaderNames();
        // 反空转守卫：扫描必须命中已知消费点，防止资源解析整体失败时契约静默通过。
        assertThat(consumed)
                .as("controllers=%d", controllerCount)
                .contains("X-OmniNest-Share-Session");

        // 统一小写比较：TreeSet#removeAll 在集合较小时退化为 List#contains
        // 的大小写敏感匹配，混合大小写会漏删。
        Set<String> unlisted = new TreeSet<>(
                consumed.stream().map(header -> header.toLowerCase(Locale.ROOT)).toList()
        );
        unlisted.removeAll(CORS_SAFE_HEADERS);
        unlisted.removeAll(
                CorsConfig.ALLOWED_HEADERS.stream()
                        .map(header -> header.toLowerCase(Locale.ROOT))
                        .toList()
        );
        assertThat(unlisted)
                .as("控制器消费但未登记进 CorsConfig.ALLOWED_HEADERS 的请求头")
                .isEmpty();
    }

    /**
     * 收集类路径上全部控制器经 @RequestHeader 消费的请求头名。
     *
     * 两段式：字节码元数据阶段无加载成本地筛出控制器类名；反射阶段仅加载
     * 控制器读取方法参数注解。@RequestHeader 是参数注解，不在方法级元数据
     * 中，只能经反射获取；注解中的常量引用在运行期已解析为字面量。
     */
    private Set<String> collectRequestHeaderNames() throws IOException {
        Set<String> controllerNames = new TreeSet<>();
        PathMatchingResourcePatternResolver resolver = new PathMatchingResourcePatternResolver();
        SimpleMetadataReaderFactory readerFactory = new SimpleMetadataReaderFactory();
        for (Resource resource : resolver.getResources("classpath*:com/omninest/**/*.class")) {
            if (!resource.isReadable()) {
                continue;
            }
            MetadataReader reader;
            try {
                reader = readerFactory.getMetadataReader(resource);
            } catch (IOException error) {
                continue;
            }
            AnnotationMetadata metadata = reader.getAnnotationMetadata();
            if (metadata.isAnnotated("org.springframework.web.bind.annotation.RestController")
                    || metadata.isAnnotated("org.springframework.stereotype.Controller")) {
                controllerNames.add(metadata.getClassName());
            }
        }
        controllerCount = controllerNames.size();
        return readControllerRequestHeaders(controllerNames);
    }

    private Set<String> readControllerRequestHeaders(Set<String> controllerNames) {
        Set<String> names = new TreeSet<>(String.CASE_INSENSITIVE_ORDER);
        ClassLoader loader = Thread.currentThread().getContextClassLoader();
        for (String className : controllerNames) {
            Class<?> type;
            try {
                type = Class.forName(className, false, loader);
            } catch (ClassNotFoundException error) {
                continue;
            }
            for (Method method : type.getDeclaredMethods()) {
                for (Parameter parameter : method.getParameters()) {
                    RequestHeader header = parameter.getAnnotation(RequestHeader.class);
                    if (header == null) {
                        continue;
                    }
                    String name = header.value().isBlank() ? header.name() : header.value();
                    if (!name.isBlank()) {
                        names.add(name);
                    }
                }
            }
        }
        return names;
    }
}
