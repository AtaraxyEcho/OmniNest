package com.omninest.app.photos;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;

import com.omninest.OmniNestApplication;
import com.omninest.common.storage.ObjectStorageClient;
import com.omninest.common.storage.ObjectStorageKey;
import com.omninest.modules.photos.repository.GeoCityRepository;
import com.omninest.modules.photos.repository.GeoCityUpsertRow;
import java.math.BigDecimal;
import java.util.List;
import java.util.Map;
import java.util.UUID;
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
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.test.context.DynamicPropertyRegistry;
import org.springframework.test.context.DynamicPropertySource;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.support.TransactionTemplate;
import org.testcontainers.containers.PostgreSQLContainer;
import org.testcontainers.junit.jupiter.Container;
import org.testcontainers.junit.jupiter.Testcontainers;
import org.springframework.test.annotation.DirtiesContext;

/**
 * GeoNames 城市批量 upsert 的真库集成测试。
 *
 * <p>批量写入把逐行原生 upsert 换成 JDBC 批处理，冲突分支、中文名保留与列绑定
 * 只有真实 PostgreSQL 才会暴露；服务单测把仓储完全桩掉，上下文冒烟也不执行 SQL。</p>
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
                "omninest.search.index-path=${java.io.tmpdir}/omninest-geo-city-it"
        }
)
@ActiveProfiles("dev")
@DirtiesContext(classMode = DirtiesContext.ClassMode.AFTER_CLASS)
@Testcontainers(disabledWithoutDocker = true)
@Import(GeoCityBatchRepositoryIT.ExternalDependencyOverrides.class)
class GeoCityBatchRepositoryIT {

    private static final String IMAGE = "postgres:18-alpine";

    @Container
    private static final PostgreSQLContainer<?> POSTGRES = new PostgreSQLContainer<>(IMAGE)
            .withDatabaseName("omninest_geo_city_it")
            .withUsername("omninest")
            .withPassword("omninest");

    @Autowired
    private GeoCityRepository geoCityRepository;

    @Autowired
    private JdbcTemplate jdbcTemplate;

    @Autowired
    private PlatformTransactionManager transactionManager;

    @DynamicPropertySource
    static void registerDatabaseProperties(DynamicPropertyRegistry registry) {
        registry.add("spring.datasource.url", POSTGRES::getJdbcUrl);
        registry.add("spring.datasource.username", POSTGRES::getUsername);
        registry.add("spring.datasource.password", POSTGRES::getPassword);
    }

    @Test
    @DisplayName("批量 upsert 插入新行，冲突更新时保留已回填的城市中文名")
    void batchUpsertInsertsNewRowsAndPreservesBackfilledCityName() {
        UUID datasetId = UUID.randomUUID();
        TransactionTemplate transaction = new TransactionTemplate(transactionManager);

        int inserted = transaction.execute(status -> geoCityRepository.upsertCities(datasetId, List.of(
                row(1809858L, "Guangzhou", "China", "Guangdong", "23.1166700", "113.2500000", 15200000L, "PPTA"),
                row(1816663L, "Hangzhou", "China", "Zhejiang", "30.2936500", "120.1614300", 11900000L, "PPTA"))));
        assertThat(inserted).isEqualTo(2);

        // 中文名回填在生产代码中是 JdbcTemplate 批量更新，这里用同一语句模拟。
        transaction.executeWithoutResult(status -> assertThat(jdbcTemplate.update(
                "UPDATE omni.geo_cities SET name_zh = ? WHERE dataset_id = ? AND geoname_id = ?"
                        + " AND (name_zh IS NULL OR name_zh <> ?)",
                "广州市", datasetId, 1809858L, "广州市")).isEqualTo(1));
        int updated = transaction.execute(status -> geoCityRepository.upsertCities(datasetId, List.of(
                row(1809858L, "Guangzhou City", "China", "Guangdong", "23.1000000", "113.2000000", 16000000L, "PPLA"))));
        assertThat(updated).isEqualTo(1);

        Map<String, Object> row = jdbcTemplate.queryForMap(
                "SELECT name, name_zh, population, feature_code FROM omni.geo_cities"
                        + " WHERE dataset_id = ? AND geoname_id = ?",
                datasetId,
                1809858L);
        assertThat(row.get("name")).isEqualTo("Guangzhou City");
        assertThat(row.get("name_zh")).isEqualTo("广州市");
        assertThat(row.get("population")).isEqualTo(16000000L);
        assertThat(row.get("feature_code")).isEqualTo("PPLA");
        assertThat(jdbcTemplate.queryForObject(
                "SELECT count(*) FROM omni.geo_cities WHERE dataset_id = ?", Long.class, datasetId))
                .isEqualTo(2L);
    }

    private static GeoCityUpsertRow row(
            long geonameId,
            String name,
            String countryNameEn,
            String provinceNameEn,
            String latitude,
            String longitude,
            long population,
            String featureCode) {
        return new GeoCityUpsertRow(
                geonameId,
                name,
                "CN",
                countryNameEn,
                provinceNameEn,
                new BigDecimal(latitude),
                new BigDecimal(longitude),
                population,
                featureCode);
    }

    /**
     * 外部基础设施替换为测试边界：对象存储与 AMQP 管理不需要真实实例，
     * 监听容器不得启动，批量写入只依赖真实 PostgreSQL。
     */
    @TestConfiguration(proxyBeanMethods = false)
    static class ExternalDependencyOverrides {

        @Bean
        @Primary
        ObjectStorageClient objectStorageClient() {
            ObjectStorageClient client = mock(ObjectStorageClient.class);
            when(client.objectExists(any(ObjectStorageKey.class))).thenReturn(true);
            return client;
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
