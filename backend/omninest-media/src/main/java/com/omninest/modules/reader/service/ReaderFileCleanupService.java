package com.omninest.modules.reader.service;

import com.omninest.common.sync.SyncScope;
import com.omninest.modules.file.event.FileNodesSoftDeletedEvent;
import com.omninest.modules.file.service.FileBusinessReference;
import com.omninest.modules.file.service.FilePurgeParticipant;
import com.omninest.modules.reader.domain.ReaderPageAsset;
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
import java.util.Collection;
import java.util.HashSet;
import java.util.LinkedHashMap;
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
     * 贡献阅读条目的多来源文件、封面和漫画页面对象。
     *
     * @param context 删除上下文
     * @param writer 资源写入器
     */
    @Override
    @Transactional(readOnly = true)
    public void contribute(PurgeContext context, PurgeContributionWriter writer) {
        List<ReaderItem> items = findReferencedItems(context.fileNodeIds());
        if (items.isEmpty()) {
            return;
        }
        List<UUID> itemIds = items.stream().map(ReaderItem::getId).toList();
        writer.addFileNodeIds(items.stream().map(ReaderItem::getFileNodeId).toList());
        writer.addFileNodeIds(items.stream().map(ReaderItem::getCoverFileId).filter(Objects::nonNull).toList());
        writer.addFileNodeIds(itemSourceRepository.findByReaderItemIdIn(itemIds).stream()
                .map(ReaderItemSource::getFileNodeId)
                .toList());
        writer.addFileNodeIds(pageAssetRepository.findByReaderItemIdIn(itemIds).stream()
                .map(ReaderPageAsset::getFileNodeId)
                .toList());
    }

    /**
     * 幂等清理阅读业务记录。
     *
     * @param context 删除上下文
     */
    @Override
    @Transactional(rollbackFor = Exception.class)
    public void finalizePurge(PurgeContext context) {
        List<UUID> fileNodeIds = List.copyOf(context.fileNodeIds());
        Map<UUID, List<ReaderItem>> itemsByOwner = findReferencedItems(fileNodeIds).stream()
                .collect(Collectors.groupingBy(
                        ReaderItem::getOwnerUserId,
                        LinkedHashMap::new,
                        Collectors.toList()
                ));
        itemsByOwner.forEach(this::deleteOwnedRows);
        clearDanglingFileReferences(fileNodeIds);
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

    private void deleteOwnedRows(UUID ownerUserId, List<ReaderItem> items) {
        if (items.isEmpty()) {
            return;
        }
        List<UUID> itemIds = items.stream().map(ReaderItem::getId).toList();
        progressRepository.deleteByOwnerUserIdAndReaderItemIdIn(ownerUserId, itemIds);
        bookshelfRepository.deleteByOwnerUserIdAndReaderItemIdIn(ownerUserId, itemIds);
        bookmarkRepository.deleteByOwnerUserIdAndReaderItemIdIn(ownerUserId, itemIds);
        annotationRepository.deleteByOwnerUserIdAndReaderItemIdIn(ownerUserId, itemIds);
        noteRepository.deleteByOwnerUserIdAndReaderItemIdIn(ownerUserId, itemIds);
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
