package com.omninest.app.video;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.Mockito.mock;

import com.omninest.OmniNestApplication;
import com.omninest.common.storage.ObjectStorageClient;
import com.omninest.modules.video.domain.MediaTvSeries;
import com.omninest.modules.video.domain.MediaVideoItem;
import com.omninest.modules.video.repository.MediaTvSeriesRepository;
import com.omninest.modules.video.repository.MediaVideoItemRepository;
import java.util.List;
import java.util.Set;
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
import org.springframework.test.context.ActiveProfiles;
import org.springframework.test.context.DynamicPropertyRegistry;
import org.springframework.test.context.DynamicPropertySource;
import org.testcontainers.containers.PostgreSQLContainer;
import org.testcontainers.junit.jupiter.Container;
import org.testcontainers.junit.jupiter.Testcontainers;

/**
 * 影视库标题关键词查询的真库集成测试（系列页与影视条目页两条查询）。
 *
 * <p>三件事只能在真实 PostgreSQL 上证明：</p>
 * <ul>
 *   <li>{@code :titlePattern is null} 这一支可执行。系列网格滚动平时就传 null，它是默认路径；
 *       影视条目那条查询则在关键词为空时改走另一个方法，所以这一支在此前从未被真实执行过。</li>
 *   <li>关键词谓词写在内容查询与显式 countQuery 两处，命中数必须一致。</li>
 *   <li>{@code buildLibraryTitlePattern} 的反斜杠转义真的按字面量生效。PostgreSQL 的 {@code LIKE}
 *       没有默认转义符，缺 {@code escape} 子句时含 {@code %} 或 {@code _} 的标题搜不到。</li>
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
                "omninest.search.index-path=${java.io.tmpdir}/omninest-video-keyword-it"
        }
)
@ActiveProfiles("dev")
@Testcontainers(disabledWithoutDocker = true)
@Import(VideoLibraryKeywordQueryIT.ExternalDependencyOverrides.class)
class VideoLibraryKeywordQueryIT {

    private static final String IMAGE = "postgres:18-alpine";

    @Container
    private static final PostgreSQLContainer<?> POSTGRES = new PostgreSQLContainer<>(IMAGE)
            .withDatabaseName("omninest_video_keyword_it")
            .withUsername("omninest")
            .withPassword("omninest");

    @Autowired
    private JdbcTemplate jdbcTemplate;

    @Autowired
    private MediaTvSeriesRepository tvSeriesRepository;

    @Autowired
    private MediaVideoItemRepository videoItemRepository;

    @DynamicPropertySource
    static void registerDatabaseProperties(DynamicPropertyRegistry registry) {
        registry.add("spring.datasource.url", POSTGRES::getJdbcUrl);
        registry.add("spring.datasource.username", POSTGRES::getUsername);
        registry.add("spring.datasource.password", POSTGRES::getPassword);
    }

    @Test
    @DisplayName("系列：无关键词走网格滚动默认路径，返回该类型全部仍有活动文件的系列")
    void nullPatternReturnsEveryActiveSeries() {
        UUID owner = UUID.randomUUID();
        insertSeries(owner, "Northern Drift", "TV");
        insertSeries(owner, "Amber Hall", "TV");
        insertSeries(owner, "Northern Drift Anime", "ANIME");
        UUID retiredSeriesId = insertSeries(owner, "Only Deleted File", "TV");
        markSoleFileNodeDeleted(owner, retiredSeriesId);

        Page<MediaTvSeries> page = tvSeriesRepository.findPageByActiveReadableAndSeriesType(
                owner, Set.of(), "TV", null, PageRequest.of(0, 10));

        assertThat(seriesTitles(page)).containsExactlyInAnyOrder("Northern Drift", "Amber Hall");
        assertThat(page.getTotalElements()).isEqualTo(2);
    }

    @Test
    @DisplayName("系列：关键词在 SQL 侧过滤，且多文件系列不被 join 放大")
    void seriesKeywordFiltersInSqlAndCountQueryAgrees() {
        UUID owner = UUID.randomUUID();
        UUID multiFileSeries = insertSeries(owner, "Northern Drift", "TV");
        // 同一系列挂两个活动剧集文件：查询的 distinct 若在值查询或 countQuery 任一处丢掉，
        // 这里会分别多出重复行或多算总数，两者都只有真实 SQL 能暴露。
        insertEpisodeItem(owner, multiFileSeries, "s01e02.mkv");
        insertSeries(owner, "northern hours", "TV");
        insertSeries(owner, "Amber Hall", "TV");

        Page<MediaTvSeries> page = tvSeriesRepository.findPageByActiveReadableAndSeriesType(
                owner, Set.of(), "TV", "%northern%", PageRequest.of(0, 10));

        // 大小写不敏感：原文大写开头的 Northern 也要被小写模式命中。
        assertThat(seriesTitles(page)).containsExactlyInAnyOrder("Northern Drift", "northern hours");
        assertThat(page.getContent()).hasSize(2);
        assertThat(page.getTotalElements()).isEqualTo(2);
    }

    @Test
    @DisplayName("系列：标题里的百分号按字面量匹配，不会被当成通配符吞掉全库")
    void seriesPercentSignInTitleStaysLiteral() {
        UUID owner = UUID.randomUUID();
        insertSeries(owner, "100% Drift", "TV");
        insertSeries(owner, "Plain Drift", "TV");

        Page<MediaTvSeries> page = tvSeriesRepository.findPageByActiveReadableAndSeriesType(
                owner, Set.of(), "TV", "%\\%%", PageRequest.of(0, 10));

        assertThat(seriesTitles(page)).containsExactly("100% Drift");
        assertThat(page.getTotalElements()).isEqualTo(1);
    }

    @Test
    @DisplayName("影视条目：未识别元数据时按文件名命中，百分号同样按字面量匹配")
    void itemKeywordFallsBackToFileNameAndKeepsLiteralPercent() {
        UUID owner = UUID.randomUUID();
        UUID wildcardNode = insertItemWithNode(owner, "100% Drift.mkv");
        insertItemWithNode(owner, "plain drift.mkv");

        Page<MediaVideoItem> page = videoItemRepository.searchReadableOriginalsByMediaType(
                owner, Set.of(), "MOVIE", null, "%\\%%", PageRequest.of(0, 10));

        // 条目没有元数据标题，coalesce 落到文件名；只有含字面量 % 的那个节点该命中。
        assertThat(page.getContent()).singleElement()
                .satisfies(item -> assertThat(item.getFileNodeId()).isEqualTo(wildcardNode));
        assertThat(page.getTotalElements()).isEqualTo(1);
    }

    private List<String> seriesTitles(Page<MediaTvSeries> page) {
        return page.getContent().stream().map(MediaTvSeries::getTitle).toList();
    }

    private UUID insertSeries(UUID owner, String title, String seriesType) {
        UUID seriesId = UUID.randomUUID();
        jdbcTemplate.update(
                "insert into omni.media_tv_series (id, owner_user_id, title, series_type) "
                        + "values (?, ?, ?, ?)",
                seriesId,
                owner,
                title,
                seriesType
        );
        insertEpisodeItem(owner, seriesId, "s01e01.mkv");
        return seriesId;
    }

    private void insertEpisodeItem(UUID owner, UUID seriesId, String fileName) {
        UUID nodeId = insertFileNode(owner, fileName, "/tv/" + seriesId + "/" + fileName);
        jdbcTemplate.update(
                "insert into omni.media_video_items (id, owner_user_id, file_node_id, media_type, series_id) "
                        + "values (?, ?, ?, 'EPISODE', ?)",
                UUID.randomUUID(),
                owner,
                nodeId,
                seriesId
        );
    }

    private UUID insertItemWithNode(UUID owner, String fileName) {
        UUID nodeId = insertFileNode(owner, fileName, "/movies/" + fileName);
        jdbcTemplate.update(
                "insert into omni.media_video_items (id, owner_user_id, file_node_id, media_type) "
                        + "values (?, ?, ?, 'MOVIE')",
                UUID.randomUUID(),
                owner,
                nodeId
        );
        return nodeId;
    }

    private UUID insertFileNode(UUID owner, String name, String normalizedPath) {
        UUID nodeId = UUID.randomUUID();
        jdbcTemplate.update(
                "insert into omni.file_nodes (id, owner_user_id, node_type, name, normalized_path) "
                        + "values (?, ?, 'FILE', ?, ?)",
                nodeId,
                owner,
                name,
                normalizedPath
        );
        return nodeId;
    }

    private void markSoleFileNodeDeleted(UUID owner, UUID seriesId) {
        jdbcTemplate.update(
                "update omni.file_nodes set is_deleted = true "
                        + "where id = (select file_node_id from omni.media_video_items "
                        + "where owner_user_id = ? and series_id = ?)",
                owner,
                seriesId
        );
    }

    /**
     * 上下文启动只需要这些外部依赖可解析，本测试不触碰对象存储与消息。
     */
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
