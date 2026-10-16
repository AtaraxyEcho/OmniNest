package com.omninest.modules.reader.service;

import com.omninest.modules.reader.domain.ReaderCatalogNode;
import com.omninest.modules.reader.domain.ReaderItem;
import com.omninest.modules.reader.domain.ReaderItemSource;
import com.omninest.modules.reader.domain.ReaderPage;
import com.omninest.modules.reader.repository.ReaderCatalogNodeRepository;
import com.omninest.modules.reader.repository.ReaderItemRepository;
import com.omninest.modules.reader.repository.ReaderItemSourceRepository;
import com.omninest.modules.reader.repository.ReaderPageRepository;
import com.omninest.modules.reader.service.model.ComicManifestDraft;
import com.omninest.modules.reader.service.model.ComicManifestDraft.ComicCatalogDraftNode;
import com.omninest.modules.reader.service.model.ComicManifestDraft.ComicPageDraft;
import java.time.Instant;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import java.util.regex.Matcher;
import java.util.regex.Pattern;
import java.util.stream.Collectors;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * 漫画清单构建器：将 Parser 输出的 ComicManifestDraft 写入数据库。
 *
 * <p>职责：
 * <ul>
 *   <li>将 ComicPageDraft 转为 ReaderPage 实体</li>
 *   <li>将 ComicCatalogDraftNode 转为 ReaderCatalogNode 实体</li>
 *   <li>通过 catalogKey 将页面映射到目录节点</li>
 *   <li>计算目录节点的 pageStartIndex/pageEndIndex</li>
 *   <li>统一重建清单（排序来源、重排页面、递增版本）</li>
 * </ul>
 */
@Slf4j
@Service
@RequiredArgsConstructor
public class ComicManifestBuilder {

    /**
     * 来源规范顺序：季、卷、话起号、附加序号、排序键。
     *
     * <p>清单重排与"主来源迁移后取剩余首个来源"必须用同一把尺，否则删除主卷后条目主文件会跳到
     * 一个与阅读顺序无关的分卷上。
     */
    static final Comparator<ReaderItemSource> SOURCE_ORDER = Comparator
            .comparingInt((ReaderItemSource s) -> s.getSeasonNo() != null ? s.getSeasonNo() : Integer.MAX_VALUE)
            .thenComparingInt(s -> s.getVolumeNo() != null ? s.getVolumeNo() : Integer.MAX_VALUE)
            .thenComparingInt(s -> s.getChapterStart() != null ? s.getChapterStart() : Integer.MAX_VALUE)
            .thenComparingInt(s -> s.getExtraOrder() != null ? s.getExtraOrder() : Integer.MAX_VALUE)
            .thenComparing(s -> s.getSourceSortKey() != null ? s.getSourceSortKey() : "");

    private final ReaderItemRepository itemRepository;
    private final ReaderItemSourceRepository sourceRepository;
    private final ReaderCatalogNodeRepository catalogRepository;
    private final ReaderPageRepository pageRepository;

    /**
     * 将 Parser 输出的草稿写入数据库。
     *
     * <p>创建页面记录，构建目录树，更新 source 状态。
     * 不负责 manifestVersion 递增（由 rebuildComicManifest 统一处理）。
     *
     * @param draft Parser 输出的清单草稿
     */
    @Transactional(rollbackFor = Exception.class)
    public List<ReaderPage> applyDraft(ComicManifestDraft draft) {
        UUID itemId = draft.itemId();
        UUID sourceId = draft.sourceId();

        pageRepository.deleteBySourceId(sourceId);

        // 将 ComicPageDraft 转为 ReaderPage 实体
        List<ReaderPage> newPages = new ArrayList<>();
        for (ComicPageDraft pageDraft : draft.pages()) {
            ReaderPage page = new ReaderPage();
            page.setReaderItemId(itemId);
            page.setSourceId(sourceId);
            page.setSourcePageIndex(pageDraft.sourcePageIndex());
            page.setSourcePath(pageDraft.sourcePath());
            page.setWidth(pageDraft.width() > 0 ? pageDraft.width() : null);
            page.setHeight(pageDraft.height() > 0 ? pageDraft.height() : null);
            page.setFingerprint(pageDraft.fingerprint());
            page.setEntryIndex(pageDraft.entryIndex());
            page.setMimeType(pageDraft.mimeType());
            page.setByteSize(pageDraft.byteSize());
            page.setCatalogKey(pageDraft.catalogKey());
            newPages.add(page);
        }
        List<ReaderPage> savedPages = pageRepository.saveAll(newPages);

        // 2. 更新 source 页数和状态
        ReaderItemSource source = sourceRepository.findById(sourceId).orElse(null);
        if (source != null) {
            source.setPageCount(newPages.size());
            sourceRepository.save(source);
        }

        log.debug("草稿应用完成: itemId={}, sourceId={}, pages={}", itemId, sourceId, savedPages.size());
        return savedPages;
    }

    /**
     * 统一重建漫画清单：排序来源、重排页面、重建目录、递增版本。
     *
     * <p>所有格式（CBZ/ZIP/EPUB）解析完页面后都调用此方法完成最终构建。
     * 使用 source-aware 目录构建：目录 key 包含 sourceId，避免多源同名目录冲突。
     *
     * @param itemId 漫画作品 ID
     */
    @Transactional(rollbackFor = Exception.class)
    public void rebuildComicManifest(UUID itemId) {
        rebuildComicManifest(itemId, List.of());
    }

    /**
     * 使用解析器目录草稿重建漫画清单。
     *
     * @param itemId 漫画作品 ID
     * @param catalogDrafts 解析器输出的目录节点草稿
     */
    @Transactional(rollbackFor = Exception.class)
    public void rebuildComicManifest(UUID itemId, List<ComicCatalogDraftNode> catalogDrafts) {
        // 1. 按结构化排序字段排序所有来源
        List<ReaderItemSource> sources = new ArrayList<>(sourceRepository.findByReaderItemId(itemId));
        sources.sort(SOURCE_ORDER);

        // 2. 按来源顺序 + sourcePageIndex 重排全局 pageIndex
        List<ReaderPage> allPages = new ArrayList<>();
        for (ReaderItemSource src : sources) {
            List<ReaderPage> sourcePages = pageRepository.findBySourceId(src.getId());
            sourcePages.sort(Comparator.comparingInt(ReaderPage::getSourcePageIndex));
            allPages.addAll(sourcePages);
        }
        for (int i = 0; i < allPages.size(); i++) {
            allPages.get(i).setPageIndex(i);
        }
        pageRepository.saveAll(allPages);

        // 3. 构建 source-aware 目录
        catalogRepository.deleteByReaderItemId(itemId);

        // 构建来源 ID → 来源名称映射
        Map<UUID, String> sourceIdToName = new HashMap<>();
        for (ReaderItemSource src : sources) {
            sourceIdToName.put(src.getId(), src.getSourceName());
        }

        // 全量页面是跨来源目录的事实来源，当前解析任务的草稿仅作为无页面键时的回退。
        List<ReaderCatalogNode> catalogNodes = buildParsedCatalog(allPages, itemId, sourceIdToName);
        if (catalogNodes.isEmpty()) {
            catalogNodes = buildDraftCatalog(catalogDrafts, itemId);
        }
        if (catalogNodes.isEmpty()) {
            catalogNodes = buildSourceAwareCatalog(allPages, itemId, sources);
        }
        Instant catalogCreatedAt = Instant.now();
        for (ReaderCatalogNode node : catalogNodes) {
            if (node.getCreatedAt() == null) {
                node.setCreatedAt(catalogCreatedAt);
            }
        }
        catalogNodes = catalogRepository.saveAll(catalogNodes);

        // 4. 通过 catalogKey 将页面映射到目录节点
        Map<String, UUID> catalogKeyToNodeId = new HashMap<>();
        for (ReaderCatalogNode node : catalogNodes) {
            if (node.getCatalogKey() != null) {
                catalogKeyToNodeId.put(node.getCatalogKey(), node.getId());
            }
        }

        for (ReaderPage page : allPages) {
            String catalogKey = resolvePageCatalogKey(page, sourceIdToName);
            UUID nodeId = catalogKeyToNodeId.get(catalogKey);
            if (nodeId == null) {
                // 回退到 ROOT
                nodeId = catalogKeyToNodeId.getOrDefault("root", null);
            }
            page.setCatalogNodeId(nodeId);
        }
        pageRepository.saveAll(allPages);

        // 5. 计算目录节点的 pageStartIndex/pageEndIndex 和页数
        recalculateNodePageRanges(itemId, catalogNodes, allPages);

        // 6. 递增 manifestVersion
        ReaderItem item = itemRepository.findById(itemId).orElse(null);
        if (item != null) {
            item.setManifestVersion(item.getManifestVersion() + 1);
            itemRepository.save(item);
        }

        log.debug("漫画清单重建完成: itemId={}, sources={}, pages={}", itemId, sources.size(), allPages.size());
    }

    /**
     * 根据解析器写入页面的 catalogKey 构建目录。
     */
    private List<ReaderCatalogNode> buildParsedCatalog(
            List<ReaderPage> pages,
            UUID itemId,
            Map<UUID, String> sourceIdToName) {
        Map<String, ReaderCatalogNode> keyMap = new HashMap<>();
        List<ReaderCatalogNode> nodes = new ArrayList<>();

        // 只有作品里确实存在解析器写入的目录键时，才替没有键的分卷补 source 级节点。
        // 全都没有键时保持返回空，让上层继续用带季/卷聚合的 source-aware 构建，
        // 否则纯 CBZ 多卷系列会连"第一卷/第二卷"这类聚合节点一起丢掉。
        boolean hasExplicitCatalogKey = pages.stream()
                .anyMatch(page -> page.getCatalogKey() != null && !page.getCatalogKey().isBlank());

        ReaderCatalogNode rootNode = createCatalogNode(itemId, null, null, "ROOT", "全部", "root");
        nodes.add(rootNode);
        keyMap.put("root", rootNode);

        for (ReaderPage page : pages) {
            String catalogKey = page.getCatalogKey();
            if (catalogKey == null || catalogKey.isBlank()) {
                // 混排作品里 CBZ/ZIP 分卷没有解析键：不补节点它们就整卷挂在隐藏的
                // ROOT 下，从目录里彻底消失、也跳不过去。
                catalogKey = hasExplicitCatalogKey ? resolvePageCatalogKey(page, sourceIdToName) : null;
            }
            if (catalogKey == null || catalogKey.isBlank()) {
                continue;
            }
            String[] segments = catalogKey.split("/");
            StringBuilder currentKey = new StringBuilder();
            String parentKey = "root";
            for (String segment : segments) {
                if (segment == null || segment.isBlank()) {
                    continue;
                }
                if (currentKey.length() > 0) {
                    currentKey.append('/');
                }
                currentKey.append(segment);
                String key = currentKey.toString();
                if (!keyMap.containsKey(key)) {
                    ReaderCatalogNode parent = keyMap.getOrDefault(parentKey, rootNode);
                    UUID segmentSourceId = parseSourceId(segment);
                    String title = segmentSourceId == null
                            ? segmentTitle(segment)
                            : stripExtension(sourceIdToName.getOrDefault(segmentSourceId, "漫画来源"));
                    String nodeType = segmentSourceId == null ? detectNodeType(title) : "COLLECTION";
                    ReaderCatalogNode node = createCatalogNode(
                            itemId,
                            parent.getId(),
                            segmentSourceId == null ? page.getSourceId() : segmentSourceId,
                            nodeType,
                            title,
                            key);
                    nodes.add(node);
                    keyMap.put(key, node);
                }
                parentKey = key;
            }
        }

        if (nodes.size() <= 1) {
            return List.of();
        }
        assignSortIndices(nodes);
        return nodes;
    }

    /**
     * 根据解析器提供的目录草稿构建目录。
     */
    private List<ReaderCatalogNode> buildDraftCatalog(List<ComicCatalogDraftNode> drafts, UUID itemId) {
        if (drafts == null || drafts.isEmpty()) {
            return List.of();
        }

        List<ReaderCatalogNode> nodes = new ArrayList<>();
        Map<String, ReaderCatalogNode> keyMap = new HashMap<>();
        ReaderCatalogNode rootNode = createCatalogNode(itemId, null, null, "ROOT", "全部", "root");
        nodes.add(rootNode);
        keyMap.put("root", rootNode);

        List<ComicCatalogDraftNode> sortedDrafts = new ArrayList<>(drafts);
        sortedDrafts.sort(Comparator
                .comparingInt((ComicCatalogDraftNode node) -> depthOf(node.catalogKey()))
                .thenComparingInt(ComicCatalogDraftNode::sortOrder));

        for (ComicCatalogDraftNode draft : sortedDrafts) {
            if (draft.catalogKey() == null || draft.catalogKey().isBlank()
                    || keyMap.containsKey(draft.catalogKey())) {
                continue;
            }

            ReaderCatalogNode parent = resolveDraftParent(draft, itemId, keyMap, nodes, rootNode);
            ReaderCatalogNode node = createCatalogNode(
                    itemId,
                    parent.getId(),
                    draft.sourceId(),
                    draft.nodeType(),
                    draft.title(),
                    draft.catalogKey());
            node.setSortIndex(draft.sortOrder());
            nodes.add(node);
            keyMap.put(draft.catalogKey(), node);
        }

        if (nodes.size() <= 1) {
            return List.of();
        }
        assignSortIndices(nodes);
        return nodes;
    }

    private ReaderCatalogNode resolveDraftParent(
            ComicCatalogDraftNode draft,
            UUID itemId,
            Map<String, ReaderCatalogNode> keyMap,
            List<ReaderCatalogNode> nodes,
            ReaderCatalogNode rootNode) {
        String parentKey = draft.parentKey();
        if (parentKey == null || parentKey.isBlank()) {
            return rootNode;
        }
        ReaderCatalogNode existing = keyMap.get(parentKey);
        if (existing != null) {
            return existing;
        }

        ReaderCatalogNode parent = rootNode;
        String[] segments = parentKey.split("/");
        StringBuilder currentKey = new StringBuilder();
        for (String segment : segments) {
            if (segment == null || segment.isBlank()) {
                continue;
            }
            if (currentKey.length() > 0) {
                currentKey.append('/');
            }
            currentKey.append(segment);
            String key = currentKey.toString();
            ReaderCatalogNode node = keyMap.get(key);
            if (node == null) {
                node = createCatalogNode(
                        itemId,
                        parent.getId(),
                        null,
                        detectNodeType(segmentTitle(segment)),
                        segmentTitle(segment),
                        key);
                nodes.add(node);
                keyMap.put(key, node);
            }
            parent = node;
        }
        return parent;
    }

    private int depthOf(String catalogKey) {
        if (catalogKey == null || catalogKey.isBlank()) {
            return 0;
        }
        return catalogKey.split("/").length;
    }

    private ReaderCatalogNode createCatalogNode(
            UUID itemId,
            UUID parentId,
            UUID sourceId,
            String nodeType,
            String title,
            String catalogKey) {
        ReaderCatalogNode node = new ReaderCatalogNode();
        node.setId(UUID.randomUUID());
        node.setReaderItemId(itemId);
        node.setParentId(parentId);
        node.setSourceId(sourceId);
        node.setNodeType(nodeType);
        node.setTitle(title);
        node.setCatalogKey(catalogKey);
        return node;
    }

    private String segmentTitle(String segment) {
        int colonIndex = segment.indexOf(':');
        int lastColonIndex = segment.lastIndexOf(':');
        if (colonIndex >= 0 && colonIndex + 1 < segment.length()) {
            if (lastColonIndex > colonIndex && lastColonIndex + 1 < segment.length()
                    && segment.substring(lastColonIndex + 1).matches("\\d+")) {
                return segment.substring(colonIndex + 1, lastColonIndex);
            }
            return segment.substring(colonIndex + 1);
        }
        return segment;
    }

    private UUID parseSourceId(String segment) {
        if (segment == null || !segment.startsWith("source:")) {
            return null;
        }
        try {
            return UUID.fromString(segment.substring("source:".length()));
        } catch (IllegalArgumentException exception) {
            log.warn("漫画目录来源键无效: segment={}", segment);
            return null;
        }
    }

    /**
     * 构建 source-aware 目录树。
     *
     * <p>键只有一套规则：聚合节点 {@code season:S/volume:V}（无季号时为 {@code volume:V}）、
     * 来源叶子 {@code source:{sourceId}}、压缩包内部目录 {@code source:{sourceId}/path:{dir}}。
     * 页面归属由 {@link #resolvePageCatalogKey} 生成同形状的键；两边规则不一致时页面会全部回退到
     * ROOT，目录节点看着在、页数却是 0，跳章也就落不到位置。
     *
     * @param pages 全部页面
     * @param itemId 漫画作品 ID
     * @param sources 已按清单顺序排序的来源
     * @return 目录节点
     */
    private List<ReaderCatalogNode> buildSourceAwareCatalog(
            List<ReaderPage> pages, UUID itemId, List<ReaderItemSource> sources) {

        List<ReaderCatalogNode> nodes = new ArrayList<>();
        Map<String, ReaderCatalogNode> keyMap = new HashMap<>();
        ReaderCatalogNode rootNode = createCatalogNode(itemId, null, null, "ROOT", "全部", "root");
        nodes.add(rootNode);
        keyMap.put("root", rootNode);

        // sortIndex 由深度优先按插入顺序分配，所以这里必须沿用清单顺序
        List<SourceMeta> metas = new ArrayList<>();
        for (ReaderItemSource source : sources) {
            metas.add(parseSourceMeta(source.getId(), source.getSourceName()));
        }

        boolean hasStructuredSources = sources.size() > 1
                || metas.stream().anyMatch(meta -> ComicVolumeParser.hasPartSignal(meta.sourceName));
        if (hasStructuredSources) {
            appendAggregateNodes(nodes, keyMap, itemId, metas);
        }
        appendSourceNodes(nodes, keyMap, itemId, metas);
        appendInternalDirNodes(nodes, keyMap, itemId, pages);

        assignSortIndices(nodes);
        return nodes;
    }

    /**
     * 按季→卷建聚合节点。
     */
    private void appendAggregateNodes(
            List<ReaderCatalogNode> nodes,
            Map<String, ReaderCatalogNode> keyMap,
            UUID itemId,
            List<SourceMeta> metas) {

        for (SourceMeta meta : metas) {
            if (meta.seasonNo != null) {
                String seasonKey = "season:" + meta.seasonNo;
                if (!keyMap.containsKey(seasonKey)) {
                    ReaderCatalogNode seasonNode = createCatalogNode(
                            itemId, nodes.get(0).getId(), null, "SEASON", "第" + meta.seasonNo + "季", seasonKey);
                    nodes.add(seasonNode);
                    keyMap.put(seasonKey, seasonNode);
                }
            }
            if (meta.volumeNo != null) {
                // 没有季号也要能单独成卷：过去卷节点只在季号分支里创建，"Vol.1"这类命名既没有卷节点，
                // 叶子键又带上不存在的父前缀，整个来源的页面只能回退到根。
                String volumeKey = volumeKey(meta);
                UUID volumeParentId = meta.seasonNo == null
                        ? nodes.get(0).getId()
                        : keyMap.get("season:" + meta.seasonNo).getId();
                if (!keyMap.containsKey(volumeKey)) {
                    ReaderCatalogNode volumeNode = createCatalogNode(
                            itemId, volumeParentId, null, "VOLUME", "第" + meta.volumeNo + "卷", volumeKey);
                    nodes.add(volumeNode);
                    keyMap.put(volumeKey, volumeNode);
                }
            }
        }
    }

    /**
     * 为每个来源建叶子节点，挂在最深的聚合节点之下。
     */
    private void appendSourceNodes(
            List<ReaderCatalogNode> nodes,
            Map<String, ReaderCatalogNode> keyMap,
            UUID itemId,
            List<SourceMeta> metas) {

        for (SourceMeta meta : metas) {
            String leafKey = "source:" + meta.sourceId;
            if (keyMap.containsKey(leafKey)) {
                continue;
            }
            ReaderCatalogNode parent = resolveAggregateParent(keyMap, meta);
            ReaderCatalogNode leafNode = createCatalogNode(
                    itemId,
                    parent.getId(),
                    meta.sourceId,
                    detectNodeType(meta.sourceName),
                    meta.sourceName.isBlank() ? "漫画来源" : meta.sourceName,
                    leafKey);
            nodes.add(leafNode);
            keyMap.put(leafKey, leafNode);
        }
    }

    /**
     * 把压缩包内部的子目录逐级挂在所属来源节点之下。
     */
    private void appendInternalDirNodes(
            List<ReaderCatalogNode> nodes,
            Map<String, ReaderCatalogNode> keyMap,
            UUID itemId,
            List<ReaderPage> pages) {

        for (ReaderPage page : pages) {
            String parentDir = getParentDir(page.getSourcePath());
            if (parentDir == null || parentDir.isEmpty()) {
                continue;
            }
            String sourceKey = "source:" + page.getSourceId();
            ReaderCatalogNode parent = keyMap.getOrDefault(sourceKey, keyMap.get("root"));
            StringBuilder currentPath = new StringBuilder();
            for (String segment : parentDir.split("/")) {
                if (segment.isEmpty()) {
                    continue;
                }
                if (currentPath.length() > 0) {
                    currentPath.append('/');
                }
                currentPath.append(segment);
                String dirKey = sourceKey + "/path:" + currentPath;
                ReaderCatalogNode dirNode = keyMap.get(dirKey);
                if (dirNode == null) {
                    dirNode = createCatalogNode(
                            itemId, parent.getId(), page.getSourceId(), detectNodeType(segment), segment, dirKey);
                    nodes.add(dirNode);
                    keyMap.put(dirKey, dirNode);
                }
                parent = dirNode;
            }
        }
    }

    /**
     * 来源叶子节点的父节点：卷优先于季，都没有时回到根。
     */
    private ReaderCatalogNode resolveAggregateParent(Map<String, ReaderCatalogNode> keyMap, SourceMeta meta) {
        if (meta.volumeNo != null) {
            ReaderCatalogNode volume = keyMap.get(volumeKey(meta));
            if (volume != null) {
                return volume;
            }
        }
        if (meta.seasonNo != null) {
            ReaderCatalogNode season = keyMap.get("season:" + meta.seasonNo);
            if (season != null) {
                return season;
            }
        }
        return keyMap.get("root");
    }

    /**
     * 卷节点的键：有季号时带季前缀，没有时独立成卷。
     */
    private static String volumeKey(SourceMeta meta) {
        return meta.seasonNo == null
                ? "volume:" + meta.volumeNo
                : "season:" + meta.seasonNo + "/volume:" + meta.volumeNo;
    }

    /**
     * 解析页面对应的 catalogKey。
     * 优先匹配 source-aware 路径，回退到 source 叶子节点。
     */
    private String resolvePageCatalogKey(ReaderPage page, Map<UUID, String> sourceIdToName) {
        if (page.getCatalogKey() != null && !page.getCatalogKey().isBlank()) {
            return page.getCatalogKey();
        }
        String parentDir = getParentDir(page.getSourcePath());
        if (parentDir != null && !parentDir.isEmpty()) {
            return "source:" + page.getSourceId() + "/path:" + parentDir;
        }
        return "source:" + page.getSourceId();
    }

    /**
     * 重新计算目录节点的 pageStartIndex/pageEndIndex 和页数。
     */
    private void recalculateNodePageRanges(
            UUID itemId, List<ReaderCatalogNode> catalogNodes, List<ReaderPage> allPages) {

        // 收集每个节点的直接页面
        Map<UUID, List<Integer>> nodePageIndices = new HashMap<>();
        for (ReaderPage page : allPages) {
            if (page.getCatalogNodeId() != null) {
                nodePageIndices.computeIfAbsent(page.getCatalogNodeId(), k -> new ArrayList<>())
                        .add(page.getPageIndex());
            }
        }

        // 构建父→子映射
        Map<UUID, List<ReaderCatalogNode>> childrenMap = new HashMap<>();
        for (ReaderCatalogNode node : catalogNodes) {
            if (node.getParentId() != null) {
                childrenMap.computeIfAbsent(node.getParentId(), k -> new ArrayList<>()).add(node);
            }
        }

        // 递归聚合
        for (ReaderCatalogNode node : catalogNodes) {
            List<Integer> allIndices = aggregatePageIndices(node.getId(), nodePageIndices, childrenMap);
            if (!allIndices.isEmpty()) {
                allIndices.sort(Integer::compareTo);
                node.setPageIndexStart(allIndices.get(0));
                node.setPageIndexEnd(allIndices.get(allIndices.size() - 1));
                node.setPageCount(allIndices.size());
            } else {
                node.setPageCount(0);
            }
        }
        catalogRepository.saveAll(catalogNodes);
    }

    private List<Integer> aggregatePageIndices(
            UUID nodeId,
            Map<UUID, List<Integer>> directCounts,
            Map<UUID, List<ReaderCatalogNode>> childrenMap) {

        List<Integer> indices = new ArrayList<>(directCounts.getOrDefault(nodeId, List.of()));
        for (ReaderCatalogNode child : childrenMap.getOrDefault(nodeId, List.of())) {
            indices.addAll(aggregatePageIndices(child.getId(), directCounts, childrenMap));
        }
        return indices;
    }

    // ── Helper methods ────────────────────────────────────────────

    private static class SourceMeta {
        UUID sourceId;
        String sourceName;
        Integer seasonNo;
        Integer volumeNo;
        Integer chapterStart;
        Integer chapterEnd;
        Integer extraOrder;
    }

    /**
     * 解析来源文件名里的季/卷/话结构。
     *
     * <p>入参必须带扩展名：分卷号常写成 "Vol.1"，把 ".1" 当扩展名削掉后就再也认不出卷号，
     * 卷节点与页面归属会一起落空。
     */
    private SourceMeta parseSourceMeta(UUID sourceId, String rawName) {
        SourceMeta meta = new SourceMeta();
        meta.sourceId = sourceId;
        meta.sourceName = stripExtension(rawName);
        if (rawName == null || rawName.isBlank()) return meta;
        String lower = rawName.toLowerCase();

        // 卷/季：先按窄正则填，再由 ComicVolumeParser 补齐它认得而这里认不出的写法
        Matcher season = Pattern.compile("s(\\d+)|season\\s*(\\d+)|第(\\d+)季").matcher(lower);
        if (season.find()) {
            String num = season.group(1) != null ? season.group(1) : season.group(2) != null ? season.group(2) : season.group(3);
            meta.seasonNo = Integer.parseInt(num);
        }

        Matcher vol = Pattern.compile("vol\\.?\\s*(\\d+)|volume\\s*(\\d+)|第(\\d+)卷").matcher(lower);
        if (vol.find()) {
            String num = vol.group(1) != null ? vol.group(1) : vol.group(2) != null ? vol.group(2) : vol.group(3);
            meta.volumeNo = Integer.parseInt(num);
        }

        // 话/章区间：兼容 ch/chapter/第X话章 及日式"話001-010"
        // 分卷判据必须与 `ReaderComicManifestService.applySourceSortMetadata` 同源：那里已经用
        // ComicVolumeParser 认出"第三卷"（中文数字）、"卷01"/"巻01"（前缀式）与 S01E02 并落库，
        // 这里只认 EPISODE/CHAPTER 时排序认得出卷号、目录却生不出"第X卷"聚合节点。
        ComicVolumeParser.PartInfo part = ComicVolumeParser.parse(rawName);
        boolean chapterFromParser = false;
        if (part.matched() && part.partNo() != null) {
            switch (part.partKind()) {
                case "VOL" -> meta.volumeNo = part.partNo();
                case "SEASON" -> meta.seasonNo = part.partNo();
                case "SEASON_EP" -> {
                    meta.seasonNo = part.partNo();
                    meta.chapterStart = part.rangeEnd();
                    meta.chapterEnd = part.rangeEnd();
                    chapterFromParser = part.rangeEnd() != null;
                }
                case "EPISODE", "CHAPTER" -> {
                    meta.chapterStart = part.partNo();
                    meta.chapterEnd = part.rangeEnd() != null ? part.rangeEnd() : part.partNo();
                    chapterFromParser = true;
                }
                default -> {
                }
            }
        }

        if (!chapterFromParser) {
            Matcher range = Pattern.compile(
                    "(?:ch\\.?\\s*|chapter\\s*|第)(\\d{1,4})\\s*[-~]\\s*(\\d{1,4})(?:话|章)?").matcher(lower);
            if (range.find()) {
                meta.chapterStart = Integer.parseInt(range.group(1));
                meta.chapterEnd = Integer.parseInt(range.group(2));
            } else {
                Matcher singleCh = Pattern.compile("(?:ch\\.?\\s*|chapter\\s*|第)(\\d+)(?:话|章)?").matcher(lower);
                if (singleCh.find()) {
                    int ch = Integer.parseInt(singleCh.group(1));
                    meta.chapterStart = ch;
                    meta.chapterEnd = ch;
                }
            }
        }

        if (lower.contains("extra") || lower.contains("番外") || lower.contains("special")) {
            Matcher extraNum = Pattern.compile("(?:extra|番外|special)\\s*(\\d+)").matcher(lower);
            meta.extraOrder = extraNum.find() ? Integer.parseInt(extraNum.group(1)) : 1;
        }

        return meta;
    }

    /**
     * 深度优先分配 sortIndex。
     */
    private void assignSortIndices(List<ReaderCatalogNode> nodes) {
        Map<UUID, List<ReaderCatalogNode>> childrenMap = new HashMap<>();
        ReaderCatalogNode root = null;
        for (ReaderCatalogNode node : nodes) {
            if ("ROOT".equals(node.getNodeType())) {
                root = node;
            }
            if (node.getParentId() != null) {
                childrenMap.computeIfAbsent(node.getParentId(), k -> new ArrayList<>()).add(node);
            }
        }
        if (root == null) return;

        int[] counter = {0};
        assignDfs(root, childrenMap, counter);
    }

    private void assignDfs(ReaderCatalogNode node, Map<UUID, List<ReaderCatalogNode>> childrenMap, int[] counter) {
        node.setSortIndex(counter[0]++);
        for (ReaderCatalogNode child : childrenMap.getOrDefault(node.getId(), List.of())) {
            assignDfs(child, childrenMap, counter);
        }
    }

    private String detectNodeType(String name) {
        if (name == null) return "CHAPTER";
        String lower = name.toLowerCase();
        if (lower.matches("s\\d+.*|season\\s*\\d+|第.+季")) return "SEASON";
        if (lower.matches("vol\\.?\\s*\\d+|volume\\s*\\d+|第.+卷")) return "VOLUME";
        if (lower.matches("ch\\.?\\s*\\d+|chapter\\s*\\d+|第.+话|第.+章")) return "CHAPTER";
        if (lower.matches("\\d+\\s*[-~]\\s*\\d+")) return "COLLECTION";
        if (lower.contains("extra") || lower.contains("sp") || lower.contains("番外")) return "EXTRA";
        return "CHAPTER";
    }

    private String stripExtension(String fileName) {
        if (fileName == null) return "";
        int lastDot = fileName.lastIndexOf('.');
        return lastDot > 0 ? fileName.substring(0, lastDot) : fileName;
    }

    private String getParentDir(String path) {
        if (path == null) return null;
        int lastSlash = path.lastIndexOf('/');
        return lastSlash > 0 ? path.substring(0, lastSlash) : null;
    }
}
