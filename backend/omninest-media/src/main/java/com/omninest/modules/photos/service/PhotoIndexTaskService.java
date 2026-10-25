package com.omninest.modules.photos.service;

import com.omninest.common.messaging.QueueNames;
import com.omninest.modules.file.service.FileLifecycleGuard;
import com.omninest.modules.photos.domain.PhotoContentAnalysisRun;
import com.omninest.modules.photos.domain.PhotoContentLabel;
import com.omninest.modules.photos.domain.PhotoItem;
import com.omninest.modules.photos.domain.PhotoTag;
import com.omninest.modules.photos.event.PhotoIndexEvent;
import com.omninest.modules.photos.repository.PhotoContentAnalysisRunRepository;
import com.omninest.modules.photos.repository.PhotoContentLabelRepository;
import com.omninest.modules.photos.repository.PhotoIndexTargetProjection;
import com.omninest.modules.photos.repository.PhotoItemRepository;
import com.omninest.modules.photos.repository.PhotoTagRepository;
import com.omninest.modules.photos.search.PhotoSearchIndexService;
import com.omninest.modules.photos.search.PhotoSearchIndexService.PhotoIndexDocument;
import com.omninest.modules.task.service.TaskDispatchItem;
import com.omninest.modules.task.service.TaskDispatchService;
import java.util.ArrayList;
import java.util.Collection;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Objects;
import java.util.Set;
import java.util.UUID;
import java.util.stream.Collectors;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.data.domain.PageRequest;
import org.springframework.stereotype.Service;

/**
 * 照片搜索索引任务服务。
 *
 * <p>索引请求一律经 Outbox 投递给 Worker，由单进程写 Lucene：API 与 Worker 共挂
 * 同一索引卷时，API 内直接打开 {@code IndexWriter} 会与 Worker 抢 {@code write.lock}，
 * 写入被吞掉后表现为索引静默丢失。</p>
 *
 * @author OmniNest
 */
@Slf4j
@Service
@RequiredArgsConstructor
public class PhotoIndexTaskService {
    /**
     * 全站重建时的单批扫描数量。
     */
    private static final int REBUILD_BATCH_SIZE = 500;
    private static final String STATUS_SUCCEEDED = "SUCCEEDED";
    private static final String STATE_AUTO = "AUTO";
    private static final String METADATA_SEMANTIC_TAGS = "semanticTags";

    private final PhotoItemRepository photoItemRepository;
    private final PhotoTagRepository photoTagRepository;
    private final PhotoContentAnalysisRunRepository analysisRunRepository;
    private final PhotoContentLabelRepository contentLabelRepository;
    private final PhotoLabelPolicy labelPolicy;
    private final PhotoSearchIndexService photoSearchIndexService;
    private final FileLifecycleGuard fileLifecycleGuard;
    private final TaskDispatchService taskDispatchService;

    /**
     * 把指定照片同步到搜索索引：可见照片写入，回收站或生命周期中的照片移出索引。
     *
     * <p>仅由 Worker 侧消费调用。</p>
     *
     * @param ownerUserId 所有者用户 ID
     * @param photoId 照片 ID
     * @return 照片存在且处于可搜索状态时返回 true
     */
    public boolean index(UUID ownerUserId, UUID photoId) {
        PhotoItem photo = photoItemRepository.findByOwnerUserIdAndId(ownerUserId, photoId).orElse(null);
        if (photo == null) {
            return false;
        }
        if (photo.getDeletedAt() != null
                || !fileLifecycleGuard.isOwnedProcessable(ownerUserId, photo.getFileNodeId())) {
            photoSearchIndexService.deletePhoto(photoId);
            return false;
        }
        photoSearchIndexService.indexPhoto(buildDocument(ownerUserId, photo));
        return true;
    }

    /**
     * 在 Worker 内批量同步一页照片的分析结果。
     *
     * <p>每页仅提交一次 Lucene 写入，避免全库重分析时逐张 commit。
     * 只能在 Worker 运行时调用，不得从 API 进程调用。</p>
     *
     * @param ownerUserId 所有者用户 ID
     * @param photoIds 已成功分析的当页照片
     * @return 实际写入索引的照片数
     */
    public int indexBatchDirect(UUID ownerUserId, List<UUID> photoIds) {
        if (photoIds == null || photoIds.isEmpty()) {
            return 0;
        }
        Map<UUID, PhotoItem> photosById = photoItemRepository
                .findByOwnerUserIdAndIdIn(ownerUserId, photoIds)
                .stream()
                .collect(Collectors.toMap(PhotoItem::getId, photo -> photo, (left, right) -> left));
        List<UUID> removalIds = new ArrayList<>();
        List<UUID> indexableIds = new ArrayList<>();
        List<UUID> candidateFileNodeIds = new ArrayList<>();
        for (UUID photoId : photoIds) {
            PhotoItem photo = photosById.get(photoId);
            if (photo == null) {
                continue;
            }
            if (photo.getDeletedAt() != null || photo.getFileNodeId() == null) {
                removalIds.add(photoId);
                continue;
            }
            indexableIds.add(photoId);
            candidateFileNodeIds.add(photo.getFileNodeId());
        }
        Set<UUID> processableFileNodeIds = fileLifecycleGuard
                .filterOwnedProcessable(ownerUserId, candidateFileNodeIds);
        indexableIds.removeIf(photoId -> {
            PhotoItem photo = photosById.get(photoId);
            if (processableFileNodeIds.contains(photo.getFileNodeId())) {
                return false;
            }
            removalIds.add(photoId);
            return true;
        });
        if (indexableIds.isEmpty()) {
            photoSearchIndexService.deletePhotos(removalIds);
            return 0;
        }

        Map<UUID, List<String>> tagsByPhoto = photoTagRepository
                .findByOwnerUserIdAndPhotoIdIn(ownerUserId, indexableIds)
                .stream()
                .collect(Collectors.groupingBy(
                        PhotoTag::getPhotoId,
                        Collectors.mapping(PhotoTag::getTag, Collectors.toList())
                ));
        Map<UUID, UUID> latestRunByPhoto = new LinkedHashMap<>();
        for (PhotoContentAnalysisRun run : analysisRunRepository
                .findByOwnerUserIdAndPhotoIdInAndStatusOrderByCreatedAtDesc(
                        ownerUserId, indexableIds, STATUS_SUCCEEDED)) {
            latestRunByPhoto.putIfAbsent(run.getPhotoId(), run.getId());
        }
        Map<UUID, List<PhotoContentLabel>> labelsByPhoto = latestRunByPhoto.isEmpty()
                ? Map.of()
                : contentLabelRepository
                        .findByOwnerUserIdAndPhotoIdInAndRunIdIn(
                                ownerUserId,
                                latestRunByPhoto.keySet(),
                                latestRunByPhoto.values())
                        .stream()
                        .collect(Collectors.groupingBy(PhotoContentLabel::getPhotoId));

        List<PhotoIndexDocument> documents = new ArrayList<>(indexableIds.size());
        for (UUID photoId : indexableIds) {
            PhotoItem photo = photosById.get(photoId);
            List<String> aiLabels = new ArrayList<>();
            for (PhotoContentLabel label : labelsByPhoto.getOrDefault(photoId, List.of())) {
                if (!STATE_AUTO.equals(label.getState())) {
                    continue;
                }
                aiLabels.addAll(labelPolicy.expandSearchKeywords(
                        label.getNamespace(),
                        label.getLabelCode()
                ));
            }
            aiLabels.addAll(semanticTags(photo));
            documents.add(buildDocument(
                    photo,
                    tagsByPhoto.getOrDefault(photoId, List.of()),
                    aiLabels
            ));
        }
        photoSearchIndexService.deletePhotos(removalIds);
        photoSearchIndexService.indexPhotosBatch(documents);
        return documents.size();
    }

    /**
     * 请求把照片重新同步进搜索索引。
     *
     * <p>投递走 Outbox，与标签等变更同一事务落库、提交后发布；索引载荷复用照片 ID
     * 作为任务标识。回收站进入/移出、批量打标签与单张增删标签都用同一入口，
     * 由消费侧按照片当前状态决定写入还是移除。</p>
     *
     * @param ownerUserId 所有者用户 ID
     * @param photoId 照片 ID
     */
    public void scheduleIndexAfterCommit(UUID ownerUserId, UUID photoId) {
        taskDispatchService.enqueue(
                photoId,
                QueueNames.TASK_EXCHANGE,
                QueueNames.PHOTO_INDEX_ROUTING_KEY,
                new PhotoIndexEvent(photoId, ownerUserId)
        );
    }

    /**
     * 清空照片索引并按存量照片重新派发索引任务。
     *
     * <p>仅由 Worker 侧消费调用。照片索引与文件索引是两个独立根目录，
     * 且索引字段口径变更后旧文档不会再被新查询命中，所以全站重建必须先整卷丢弃再逐张重投；
     * 重投复用 {@code PHOTO_INDEX} 任务类型，因此既有的去重、重试与死信语义一并生效。
     * 回收站照片与文件已删除的照片不在扫描范围，其残留文档由整卷丢弃直接清除。</p>
     *
     * @return 重新派发的照片数
     */
    public int rebuildAll() {
        int cleared = photoSearchIndexService.clearAll();
        long total = photoItemRepository.countIndexablePhotos();
        log.info("开始重建照片索引: 已丢弃文档数={}, 待派发照片数={}", cleared, total);
        int dispatched = 0;
        UUID afterId = new UUID(0L, 0L);
        while (true) {
            List<PhotoIndexTargetProjection> batch = photoItemRepository.findIndexablePhotosAfterId(
                    afterId, PageRequest.of(0, REBUILD_BATCH_SIZE));
            if (batch.isEmpty()) {
                break;
            }
            List<TaskDispatchItem> dispatches = new ArrayList<>(batch.size());
            for (PhotoIndexTargetProjection photo : batch) {
                dispatches.add(new TaskDispatchItem(
                        photo.getId(),
                        new PhotoIndexEvent(photo.getId(), photo.getOwnerUserId())));
            }
            // 单批一次 Outbox 事务，避免全站重建时逐张照片提交。
            taskDispatchService.enqueueAll(
                    QueueNames.TASK_EXCHANGE,
                    QueueNames.PHOTO_INDEX_ROUTING_KEY,
                    dispatches);
            dispatched += dispatches.size();
            afterId = batch.getLast().getId();
            if (batch.size() < REBUILD_BATCH_SIZE) {
                break;
            }
        }
        log.info("照片索引重建派发完成: 待派发照片数={}, 已派发={}", total, dispatched);
        return dispatched;
    }

    private PhotoIndexDocument buildDocument(UUID ownerUserId, PhotoItem photo) {
        List<String> tags = photoTagRepository
                .findByOwnerUserIdAndPhotoId(ownerUserId, photo.getId())
                .stream()
                .map(PhotoTag::getTag)
                .toList();
        List<String> aiLabels = new ArrayList<>();
        PhotoContentAnalysisRun run = analysisRunRepository
                .findTopByOwnerUserIdAndPhotoIdAndStatusOrderByCreatedAtDesc(
                        ownerUserId,
                        photo.getId(),
                        STATUS_SUCCEEDED
                );
        if (run != null) {
            for (PhotoContentLabel label : contentLabelRepository
                    .findByOwnerUserIdAndPhotoIdAndRunId(ownerUserId, photo.getId(), run.getId())) {
                if (!STATE_AUTO.equals(label.getState())) {
                    continue;
                }
                aiLabels.addAll(labelPolicy.expandSearchKeywords(
                        label.getNamespace(),
                        label.getLabelCode()
                ));
            }
        }
        aiLabels.addAll(semanticTags(photo));
        return buildDocument(photo, tags, aiLabels);
    }

    private PhotoIndexDocument buildDocument(
            PhotoItem photo,
            List<String> tags,
            List<String> aiLabels
    ) {
        return new PhotoIndexDocument(
                photo.getId(),
                photo.getOwnerUserId(),
                photo.getTitle(),
                photo.getDescription(),
                tags,
                aiLabels,
                photo.getOcrText()
        );
    }

    private List<String> semanticTags(PhotoItem photo) {
        if (photo.getProviderMetadata() == null) {
            return List.of();
        }
        Object value = photo.getProviderMetadata().get(METADATA_SEMANTIC_TAGS);
        if (!(value instanceof Collection<?> collection)) {
            return List.of();
        }
        return collection.stream()
                .filter(Objects::nonNull)
                .map(Object::toString)
                .filter(tag -> !tag.isBlank())
                .toList();
    }
}
