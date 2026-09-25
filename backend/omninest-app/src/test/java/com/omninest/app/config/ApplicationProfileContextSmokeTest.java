package com.omninest.app.config;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.Mockito.mock;

import com.omninest.OmniNestApplication;
import com.omninest.common.config.ClamAvProperties;
import com.omninest.common.config.SecurityProperties;
import com.omninest.modules.video.service.VideoProcessExecutor;
import io.minio.MinioClient;
import java.io.IOException;
import java.time.Duration;
import java.util.List;
import org.junit.jupiter.api.Test;
import org.springframework.amqp.core.AmqpAdmin;
import org.springframework.amqp.rabbit.config.SimpleRabbitListenerContainerFactory;
import org.springframework.beans.BeansException;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.beans.factory.config.BeanPostProcessor;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.context.TestConfiguration;
import org.springframework.context.ConfigurableApplicationContext;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Import;
import org.springframework.context.annotation.Primary;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.test.context.DynamicPropertyRegistry;
import org.springframework.test.context.DynamicPropertySource;
import org.testcontainers.containers.PostgreSQLContainer;
import org.testcontainers.junit.jupiter.Container;
import org.testcontainers.junit.jupiter.Testcontainers;

/**
 * dev 与 prod Profile 共用的完整应用上下文冒烟测试基础设施。
 *
 * @author OmniNest
 */
abstract class ApplicationProfileContextSmokeSupport {
    private static final String POSTGRES_IMAGE = "postgres:18-alpine";

    @Container
    static final PostgreSQLContainer<?> POSTGRES = new PostgreSQLContainer<>(POSTGRES_IMAGE)
            .withDatabaseName("omninest_context_smoke")
            .withUsername("omninest")
            .withPassword("omninest");

    @Autowired
    private ConfigurableApplicationContext applicationContext;

    @Autowired
    private ClamAvProperties clamAvProperties;

    @Autowired
    private SecurityProperties securityProperties;

    @DynamicPropertySource
    static void registerDatabaseProperties(DynamicPropertyRegistry registry) {
        registry.add("spring.datasource.url", POSTGRES::getJdbcUrl);
        registry.add("spring.datasource.username", POSTGRES::getUsername);
        registry.add("spring.datasource.password", POSTGRES::getPassword);
    }

    @Test
    void completeApplicationContextStartsWithBoundProfileConfiguration() {
        assertThat(applicationContext.isActive()).isTrue();
        assertThat(clamAvProperties.getPort()).isEqualTo(3310);
        assertThat(securityProperties.getAllowedOrigins()).containsExactly(
                "http://localhost:3000",
                "http://127.0.0.1:3000"
        );
    }

    /**
     * 将外部基础设施替换为确定性测试边界，同时保留全部业务 Bean 装配。
     *
     * @author OmniNest
     */
    @TestConfiguration(proxyBeanMethods = false)
    static class ExternalDependencyOverrides {

        @Bean
        @Primary
        MinioClient smokeTestMinioClient() {
            return mock(MinioClient.class);
        }

        @Bean
        @Primary
        AmqpAdmin smokeTestAmqpAdmin() {
            return mock(AmqpAdmin.class);
        }

        @Bean
        @Primary
        VideoProcessExecutor smokeTestVideoProcessExecutor() {
            return new VideoProcessExecutor() {
                @Override
                public Result execute(List<String> command, Duration timeout)
                        throws IOException, InterruptedException {
                    return new Result(1, "", false, false);
                }
            };
        }

        @Bean
        static BeanPostProcessor disableRabbitListenerStartup() {
            return new BeanPostProcessor() {
                @Override
                public Object postProcessBeforeInitialization(Object bean, String beanName) throws BeansException {
                    if (bean instanceof SimpleRabbitListenerContainerFactory factory) {
                        factory.setAutoStartup(false);
                    }
                    return bean;
                }
            };
        }
    }
}

/**
 * dev Profile 完整应用上下文冒烟测试。
 *
 * @author OmniNest
 */
@SpringBootTest(
        classes = OmniNestApplication.class,
        webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT,
        properties = {
                "spring.rabbitmq.dynamic=false",
                "omninest.messaging.rabbit.backlog-monitoring-enabled=false",
                "omninest.redis.capacity.monitoring-enabled=false",
                "omninest.runtime.role=api",
                "omninest.runtime.embedded-worker-enabled=false",
                "omninest.setup.persistent-state-enabled=false",
                "reader.comic-parser.consume-in-api=false",
                "file.local-media.enabled=false",
                "omninest.search.index-path=${java.io.tmpdir}/omninest-smoke-dev"
        }
)
@ActiveProfiles("dev")
@Testcontainers(disabledWithoutDocker = true)
@Import(ApplicationProfileContextSmokeSupport.ExternalDependencyOverrides.class)
class DevApplicationProfileContextSmokeTest extends ApplicationProfileContextSmokeSupport {
}

/**
 * prod Profile 完整应用上下文冒烟测试。
 *
 * @author OmniNest
 */
@SpringBootTest(
        classes = OmniNestApplication.class,
        webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT,
        properties = {
                "spring.rabbitmq.dynamic=false",
                "omninest.messaging.rabbit.backlog-monitoring-enabled=false",
                "omninest.redis.capacity.monitoring-enabled=false",
                "omninest.runtime.role=api",
                "omninest.runtime.embedded-worker-enabled=false",
                "omninest.setup.persistent-state-enabled=false",
                "reader.comic-parser.consume-in-api=false",
                "file.local-media.enabled=false",
                "omninest.search.index-path=${java.io.tmpdir}/omninest-smoke-prod",
                "omninest.security.jwt-secret=smoke-test-jwt-secret-at-least-32-bytes-long!",
                "spring.rabbitmq.password=smoke-rabbit-password",
                "spring.data.redis.password=smoke-redis-password",
                "omninest.minio.access-key=smoke-minio-access",
                "omninest.minio.secret-key=smoke-minio-secret",
                "omninest.rclone.password=smoke-rclone-password",
                "omninest.aria2.rpc-secret=smoke-aria2-secret",
                "photo.ai.secret=smoke-ai-sidecar-secret",
                "omninest.setup.enabled=false"
        }
)
@ActiveProfiles("prod")
@Testcontainers(disabledWithoutDocker = true)
@Import(ApplicationProfileContextSmokeSupport.ExternalDependencyOverrides.class)
class ProdApplicationProfileContextSmokeTest extends ApplicationProfileContextSmokeSupport {
}
