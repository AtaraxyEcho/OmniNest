package com.omninest.app.security;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.Mockito.mock;

import com.omninest.OmniNestApplication;
import com.omninest.common.security.Permissions;
import com.omninest.modules.video.service.VideoProcessExecutor;
import io.minio.MinioClient;
import java.io.IOException;
import java.time.Duration;
import java.time.Instant;
import java.util.List;
import java.util.UUID;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.amqp.core.AmqpAdmin;
import org.springframework.amqp.rabbit.config.SimpleRabbitListenerContainerFactory;
import org.springframework.beans.BeansException;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.beans.factory.config.BeanPostProcessor;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.context.TestConfiguration;
import org.springframework.boot.test.web.server.LocalServerPort;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Import;
import org.springframework.context.annotation.Primary;
import org.springframework.http.HttpEntity;
import org.springframework.http.HttpHeaders;
import org.springframework.http.HttpMethod;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.http.client.ClientHttpResponse;
import org.springframework.web.client.DefaultResponseErrorHandler;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.security.oauth2.jose.jws.MacAlgorithm;
import org.springframework.security.oauth2.jwt.JwsHeader;
import org.springframework.security.oauth2.jwt.JwtClaimsSet;
import org.springframework.security.oauth2.jwt.JwtEncoder;
import org.springframework.security.oauth2.jwt.JwtEncoderParameters;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.test.context.DynamicPropertyRegistry;
import org.springframework.test.context.DynamicPropertySource;
import org.springframework.web.client.RestTemplate;
import org.testcontainers.containers.PostgreSQLContainer;
import org.testcontainers.junit.jupiter.Container;
import org.testcontainers.junit.jupiter.Testcontainers;

/**
 * 任务权限 API 隔离集成测试。
 *
 * <p>在真实 PostgreSQL + 完整 Spring Security 链路上验证：
 * MEMBER 不可读全站任务，ADMIN 可读但不可重试，个人任务接口仅本人可见。</p>
 *
 * @author OmniNest
 */
@SpringBootTest(
        classes = OmniNestApplication.class,
        webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT,
        properties = {
                "spring.rabbitmq.dynamic=false",
                "spring.rabbitmq.listener.simple.auto-startup=false",
                "spring.main.allow-bean-definition-overriding=true",
                "omninest.messaging.rabbit.backlog-monitoring-enabled=false",
                "omninest.redis.capacity.monitoring-enabled=false",
                "omninest.runtime.role=api",
                "omninest.runtime.embedded-worker-enabled=false",
                "omninest.setup.persistent-state-enabled=false",
                "reader.comic-parser.consume-in-api=false",
                "file.local-media.enabled=false",
                "omninest.clamav.enabled=false",
                "omninest.search.index-path=${java.io.tmpdir}/omninest-task-perm-it"
        }
)
@ActiveProfiles("dev")
@Testcontainers(disabledWithoutDocker = true)
@Import(AdminTaskPermissionApiIT.ExternalDependencyOverrides.class)
class AdminTaskPermissionApiIT {

    private static final String IMAGE = "postgres:18-alpine";
    private static final UUID MEMBER_ID = UUID.fromString("10000000-0000-0000-0000-0000000000a1");
    private static final UUID ADMIN_ID = UUID.fromString("10000000-0000-0000-0000-0000000000a2");
    private static final UUID SUPER_ADMIN_ID = UUID.fromString("10000000-0000-0000-0000-0000000000a3");
    private static final UUID OTHER_USER_ID = UUID.fromString("10000000-0000-0000-0000-0000000000a4");
    private static final UUID MEMBER_TASK_ID = UUID.fromString("20000000-0000-0000-0000-0000000000b1");
    private static final UUID OTHER_TASK_ID = UUID.fromString("20000000-0000-0000-0000-0000000000b2");

    @Container
    private static final PostgreSQLContainer<?> POSTGRES = new PostgreSQLContainer<>(IMAGE)
            .withDatabaseName("omninest_task_perm_it")
            .withUsername("omninest")
            .withPassword("omninest");

    @LocalServerPort
    private int port;

    private final RestTemplate rest = createRestTemplate();

    @Autowired
    private JwtEncoder jwtEncoder;

    @Autowired
    private JdbcTemplate jdbcTemplate;

    @DynamicPropertySource
    static void registerDatabaseProperties(DynamicPropertyRegistry registry) {
        registry.add("spring.datasource.url", POSTGRES::getJdbcUrl);
        registry.add("spring.datasource.username", POSTGRES::getUsername);
        registry.add("spring.datasource.password", POSTGRES::getPassword);
    }

    @BeforeEach
    void seedCatalogData() {
        Integer existing = jdbcTemplate.queryForObject(
                "SELECT count(*) FROM omni.auth_users WHERE username = 'member-it'", Integer.class);
        if (existing != null && existing > 0) {
            return;
        }
        jdbcTemplate.update("""
                INSERT INTO omni.auth_users (id, username, password_hash, status)
                VALUES (?, 'member-it', '$2a$10$invalidhashfortestonly', 'ACTIVE'),
                       (?, 'admin-it', '$2a$10$invalidhashfortestonly', 'ACTIVE'),
                       (?, 'super-it', '$2a$10$invalidhashfortestonly', 'ACTIVE'),
                       (?, 'other-it', '$2a$10$invalidhashfortestonly', 'ACTIVE')
                """, MEMBER_ID, ADMIN_ID, SUPER_ADMIN_ID, OTHER_USER_ID);
        jdbcTemplate.update("""
                INSERT INTO omni.auth_user_roles (user_id, role_id)
                SELECT ?, id FROM omni.auth_roles WHERE code = 'MEMBER'
                """, MEMBER_ID);
        jdbcTemplate.update("""
                INSERT INTO omni.auth_user_roles (user_id, role_id)
                SELECT ?, id FROM omni.auth_roles WHERE code = 'ADMIN'
                """, ADMIN_ID);
        jdbcTemplate.update("""
                INSERT INTO omni.auth_user_roles (user_id, role_id)
                SELECT ?, id FROM omni.auth_roles WHERE code = 'SUPER_ADMIN'
                """, SUPER_ADMIN_ID);
        jdbcTemplate.update("""
                INSERT INTO omni.auth_user_roles (user_id, role_id)
                SELECT ?, id FROM omni.auth_roles WHERE code = 'MEMBER'
                """, OTHER_USER_ID);
        jdbcTemplate.update("""
                INSERT INTO omni.sys_tasks (
                    id, owner_user_id, task_type, status, progress, retry_count, max_retries
                ) VALUES
                    (?, ?, 'FILE_INDEX', 'COMPLETED', 100, 0, 3),
                    (?, ?, 'FILE_INDEX', 'COMPLETED', 100, 0, 3)
                """, MEMBER_TASK_ID, MEMBER_ID, OTHER_TASK_ID, OTHER_USER_ID);
    }

    @Test
    @DisplayName("MEMBER 访问全站任务管理接口返回 403")
    void memberCannotReadAdminTaskConsole() {
        ResponseEntity<String> response = exchange(
                "/api/v1/admin/tasks", HttpMethod.GET, memberToken(), null, String.class);
        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.FORBIDDEN);

        ResponseEntity<String> page = exchange(
                "/api/v1/admin/tasks/page", HttpMethod.GET, memberToken(), null, String.class);
        assertThat(page.getStatusCode()).isEqualTo(HttpStatus.FORBIDDEN);
    }

    @Test
    @DisplayName("MEMBER 可读取本人任务且不可见他人任务")
    void memberReadsOnlyOwnTasks() {
        ResponseEntity<String> response = exchange(
                "/api/v1/tasks", HttpMethod.GET, memberToken(), null, String.class);
        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.OK);
        assertThat(response.getBody()).contains(MEMBER_TASK_ID.toString());
        assertThat(response.getBody()).doesNotContain(OTHER_TASK_ID.toString());
    }

    @Test
    @DisplayName("ADMIN 可读取全站任务")
    void adminCanReadAdminTaskConsole() {
        ResponseEntity<String> response = exchange(
                "/api/v1/admin/tasks/page", HttpMethod.GET, adminToken(), null, String.class);
        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.OK);
        assertThat(response.getBody()).contains(MEMBER_TASK_ID.toString());
        assertThat(response.getBody()).contains(OTHER_TASK_ID.toString());
    }

    @Test
    @DisplayName("ADMIN 不可重试任务，SUPER_ADMIN 不因权限被拒绝")
    void onlySuperAdminRetriesTasks() {
        ResponseEntity<String> adminRetry = exchange(
                "/api/v1/admin/tasks/" + MEMBER_TASK_ID + "/retry",
                HttpMethod.POST,
                adminToken(),
                null,
                String.class);
        assertThat(adminRetry.getStatusCode()).isEqualTo(HttpStatus.FORBIDDEN);

        ResponseEntity<String> superRetry = exchange(
                "/api/v1/admin/tasks/" + MEMBER_TASK_ID + "/retry",
                HttpMethod.POST,
                superAdminToken(),
                null,
                String.class);
        assertThat(superRetry.getStatusCode()).isNotEqualTo(HttpStatus.FORBIDDEN);
    }

    @Test
    @DisplayName("死信队列查看要求 task:admin")
    void dlqRequiresTaskAdmin() {
        ResponseEntity<String> member = exchange(
                "/api/v1/tasks/dlq", HttpMethod.GET, memberToken(), null, String.class);
        assertThat(member.getStatusCode()).isEqualTo(HttpStatus.FORBIDDEN);

        ResponseEntity<String> admin = exchange(
                "/api/v1/tasks/dlq", HttpMethod.GET, adminToken(), null, String.class);
        assertThat(admin.getStatusCode()).isEqualTo(HttpStatus.OK);
    }

    private String memberToken() {
        return accessToken(MEMBER_ID, "member-it", "MEMBER", List.of(
                Permissions.PROFILE_READ,
                Permissions.FILE_READ,
                Permissions.TASK_READ,
                Permissions.MEDIA_READ
        ));
    }

    private String adminToken() {
        return accessToken(ADMIN_ID, "admin-it", "ADMIN", List.of(
                Permissions.TASK_READ,
                Permissions.TASK_ADMIN,
                Permissions.SYSTEM_CONFIG_READ,
                Permissions.SYSTEM_USER_READ
        ));
    }

    private String superAdminToken() {
        return accessToken(SUPER_ADMIN_ID, "super-it", "SUPER_ADMIN",
                List.copyOf(Permissions.SUPER_ADMIN_PERMISSIONS));
    }

    private String accessToken(UUID userId, String username, String role, List<String> permissions) {
        Instant now = Instant.now();
        JwtClaimsSet claims = JwtClaimsSet.builder()
                .subject(userId.toString())
                .issuedAt(now.minusSeconds(5))
                .expiresAt(now.plusSeconds(300))
                .claim("token_use", "access")
                .claim("sid", UUID.randomUUID().toString())
                .claim("username", username)
                .claim("role", role)
                .claim("roles", List.of(role))
                .claim("permissions", permissions)
                .build();
        return jwtEncoder.encode(JwtEncoderParameters.from(
                JwsHeader.with(MacAlgorithm.HS256).build(), claims)).getTokenValue();
    }

    private <T> ResponseEntity<T> exchange(
            String path,
            HttpMethod method,
            String token,
            Object body,
            Class<T> responseType
    ) {
        HttpHeaders headers = new HttpHeaders();
        headers.setContentType(MediaType.APPLICATION_JSON);
        headers.setBearerAuth(token);
        return rest.exchange(
                "http://localhost:" + port + path,
                method,
                new HttpEntity<>(body, headers),
                responseType);
    }

    /**
     * 保留 4xx/5xx 响应体，便于断言 HTTP 状态而不是抛异常。
     */
    private static RestTemplate createRestTemplate() {
        RestTemplate template = new RestTemplate();
        template.setErrorHandler(new DefaultResponseErrorHandler() {
            @Override
            public boolean hasError(ClientHttpResponse response) {
                return false;
            }
        });
        return template;
    }

    /**
     * 将外部基础设施替换为测试边界，保留业务与安全装配。
     */
    @TestConfiguration(proxyBeanMethods = false)
    static class ExternalDependencyOverrides {

        @Bean
        @Primary
        MinioClient minioClient() {
            return mock(MinioClient.class);
        }

        @Bean
        @Primary
        AmqpAdmin amqpAdmin() {
            return mock(AmqpAdmin.class);
        }

        @Bean
        @Primary
        VideoProcessExecutor videoProcessExecutor() {
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
                public Object postProcessBeforeInitialization(Object bean, String beanName)
                        throws BeansException {
                    if (bean instanceof SimpleRabbitListenerContainerFactory factory) {
                        factory.setAutoStartup(false);
                    }
                    return bean;
                }
            };
        }
    }
}
