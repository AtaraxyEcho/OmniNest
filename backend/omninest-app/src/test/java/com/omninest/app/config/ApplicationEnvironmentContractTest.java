package com.omninest.app.config;

import static org.assertj.core.api.Assertions.assertThat;

import java.io.IOException;
import java.io.InputStream;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.regex.Matcher;
import java.util.regex.Pattern;
import org.junit.jupiter.api.Test;
import org.springframework.boot.env.YamlPropertySourceLoader;
import org.springframework.core.env.MapPropertySource;
import org.springframework.core.env.PropertySource;
import org.springframework.core.env.StandardEnvironment;
import org.springframework.core.io.ClassPathResource;

/**
 * 确保 application 配置暴露的环境变量与最小模板保持一致。
 */
class ApplicationEnvironmentContractTest {
    private static final Pattern APPLICATION_VARIABLE = Pattern.compile("\\$\\{(OMNINEST_[A-Z0-9_]+)");
    private static final Pattern TEMPLATE_VARIABLE = Pattern.compile("^(OMNINEST_[A-Z0-9_]+)=", Pattern.MULTILINE);

    @Test
    void applicationEnvironmentVariablesMatchTemplateExactly() throws IOException {
        Set<String> applicationVariables = new LinkedHashSet<>();
        applicationVariables.addAll(applicationVariables("application.yml"));
        applicationVariables.addAll(applicationVariables("application-dev.yml"));
        applicationVariables.addAll(applicationVariables("application-prod.yml"));

        String template = Files.readString(resolveEnvironmentTemplate(), StandardCharsets.UTF_8);
        Set<String> templateVariables = matches(TEMPLATE_VARIABLE, template);

        assertThat(applicationVariables).containsExactlyInAnyOrderElementsOf(templateVariables);
    }

    @Test
    void productionProfileDisablesPublicApiDocumentation() throws IOException {
        YamlPropertySourceLoader loader = new YamlPropertySourceLoader();
        PropertySource<?> source = loader.load(
                "application-prod",
                new ClassPathResource("application-prod.yml")
        ).getFirst();

        assertThat(source.getProperty("springdoc.api-docs.enabled")).isEqualTo(false);
        assertThat(source.getProperty("springdoc.swagger-ui.enabled")).isEqualTo(false);
        assertThat(source.getProperty("omninest.security.allowed-origins"))
                .isEqualTo("${OMNINEST_SECURITY_ALLOWED_ORIGINS:http://localhost:3000,http://127.0.0.1:3000}");
        assertThat(source.getProperty("omninest.security.refresh-cookie-secure"))
                .isEqualTo("${OMNINEST_HTTPS_ENABLED:true}");
    }

    @Test
    void productionHttpsSwitchControlsRefreshCookieSecurity() throws IOException {
        YamlPropertySourceLoader loader = new YamlPropertySourceLoader();
        PropertySource<?> source = loader.load(
                "application-prod",
                new ClassPathResource("application-prod.yml")
        ).getFirst();
        String expression = (String) source.getProperty("omninest.security.refresh-cookie-secure");

        StandardEnvironment defaultEnvironment = new StandardEnvironment();
        assertThat(defaultEnvironment.resolvePlaceholders(expression)).isEqualTo("true");

        StandardEnvironment httpsEnvironment = new StandardEnvironment();
        httpsEnvironment.getPropertySources().addFirst(new MapPropertySource(
                "https-test",
                Map.of("OMNINEST_HTTPS_ENABLED", "true")
        ));
        assertThat(httpsEnvironment.resolvePlaceholders(expression)).isEqualTo("true");

        StandardEnvironment httpEnvironment = new StandardEnvironment();
        httpEnvironment.getPropertySources().addFirst(new MapPropertySource(
                "http-test",
                Map.of("OMNINEST_HTTPS_ENABLED", "false")
        ));
        assertThat(httpEnvironment.resolvePlaceholders(expression)).isEqualTo("false");
    }

    @Test
    void environmentSpecificSettingsStayInProfileFiles() throws IOException {
        YamlPropertySourceLoader loader = new YamlPropertySourceLoader();
        PropertySource<?> common = loader.load(
                "application",
                new ClassPathResource("application.yml")
        ).getFirst();
        PropertySource<?> dev = loader.load(
                "application-dev",
                new ClassPathResource("application-dev.yml")
        ).getFirst();
        PropertySource<?> prod = loader.load(
                "application-prod",
                new ClassPathResource("application-prod.yml")
        ).getFirst();

        assertThat(common.getProperty("spring.datasource.url")).isNull();
        assertThat(common.getProperty("spring.rabbitmq.host")).isNull();
        assertThat(common.getProperty("music.providers.netease-base-url")).isNull();
        assertThat(common.getProperty("omninest.minio.endpoint")).isNull();
        assertThat(common.getProperty("omninest.setup.enabled")).isNull();

        assertThat(dev.getProperty("spring.config.activate.on-profile")).isEqualTo("dev");
        assertThat(dev.getProperty("omninest.runtime.embedded-worker-enabled")).isEqualTo(true);
        assertThat(dev.getProperty("photo.geo.import.dir")).isEqualTo("../data/geonames");
        assertThat(prod.getProperty("spring.config.activate.on-profile")).isEqualTo("prod");
        assertThat(prod.getProperty("omninest.runtime.embedded-worker-enabled")).isEqualTo(false);

        List<String> synchronizedProperties = List.of(
                "spring.datasource.url",
                "spring.datasource.username",
                "spring.datasource.password",
                "spring.rabbitmq.host",
                "spring.rabbitmq.username",
                "spring.rabbitmq.password",
                "spring.data.redis.host",
                "spring.data.redis.password",
                "server.port",
                "music.providers.music-brainz-user-agent",
                "music.providers.netease-base-url",
                "photo.ai.endpoint",
                "photo.ai.secret",
                "file.local-media.enabled",
                "file.local-media.mounts.media.host-path",
                "file.local-media.mounts.media.process-path",
                "omninest.setup.enabled",
                "omninest.setup.token",
                "omninest.setup.persistent-state-enabled",
                "omninest.setup.web-base-url",
                "omninest.security.jwt-secret",
                "omninest.security.credential-encryption-key",
                "omninest.security.registration-enabled",
                "omninest.security.trusted-proxies",
                "omninest.security.allowed-origins",
                "omninest.aria2.rpc-url",
                "omninest.aria2.rpc-secret",
                "omninest.aria2.download-root",
                "omninest.clamav.enabled",
                "omninest.clamav.host",
                "omninest.clamav.port",
                "omninest.rclone.endpoint",
                "omninest.rclone.username",
                "omninest.rclone.password",
                "omninest.rclone.local-host-path",
                "omninest.rclone.import-host-path",
                "omninest.rclone.import-container-path",
                "omninest.minio.endpoint",
                "omninest.minio.public-endpoint",
                "omninest.minio.docker-endpoint",
                "omninest.minio.access-key",
                "omninest.minio.secret-key",
                "omninest.search.index-path",
                "omninest.search.photo-index-path"
        );
        for (String property : synchronizedProperties) {
            assertThat(prod.getProperty(property))
                    .as("dev/prod 配置项 %s 应使用同一变量和默认值", property)
                    .isEqualTo(dev.getProperty(property));
        }
    }

    private Set<String> applicationVariables(String resourceName) throws IOException {
        try (InputStream stream = getClass().getClassLoader().getResourceAsStream(resourceName)) {
            assertThat(stream).as("配置资源 %s", resourceName).isNotNull();
            return matches(APPLICATION_VARIABLE, new String(stream.readAllBytes(), StandardCharsets.UTF_8));
        }
    }

    private Set<String> matches(Pattern pattern, String content) {
        Set<String> values = new LinkedHashSet<>();
        Matcher matcher = pattern.matcher(content);
        while (matcher.find()) {
            values.add(matcher.group(1));
        }
        return values;
    }

    private Path resolveEnvironmentTemplate() {
        Path fromReactorRoot = Path.of(".env.example");
        if (Files.isRegularFile(fromReactorRoot)) {
            return fromReactorRoot;
        }
        return Path.of("..", ".env.example");
    }
}
