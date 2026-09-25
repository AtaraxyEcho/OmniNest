package com.omninest.modules.photos.service;

import com.omninest.common.ai.ImageAnalysisGateway;
import com.omninest.common.ai.ImageAnalysisGateway.FaceDetection;
import com.omninest.common.ai.ImageAnalysisGateway.ContentAnalysis;
import com.omninest.common.config.AiSidecarProperties;
import com.omninest.common.enums.ErrorCode;
import com.omninest.common.error.BusinessException;
import com.omninest.modules.file.dto.FileContentStream;
import com.omninest.modules.file.dto.FileDownloadUrlDto;
import com.omninest.modules.file.service.FileLifecycleGuard;
import com.omninest.modules.file.service.FileQueryService;
import com.omninest.modules.photos.domain.PhotoFace;
import com.omninest.modules.photos.domain.PhotoFaceCluster;
import com.omninest.modules.photos.domain.PhotoItem;
import com.omninest.modules.photos.domain.PhotoTag;
import com.omninest.modules.photos.dto.PhotoDtos.PhotoFaceClusterDto;
import com.omninest.modules.photos.dto.PhotoDtos.PhotoItemDto;
import com.omninest.modules.photos.repository.PhotoFaceClusterRepository;
import com.omninest.modules.photos.repository.PhotoFaceRepository;
import com.omninest.modules.photos.repository.PhotoFavoriteRepository;
import com.omninest.modules.photos.repository.PhotoItemRepository;
import com.omninest.modules.photos.repository.PhotoTagRepository;
import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.nio.ByteBuffer;
import java.nio.ByteOrder;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.Objects;
import java.util.Set;
import java.util.UUID;
import java.util.function.Function;
import java.util.stream.Collectors;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * 照片图像分析服务。
 * 负责内容分析、人脸检测和人脸聚类的编排。
 * 始终注册为 Bean，由调用方通过 PhotosRuntimeConfigService.isAiEnabled() 做运行时开关检查。
 *
 * @author OmniNest
 */
@Slf4j
@Service
@RequiredArgsConstructor
public class PhotoAiService {
    private static final int MAX_CLUSTER_FACES = 10_000;

    private final ImageAnalysisGateway imageAnalysisGateway;
    private final AiSidecarProperties aiSidecarProperties;
    private final PhotoLabelPolicy labelPolicy;
    private final PhotoContentAnalysisService contentAnalysisService;
    private final PhotosRuntimeConfigService configService;
    private final PhotoFaceClusterMaintenanceService clusterMaintenanceService;
    private final PhotoFaceRepository faceRepository;
    private final PhotoFaceClusterRepository clusterRepository;
    private final PhotoItemRepository photoItemRepository;
    private final PhotoFavoriteRepository favoriteRepository;
    private final PhotoTagRepository tagRepository;
    private final FileQueryService fileQueryService;
    private final FileLifecycleGuard fileLifecycleGuard;

    /**
     * 处理单张照片：人脸检测 + 主体检测 + 场景分析。
     */
    public void processPhoto(UUID ownerUserId, UUID photoId) {
        PhotoItem photo = photoItemRepository.findByOwnerUserIdAndId(ownerUserId, photoId)
                .orElseThrow(() -> new BusinessException(ErrorCode.NOT_FOUND, "照片不存在"));
        requirePhotoProcessable(ownerUserId, photo);

        Path imageFile = stagePhotoFile(ownerUserId, photo);
        try {
            String endpoint = configService.aiEndpoint();
            int timeout = configService.aiTimeoutSeconds();
            List<FaceDetection> faces = imageAnalysisGateway.detectFaces(imageFile, endpoint, timeout);
            ContentAnalysis analysis = imageAnalysisGateway.analyzeContent(imageFile, endpoint, timeout);
            requireValidAnalysis(faces, analysis);

            List<PhotoFace> faceEntities = faces.stream()
                    .map(face -> toFaceEntity(ownerUserId, photoId, face))
                    .toList();
            List<PhotoLabelPolicy.PhotoLabel> labels = labelPolicy.classify(
                    analysis,
                    !faceEntities.isEmpty()
            );
            contentAnalysisService.apply(ownerUserId, photoId, faceEntities, analysis, labels);
            log.info(
                    "照片图像分析完成: photoId={}, faceCount={}, labelCount={}",
                    photoId,
                    faceEntities.size(),
                    labels.size()
            );
        } finally {
            deleteStagedFile(imageFile);
        }
    }

    /**
     * 对用户所有人脸进行聚类。
     *
     * <p>侧车调用在事务外执行；聚类归属的清空、旧聚类删除与新聚类写入由
     * 聚类维护服务在同一短事务内原子完成，避免外呼期间长时间占用数据库连接。</p>
     */
    public void clusterFaces(UUID ownerUserId) {
        List<PhotoFace> allFaces = faceRepository.findByOwnerUserId(ownerUserId);
        if (allFaces.isEmpty()) {
            log.info("用户没有人脸数据，跳过聚类: ownerUserId={}", ownerUserId);
            return;
        }
        if (allFaces.size() > MAX_CLUSTER_FACES) {
            throw new BusinessException(
                    ErrorCode.RATE_LIMITED,
                    "人脸数量超过单次聚类限制，请分批执行"
            );
        }

        int embeddingDimension = aiSidecarProperties.getFaceEmbeddingDimension();
        List<float[]> embeddings = new ArrayList<>();
        List<UUID> faceIds = new ArrayList<>();
        for (PhotoFace face : allFaces) {
            float[] embedding = bytesToFloatArray(face.getEmbedding(), embeddingDimension);
            if (embedding == null) {
                log.warn("人脸嵌入向量缺失或维度异常，跳过聚类: ownerUserId={}, faceId={}, byteLength={}",
                        ownerUserId,
                        face.getId(),
                        face.getEmbedding() == null ? 0 : face.getEmbedding().length);
                continue;
            }
            embeddings.add(embedding);
            faceIds.add(face.getId());
        }

        if (embeddings.isEmpty()) {
            log.info("用户没有有效的人脸嵌入向量，跳过聚类: ownerUserId={}", ownerUserId);
            return;
        }

        String endpoint = configService.aiEndpoint();
        int timeout = configService.aiTimeoutSeconds();
        List<Integer> clusterAssignments = imageAnalysisGateway.clusterFaces(embeddings, endpoint, timeout);
        if (clusterAssignments == null || clusterAssignments.size() != faceIds.size()) {
            throw new IllegalStateException("图像分析人脸聚类结果数量与输入数量不一致");
        }
        Map<Integer, List<UUID>> clusterMap = new HashMap<>();
        for (int i = 0; i < faceIds.size(); i++) {
            int clusterId = clusterAssignments.get(i);
            if (clusterId < 0) {
                continue;
            }
            clusterMap.computeIfAbsent(clusterId, k -> new ArrayList<>()).add(faceIds.get(i));
        }
        int createdClusterCount = clusterMaintenanceService.replaceClusters(ownerUserId, allFaces, clusterMap);
        log.info("人脸聚类完成: ownerUserId={}, 聚类数={}", ownerUserId, createdClusterCount);
    }

    /**
     * 获取用户的人脸聚类列表。
     */
    @Transactional(readOnly = true)
    public List<PhotoFaceClusterDto> getClusters(UUID ownerUserId) {
        List<PhotoFaceCluster> clusters = clusterRepository.findByOwnerUserIdOrderByFaceCountDesc(ownerUserId);
        if (clusters.isEmpty()) {
            return List.of();
        }
        List<UUID> coverFaceIds = clusters.stream()
                .map(PhotoFaceCluster::getCoverFaceId)
                .filter(Objects::nonNull)
                .toList();
        Map<UUID, PhotoFace> coverFaces = coverFaceIds.isEmpty()
                ? Map.of()
                : faceRepository.findAllById(coverFaceIds).stream()
                        .collect(Collectors.toMap(PhotoFace::getId, Function.identity()));
        List<UUID> coverPhotoIds = coverFaces.values().stream()
                .map(PhotoFace::getPhotoId)
                .distinct()
                .toList();
        Map<UUID, PhotoItem> coverPhotos = coverPhotoIds.isEmpty()
                ? Map.of()
                : photoItemRepository.findAllById(coverPhotoIds).stream()
                        .collect(Collectors.toMap(PhotoItem::getId, Function.identity()));
        return clusters.stream()
                .map(cluster -> {
                    String coverUrl = resolveClusterCoverUrl(ownerUserId, cluster, coverFaces, coverPhotos);
                    return new PhotoFaceClusterDto(
                            cluster.getId(),
                            cluster.getName(),
                            cluster.getFaceCount(),
                            coverUrl
                    );
                })
                .toList();
    }

    private String resolveClusterCoverUrl(
            UUID ownerUserId,
            PhotoFaceCluster cluster,
            Map<UUID, PhotoFace> coverFaces,
            Map<UUID, PhotoItem> coverPhotos
    ) {
        if (cluster.getCoverFaceId() == null) {
            return null;
        }
        PhotoFace face = coverFaces.get(cluster.getCoverFaceId());
        PhotoItem photo = face == null ? null : coverPhotos.get(face.getPhotoId());
        if (photo == null) {
            return null;
        }
        return resolveCoverUrl(ownerUserId, photo.getCoverFileId());
    }

    /**
     * 获取聚类中的所有照片。
     */
    @Transactional(readOnly = true)
    public List<PhotoItemDto> getPhotosByCluster(UUID ownerUserId, UUID clusterId) {
        PhotoFaceCluster cluster = clusterRepository.findByIdAndOwnerUserId(clusterId, ownerUserId)
                .orElseThrow(() -> new BusinessException(ErrorCode.NOT_FOUND, "聚类不存在"));

        List<UUID> photoIds = faceRepository.findByClusterId(clusterId).stream()
                .map(PhotoFace::getPhotoId)
                .distinct()
                .toList();
        if (photoIds.isEmpty()) {
            return List.of();
        }
        Map<UUID, PhotoItem> photosById = photoItemRepository.findAllById(photoIds).stream()
                .collect(Collectors.toMap(PhotoItem::getId, Function.identity()));
        Set<UUID> favoritePhotoIds = favoriteRepository
                .findPhotoIdsByOwnerUserIdAndPhotoIdIn(ownerUserId, photoIds)
                .stream()
                .collect(Collectors.toSet());
        Map<UUID, List<String>> tagsByPhotoId = tagRepository.findByOwnerUserIdAndPhotoIdIn(ownerUserId, photoIds)
                .stream()
                .collect(Collectors.groupingBy(PhotoTag::getPhotoId,
                        Collectors.mapping(PhotoTag::getTag, Collectors.toList())));
        return photoIds.stream()
                .map(photosById::get)
                .filter(Objects::nonNull)
                .map(photo -> toDto(ownerUserId, photo,
                        favoritePhotoIds.contains(photo.getId()),
                        tagsByPhotoId.getOrDefault(photo.getId(), List.of())))
                .toList();
    }

    /**
     * 为聚类命名。
     */
    @Transactional(rollbackFor = Exception.class)
    public void nameCluster(UUID ownerUserId, UUID clusterId, String name) {
        PhotoFaceCluster cluster = clusterRepository.findByIdAndOwnerUserId(clusterId, ownerUserId)
                .orElseThrow(() -> new BusinessException(ErrorCode.NOT_FOUND, "聚类不存在"));
        cluster.setName(name);
        clusterRepository.save(cluster);
    }

    private Path stagePhotoFile(UUID ownerUserId, PhotoItem photo) {
        if (photo.getCoverFileId() == null) {
            // 封面由异步缩略图任务回填，导入后短暂缺失属预期；按依赖未就绪
            // 抛出以进入短间隔重试，与真实分析失败区分。
            throw new BusinessException(
                    ErrorCode.TASK_DEPENDENCY_NOT_READY,
                    "照片封面尚未生成，等待缩略图任务回填"
            );
        }
        Path tempFile = null;
        try (FileContentStream content = fileQueryService.openOwnedFileContent(
                ownerUserId,
                photo.getCoverFileId()
        )) {
            long maxImageBytes = imageAnalysisGateway.maxImageBytes();
            if (content.sizeBytes() > maxImageBytes) {
                log.warn(
                        "照片超过图像分析输入限制: photoId={}, sizeBytes={}, maxBytes={}",
                        photo.getId(),
                        content.sizeBytes(),
                        maxImageBytes
                );
                throw new IllegalStateException("照片超过图像分析输入大小限制");
            }
            tempFile = Files.createTempFile("omninest-photo-analysis-", ".img");
            try (InputStream stream = content.inputStream();
                 OutputStream output = Files.newOutputStream(tempFile)) {
                byte[] chunk = new byte[8192];
                long totalBytes = 0;
                int bytesRead;
                while ((bytesRead = stream.read(chunk)) != -1) {
                    totalBytes += bytesRead;
                    if (totalBytes > maxImageBytes) {
                        throw new IOException("图像分析输入文件超过大小限制");
                    }
                    output.write(chunk, 0, bytesRead);
                }
            }
            return tempFile;
        } catch (Exception ex) {
            log.warn("读取照片文件失败: photoId={}", photo.getId(), ex);
            deleteStagedFile(tempFile);
            throw new IllegalStateException("读取照片文件失败", ex);
        }
    }

    private void requirePhotoProcessable(UUID ownerUserId, PhotoItem photo) {
        fileLifecycleGuard.requireOwnedWritable(ownerUserId, photo.getFileNodeId());
        UUID coverFileId = photo.getCoverFileId();
        if (coverFileId != null && !coverFileId.equals(photo.getFileNodeId())) {
            fileLifecycleGuard.requireOwnedWritable(ownerUserId, coverFileId);
        }
    }

    /**
     * 校验图像分析侧车返回的结构化结果。
     */
    private void requireValidAnalysis(List<FaceDetection> faces, ContentAnalysis analysis) {
        if (faces == null || analysis == null || analysis.observations() == null) {
            throw new IllegalStateException("图像分析侧车返回了不完整的分析结果");
        }
        int embeddingDimension = aiSidecarProperties.getFaceEmbeddingDimension();
        for (FaceDetection face : faces) {
            if (face == null
                    || face.bboxW() <= 0
                    || face.bboxH() <= 0
                    || face.embedding() == null
                    || face.embedding().length != embeddingDimension) {
                throw new IllegalStateException("图像分析侧车返回了无效的人脸检测结果");
            }
        }
    }

    private PhotoFace toFaceEntity(UUID ownerUserId, UUID photoId, FaceDetection face) {
        PhotoFace faceEntity = new PhotoFace();
        faceEntity.setPhotoId(photoId);
        faceEntity.setOwnerUserId(ownerUserId);
        faceEntity.setBboxX(face.bboxX());
        faceEntity.setBboxY(face.bboxY());
        faceEntity.setBboxW(face.bboxW());
        faceEntity.setBboxH(face.bboxH());
        faceEntity.setEmbedding(floatArrayToBytes(face.embedding()));
        return faceEntity;
    }

    private void deleteStagedFile(Path tempFile) {
        if (tempFile == null) {
            return;
        }
        try {
            Files.deleteIfExists(tempFile);
        } catch (IOException exception) {
            log.warn("图像分析临时文件删除失败", exception);
        }
    }

    private byte[] floatArrayToBytes(float[] floats) {
        ByteBuffer buffer = ByteBuffer.allocate(floats.length * 4);
        buffer.order(ByteOrder.LITTLE_ENDIAN);
        for (float f : floats) {
            buffer.putFloat(f);
        }
        return buffer.array();
    }

    /**
     * 将小端字节序列还原为浮点向量。
     * 字节序列为空、长度不是 4 的倍数或维度与期望值不符时返回 null，由调用方跳过。
     */
    private float[] bytesToFloatArray(byte[] bytes, int expectedDimension) {
        if (bytes == null || bytes.length == 0 || bytes.length % 4 != 0) {
            return null;
        }
        int dimension = bytes.length / 4;
        if (dimension != expectedDimension) {
            return null;
        }
        ByteBuffer buffer = ByteBuffer.wrap(bytes);
        buffer.order(ByteOrder.LITTLE_ENDIAN);
        float[] floats = new float[dimension];
        for (int i = 0; i < dimension; i++) {
            floats[i] = buffer.getFloat();
        }
        return floats;
    }

    private PhotoItemDto toDto(UUID ownerUserId, PhotoItem photo, boolean isFavorite, List<String> tags) {
        String coverUrl = resolveCoverUrl(ownerUserId, photo.getCoverFileId());
        return PhotoItemDto.fromEntity(photo, coverUrl, isFavorite, tags);
    }

    private String resolveCoverUrl(UUID ownerUserId, UUID coverFileId) {
        if (coverFileId == null) {
            return null;
        }
        try {
            FileDownloadUrlDto url = fileQueryService.createDownloadUrl(ownerUserId, coverFileId);
            return url.downloadUrl();
        } catch (Exception e) {
            log.warn("解析封面 URL 失败: coverFileId={}, error={}", coverFileId, e.getMessage());
            return null;
        }
    }
}
