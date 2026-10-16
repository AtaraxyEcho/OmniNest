package com.omninest.modules.reader.service;

import com.omninest.common.sync.SyncScope;
import com.omninest.modules.file.event.FileNodesSoftDeletedEvent;
import com.omninest.modules.file.service.FileBusinessReference;
import com.omninest.modules.file.service.FilePurgeParticipant;
import com.omninest.modules.reader.domain.ReaderPageAsset;
import com.omninest.modules.reader.domain.ReaderTextChapter;
import com.omninest.modules.file.service.PurgeContext;
import com.omninest.modules.file.service.PurgeContributionWriter;
import com.omninest.modules.media.service.MediaFileVisibilitySyncParticipant;
import com.omninest.modules.media.service.MediaSyncEventService;
import com.omninest.modules.reader.domain.ReaderItem;
import com.omninest.modules.reader.domain.ReaderItemSource;
import com.omninest.modules.reader.repository.ReaderAnnotationRepository;
import com.omninest.modules.reader.repository.ReaderBookmarkRepository;
import com.omninest.modules.reader.repository.ReaderBookshelfRepository;
import com.omninest.modules.reader.repository.ReaderCatalogNodeRepository;
import com.omninest.modules.reader.repository.ReaderItemRepository;
import com.omninest.modules.reader.repository.ReaderItemSourceRepository;
import com.omninest.modules.reader.repository.ReaderNoteRepository;
import com.omninest.modules.reader.repository.ReaderPageAssetRepository;
import com.omninest.modules.reader.repository.ReaderPageRepository;
import com.omninest.modules.reader.repository.ReaderProgressRepository;
import com.omninest.modules.reader.repository.ReaderReadingSessionRepository;
import com.omninest.modules.reader.repository.ReaderTextChapterRepository;
import java.util.ArrayList;
import java.util.Collection;
import java.util.HashSet;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Map;
import java.util.Objects;
import java.util.Set;
import java.util.UUID;
import java.util.stream.Collectors;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.context.event.EventListener;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * 文件删除触发的阅读业务数据清理服务。
 *
 * @author OmniNest
 */
@Slf4j
@Service
@RequiredArgsConstructor
public class ReaderFileCleanupService implements
        FilePurgeParticipant,
        MediaFileVisibilitySyncParticipant {
    private static final String MODULE = "READER";
    private static final String RESOURCE_TYPE = "READER_ITEM";
    private final ReaderItemRepository itemRepository;
    private final ReaderItemSourceRepository itemSourceRepository;
    private final ReaderPageAssetRepository pageAssetRepository;
    private final ReaderPageRepository pageRepository;
    private final ReaderCatalogNodeRepository catalogRepository;
    private final ReaderTextChapterRepository textChapterRepository;
    private final ReaderProgressRepository progressRepository;
    private final ReaderBookmarkRepository bookmarkRepository;
    private final ReaderAnnotationRepository annotationRepository;
    private final ReaderNoteRepository noteRepository;
    private final ReaderBookshelfRepository bookshelfRepository;
    private final ReaderReadingSessionRepository readingSessionRepository;
    private final MediaSyncEventService syncEventService;
    private final ReaderComicManifestService comicManifestService;

    /**
     * 查询目标文件作为阅读主来源或附加来源的业务引用。
     *
     * @param context 删除上下文
     * @return 阅读条目引用
     */
    @Override
    @Transactional(readOnly = true)
    public List<FileBusinessReference> findBusinessReferences(PurgeContext context) {
        Set<UUID> targetIds = Set.copyOf(context.fileNodeIds());
        return findReferencedItems(context.fileNodeIds()).stream()
                .map(item -> new FileBusinessReference(
                        MODULE,
                        RESOURCE_TYPE,
                        item.getId(),
                        targetIds.contains(item.getFileNodeId())
                                ? item.getFileNodeId()
                                : context.rootFileNodeId()
                ))
                .toList();
    }

    /**
     * 贡献阅读条目的多来源文件、封面、漫画页面与每章正文派生对象。
     *
     * <p>只有"没有任何来源能活下来"的条目才连带贡献全部派生对象。多卷漫画永久删除其中一卷时，
     * 其余分卷的文件、封面与正文仍在使用，贡献它们会把整部作品物理删掉。
     *
     * @param context 删除上下文
     * @param writer 资源写入器
     */
    @Override
    @Transactional(readOnly = true)
    public void contribute(PurgeContext context, PurgeContributionWriter writer) {
        Set<UUID> purgingFileIds = Set.copyOf(context.fileNodeIds());
        List<ReaderItem> items = findReferencedItems(context.fileNodeIds());
        if (items.isEmpty()) {
            return;
        }
        List<UUID> fullPurgeItemIds = new ArrayList<>();
        List<UUID> removedSourceIds = new ArrayList<>();
        for (ReaderItem item : items) {
            List<ReaderItemSource> sources = itemSourceRepository.findByReaderItemId(item.getId());
            if (hasSurvivingSource(sources, purgingFileIds)) {
                sources.stream()
                        .filter(source -> source.getFileNodeId() != null
                                && purgingFileIds.contains(source.getFileNodeId()))
                        .map(ReaderItemSource::getId)
                        .forEach(removedSourceIds::add);
                continue;
            }
            fullPurgeItemIds.add(item.getId());
        }

        List<ReaderItem> fullPurgeItems = items.stream()
                .filter(item -> fullPurgeItemIds.contains(item.getId()))
                .toList();
        writer.addFileNodeIds(fullPurgeItems.stream()
                .map(ReaderItem::getFileNodeId)
                .filter(Objects::nonNull)
                .toList());
        writer.addFileNodeIds(fullPurgeItems.stream()
                .map(ReaderItem::getCoverFileId)
                .filter(Objects::nonNull)
                .toList());
        if (!fullPurgeItemIds.isEmpty()) {
            writer.addFileNodeIds(itemSourceRepository.findByReaderItemIdIn(fullPurgeItemIds).stream()
                    .map(ReaderItemSource::getFileNodeId)
                    .filter(Objects::nonNull)
                    .toList());
            writer.addFileNodeIds(pageAssetRepository.findByReaderItemIdIn(fullPurgeItemIds).stream()
                    .map(ReaderPageAsset::getFileNodeId)
                    .toList());
            writer.addFileNodeIds(textChapterRepository.findByReaderItemIdIn(fullPurgeItemIds).stream()
                    .map(ReaderTextChapter::getContentFileNodeId)
                    .filter(Objects::nonNull)
                    .toList());
        }
        for (UUID sourceId : removedSourceIds) {
            writer.addFileNodeIds(pageAssetRepository.findBySourceId(sourceId).stream()
                    .map(ReaderPageAsset::getFileNodeId)
                    .toList());
        }
    }

    /**
     * 幂等清理阅读业务记录。
     *
     * <p>关联行按条目而不是按删除发起者清理：共享条目的进度、书架、书签、批注与笔记属于空间里
     * 每个用户，只删条目所有者的那一份会让其他成员的行永远留在库里。
     *
     * @param context 删除上下文
     */
    @Override
    @Transactional(rollbackFor = Exception.class)
    public void finalizePurge(PurgeContext context) {
        List<UUID> fileNodeIds = List.copyOf(context.fileNodeIds());
        Set<UUID> purgingFileIds = Set.copyOf(fileNodeIds);
        List<ReaderItem> itemsToDelete = new ArrayList<>();
        List<ReaderItem> referencedItems = findReferencedItems(fileNodeIds);
        for (ReaderItem item : referencedItems) {
            List<ReaderItemSource> sources = itemSourceRepository.findByReaderItemId(item.getId());
            if (!hasSurvivingSource(sources, purgingFileIds)) {
                itemsToDelete.add(item);
                continue;
            }
            removeSingleSourceRows(item, sources, purgingFileIds);
        }
        deleteItemsCompletely(itemsToDelete);
        clearDanglingFileReferences(fileNodeIds);
    }

    /**
     * 多源漫画只删掉其中一个分卷：清该来源的页面与派生对象，主文件被删时把条目指向剩余首个来源。
     */
    private void removeSingleSourceRows(ReaderItem item, List<ReaderItemSource> sources, Set<UUID> purgingFileIds) {
        List<ReaderItemSource> removedSources = sources.stream()
                .filter(source -> source.getFileNodeId() != null && purgingFileIds.contains(source.getFileNodeId()))
                .toList();
        if (removedSources.isEmpty()) {
            return;
        }
        for (ReaderItemSource source : removedSources) {
            pageAssetRepository.deleteBySourceId(source.getId());
            pageRepository.deleteBySourceId(source.getId());
            itemSourceRepository.delete(source);
        }
        itemSourceRepository.flush();

        boolean primaryRemoved = item.getFileNodeId() != null && purgingFileIds.contains(item.getFileNodeId());
        if (primaryRemoved) {
            List<ReaderItemSource> remaining = new ArrayList<>(itemSourceRepository.findByReaderItemId(item.getId()));
            remaining.sort(ComicManifestBuilder.SOURCE_ORDER);
            if (remaining.isEmpty()) {
                return;
            }
            ReaderItemSource nextPrimary = remaining.getFirst();
            item.setFileNodeId(nextPrimary.getFileNodeId());
            item.setContentHash(nextPrimary.getContentHash());
            itemRepository.save(item);
        }
        if ("COMIC".equalsIgnoreCase(item.getContentKind())) {
            comicManifestService.rebuildComicManifest(item.getId());
            comicManifestService.refreshItemImportStatus(item.getId());
        }
        log.info("漫画分卷来源已随文件永久删除: itemId={}, removedSourceCount={}",
                item.getId(), removedSources.size());
    }

    private boolean hasSurvivingSource(List<ReaderItemSource> sources, Set<UUID> purgingFileIds) {
        return sources.stream()
                .anyMatch(source -> source.getFileNodeId() != null
                        && !purgingFileIds.contains(source.getFileNodeId()));
    }

    /**
     * 处理文件移入回收站事件。
     *
     * @param event 文件节点软删除事件
     */
    @EventListener
    @Transactional(rollbackFor = Exception.class)
    public void handleFileNodesSoftDeleted(FileNodesSoftDeletedEvent event) {
        if (event.fileNodeIds() == null || event.fileNodeIds().isEmpty()) {
            return;
        }
        log.debug("文件移入回收站，保留阅读业务数据: ownerUserId={}, fileNodeCount={}",
                event.ownerUserId(), event.fileNodeIds().size());
    }

    /**
     * 使引用指定文件节点的阅读库缓存失效。
     *
     * @param fileNodeIds 文件节点 ID
     */
    @Override
    @Transactional(rollbackFor = Exception.class)
    public void invalidateFileVisibility(Collection<UUID> fileNodeIds) {
        if (fileNodeIds == null || fileNodeIds.isEmpty()) {
            return;
        }
        findReferencedItems(List.copyOf(fileNodeIds)).stream()
                .map(ReaderItem::getOwnerUserId)
                .filter(Objects::nonNull)
                .collect(Collectors.toCollection(LinkedHashSet::new))
                .forEach(ownerUserId -> syncEventService.invalidate(
                        ownerUserId,
                        SyncScope.READER,
                        "READER_LIBRARY",
                        Map.of("reason", "FILE_VISIBILITY_CHANGED")
                ));
    }

    private void deleteItemsCompletely(List<ReaderItem> items) {
        if (items.isEmpty()) {
            return;
        }
        List<UUID> itemIds = items.stream().map(ReaderItem::getId).toList();
        progressRepository.deleteByReaderItemIdIn(itemIds);
        bookshelfRepository.deleteByReaderItemIdIn(itemIds);
        bookmarkRepository.deleteByReaderItemIdIn(itemIds);
        annotationRepository.deleteByReaderItemIdIn(itemIds);
        noteRepository.deleteByReaderItemIdIn(itemIds);
        readingSessionRepository.deleteByReaderItemIdIn(itemIds);
        pageAssetRepository.deleteByReaderItemIdIn(itemIds);
        pageRepository.deleteByReaderItemIdIn(itemIds);
        catalogRepository.deleteByReaderItemIdIn(itemIds);
        itemSourceRepository.deleteByReaderItemIdIn(itemIds);
        textChapterRepository.deleteByReaderItemIdIn(itemIds);
        itemRepository.deleteAllInBatch(items);
    }

    private void clearDanglingFileReferences(List<UUID> deletedFileIds) {
        Set<UUID> fileIds = new HashSet<>(deletedFileIds);
        itemRepository.findByCoverFileIdIn(fileIds)
                .forEach(item -> item.setCoverFileId(null));
    }

    private List<ReaderItem> findReferencedItems(List<UUID> fileNodeIds) {
        Set<UUID> itemIds = new LinkedHashSet<>();
        itemRepository.findByFileNodeIdIn(fileNodeIds).stream()
                .map(ReaderItem::getId)
                .forEach(itemIds::add);
        itemSourceRepository.findByFileNodeIdIn(fileNodeIds).stream()
                .map(ReaderItemSource::getReaderItemId)
                .forEach(itemIds::add);
        if (itemIds.isEmpty()) {
            return List.of();
        }
        return itemRepository.findAllById(itemIds);
    }
}
