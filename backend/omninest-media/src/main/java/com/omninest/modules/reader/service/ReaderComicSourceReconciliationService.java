package com.omninest.modules.reader.service;

import com.omninest.modules.reader.domain.ReaderItemSource;
import com.omninest.modules.reader.domain.ReaderPage;
import com.omninest.modules.reader.repository.ReaderItemRepository;
import com.omninest.modules.reader.repository.ReaderItemSourceRepository;
import com.omninest.modules.reader.repository.ReaderPageRepository;
import java.util.ArrayList;
import java.util.HashSet;
import java.util.List;
import java.util.Set;
import java.util.UUID;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.data.domain.PageRequest;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * 漫画来源排序元数据对账服务。
 *
 * <p>季号、卷号、话号区间与排序键只在来源新建时按当时的解析规则落库，解析规则改口径后
 * 已有行不会自己回正，而目录重排、"主来源迁移后取剩余首个来源"与清单排序都以这几列为
 * 尺子，脏值会一直把来源排到错误的季节点下。
 *
 * <p>回正分两级：数值变化一律落库；只有目录形状（来源顺序、来源显示名与季/卷聚合归属）
 * 真的变了才重建清单。重建会递增 manifestVersion 并重新生成目录节点，客户端遇到版本
 * 不匹配会丢弃页码锚点退回按百分比恢复，所以不该重建时绝不重建。
 *
 * <p>{@link #previewItem(UUID)} 走只读事务，供试运行统计规模：写入事务里改受管实体即使
 * 不调用 save 也会在提交时被脏检查刷库。
 */
@Slf4j
@Service
@RequiredArgsConstructor
public class ReaderComicSourceReconciliationService {

    private static final String CONTENT_KIND_COMIC = "COMIC";

    /** 游标起点：nil UUID 按字典序小于任何条目 ID。 */
    public static final UUID FIRST_CURSOR = new UUID(0L, 0L);

    private final ReaderItemRepository itemRepository;
    private final ReaderItemSourceRepository sourceRepository;
    private final ReaderPageRepository pageRepository;
    private final ReaderComicManifestService manifestService;
    private final ComicManifestBuilder manifestBuilder;

    /**
     * 从给定游标往后取下一段待对账的漫画条目 ID。
     *
     * @param afterId 上一轮最后处理的条目 ID，从头开始时传 {@link #FIRST_CURSOR}
     * @param size    单段条目数
     * @return 条目 ID，按字典序升序
     */
    public List<UUID> findReconcileCandidateIds(UUID afterId, int size) {
        return sourceRepository.findComicItemIdsAfter(CONTENT_KIND_COMIC, afterId, PageRequest.of(0, size));
    }

    /**
     * 只统计不落库：用于首轮确认回正规模。
     *
     * @param itemId 漫画条目 ID
     * @return 该条目的回正结论
     */
    @Transactional(readOnly = true)
    public ReconcileOutcome previewItem(UUID itemId) {
        return evaluate(itemId).outcome();
    }

    /**
     * 按当前解析规则回正单个条目，并在目录形状变化时重建清单。
     *
     * <p>先取条目行锁再动手：导入、加入来源与删除来源的链路都持同一把 {@code findByIdForUpdate}
     * 锁，清单重建只靠 {@code ReaderItem} 的乐观锁保护，不排队就会撞成一次无谓的回滚。
     *
     * @param itemId 漫画条目 ID
     * @return 该条目的回正结论
     */
    @Transactional(rollbackFor = Exception.class)
    public ReconcileOutcome reconcileItem(UUID itemId) {
        if (itemRepository.findByIdForUpdate(itemId).isEmpty()) {
            return ReconcileOutcome.UNCHANGED;
        }
        Evaluation evaluation = evaluate(itemId);
        if (evaluation.outcome() == ReconcileOutcome.UNCHANGED) {
            return ReconcileOutcome.UNCHANGED;
        }
        sourceRepository.saveAll(evaluation.changed());
        if (evaluation.outcome() == ReconcileOutcome.REBUILD_REQUIRED) {
            clearDanglingCatalogRefs(evaluation.sources());
            manifestBuilder.rebuildComicManifest(itemId);
            log.info("回正漫画来源排序元数据并重建目录: itemId={}, 来源数={}", itemId, evaluation.changed().size());
        } else {
            log.info("回正漫画来源排序元数据（目录形状未变，跳过重建）: itemId={}, 来源数={}",
                    itemId, evaluation.changed().size());
        }
        return evaluation.outcome();
    }

    private Evaluation evaluate(UUID itemId) {
        List<ReaderItemSource> sources = sourceRepository.findByReaderItemId(itemId);
        if (sources.isEmpty()) {
            return new Evaluation(List.of(), List.of(), ReconcileOutcome.UNCHANGED);
        }
        List<SourceSignature> shapeBefore = catalogShape(sources);
        List<ReaderItemSource> changed = new ArrayList<>();
        for (ReaderItemSource source : sources) {
            MetadataSnapshot before = snapshot(source);
            manifestService.applySourceSortMetadata(source, source.getSourceName());
            if (!before.equals(snapshot(source))) {
                changed.add(source);
            }
        }
        if (changed.isEmpty()) {
            return new Evaluation(sources, List.of(), ReconcileOutcome.UNCHANGED);
        }
        boolean shapeChanged = !shapeBefore.equals(catalogShape(sources));
        return new Evaluation(sources, changed,
                shapeChanged ? ReconcileOutcome.REBUILD_REQUIRED : ReconcileOutcome.METADATA_ONLY);
    }

    /**
     * 目录形状签名：来源顺序、来源显示名与季/卷聚合归属。
     *
     * <p>顺序决定页码编排，显示名决定叶子节点标题与类型，季/卷决定聚合节点，三者不变则
     * 重建出来的是同一棵树，不值得让客户端丢锚点。
     */
    private List<SourceSignature> catalogShape(List<ReaderItemSource> sources) {
        List<ReaderItemSource> ordered = new ArrayList<>(sources);
        ordered.sort(ComicManifestBuilder.SOURCE_ORDER);
        return ordered.stream()
                .map(source -> new SourceSignature(
                        source.getId(),
                        ComicVolumeParser.stripExtension(source.getSourceName()),
                        source.getSeasonNo(),
                        source.getVolumeNo()
                ))
                .toList();
    }

    /**
     * 清掉指向已被删除目录节点的页面引用。
     *
     * <p>重建只处理当前来源下的页面；来源行已不存在却仍留有页面时，这些页的节点 ID 会随
     * 旧目录一起被删掉而悬空。只清引用不删页：删页会连带把按 page_id 关联的派生资产变成
     * 无人引用的残留。
     */
    private void clearDanglingCatalogRefs(List<ReaderItemSource> sources) {
        Set<UUID> liveSourceIds = new HashSet<>();
        for (ReaderItemSource source : sources) {
            liveSourceIds.add(source.getId());
        }
        List<ReaderPage> dangling = new ArrayList<>();
        for (ReaderPage page : pageRepository.findByReaderItemIdOrderByPageIndex(sources.get(0).getReaderItemId())) {
            if (page.getCatalogNodeId() == null) {
                continue;
            }
            if (page.getSourceId() == null || !liveSourceIds.contains(page.getSourceId())) {
                page.setCatalogNodeId(null);
                dangling.add(page);
            }
        }
        if (!dangling.isEmpty()) {
            pageRepository.saveAll(dangling);
            log.info("清理漫画目录悬空页引用: itemId={}, 页数={}", sources.get(0).getReaderItemId(), dangling.size());
        }
    }

    private MetadataSnapshot snapshot(ReaderItemSource source) {
        return new MetadataSnapshot(
                source.getSeasonNo(),
                source.getVolumeNo(),
                source.getChapterStart(),
                source.getChapterEnd(),
                source.getExtraOrder(),
                source.getSourceSortKey()
        );
    }

    /** 参与差异比较的排序字段快照。 */
    private record MetadataSnapshot(
            Integer seasonNo,
            Integer volumeNo,
            Integer chapterStart,
            Integer chapterEnd,
            Integer extraOrder,
            String sourceSortKey
    ) {
    }

    /** 决定是否需要重建清单的目录形状单元。 */
    private record SourceSignature(
            UUID sourceId,
            String displayName,
            Integer seasonNo,
            Integer volumeNo
    ) {
    }

    /** 单条目评估结果。 */
    private record Evaluation(
            List<ReaderItemSource> sources,
            List<ReaderItemSource> changed,
            ReconcileOutcome outcome
    ) {
    }

    /** 单条目对账结论。 */
    public enum ReconcileOutcome {

        /** 数值与当前规则一致，无需任何写入。 */
        UNCHANGED,

        /** 排序元数据已回正，目录形状未变，不重建清单。 */
        METADATA_ONLY,

        /** 排序元数据已回正且目录形状变化，已重建清单。 */
        REBUILD_REQUIRED
    }
}
