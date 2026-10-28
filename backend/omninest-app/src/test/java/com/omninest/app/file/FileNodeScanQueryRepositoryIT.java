package com.omninest.app.file;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;

import com.omninest.OmniNestApplication;
import com.omninest.common.storage.ObjectStorageClient;
import com.omninest.common.storage.ObjectStorageKey;
import com.omninest.modules.file.domain.FileNode;
import com.omninest.modules.file.dto.FileDescriptor;
import com.omninest.modules.file.service.FileMetadataQueryService;
import com.omninest.modules.file.domain.SpaceType;
import com.omninest.modules.file.repository.FileNodeScanQueryRepository;
import java.sql.Types;
import java.util.List;
import java.util.UUID;
import java.util.stream.Collectors;
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
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Import;
import org.springframework.context.annotation.Primary;
import org.springframework.data.domain.PageRequest;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.test.annotation.DirtiesContext;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.test.context.DynamicPropertyRegistry;
import org.springframework.test.context.DynamicPropertySource;
import org.testcontainers.containers.PostgreSQLContainer;
import org.testcontainers.junit.jupiter.Container;
import org.testcontainers.junit.jupiter.Testcontainers;

/**
 * 全库扫描候选查询的真库集成测试。
 *
 * <p>这些查询把分类、派生资产排除、歌词放行与游标分页下推到 SQL，只有真实
 * PostgreSQL 能验证 JPQL 解析、UUID 游标比较与 LIKE 转义；上下文启动同时会校验
 * 全部仓储查询的语法。NULL 分类的存量行按设计不参与扫描，本类把该口径固定下来。</p>
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
                "omninest.search.index-path=${java.io.tmpdir}/omninest-file-scan-it"
        }
)
@ActiveProfiles("dev")
@DirtiesContext(classMode = DirtiesContext.ClassMode.AFTER_CLASS)
@Testcontainers(disabledWithoutDocker = true)
@Import(FileNodeScanQueryRepositoryIT.ExternalDependencyOverrides.class)
class FileNodeScanQueryRepositoryIT {

    private static final String IMAGE = "postgres:18-alpine";
    private static final UUID OWNER_ID = UUID.fromString("10000000-0000-0000-0000-00000000a001");
    private static final UUID OTHER_OWNER_ID = UUID.fromString("10000000-0000-0000-0000-00000000a002");
    private static final List<String> AUDIO = List.of("audio");
    private static final List<String> VIDEO = List.of("video");

    @Container
    private static final PostgreSQLContainer<?> POSTGRES = new PostgreSQLContainer<>(IMAGE)
            .withDatabaseName("omninest_file_scan_it")
            .withUsername("omninest")
            .withPassword("omninest");

    @Autowired
    private JdbcTemplate jdbcTemplate;

    @Autowired
    private FileNodeScanQueryRepository repository;

    @Autowired
    private FileMetadataQueryService fileMetadataQueryService;

    @DynamicPropertySource
    static void registerDatabaseProperties(DynamicPropertyRegistry registry) {
        registry.add("spring.datasource.url", POSTGRES::getJdbcUrl);
        registry.add("spring.datasource.username", POSTGRES::getUsername);
        registry.add("spring.datasource.password", POSTGRES::getPassword);
    }

    @BeforeEach
    void seedFiles() {
        jdbcTemplate.update("delete from omni.file_nodes");
        insertFile("photo.jpg", "/photo.jpg", "image", SpaceType.PERSONAL, false, "LOCAL", false);
        insertFile("a.mp3", "/Music/a.mp3", "audio", SpaceType.PERSONAL, false, "LOCAL", false);
        insertFile("b.flac", "/Music/b.flac", "audio", SpaceType.PERSONAL, false, "LOCAL", false);
        insertFile("shared-space.mp3", "/Music/shared-space.mp3", "audio", SpaceType.SHARED, false, "LOCAL", false);
        insertFile("a.lrc", "/Music/a.lrc", "other", SpaceType.PERSONAL, false, "LOCAL", false);
        insertFile("derived.mp3", "/Music/derived.mp3", "audio", SpaceType.PERSONAL, false, "DERIVED", false);
        insertFile("null-cat.mp3", "/Music/null-cat.mp3", null, SpaceType.PERSONAL, false, "LOCAL", false);
        insertFile("deleted.mp3", "/Music/deleted.mp3", "audio", SpaceType.PERSONAL, false, "LOCAL", true);
        insertFile("in.mp4", "/Movies/in.mp4", "video", SpaceType.PERSONAL, false, "LOCAL", false);
        insertFile("sibling.mp4", "/Movies_2026/sibling.mp4", "video", SpaceType.PERSONAL, false, "LOCAL", false);
        insertFile("percent.mp4", "/100%_movies/percent.mp4", "video", SpaceType.PERSONAL, false, "LOCAL", false);
        insertFile("decoy.mp4", "/100Xmovies/decoy.mp4", "video", SpaceType.PERSONAL, false, "LOCAL", false);
        insertSharedFile(OTHER_OWNER_ID, "s.mp3", "/B/s.mp3", "audio", true);
        insertSharedFile(OTHER_OWNER_ID, "private.mp3", "/B/private.mp3", "audio", false);
        insertSharedFile(OWNER_ID, "self-shared.mp3", "/A/self-shared.mp3", "audio", true);
    }

    @Test
    @DisplayName("个人音频分页查询排除照片、派生资产、NULL 分类与已删除行")
    void ownedAudioPagesFilterByCategoryAndSource() {
        List<FileNode> audio = repository.findOwnedActiveFilesByCategoriesAfterId(
                OWNER_ID, AUDIO, zeroUuid(), PageRequest.of(0, 50));

        // 自己标记共享的文件仍属自有文件，个人扫描包含它；共享查询则排除本人文件。
        assertThat(audio).extracting(FileNode::getName)
                .containsExactlyInAnyOrder("a.mp3", "b.flac", "shared-space.mp3", "self-shared.mp3");
        assertThat(repository.countOwnedActiveFilesByCategories(OWNER_ID, AUDIO)).isEqualTo(4);
    }

    @Test
    @DisplayName("ID 游标逐批推进且不重复返回")
    void afterIdCursorAdvances() {
        List<FileNode> first = repository.findOwnedActiveFilesByCategoriesAfterId(
                OWNER_ID, AUDIO, zeroUuid(), PageRequest.of(0, 2));
        assertThat(first).hasSize(2);
        List<FileNode> second = repository.findOwnedActiveFilesByCategoriesAfterId(
                OWNER_ID, AUDIO, first.getLast().getId(), PageRequest.of(0, 2));

        assertThat(second).isNotEmpty();
        assertThat(second).noneMatch(node -> first.stream().anyMatch(seen -> seen.getId().equals(node.getId())));
    }

    @Test
    @DisplayName("共享查询只返回他人共享的文件")
    void sharedQueryExcludesOwnAndUnshared() {
        List<FileNode> shared = repository.findSharedFilesByCategoriesAfterId(
                OWNER_ID, AUDIO, zeroUuid(), PageRequest.of(0, 50));

        assertThat(shared).extracting(FileNode::getName).containsExactly("s.mp3");
        assertThat(repository.countSharedFilesByCategories(OWNER_ID, AUDIO)).isEqualTo(1);
    }

    @Test
    @DisplayName("歌词查询单独返回 .lrc 且不混入音频分页")
    void lyricQueriesAreSeparate() {
        assertThat(repository.findOwnedLyricFiles(OWNER_ID))
                .extracting(FileNode::getName).containsExactly("a.lrc");
        assertThat(repository.findOwnedActiveFilesByCategoriesAfterId(
                OWNER_ID, AUDIO, zeroUuid(), PageRequest.of(0, 50)))
                .extracting(FileNode::getName).doesNotContain("a.lrc");
    }

    @Test
    @DisplayName("路径前缀不误伤兄弟目录，LIKE 特殊字符按字面量匹配")
    void pathPrefixIsExactAndEscaped() {
        List<FileNode> movies = repository.findOwnedActiveFilesByPathPrefixAndCategoriesAfterId(
                OWNER_ID, SpaceType.PERSONAL, "/Movies/", VIDEO, zeroUuid(), PageRequest.of(0, 50));
        assertThat(movies).extracting(FileNode::getName).containsExactly("in.mp4");

        // 走服务层验证转义：目录名里的 % 与 _ 必须按字面量匹配，不能命中 /100Xmovies。
        List<FileDescriptor> percent = fileMetadataQueryService.listOwnedActiveByPathPrefixAndCategoriesAfterId(
                OWNER_ID, SpaceType.PERSONAL, "/100%_movies/", VIDEO, zeroUuid(), 50);
        assertThat(percent).extracting(FileDescriptor::name).containsExactly("percent.mp4");
        assertThat(fileMetadataQueryService.countOwnedActiveByPathPrefixAndCategories(
                OWNER_ID, SpaceType.PERSONAL, "/100%_movies/", VIDEO)).isEqualTo(1);
    }

    @Test
    @DisplayName("有上限的候选查询按创建时间倒序截断")
    void limitedQueryCapsResults() {
        List<FileNode> limited = repository.findOwnedActiveFilesByCategoriesLimited(
                OWNER_ID, AUDIO, PageRequest.of(0, 2));

        assertThat(limited).hasSize(2);
        assertThat(limited.stream().map(FileNode::getName).collect(Collectors.toSet()))
                .isSubsetOf("a.mp3", "b.flac", "shared-space.mp3", "self-shared.mp3");
        assertThat(repository.findSpaceFilesByCategoriesLimited(
                SpaceType.SHARED, AUDIO, PageRequest.of(0, 10)))
                .extracting(FileNode::getName).contains("shared-space.mp3");
    }

    private UUID insertFile(
            String name,
            String path,
            String category,
            SpaceType spaceType,
            boolean shared,
            String sourceType,
            boolean deleted
    ) {
        UUID id = UUID.randomUUID();
        insertRow(id, OWNER_ID, name, path, category, spaceType, shared, sourceType, deleted);
        return id;
    }

    private void insertSharedFile(
            UUID ownerId, String name, String path, String category, boolean shared) {
        insertRow(UUID.randomUUID(), ownerId, name, path, category, SpaceType.PERSONAL, shared, "LOCAL", false);
    }

    private void insertRow(
            UUID id,
            UUID ownerId,
            String name,
            String path,
            String category,
            SpaceType spaceType,
            boolean shared,
            String sourceType,
            boolean deleted
    ) {
        jdbcTemplate.update("""
                insert into omni.file_nodes
                    (id, owner_user_id, parent_id, node_type, name, normalized_path, mime_type,
                     category, size_bytes, source_type, is_deleted, shared, space_type, uploaded_by)
                values (?, ?, null, 'FILE', ?, ?, 'application/octet-stream',
                        ?, 1, ?, ?, ?, ?, ?)
                """,
                ps -> {
                    ps.setObject(1, id);
                    ps.setObject(2, ownerId);
                    ps.setString(3, name);
                    ps.setString(4, path);
                    if (category == null) {
                        ps.setNull(5, Types.VARCHAR);
                    } else {
                        ps.setString(5, category);
                    }
                    ps.setString(6, sourceType);
                    ps.setBoolean(7, deleted);
                    ps.setBoolean(8, shared);
                    ps.setString(9, spaceType.getValue());
                    ps.setObject(10, ownerId);
                });
    }

    private UUID zeroUuid() {
        return new UUID(0L, 0L);
    }

    @TestConfiguration
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
        static BeanPostProcessor rabbitListenerGuard() {
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
