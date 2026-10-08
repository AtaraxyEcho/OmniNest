package com.omninest.app.search;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.Mockito.mock;

import com.omninest.OmniNestApplication;
import com.omninest.common.storage.ObjectStorageClient;
import com.omninest.modules.music.domain.MusicTrack;
import com.omninest.modules.music.repository.MusicTrackRepository;
import com.omninest.modules.photos.domain.PhotoItem;
import com.omninest.modules.photos.repository.PhotoItemRepository;
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
 * 媒体库标题关键词查询的真库集成测试，覆盖影视（条目与系列）、音乐曲目与照片三条 LIKE 路径。
 *
 * <p>四件事只能在真实 PostgreSQL 上证明：</p>
 * <ul>
 *   <li>{@code :titlePattern is null} 这一支可执行。系列网格滚动平时就传 null，它是默认路径；
 *       影视条目那条查询则在关键词为空时改走另一个方法，所以这一支此前从未被真实执行过。</li>
 *   <li>关键词谓词写在内容查询与显式 countQuery 两处时，命中数必须一致。</li>
 *   <li>声明了 {@code escape} 之后，模式里的 {@code \%} 才按字面量匹配；
 *       未转义的 {@code %} 会把条件放宽成近似全库——这一条同时给出"为什么要转义"的证据。</li>
 *   <li>影视条目在未识别元数据时按文件名命中（{@code coalesce} 口径）。</li>
 * </ul>
 *
 * <p>服务侧的关键词转义由各自的单元测试钉住，本测试只验 SQL 语义。</p>
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
                "omninest.search.index-path=${java.io.tmpdir}/omninest-media-keyword-it"
        }
)
@ActiveProfiles("dev")
@Testcontainers(disabledWithoutDocker = true)
@Import(MediaLibraryKeywordQueryIT.ExternalDependencyOverrides.class)
class MediaLibraryKeywordQueryIT {

    private static final String IMAGE = "postgres:18-alpine";

    @Container
    private static final PostgreSQLContainer<?> POSTGRES = new PostgreSQLContainer<>(IMAGE)
            .withDatabaseName("omninest_media_keyword_it")
            .withUsername("omninest")
            .withPassword("omninest");

    @Autowired
    private JdbcTemplate jdbcTemplate;

    @Autowired
    private MediaTvSeriesRepository tvSeriesRepository;

    @Autowired
    private MediaVideoItemRepository videoItemRepository;

    @Autowired
    private MusicTrackRepository trackRepository;

    @Autowired
    private PhotoItemRepository photoItemRepository;

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

    @Test
    @DisplayName("音乐：转义后的百分号只命中含百分号的曲目，未转义时同一个字符会放宽成全库")
    void trackKeywordTreatsPercentAsLiteralOnlyWhenEscaped() {
        UUID owner = UUID.randomUUID();
        insertTrack(owner, "100% Love");
        insertTrack(owner, "Plain Love");

        List<MusicTrack> literal = trackRepository.searchByOwnerUserId(
                owner, "100\\%", PageRequest.of(0, 20));
        assertThat(literal).singleElement()
                .satisfies(track -> assertThat(track.getTitle()).isEqualTo("100% Love"));

        // 反证：用户敲的 % 若不转义就是通配符，两条曲目都会被当成命中。
        List<MusicTrack> wildcard = trackRepository.searchByOwnerUserId(
                owner, "%", PageRequest.of(0, 20));
        assertThat(wildcard).hasSize(2);
    }

    @Test
    @DisplayName("照片：SQL 回退查询按字面量匹配标题里的百分号")
    void photoFallbackKeywordKeepsLiteralPercent() {
        UUID owner = UUID.randomUUID();
        insertPhoto(owner, "70% Sunset");
        insertPhoto(owner, "Plain Sunset");

        List<PhotoItem> items = photoItemRepository.searchByOwnerUserIdAndKeyword(
                owner, "70\\%", PageRequest.of(0, 20));

        assertThat(items).singleElement()
                .satisfies(item -> assertThat(item.getTitle()).isEqualTo("70% Sunset"));
    }

    @Test
    @DisplayName("口径：显式声明 ESCAPE 之后，模式里的 \\% 才按字面量匹配")
    void escapeClauseMakesBackslashEscapeWildcards() {
        // 这条不经过 Hibernate，直接问数据库；本批 escapeSpecials + ESCAPE 的写法都靠它成立。
        Boolean literalHit = jdbcTemplate.queryForObject(
                "select '100% drift' like ? escape '\\'", Boolean.class, "%100\\% drift%");
        Boolean plainWildcardStillWorks = jdbcTemplate.queryForObject(
                "select '100% drift' like ? escape '\\'", Boolean.class, "%drift%");
        // 反证：标题不含百分号时，要求字面量 % 的模式不该命中。
        Boolean shouldNotHit = jdbcTemplate.queryForObject(
                "select 'plain drift' like ? escape '\\'", Boolean.class, "%\\%%");

        assertThat(literalHit).isTrue();
        assertThat(plainWildcardStillWorks).isTrue();
        assertThat(shouldNotHit).isFalse();
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

    private void insertTrack(UUID owner, String title) {
        UUID nodeId = insertFileNode(owner, title + ".flac", "/music/" + title + ".flac");
        jdbcTemplate.update(
                "insert into omni.music_tracks (id, owner_user_id, file_node_id, title) "
                        + "values (?, ?, ?, ?)",
                UUID.randomUUID(),
                owner,
                nodeId,
                title
        );
    }

    private void insertPhoto(UUID owner, String title) {
        UUID nodeId = insertFileNode(owner, title + ".jpg", "/photos/" + title + ".jpg");
        jdbcTemplate.update(
                "insert into omni.photo_items (id, owner_user_id, file_node_id, title) "
                        + "values (?, ?, ?, ?)",
                UUID.randomUUID(),
                owner,
                nodeId,
                title
        );
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
