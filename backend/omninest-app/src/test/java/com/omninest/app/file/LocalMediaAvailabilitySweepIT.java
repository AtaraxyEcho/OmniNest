package com.omninest.app.file;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.Mockito.mock;

import com.omninest.OmniNestApplication;
import com.omninest.common.storage.ObjectStorageClient;
import com.omninest.common.util.LikePatterns;
import com.omninest.modules.file.domain.FileNode;
import com.omninest.modules.file.domain.FilePurgeState;
import com.omninest.modules.file.domain.SpaceType;
import com.omninest.modules.file.repository.FileNodeRepository;
import com.omninest.modules.file.service.LocalMediaAvailabilityService;
import java.time.Duration;
import java.time.Instant;
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
import org.springframework.data.domain.Page;
import org.springframework.data.domain.PageRequest;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.test.annotation.DirtiesContext;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.test.context.DynamicPropertyRegistry;
import org.springframework.test.context.DynamicPropertySource;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.support.TransactionTemplate;
import org.testcontainers.containers.PostgreSQLContainer;
import org.testcontainers.junit.jupiter.Container;
import org.testcontainers.junit.jupiter.Testcontainers;

/**
 * 本地影视库扫描的缺失状态推进在真库上的行为测试。
 *
 * <p>扫描前缀来自真实目录名，而缺失推进与清理认领都是 {@code UPDATE}：前缀里的 {@code _} 或 {@code %}
 * 若按通配符解释，兄弟目录的内容引用会被一起标成缺失，兄弟目录的已删除文件会被同一个清理任务认领后
 * 物理清除。这类转义语义与批量更新的结果只能在真实 PostgreSQL 上证明：</p>
 * <ul>
 *   <li>目录名含 {@code _} 时只影响本目录，不波及同层 {@code S01XE01} 这类兄弟目录。</li>
 *   <li>目录名含 {@code %} 时同上；未转义会跨过 {@code /} 命中整库。</li>
 *   <li>返回值与更新谓词同口径，统计数不会把兄弟目录算进来。</li>
 *   <li>连续扫描按"待确认 → 确认缺失"推进，宽限期与确认次数生效。</li>
 *   <li>清理认领的批量更新同样只认领转义前缀下的节点，并给出未转义会多认领的证据。</li>
 * </ul>
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
                "omninest.search.index-path=${java.io.tmpdir}/omninest-availability-sweep-it"
        }
)
@ActiveProfiles("dev")
@DirtiesContext(classMode = DirtiesContext.ClassMode.AFTER_CLASS)
@Testcontainers(disabledWithoutDocker = true)
@Import(LocalMediaAvailabilitySweepIT.ExternalDependencyOverrides.class)
class LocalMediaAvailabilitySweepIT {

    private static final String IMAGE = "postgres:18-alpine";

    @Container
    private static final PostgreSQLContainer<?> POSTGRES = new PostgreSQLContainer<>(IMAGE)
            .withDatabaseName("omninest_availability_sweep_it")
            .withUsername("omninest")
            .withPassword("omninest");

    @Autowired
    private JdbcTemplate jdbcTemplate;

    @Autowired
    private LocalMediaAvailabilityService availabilityService;

    @Autowired
    private FileNodeRepository fileNodeRepository;

    @Autowired
    private PlatformTransactionManager transactionManager;

    @DynamicPropertySource
    static void registerDatabaseProperties(DynamicPropertyRegistry registry) {
        registry.add("spring.datasource.url", POSTGRES::getJdbcUrl);
        registry.add("spring.datasource.username", POSTGRES::getUsername);
        registry.add("spring.datasource.password", POSTGRES::getPassword);
    }

    @Test
    @DisplayName("目录名含下划线：只把本目录的引用标成待确认，兄弟目录不受影响")
    void underscoreRootOnlyAffectsItsOwnSubtree() {
        UUID owner = UUID.randomUUID();
        UUID location = UUID.randomUUID();
        insertRef(owner, location, "S01_E01/show.mkv");
        insertRef(owner, location, "S01XE01/other.mkv");

        int unavailable = availabilityService.finishSuccessfulScan(
                owner,
                location,
                "S01_E01",
                UUID.randomUUID(),
                1,
                Duration.ZERO
        );

        assertThat(statusOf(owner, location, "S01_E01/show.mkv")).isEqualTo("MISSING_PENDING");
        assertThat(statusOf(owner, location, "S01XE01/other.mkv")).isEqualTo("AVAILABLE");
        assertThat(unavailable).isEqualTo(1);
    }

    @Test
    @DisplayName("目录名含百分号：不把整库当成本子树")
    void percentRootOnlyAffectsItsOwnSubtree() {
        UUID owner = UUID.randomUUID();
        UUID location = UUID.randomUUID();
        insertRef(owner, location, "100%d/rate.mkv");
        insertRef(owner, location, "100Xd/rate.mkv");
        insertRef(owner, location, "elsewhere/keep.mkv");

        int unavailable = availabilityService.finishSuccessfulScan(
                owner,
                location,
                "100%d",
                UUID.randomUUID(),
                1,
                Duration.ZERO
        );

        assertThat(statusOf(owner, location, "100%d/rate.mkv")).isEqualTo("MISSING_PENDING");
        assertThat(statusOf(owner, location, "100Xd/rate.mkv")).isEqualTo("AVAILABLE");
        assertThat(statusOf(owner, location, "elsewhere/keep.mkv")).isEqualTo("AVAILABLE");
        assertThat(unavailable).isEqualTo(1);
    }

    @Test
    @DisplayName("库根扫描仍以整个存储位置为范围")
    void dotRootCoversTheWholeLocation() {
        UUID owner = UUID.randomUUID();
        UUID location = UUID.randomUUID();
        insertRef(owner, location, "a/one.mkv");
        insertRef(owner, location, "b/two.mkv");

        int unavailable = availabilityService.finishSuccessfulScan(
                owner,
                location,
                ".",
                UUID.randomUUID(),
                1,
                Duration.ZERO
        );

        assertThat(unavailable).isEqualTo(2);
        assertThat(statusOf(owner, location, "a/one.mkv")).isEqualTo("MISSING_PENDING");
        assertThat(statusOf(owner, location, "b/two.mkv")).isEqualTo("MISSING_PENDING");
    }

    @Test
    @DisplayName("连续扫描推进到确认缺失，确认次数与宽限期都参与判定")
    void repeatedSweepsConfirmMissing() {
        UUID owner = UUID.randomUUID();
        UUID location = UUID.randomUUID();
        insertRef(owner, location, "S01_E01/show.mkv");
        insertRef(owner, location, "S01XE01/other.mkv");

        availabilityService.finishSuccessfulScan(
                owner,
                location,
                "S01_E01",
                UUID.randomUUID(),
                2,
                Duration.ofMinutes(10)
        );
        assertThat(statusOf(owner, location, "S01_E01/show.mkv")).isEqualTo("MISSING_PENDING");

        availabilityService.finishSuccessfulScan(
                owner,
                location,
                "S01_E01",
                UUID.randomUUID(),
                1,
                Duration.ZERO
        );

        // 第二次扫描先把待确认次数推进到 2，再按 requiredConfirmations=1 确认缺失。
        assertThat(statusOf(owner, location, "S01_E01/show.mkv")).isEqualTo("MISSING");
        assertThat(statusOf(owner, location, "S01XE01/other.mkv")).isEqualTo("AVAILABLE");
    }

    @Test
    @DisplayName("清理认领后代的批量更新：转义后的前缀只认领本目录，未转义时同一个 % 会多认领兄弟目录")
    void purgeAssignmentClaimsOnlyTheEscapedSubtree() {
        UUID owner = UUID.randomUUID();
        UUID taskId = UUID.randomUUID();
        UUID claimed = insertDeletedNode(owner, "/100%_done/a.mkv");
        UUID bystander = insertDeletedNode(owner, "/100X_done/b.mkv");

        // 批量更新自带 flush，必须跑在事务里；其余用例走的是 @Transactional 服务，
        // 这里直连仓储是为了只钉住这条 SQL 的谓词。
        var transaction = new TransactionTemplate(transactionManager);
        int updated = transaction.execute(status -> fileNodeRepository.assignDeletedDescendantsToPurge(
                owner,
                SpaceType.PERSONAL,
                LikePatterns.escapeSpecials("/100%_done/"),
                taskId,
                FilePurgeState.QUEUED,
                Instant.now()
        ));

        assertThat(updated).isEqualTo(1);
        assertThat(purgeTaskOf(claimed)).isEqualTo(taskId);
        assertThat(purgeTaskOf(bystander)).isNull();

        // 反证：不转义时 % 是任意串、_ 是单字符，两条都落进谓词（含已认领的那条），
        // 兄弟目录的文件被同一 taskId 认领后就会随本任务物理清除。
        int unescaped = transaction.execute(status -> fileNodeRepository.assignDeletedDescendantsToPurge(
                owner,
                SpaceType.PERSONAL,
                "/100%_done/",
                taskId,
                FilePurgeState.QUEUED,
                Instant.now()
        ));
        assertThat(unescaped).isEqualTo(2);
        assertThat(purgeTaskOf(bystander)).isEqualTo(taskId);
    }

    @Test
    @DisplayName("读侧子树查询同样按字面量匹配，且分页查询保留按 id 排序")
    void subtreeReadFindersKeepLiteralSemantics() {
        UUID owner = UUID.randomUUID();
        UUID inSubtree = insertActiveNode(owner, "S01_E01/a.mkv");
        UUID sibling = insertActiveNode(owner, "S01XE01/b.mkv");

        List<FileNode> listed = fileNodeRepository
                .findByOwnerUserIdAndSpaceTypeAndNormalizedPathStartingWithAndDeletedFalse(
                        owner, SpaceType.PERSONAL, LikePatterns.escapeSpecials("/S01_E01/"));
        assertThat(listed).singleElement().satisfies(node -> {
            assertThat(node.getId()).isEqualTo(inSubtree);
            assertThat(node.getNormalizedPath()).isEqualTo("/S01_E01/a.mkv");
        });

        // 这两个方法原本是 derived finder，改为显式查询后排序必须仍来自查询本身：
        // 调用方传的是不带 Sort 的 PageRequest。
        Page<FileNode> paged = fileNodeRepository
                .findByOwnerUserIdAndSpaceTypeAndNormalizedPathStartingWithOrderById(
                        owner, SpaceType.PERSONAL, LikePatterns.escapeSpecials("/S01_E01/"),
                        PageRequest.of(0, 10));
        assertThat(paged.getContent()).singleElement()
                .satisfies(node -> assertThat(node.getId()).isEqualTo(inSubtree));
        assertThat(sibling).isNotNull();
    }

    @Test
    @DisplayName("同名路径分属两个空间时，子树读写不得跨空间认领")
    void subtreeQueriesDoNotClaimTheOtherSpace() {
        // 个人与共享空间允许同名根目录（导入阅读默认目录就会各建一个 /Reader），
        // 前缀一致时只按 owner 匹配的批量更新会把另一空间的文件挂进本次清理任务并物理删除。
        UUID owner = UUID.randomUUID();
        UUID taskId = UUID.randomUUID();
        UUID personalChild = insertDeletedNode(owner, "/Reader/personal.mkv", SpaceType.PERSONAL);
        UUID sharedChild = insertDeletedNode(owner, "/Reader/shared.mkv", SpaceType.SHARED);

        int updated = new TransactionTemplate(transactionManager).execute(status ->
                fileNodeRepository.assignDeletedDescendantsToPurge(
                        owner,
                        SpaceType.PERSONAL,
                        LikePatterns.escapeSpecials("/Reader/"),
                        taskId,
                        FilePurgeState.QUEUED,
                        Instant.now()
                ));

        assertThat(updated).isEqualTo(1);
        assertThat(purgeTaskOf(personalChild)).isEqualTo(taskId);
        assertThat(purgeTaskOf(sharedChild)).isNull();

        // 读侧同一口径：软删链路的子树列举也只按空间取活动节点。
        UUID activePersonal = insertActiveNode(owner, "Reader/in-personal.mkv", SpaceType.PERSONAL);
        insertActiveNode(owner, "Reader/in-shared.mkv", SpaceType.SHARED);
        assertThat(fileNodeRepository
                .findByOwnerUserIdAndSpaceTypeAndNormalizedPathStartingWithAndDeletedFalse(
                        owner, SpaceType.PERSONAL, LikePatterns.escapeSpecials("/Reader/")))
                .extracting(FileNode::getId).containsExactly(activePersonal);
    }

    private UUID insertActiveNode(UUID ownerUserId, String relativePath) {
        return insertActiveNode(ownerUserId, relativePath, SpaceType.PERSONAL);
    }

    private UUID insertActiveNode(UUID ownerUserId, String relativePath, SpaceType spaceType) {
        UUID nodeId = UUID.randomUUID();
        jdbcTemplate.update(
                "insert into omni.file_nodes (id, owner_user_id, node_type, name, normalized_path, space_type) "
                        + "values (?, ?, 'FILE', ?, ?, ?)",
                nodeId,
                ownerUserId,
                relativePath.substring(relativePath.lastIndexOf('/') + 1),
                "/" + relativePath,
                spaceType.getValue()
        );
        return nodeId;
    }

    private UUID insertDeletedNode(UUID ownerUserId, String normalizedPath) {
        return insertDeletedNode(ownerUserId, normalizedPath, SpaceType.PERSONAL);
    }

    private UUID insertDeletedNode(UUID ownerUserId, String normalizedPath, SpaceType spaceType) {
        UUID nodeId = UUID.randomUUID();
        jdbcTemplate.update(
                "insert into omni.file_nodes (id, owner_user_id, node_type, name, normalized_path, "
                        + "space_type, is_deleted) values (?, ?, 'FILE', ?, ?, ?, true)",
                nodeId,
                ownerUserId,
                normalizedPath.substring(normalizedPath.lastIndexOf('/') + 1),
                normalizedPath,
                spaceType.getValue()
        );
        return nodeId;
    }

    private UUID purgeTaskOf(UUID nodeId) {
        return jdbcTemplate.queryForObject(
                "select purge_task_id from omni.file_nodes where id = ?",
                UUID.class,
                nodeId
        );
    }

    private void insertRef(UUID ownerUserId, UUID storageLocationId, String relativePath) {
        jdbcTemplate.update(
                "insert into omni.file_content_refs "
                        + "(id, owner_user_id, file_node_id, storage_location_id, relative_path) "
                        + "values (?, ?, ?, ?, ?)",
                UUID.randomUUID(),
                ownerUserId,
                UUID.randomUUID(),
                storageLocationId,
                relativePath
        );
    }

    private String statusOf(UUID ownerUserId, UUID storageLocationId, String relativePath) {
        return jdbcTemplate.queryForObject(
                "select availability_status from omni.file_content_refs "
                        + "where owner_user_id = ? and storage_location_id = ? and relative_path = ?",
                String.class,
                ownerUserId,
                storageLocationId,
                relativePath
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
