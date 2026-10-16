package com.omninest.modules.reader.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.tuple;
import static org.mockito.ArgumentMatchers.anyList;
import static org.mockito.Mockito.atLeastOnce;
import static org.mockito.Mockito.times;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import com.omninest.modules.reader.domain.ReaderCatalogNode;
import com.omninest.modules.reader.domain.ReaderItemSource;
import com.omninest.modules.reader.domain.ReaderPage;
import com.omninest.modules.reader.repository.ReaderCatalogNodeRepository;
import com.omninest.modules.reader.repository.ReaderItemRepository;
import com.omninest.modules.reader.repository.ReaderItemSourceRepository;
import com.omninest.modules.reader.repository.ReaderPageRepository;
import com.omninest.modules.reader.service.model.ComicManifestDraft.ComicCatalogDraftNode;
import java.lang.reflect.Field;
import java.lang.reflect.Method;
import java.util.ArrayList;
import java.util.List;
import java.util.Optional;
import java.util.UUID;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Nested;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.ArgumentCaptor;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

/**
 * 漫画清单构建器单元测试：覆盖节点类型推断和 source-aware 目录构建。
 */
@ExtendWith(MockitoExtension.class)
class ComicManifestBuilderTest {

    @InjectMocks
    private ComicManifestBuilder builder;

    @Mock
    private ReaderItemRepository itemRepository;
    @Mock
    private ReaderItemSourceRepository sourceRepository;
    @Mock
    private ReaderCatalogNodeRepository catalogRepository;
    @Mock
    private ReaderPageRepository pageRepository;

    private Method detectNodeTypeMethod;
    private Method buildDraftCatalogMethod;
    private Method parseSourceMetaMethod;

    @BeforeEach
    void setUp() throws Exception {
        detectNodeTypeMethod = ComicManifestBuilder.class
                .getDeclaredMethod("detectNodeType", String.class);
        detectNodeTypeMethod.setAccessible(true);

        buildDraftCatalogMethod = ComicManifestBuilder.class
                .getDeclaredMethod("buildDraftCatalog", List.class, UUID.class);
        buildDraftCatalogMethod.setAccessible(true);

        parseSourceMetaMethod = ComicManifestBuilder.class
                .getDeclaredMethod("parseSourceMeta", UUID.class, String.class);
        parseSourceMetaMethod.setAccessible(true);
    }

    // ==================== parseSourceMeta ====================

    /// 目录构建的分卷识别必须与 `applySourceSortMetadata` 落库时用的 ComicVolumeParser 同源。
    ///
    /// 各写一份时"第三卷"（中文数字）、"卷01"/"巻01"（前缀式）在排序里认得出卷号，
    /// 生成目录树却拿不到 volumeNo，整卷没有"第X卷"聚合节点。
    @Nested
    @DisplayName("parseSourceMeta 与 ComicVolumeParser 同口径")
    class ParseSourceMetaTests {

        @Test
        @DisplayName("中文数字卷 → volumeNo")
        void chineseVolume_detected() throws Exception {
            assertThat(metaInt("葬送的芙莉莲 第三卷.cbz", "volumeNo")).isEqualTo(3);
        }

        @Test
        @DisplayName("前缀式卷号（简体与日文异体）→ volumeNo")
        void prefixedVolume_detected() throws Exception {
            assertThat(metaInt("[Kmoe][Frieren][01].cbz", "volumeNo")).isNull();
            assertThat(metaInt("卷01.cbz", "volumeNo")).isEqualTo(1);
            assertThat(metaInt("巻01.cbz", "volumeNo")).isEqualTo(1);
        }

        @Test
        @DisplayName("季集 S01E02 → seasonNo 与话号同时落")
        void seasonEpisode_detected() throws Exception {
            assertThat(metaInt("S01E02.cbz", "seasonNo")).isEqualTo(1);
            assertThat(metaInt("S01E02.cbz", "chapterStart")).isEqualTo(2);
            assertThat(metaInt("S01E02.cbz", "chapterEnd")).isEqualTo(2);
        }

        @Test
        @DisplayName("话区间仍按 parser 结果，不被窄正则二次覆写")
        void episodeRange_detected() throws Exception {
            assertThat(metaInt("話001-010.cbz", "chapterStart")).isEqualTo(1);
            assertThat(metaInt("話001-010.cbz", "chapterEnd")).isEqualTo(10);
        }
    }

    private Integer metaInt(String rawName, String fieldName) throws Exception {
        Object meta = parseSourceMetaMethod.invoke(builder, UUID.randomUUID(), rawName);
        Field field = meta.getClass().getDeclaredField(fieldName);
        field.setAccessible(true);
        return (Integer) field.get(meta);
    }

    // ==================== detectNodeType ====================

    @Nested
    @DisplayName("detectNodeType 节点类型推断")
    class DetectNodeTypeTests {

        @Test
        @DisplayName("Season 01 → SEASON")
        void seasonPattern_detectsSeason() throws Exception {
            String result = (String) detectNodeTypeMethod.invoke(builder, "Season 01");
            assertThat(result).isEqualTo("SEASON");
        }

        @Test
        @DisplayName("Vol.02 → VOLUME")
        void volPattern_detectsVolume() throws Exception {
            String result = (String) detectNodeTypeMethod.invoke(builder, "Vol.02");
            assertThat(result).isEqualTo("VOLUME");
        }

        @Test
        @DisplayName("Ch.003 → CHAPTER")
        void chapterPattern_detectsChapter() throws Exception {
            String result = (String) detectNodeTypeMethod.invoke(builder, "Ch.003");
            assertThat(result).isEqualTo("CHAPTER");
        }

        @Test
        @DisplayName("001-010 → COLLECTION")
        void rangePattern_detectsCollection() throws Exception {
            String result = (String) detectNodeTypeMethod.invoke(builder, "001-010");
            assertThat(result).isEqualTo("COLLECTION");
        }

        @Test
        @DisplayName("Extra → EXTRA")
        void extraPattern_detectsExtra() throws Exception {
            String result = (String) detectNodeTypeMethod.invoke(builder, "Extra");
            assertThat(result).isEqualTo("EXTRA");
        }

        @Test
        @DisplayName("SP → EXTRA")
        void spPattern_detectsExtra() throws Exception {
            String result = (String) detectNodeTypeMethod.invoke(builder, "SP");
            assertThat(result).isEqualTo("EXTRA");
        }

        @Test
        @DisplayName("番外 → EXTRA")
        void chineseExtraPattern_detectsExtra() throws Exception {
            String result = (String) detectNodeTypeMethod.invoke(builder, "番外");
            assertThat(result).isEqualTo("EXTRA");
        }

        @Test
        @DisplayName("第001话 → CHAPTER")
        void chineseChapterPattern_detectsChapter() throws Exception {
            String result = (String) detectNodeTypeMethod.invoke(builder, "第001话");
            assertThat(result).isEqualTo("CHAPTER");
        }

        @Test
        @DisplayName("未知名称 → 默认 CHAPTER")
        void unknownName_defaultsToChapter() throws Exception {
            String result = (String) detectNodeTypeMethod.invoke(builder, "random_stuff");
            assertThat(result).isEqualTo("CHAPTER");
        }
    }

    @Test
    @DisplayName("buildDraftCatalog 保留解析器目录父子结构")
    void buildDraftCatalog_preservesParserHierarchy() throws Exception {
        UUID itemId = UUID.fromString("20000000-0000-0000-0000-000000000001");
        UUID sourceId = UUID.fromString("30000000-0000-0000-0000-000000000001");
        List<ComicCatalogDraftNode> drafts = List.of(
                new ComicCatalogDraftNode("toc:第1卷:0", null, "第1卷", "VOLUME", 0, null),
                new ComicCatalogDraftNode("toc:第1卷:0/toc:第1话:0", "toc:第1卷:0", "第1话", "CHAPTER", 0, sourceId)
        );

        @SuppressWarnings("unchecked")
        List<ReaderCatalogNode> nodes = new ArrayList<>((List<ReaderCatalogNode>)
                buildDraftCatalogMethod.invoke(builder, drafts, itemId));

        assertThat(nodes).hasSize(3);
        ReaderCatalogNode root = nodes.stream()
                .filter(node -> "ROOT".equals(node.getNodeType()))
                .findFirst()
                .orElseThrow();
        ReaderCatalogNode volume = nodes.stream()
                .filter(node -> "第1卷".equals(node.getTitle()))
                .findFirst()
                .orElseThrow();
        ReaderCatalogNode chapter = nodes.stream()
                .filter(node -> "第1话".equals(node.getTitle()))
                .findFirst()
                .orElseThrow();

        assertThat(volume.getParentId()).isEqualTo(root.getId());
        assertThat(chapter.getParentId()).isEqualTo(volume.getId());
        assertThat(chapter.getSourceId()).isEqualTo(sourceId);
    }

    @Test
    @DisplayName("重建目录时显式保留非空创建时间")
    void rebuildComicManifest_initializesCatalogCreatedAt() {
        UUID itemId = UUID.fromString("20000000-0000-0000-0000-000000000002");
        when(sourceRepository.findByReaderItemId(itemId)).thenReturn(new ArrayList<>());
        when(catalogRepository.saveAll(anyList())).thenAnswer(invocation -> invocation.getArgument(0));
        when(itemRepository.findById(itemId)).thenReturn(Optional.empty());

        builder.rebuildComicManifest(itemId);

        @SuppressWarnings("unchecked")
        ArgumentCaptor<List<ReaderCatalogNode>> nodes = ArgumentCaptor.forClass(List.class);
        verify(catalogRepository, times(2)).saveAll(nodes.capture());
        assertThat(nodes.getAllValues()).allSatisfy(savedNodes ->
                assertThat(savedNodes).allSatisfy(node -> assertThat(node.getCreatedAt()).isNotNull()));
    }

    @Test
    @DisplayName("重建多分卷目录时按来源隔离同名章节并累计总页数")
    void rebuildComicManifest_aggregatesPagesAcrossSources() {
        UUID itemId = UUID.fromString("20000000-0000-0000-0000-000000000003");
        UUID firstSourceId = UUID.fromString("30000000-0000-0000-0000-000000000011");
        UUID secondSourceId = UUID.fromString("30000000-0000-0000-0000-000000000012");
        ReaderItemSource firstSource = source(firstSourceId, itemId, "[Kmoe][紹宋]話001-010.epub", 1);
        ReaderItemSource secondSource = source(secondSourceId, itemId, "[Kmoe][紹宋]話011-020.epub", 11);
        List<ReaderPage> firstPages = pages(itemId, firstSourceId, 2);
        List<ReaderPage> secondPages = pages(itemId, secondSourceId, 3);

        when(sourceRepository.findByReaderItemId(itemId)).thenReturn(List.of(firstSource, secondSource));
        when(pageRepository.findBySourceId(firstSourceId)).thenReturn(firstPages);
        when(pageRepository.findBySourceId(secondSourceId)).thenReturn(secondPages);
        when(pageRepository.saveAll(anyList())).thenAnswer(invocation -> invocation.getArgument(0));
        when(catalogRepository.saveAll(anyList())).thenAnswer(invocation -> invocation.getArgument(0));
        when(itemRepository.findById(itemId)).thenReturn(Optional.empty());

        builder.rebuildComicManifest(itemId);

        @SuppressWarnings("unchecked")
        ArgumentCaptor<List<ReaderCatalogNode>> nodes = ArgumentCaptor.forClass(List.class);
        verify(catalogRepository, times(2)).saveAll(nodes.capture());
        List<ReaderCatalogNode> savedNodes = nodes.getAllValues().getLast();
        ReaderCatalogNode root = savedNodes.stream()
                .filter(node -> "ROOT".equals(node.getNodeType()))
                .findFirst()
                .orElseThrow();
        assertThat(root.getPageCount()).isEqualTo(5);
        assertThat(savedNodes)
                .filteredOn(node -> "COLLECTION".equals(node.getNodeType()))
                .extracting(ReaderCatalogNode::getPageCount)
                .containsExactlyInAnyOrder(2, 3);
    }

    @Test
    @DisplayName("压缩包没有解析器目录键时按卷与来源归页")
    void rebuildComicManifest_mountsPagesOnVolumeAndSourceNodesWithoutParserKeys() {
        // 过去叶子键写成 "/volume:1/source:{id}"，页面问的是 "source:{id}"，
        // 两边永远对不上：卷与来源节点都建了出来，页数全是 0，页面一律回退到根。
        UUID itemId = UUID.fromString("20000000-0000-0000-0000-000000000021");
        UUID firstSourceId = UUID.fromString("30000000-0000-0000-0000-000000000021");
        UUID secondSourceId = UUID.fromString("30000000-0000-0000-0000-000000000022");
        ReaderItemSource firstSource = source(firstSourceId, itemId, "葬送的芙莉莲 Vol.1.cbz", 1);
        ReaderItemSource secondSource = source(secondSourceId, itemId, "葬送的芙莉莲 Vol.2.cbz", 2);
        List<ReaderPage> firstPages = flatPages(itemId, firstSourceId, 2);
        List<ReaderPage> secondPages = flatPages(itemId, secondSourceId, 3);

        when(sourceRepository.findByReaderItemId(itemId)).thenReturn(List.of(firstSource, secondSource));
        when(pageRepository.findBySourceId(firstSourceId)).thenReturn(firstPages);
        when(pageRepository.findBySourceId(secondSourceId)).thenReturn(secondPages);
        when(pageRepository.saveAll(anyList())).thenAnswer(invocation -> invocation.getArgument(0));
        when(catalogRepository.saveAll(anyList())).thenAnswer(invocation -> invocation.getArgument(0));
        when(itemRepository.findById(itemId)).thenReturn(Optional.empty());

        builder.rebuildComicManifest(itemId);

        List<ReaderCatalogNode> savedNodes = capturedCatalogNodes();
        ReaderCatalogNode firstLeaf = nodeForKey(savedNodes, "source:" + firstSourceId);
        ReaderCatalogNode secondLeaf = nodeForKey(savedNodes, "source:" + secondSourceId);
        assertThat(savedNodes)
                .filteredOn(node -> "VOLUME".equals(node.getNodeType()))
                .extracting(ReaderCatalogNode::getTitle, ReaderCatalogNode::getPageCount)
                .containsExactly(tuple("第1卷", 2), tuple("第2卷", 3));
        assertThat(firstLeaf.getPageCount()).isEqualTo(2);
        assertThat(secondLeaf.getPageCount()).isEqualTo(3);
        assertThat(firstLeaf.getParentId()).isEqualTo(nodeForKey(savedNodes, "volume:1").getId());
        assertThat(secondLeaf.getParentId()).isEqualTo(nodeForKey(savedNodes, "volume:2").getId());
        assertThat(firstPages).allSatisfy(page ->
                assertThat(page.getCatalogNodeId()).isEqualTo(firstLeaf.getId()));
        assertThat(secondPages).allSatisfy(page ->
                assertThat(page.getCatalogNodeId()).isEqualTo(secondLeaf.getId()));
        assertThat(nodeForKey(savedNodes, "root").getPageCount()).isEqualTo(5);
    }

    @Test
    @DisplayName("压缩包内子目录挂在各自的来源节点之下")
    void rebuildComicManifest_mountsArchiveSubdirectoriesUnderTheirSource() {
        UUID itemId = UUID.fromString("20000000-0000-0000-0000-000000000022");
        UUID sourceId = UUID.fromString("30000000-0000-0000-0000-000000000023");
        ReaderItemSource archive = source(sourceId, itemId, "合订本.cbz", 1);
        List<ReaderPage> pages = new ArrayList<>(List.of(
                pageAt(itemId, sourceId, 0, "ch01/001.jpg"),
                pageAt(itemId, sourceId, 1, "ch01/002.jpg"),
                pageAt(itemId, sourceId, 2, "ch02/001.jpg")));

        when(sourceRepository.findByReaderItemId(itemId)).thenReturn(List.of(archive));
        when(pageRepository.findBySourceId(sourceId)).thenReturn(pages);
        when(pageRepository.saveAll(anyList())).thenAnswer(invocation -> invocation.getArgument(0));
        when(catalogRepository.saveAll(anyList())).thenAnswer(invocation -> invocation.getArgument(0));
        when(itemRepository.findById(itemId)).thenReturn(Optional.empty());

        builder.rebuildComicManifest(itemId);

        List<ReaderCatalogNode> savedNodes = capturedCatalogNodes();
        ReaderCatalogNode sourceLeaf = nodeForKey(savedNodes, "source:" + sourceId);
        ReaderCatalogNode firstChapter = nodeForKey(savedNodes, "source:" + sourceId + "/path:ch01");
        ReaderCatalogNode secondChapter = nodeForKey(savedNodes, "source:" + sourceId + "/path:ch02");
        assertThat(firstChapter.getParentId()).isEqualTo(sourceLeaf.getId());
        assertThat(secondChapter.getParentId()).isEqualTo(sourceLeaf.getId());
        assertThat(firstChapter.getPageCount()).isEqualTo(2);
        assertThat(secondChapter.getPageCount()).isEqualTo(1);
        assertThat(pages.get(0).getCatalogNodeId()).isEqualTo(firstChapter.getId());
        assertThat(pages.get(2).getCatalogNodeId()).isEqualTo(secondChapter.getId());
    }

    @SuppressWarnings("unchecked")
    private List<ReaderCatalogNode> capturedCatalogNodes() {
        ArgumentCaptor<List<ReaderCatalogNode>> nodes = ArgumentCaptor.forClass(List.class);
        verify(catalogRepository, atLeastOnce()).saveAll(nodes.capture());
        return nodes.getAllValues().getLast();
    }

    private ReaderCatalogNode nodeForKey(List<ReaderCatalogNode> nodes, String catalogKey) {
        return nodes.stream()
                .filter(node -> catalogKey.equals(node.getCatalogKey()))
                .findFirst()
                .orElseThrow(() -> new AssertionError("缺少目录节点: " + catalogKey));
    }

    private List<ReaderPage> flatPages(UUID itemId, UUID sourceId, int count) {
        List<ReaderPage> pages = new ArrayList<>();
        for (int index = 0; index < count; index++) {
            pages.add(pageAt(itemId, sourceId, index, String.format("%03d.jpg", index + 1)));
        }
        return pages;
    }

    private ReaderPage pageAt(UUID itemId, UUID sourceId, int sourcePageIndex, String sourcePath) {
        ReaderPage page = new ReaderPage();
        page.setId(UUID.randomUUID());
        page.setReaderItemId(itemId);
        page.setSourceId(sourceId);
        page.setSourcePageIndex(sourcePageIndex);
        page.setSourcePath(sourcePath);
        return page;
    }

    private ReaderItemSource source(UUID sourceId, UUID itemId, String name, int chapterStart) {
        ReaderItemSource source = new ReaderItemSource();
        source.setId(sourceId);
        source.setReaderItemId(itemId);
        source.setSourceName(name);
        source.setChapterStart(chapterStart);
        source.setSourceSortKey(String.format("%04d", chapterStart));
        return source;
    }

    private List<ReaderPage> pages(UUID itemId, UUID sourceId, int count) {
        List<ReaderPage> pages = new ArrayList<>();
        for (int index = 0; index < count; index++) {
            ReaderPage page = new ReaderPage();
            page.setId(UUID.randomUUID());
            page.setReaderItemId(itemId);
            page.setSourceId(sourceId);
            page.setSourcePageIndex(index);
            page.setCatalogKey("source:" + sourceId + "/toc:第001页:0");
            pages.add(page);
        }
        return pages;
    }
}
