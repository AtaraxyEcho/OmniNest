package com.omninest.app.migration;

import jakarta.persistence.Entity;
import java.util.Objects;
import org.flywaydb.core.Flyway;
import org.hibernate.SessionFactory;
import org.hibernate.boot.MetadataSources;
import org.hibernate.boot.registry.StandardServiceRegistry;
import org.hibernate.boot.registry.StandardServiceRegistryBuilder;
import org.hibernate.cfg.AvailableSettings;
import org.assertj.core.api.Assertions;
import org.junit.jupiter.api.BeforeAll;
import org.junit.jupiter.api.Test;
import org.springframework.context.annotation.ClassPathScanningCandidateComponentProvider;
import org.springframework.core.type.filter.AnnotationTypeFilter;
import org.testcontainers.containers.PostgreSQLContainer;
import org.testcontainers.junit.jupiter.Container;
import org.testcontainers.junit.jupiter.Testcontainers;
import org.springframework.test.annotation.DirtiesContext;

/**
 * 在当前 Flyway 基线上验证全部 JPA 实体映射。
 *
 * @author OmniNest
 */
@DirtiesContext(classMode = DirtiesContext.ClassMode.AFTER_CLASS)
@Testcontainers(disabledWithoutDocker = true)
class JpaBaselineSchemaValidationTest {
    private static final String IMAGE = "postgres:18-alpine";

    @Container
    private static final PostgreSQLContainer<?> POSTGRES = new PostgreSQLContainer<>(IMAGE)
            .withDatabaseName("omninest_jpa_schema_validation")
            .withUsername("omninest")
            .withPassword("omninest");

    @BeforeAll
    static void migrateSchema() {
        Flyway.configure()
                .dataSource(POSTGRES.getJdbcUrl(), POSTGRES.getUsername(), POSTGRES.getPassword())
                .locations("classpath:db/migration")
                .validateMigrationNaming(true)
                .schemas("omni")
                .defaultSchema("omni")
                .load()
                .migrate();
    }

    @Test
    void allJpaEntitiesMatchCurrentBaseline() throws ClassNotFoundException {
        StandardServiceRegistry registry = new StandardServiceRegistryBuilder()
                .applySetting(AvailableSettings.JAKARTA_JDBC_URL, POSTGRES.getJdbcUrl())
                .applySetting(AvailableSettings.JAKARTA_JDBC_USER, POSTGRES.getUsername())
                .applySetting(AvailableSettings.JAKARTA_JDBC_PASSWORD, POSTGRES.getPassword())
                .applySetting(AvailableSettings.DEFAULT_SCHEMA, "omni")
                .applySetting(AvailableSettings.HBM2DDL_AUTO, "validate")
                .build();
        try {
            MetadataSources metadataSources = new MetadataSources(registry);
            ClassPathScanningCandidateComponentProvider scanner =
                    new ClassPathScanningCandidateComponentProvider(false);
            scanner.addIncludeFilter(new AnnotationTypeFilter(Entity.class));
            for (var candidate : scanner.findCandidateComponents("com.omninest")) {
                String className = Objects.requireNonNull(candidate.getBeanClassName());
                metadataSources.addAnnotatedClass(Class.forName(className));
            }
            try (SessionFactory sessionFactory = metadataSources.buildMetadata().buildSessionFactory()) {
                Assertions.assertThat(sessionFactory.isOpen()).isTrue();
            }
        } finally {
            StandardServiceRegistryBuilder.destroy(registry);
        }
    }
}
