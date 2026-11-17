package com.omninest.app.admin;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.Mockito.mock;

import com.omninest.OmniNestApplication;
import com.omninest.common.storage.ObjectStorageClient;
import com.omninest.modules.user.dto.AuthUserDto;
import com.omninest.modules.user.service.AdminUserService;
import jakarta.persistence.EntityManagerFactory;
import java.util.UUID;
import org.hibernate.SessionFactory;
import org.hibernate.stat.Statistics;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.amqp.core.AmqpAdmin;
import org.springframework.amqp.rabbit.config.SimpleRabbitListenerContainerFactory;
import org.springframework.beans.BeansException;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.beans.factory.config.BeanPostProcessor;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.context.TestConfiguration;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Import;
import org.springframework.context.annotation.Primary;
import org.springframework.data.domain.Page;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.test.context.DynamicPropertyRegistry;
import org.springframework.test.context.DynamicPropertySource;
import org.testcontainers.containers.PostgreSQLContainer;
import org.testcontainers.junit.jupiter.Container;
import org.testcontainers.junit.jupiter.Testcontainers;

/**
 * 管理端用户分页的角色往返数真库回归测试。
 *
 * <p>分页查询不能对 to-many 关联用 {@code @EntityGraph}：fetch join 会让分页总数按连接后的
 * 行数计算，因此角色集合靠懒加载加全局 {@code hibernate.default_batch_fetch_size} 批取。
 * 本测试用 Hibernate 统计断言"往返语句数不随页数线性增长"；移除该配置后整页会退化成每行
 * 一条集合查询，本断言随之失败（已用变异验证）。</p>
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
                "file.local-media.enabled=false",
                "omninest.clamav.enabled=false",
                "spring.jpa.properties.hibernate.generate_statistics=true"
        }
)
@ActiveProfiles("dev")
@Testcontainers(disabledWithoutDocker = true)
@Import(AdminUserListBatchLoadIT.ExternalDependencyOverrides.class)
class AdminUserListBatchLoadIT {

    private static final String IMAGE = "postgres:18-alpine";
    private static final int USER_COUNT = 12;

    @Container
    private static final PostgreSQLContainer<?> POSTGRES = new PostgreSQLContainer<>(IMAGE)
            .withDatabaseName("omninest_admin_user_batch_it")
            .withUsername("omninest")
            .withPassword("omninest");

    @Autowired
    private AdminUserService adminUserService;

    @Autowired
    private JdbcTemplate jdbcTemplate;

    @Autowired
    private EntityManagerFactory entityManagerFactory;

    @DynamicPropertySource
    static void registerDatabaseProperties(DynamicPropertyRegistry registry) {
        registry.add("spring.datasource.url", POSTGRES::getJdbcUrl);
        registry.add("spring.datasource.username", POSTGRES::getUsername);
        registry.add("spring.datasource.password", POSTGRES::getPassword);
    }

    @Test
    @DisplayName("用户分页只按批初始化一次角色集合")
    void listUsersInitializesRoleCollectionsInOneBatch() {
        UUID roleId = seedRole("BATCH_MEMBER");
        seedUsersWithRole(roleId, USER_COUNT);

        Statistics statistics = entityManagerFactory.unwrap(SessionFactory.class).getStatistics();
        statistics.clear();

        Page<AuthUserDto> page = adminUserService.listUsers(0, 20, null, null, "username", "asc");

        assertThat(page.getContent()).hasSize(USER_COUNT);
        // 判据是往返语句数，不是集合初始化计数：批取下 12 个集合仍各记一次初始化
        // （实测 collLoad=12），但只发一条 IN（实测整页 stmt=6）。
        assertThat(statistics.getPrepareStatementCount())
                .as("一页 %d 个用户的角色必须批取，不能每行一条语句", USER_COUNT)
                .isLessThan((long) USER_COUNT);
    }

    private UUID seedRole(String code) {
        UUID roleId = UUID.randomUUID();
        jdbcTemplate.update(
                "insert into omni.auth_roles (id, code, name) values (?, ?, ?)",
                roleId,
                code,
                "批取测试角色"
        );
        return roleId;
    }

    private void seedUsersWithRole(UUID roleId, int count) {
        for (int index = 0; index < count; index++) {
            UUID userId = UUID.randomUUID();
            String username = "batch-user-" + index;
            jdbcTemplate.update(
                    "insert into omni.auth_users (id, username, password_hash, display_name) "
                            + "values (?, ?, ?, ?)",
                    userId,
                    username,
                    "not-a-real-hash",
                    username
            );
            jdbcTemplate.update(
                    "insert into omni.auth_user_roles (user_id, role_id) values (?, ?)",
                    userId,
                    roleId
            );
        }
    }

    @TestConfiguration
    static class ExternalDependencyOverrides {

        @Bean
        @Primary
        ObjectStorageClient objectStorageClient() {
            return mock(ObjectStorageClient.class);
        }

        @Bean
        @Primary
        AmqpAdmin amqpAdmin() {
            return mock(AmqpAdmin.class);
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
