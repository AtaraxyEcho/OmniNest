package com.omninest.app.migration;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.Table;
import jakarta.persistence.metamodel.Attribute;
import jakarta.persistence.metamodel.EmbeddableType;
import jakarta.persistence.metamodel.EntityType;
import jakarta.persistence.metamodel.ManagedType;
import jakarta.persistence.metamodel.SingularAttribute;
import java.lang.reflect.Field;
import java.sql.Connection;
import java.sql.DriverManager;
import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;
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
        StandardServiceRegistry registry = newRegistry();
        try (SessionFactory sessionFactory = buildSessionFactory(registry)) {
            Assertions.assertThat(sessionFactory.isOpen()).isTrue();
        } finally {
            StandardServiceRegistryBuilder.destroy(registry);
        }
    }

    /**
     * Hibernate 的 {@code validate} 只校验列存在与类型族，不校验 {@code varchar} 长度。
     * 这里直接把实体 {@code @Column(length)} 与 {@code information_schema} 的实际长度对齐，
     * 防止 DTO 校验放行、数据库落库时抛 {@code value too long}。
     */
    @Test
    void columnLengthsMatchCurrentBaseline() throws Exception {
        StandardServiceRegistry registry = newRegistry();
        try (SessionFactory sessionFactory = buildSessionFactory(registry);
                Connection connection = DriverManager.getConnection(
                        POSTGRES.getJdbcUrl(), POSTGRES.getUsername(), POSTGRES.getPassword())) {
            Map<String, Integer> databaseLengths = loadCharacterLengths(connection);
            List<String> violations = new ArrayList<>();
            for (EntityType<?> entity : sessionFactory.getMetamodel().getEntities()) {
                collectLengthViolations(entity, databaseLengths, violations);
            }
            Assertions.assertThat(violations)
                    .as("JPA @Column(length) 超过数据库 varchar 实际长度，合法输入会在落库时 500")
                    .isEmpty();
        } finally {
            StandardServiceRegistryBuilder.destroy(registry);
        }
    }

    private static StandardServiceRegistry newRegistry() {
        return new StandardServiceRegistryBuilder()
                .applySetting(AvailableSettings.JAKARTA_JDBC_URL, POSTGRES.getJdbcUrl())
                .applySetting(AvailableSettings.JAKARTA_JDBC_USER, POSTGRES.getUsername())
                .applySetting(AvailableSettings.JAKARTA_JDBC_PASSWORD, POSTGRES.getPassword())
                .applySetting(AvailableSettings.DEFAULT_SCHEMA, "omni")
                .applySetting(AvailableSettings.HBM2DDL_AUTO, "validate")
                .build();
    }

    private static SessionFactory buildSessionFactory(StandardServiceRegistry registry)
            throws ClassNotFoundException {
        MetadataSources metadataSources = new MetadataSources(registry);
        ClassPathScanningCandidateComponentProvider scanner =
                new ClassPathScanningCandidateComponentProvider(false);
        scanner.addIncludeFilter(new AnnotationTypeFilter(Entity.class));
        for (var candidate : scanner.findCandidateComponents("com.omninest")) {
            String className = Objects.requireNonNull(candidate.getBeanClassName());
            metadataSources.addAnnotatedClass(Class.forName(className));
        }
        return metadataSources.buildMetadata().buildSessionFactory();
    }

    private static Map<String, Integer> loadCharacterLengths(Connection connection) throws Exception {
        Map<String, Integer> lengths = new HashMap<>();
        String sql = """
                SELECT table_name, column_name, character_maximum_length
                  FROM information_schema.columns
                 WHERE table_schema = 'omni'
                   AND character_maximum_length IS NOT NULL
                """;
        try (PreparedStatement statement = connection.prepareStatement(sql);
                ResultSet resultSet = statement.executeQuery()) {
            while (resultSet.next()) {
                lengths.put(
                        resultSet.getString("table_name") + "." + resultSet.getString("column_name"),
                        resultSet.getInt("character_maximum_length"));
            }
        }
        return lengths;
    }

    private static void collectLengthViolations(
            ManagedType<?> type,
            Map<String, Integer> databaseLengths,
            List<String> violations
    ) {
        Class<?> javaType = type.getJavaType();
        Table table = javaType.getAnnotation(Table.class);
        if (table == null || table.name().isBlank()) {
            return;
        }
        for (Attribute<?, ?> attribute : type.getAttributes()) {
            if (attribute.getPersistentAttributeType() == Attribute.PersistentAttributeType.EMBEDDED) {
                if (attribute instanceof SingularAttribute<?, ?> singular
                        && singular.getType() instanceof EmbeddableType<?> embeddable) {
                    collectLengthViolations(embeddable, databaseLengths, violations);
                }
                continue;
            }
            if (!(attribute instanceof SingularAttribute<?, ?> singular)
                    || !String.class.equals(singular.getJavaType())) {
                continue;
            }
            Field field = findField(javaType, attribute.getName());
            Column column = field == null ? null : field.getAnnotation(Column.class);
            boolean textColumn = column != null
                    && column.columnDefinition().toLowerCase(Locale.ROOT).contains("text");
            if (textColumn) {
                continue;
            }
            String columnName = column != null && !column.name().isBlank()
                    ? column.name()
                    : toSnakeCase(attribute.getName());
            Integer databaseLength = databaseLengths.get(table.name() + "." + columnName);
            if (databaseLength == null) {
                continue;
            }
            int declaredLength = column == null ? 255 : column.length();
            if (declaredLength > databaseLength) {
                violations.add(table.name() + "." + columnName
                        + " declared=" + declaredLength + " database=" + databaseLength);
            }
        }
    }

    private static Field findField(Class<?> type, String name) {
        Class<?> current = type;
        while (current != null && current != Object.class) {
            try {
                return current.getDeclaredField(name);
            } catch (NoSuchFieldException ignored) {
                current = current.getSuperclass();
            }
        }
        return null;
    }

    private static String toSnakeCase(String value) {
        return value.replaceAll("([a-z0-9])([A-Z])", "$1_$2").toLowerCase(Locale.ROOT);
    }
}
