package com.omninest.app.search;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.Mockito.mock;

import com.omninest.OmniNestApplication;
import com.omninest.common.api.PageResponse;
import com.omninest.common.storage.ObjectStorageClient;
import com.omninest.modules.user.dto.UserDirectoryDtos.UserDirectoryEntry;
import com.omninest.modules.user.service.UserDirectoryQueryService;
import java.util.List;
import java.util.UUID;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.amqp.core.AmqpAdmin;
import org.springframework.amqp.rabbit.config.SimpleRabbitListenerContainerFactory;
import org.springframework.beans.BeansException;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.beans.factory.config.BeanPostProcessor;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Import;
import org.springframework.context.annotation.Primary;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.test.context.DynamicPropertyRegistry;
import org.springframework.test.context.DynamicPropertySource;
import org.testcontainers.containers.PostgreSQLContainer;
import org.testcontainers.junit.jupiter.Container;
import org.testcontainers.junit.jupiter.Testcontainers;
import org.springframework.test.annotation.DirtiesContext;

/**
 * 管理端成员候选查询的真库集成测试。
 *
 * <p>这条查询的关键词由管理员在输入框里手打，服务侧转义、谓词侧声明 {@code escape '\'}，
 * 两侧口径必须一起跑在真实 PostgreSQL 上才成立：单元测试只能证明服务传了什么参数，
 * 证明不了 JDBC 绑定后的 LIKE 是否真把 {@code %} 与 {@code _} 当字面量。</p>
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
                "omninest.search.index-path=${java.io.tmpdir}/omninest-user-directory-keyword-it"
        }
)
@ActiveProfiles("dev")
@DirtiesContext(classMode = DirtiesContext.ClassMode.AFTER_CLASS)
@Testcontainers(disabledWithoutDocker = true)
@Import(AdminUserDirectoryKeywordIT.ExternalDependencyOverrides.class)
class AdminUserDirectoryKeywordIT {

    private static final String IMAGE = "postgres:18-alpine";

    @Container
    private static final PostgreSQLContainer<?> POSTGRES = new PostgreSQLContainer<>(IMAGE)
            .withDatabaseName("omninest_user_directory_keyword_it")
            .withUsername("omninest")
            .withPassword("omninest");

    @Autowired
    private JdbcTemplate jdbcTemplate;

    @Autowired
    private UserDirectoryQueryService userDirectoryQueryService;

    @DynamicPropertySource
    static void registerDatabaseProperties(DynamicPropertyRegistry registry) {
        registry.add("spring.datasource.url", POSTGRES::getJdbcUrl);
        registry.add("spring.datasource.username", POSTGRES::getUsername);
        registry.add("spring.datasource.password", POSTGRES::getPassword);
    }

    @Test
    @DisplayName("关键词里的百分号只匹配含百分号的用户名，不当通配符放宽")
    void percentStaysLiteralInMemberCandidateSearch() {
        insertUser("100% operator");
        insertUser("100X operator");

        List<String> hits = usernamesOf(userDirectoryQueryService.findActiveUsers("100%", 0, 20));

        assertThat(hits).containsExactly("100% operator");
    }

    @Test
    @DisplayName("关键词里的下划线不吃掉一个字符")
    void underscoreStaysLiteralInMemberCandidateSearch() {
        insertUser("a_b operator");
        insertUser("aXb operator");

        List<String> hits = usernamesOf(userDirectoryQueryService.findActiveUsers("a_b", 0, 20));

        assertThat(hits).containsExactly("a_b operator");
    }

    @Test
    @DisplayName("普通关键词仍按子串命中，转义没有把查询变成全等匹配")
    void plainKeywordStillMatchesAsSubstring() {
        insertUser("operator one");
        insertUser("operator two");

        List<String> hits = usernamesOf(userDirectoryQueryService.findActiveUsers("operator", 0, 20));

        assertThat(hits).contains("operator one", "operator two");
    }

    private List<String> usernamesOf(PageResponse<UserDirectoryEntry> page) {
        return page.items().stream().map(UserDirectoryEntry::username).toList();
    }

    private void insertUser(String username) {
        jdbcTemplate.update(
                "insert into omni.auth_users (id, username, password_hash, display_name) "
                        + "values (?, ?, ?, ?)",
                UUID.randomUUID(),
                username,
                "not-a-real-hash",
                username
        );
    }

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
