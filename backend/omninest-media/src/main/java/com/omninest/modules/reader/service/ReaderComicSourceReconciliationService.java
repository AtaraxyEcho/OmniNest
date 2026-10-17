package com.omninest.modules.reader.service;

import com.omninest.modules.reader.domain.ReaderItemSource;
import com.omninest.modules.reader.repository.ReaderItemSourceRepository;
import java.util.ArrayList;
import java.util.List;
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
 * <p>回正走 {@link ComicManifestBuilder#rebuildComicManifest(UUID)}：纯数据库操作，不改
 * importStatus、不投递解析任务，用户看不到"重新解析中"，也不会重跑压缩包解析。只有数值
 * 真的变化才落库并重建目录。
 */
@Slf4j
@Service
@RequiredArgsConstructor
public class ReaderComicSourceReconciliationService {

    private static final String CONTENT_KIND_COMIC = "COMIC";

    private final ReaderItemSourceRepository sourceRepository;
    private final ReaderComicManifestService manifestService;
    private final ComicManifestBuilder manifestBuilder;

    /**
     * 分页取出待对账的漫画条目 ID。
     *
     * @param page 页码，从 0 开始
     * @param size 每页条目数
     * @return 条目 ID 列表
     */
    public List<UUID> findReconcileCandidateIds(int page, int size) {
        return sourceRepository.findComicItemIds(CONTENT_KIND_COMIC, PageRequest.of(page, size));
    }

    /**
     * 按当前解析规则回正单个条目的来源排序元数据。
     *
     * @param itemId 漫画条目 ID
     * @return true 表示该条目发生了回正
     */
    @Transactional(rollbackFor = Exception.class)
    public boolean reconcileItem(UUID itemId) {
        List<ReaderItemSource> changed = new ArrayList<>();
        for (ReaderItemSource source : sourceRepository.findByReaderItemId(itemId)) {
            SortKeySnapshot before = snapshot(source);
            manifestService.applySourceSortMetadata(source, source.getSourceName());
            if (!before.equals(snapshot(source))) {
                changed.add(source);
            }
        }
        if (changed.isEmpty()) {
            return false;
        }
        sourceRepository.saveAll(changed);
        manifestBuilder.rebuildComicManifest(itemId);
        log.info("回正漫画来源排序元数据: itemId={}, 来源数={}", itemId, changed.size());
        return true;
    }

    private SortKeySnapshot snapshot(ReaderItemSource source) {
        return new SortKeySnapshot(
                source.getSeasonNo(),
                source.getVolumeNo(),
                source.getChapterStart(),
                source.getChapterEnd(),
                source.getExtraOrder(),
                source.getSourceSortKey()
        );
    }

    /** 参与差异比较的排序字段快照。 */
    private record SortKeySnapshot(
            Integer seasonNo,
            Integer volumeNo,
            Integer chapterStart,
            Integer chapterEnd,
            Integer extraOrder,
            String sourceSortKey
    ) {
    }
}
