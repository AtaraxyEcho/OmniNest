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
        Object devEmbeddedWorker = dev.getProperty("omninest.runtime.embedded-worker-enabled");
        assertThat(devEmbeddedWorker).isEqualTo("${OMNINEST_RUNTIME_EMBEDDED_WORKER_ENABLED:true}");
        StandardEnvironment devEmbeddedDefaultEnvironment = new StandardEnvironment();
        assertThat(devEmbeddedDefaultEnvironment.resolvePlaceholders(String.valueOf(devEmbeddedWorker)))
                .isEqualTo("true");
        Object devGeoImportDir = dev.getProperty("photo.geo.import.dir");
        assertThat(devGeoImportDir).isEqualTo("${OMNINEST_GEO_IMPORT_DIR:../data/geonames}");
        assertThat(devEmbeddedDefaultEnvironment.resolvePlaceholders(String.valueOf(devGeoImportDir)))
                .isEqualTo("../data/geonames");
        assertThat(prod.getProperty("spring.config.activate.on-profile")).isEqualTo("prod");
        Object prodEmbeddedWorker = prod.getProperty("omninest.runtime.embedded-worker-enabled");
        assertThat(prodEmbeddedWorker).isEqualTo("${OMNINEST_RUNTIME_EMBEDDED_WORKER_ENABLED:false}");
        StandardEnvironment embeddedDefaultEnvironment = new StandardEnvironment();
        assertThat(embeddedDefaultEnvironment.resolvePlaceholders(String.valueOf(prodEmbeddedWorker)))
                .isEqualTo("false");
        Object prodGeoImportDir = prod.getProperty("photo.geo.import.dir");
        assertThat(prodGeoImportDir).isEqualTo("${OMNINEST_GEO_IMPORT_DIR:/var/lib/omninest/geonames}");
        assertThat(embeddedDefaultEnvironment.resolvePlaceholders(String.valueOf(prodGeoImportDir)))
                .isEqualTo("/var/lib/omninest/geonames");
        // web-base-url 的 dev/prod 默认值有意不同：dev 指向本机前端（分享链接便利），
        // prod 留空回退同源托管形态，故不进入下方“同一变量和默认值”清单。
        assertThat(dev.getProperty("omninest.setup.web-base-url"))
                .isEqualTo("${OMNINEST_SETUP_WEB_BASE_URL:http://localhost:3000}");
        assertThat(prod.getProperty("omninest.setup.web-base-url"))
                .isEqualTo("${OMNINEST_SETUP_WEB_BASE_URL:}");

        List<String> synchronizedProperties = List.of(
                "spring.datasource.url",
                "spring.datasource.username",
                "spring.rabbitmq.host",
                "spring.rabbitmq.username",
                "spring.data.redis.host",
                "server.port",
                "music.providers.music-brainz-user-agent",
                "music.providers.netease-base-url",
                "photo.ai.endpoint",
                "file.local-media.enabled",
                "file.local-media.mounts.media.host-path",
                "file.local-media.mounts.media.process-path",
                "omninest.setup.enabled",
                "omninest.setup.persistent-state-enabled",
                "omninest.security.credential-encryption-key",
                "omninest.security.registration-enabled",
                "omninest.security.trusted-proxies",
                "omninest.security.allowed-origins",
                "omninest.aria2.rpc-url",
                "omninest.aria2.download-root",
                "omninest.clamav.enabled",
                "omninest.clamav.host",
                "omninest.clamav.port",
                "omninest.rclone.endpoint",
                "omninest.rclone.username",
                "omninest.rclone.local-host-path",
                "omninest.rclone.import-host-path",
                "omninest.rclone.import-container-path",
                "omninest.minio.endpoint",
                "omninest.minio.public-endpoint",
                "omninest.minio.docker-endpoint",
                "omninest.search.index-path",
                "omninest.search.photo-index-path",
                "logging.file.name"
        );
        // 口令/密钥项允许 dev 与 prod 默认值不同：prod 禁止弱默认，运行时由
        // ProductionSecretsValidator / JwtSecretValidator 拒绝空白或示例值。
        for (String property : synchronizedProperties) {
            assertThat(prod.getProperty(property))
                    .as("dev/prod 配置项 %s 应使用同一变量和默认值", property)
                    .isEqualTo(dev.getProperty(property));
        }
        assertThat(dev.getProperty("spring.datasource.password"))
                .isEqualTo("${OMNINEST_DB_PASSWORD:omninest}");
        assertThat(prod.getProperty("spring.datasource.password"))
                .isEqualTo("${OMNINEST_DB_PASSWORD:}");
        assertThat(prod.getProperty("spring.rabbitmq.password"))
                .isEqualTo("${OMNINEST_RABBITMQ_PASSWORD:}");
        assertThat(prod.getProperty("omninest.minio.access-key"))
                .isEqualTo("${OMNINEST_MINIO_ACCESS_KEY:}");
        assertThat(prod.getProperty("omninest.minio.secret-key"))
                .isEqualTo("${OMNINEST_MINIO_SECRET_KEY:}");
        assertThat(prod.getProperty("omninest.rclone.password"))
                .isEqualTo("${OMNINEST_RCLONE_RC_PASS:}");
        assertThat(prod.getProperty("omninest.aria2.rpc-secret"))
                .isEqualTo("${OMNINEST_ARIA2_RPC_SECRET:}");
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
