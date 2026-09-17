package com.omninest.modules.photos.service;

import com.omninest.modules.photos.domain.PhotoFace;
import com.omninest.modules.photos.domain.PhotoFaceCluster;
import com.omninest.modules.photos.repository.PhotoFaceClusterRepository;
import com.omninest.modules.photos.repository.PhotoFaceRepository;
import java.util.ArrayList;
import java.util.Collection;
import java.util.Comparator;
import java.util.HashMap;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Objects;
import java.util.Set;
import java.util.UUID;
import java.util.stream.Collectors;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * 人脸聚类维护服务。
 * 负责聚类重建的原子落库，以及人脸删除后的聚类成员数与封面维护；
 * 侧车等外部调用必须由调用方在事务外完成后再进入本服务。
 *
 * @author OmniNest
 */
@Slf4j
@Service
@RequiredArgsConstructor
public class PhotoFaceClusterMaintenanceService {

    private final PhotoFaceRepository faceRepository;
    private final PhotoFaceClusterRepository clusterRepository;

    /**
     * 原子重建用户人脸聚类。
     * 在同一事务内清空全部旧归属、删除旧聚类，并按聚类映射重建成员数不少于 2 的聚类；
     * 中途失败整体回滚，避免留下无归属人脸或悬空聚类。
     *
     * @param ownerUserId 用户标识
     * @param allFaces 用户全部人脸实体
     * @param clusterMap 聚类 ID 到人脸 ID 列表的映射
     * @return 重建的聚类数量
     */
    @Transactional(rollbackFor = Exception.class)
    public int replaceClusters(UUID ownerUserId, List<PhotoFace> allFaces, Map<Integer, List<UUID>> clusterMap) {
        // 先用批量 UPDATE 清空归属，避免对全部人脸做一次实体级 saveAll。
        faceRepository.clearClusterIdsByOwnerUserId(ownerUserId);

        List<PhotoFaceCluster> oldClusters = clusterRepository.findByOwnerUserIdOrderByFaceCountDesc(ownerUserId);
        if (!oldClusters.isEmpty()) {
            clusterRepository.deleteAll(oldClusters);
        }

        Map<UUID, PhotoFace> facesById = new HashMap<>();
        for (PhotoFace face : allFaces) {
            face.setClusterId(null);
            facesById.put(face.getId(), face);
        }
        List<PhotoFace> assignedFaces = new ArrayList<>();
        int createdClusterCount = 0;
        for (Map.Entry<Integer, List<UUID>> entry : clusterMap.entrySet()) {
            List<UUID> clusterFaceIds = entry.getValue();
            if (clusterFaceIds.size() < 2) {
                continue;
            }
            PhotoFaceCluster cluster = new PhotoFaceCluster();
            cluster.setOwnerUserId(ownerUserId);
            cluster.setFaceCount(clusterFaceIds.size());
            cluster.setCoverFaceId(clusterFaceIds.get(0));
            clusterRepository.save(cluster);
            for (UUID faceId : clusterFaceIds) {
                PhotoFace face = facesById.get(faceId);
                if (face != null) {
                    face.setClusterId(cluster.getId());
                    assignedFaces.add(face);
                }
            }
            createdClusterCount++;
        }
        if (!assignedFaces.isEmpty()) {
            faceRepository.saveAll(assignedFaces);
        }
        log.info("人脸聚类重建完成: ownerUserId={}, 聚类数={}", ownerUserId, createdClusterCount);
        return createdClusterCount;
    }

    /**
     * 在人脸被删除后维护聚类归属。
     * 刷新受影响聚类的成员数，封面被删时迁移到剩余最早成员，剩余成员不足 2 个时移除聚类。
     * 必须在删除人脸的同一事务内调用。
     *
     * @param ownerUserId 用户标识
     * @param removedFaces 被删除的人脸实体
     */
    @Transactional(rollbackFor = Exception.class)
    public void onFacesRemoved(UUID ownerUserId, Collection<PhotoFace> removedFaces) {
        if (removedFaces == null || removedFaces.isEmpty()) {
            return;
        }
        Set<UUID> removedIds = removedFaces.stream()
                .map(PhotoFace::getId)
                .filter(Objects::nonNull)
                .collect(Collectors.toSet());
        Map<UUID, List<PhotoFace>> removedByCluster = removedFaces.stream()
                .filter(face -> face.getClusterId() != null)
                .collect(Collectors.groupingBy(PhotoFace::getClusterId,
                        LinkedHashMap::new, Collectors.toList()));
        if (removedByCluster.isEmpty()) {
            return;
        }
        for (Map.Entry<UUID, List<PhotoFace>> entry : removedByCluster.entrySet()) {
            UUID clusterId = entry.getKey();
            PhotoFaceCluster cluster = clusterRepository.findByIdAndOwnerUserId(clusterId, ownerUserId)
                    .orElse(null);
            if (cluster == null) {
                continue;
            }
            List<PhotoFace> remainingFaces = faceRepository.findByClusterId(clusterId).stream()
                    .filter(face -> !removedIds.contains(face.getId()))
                    .sorted(Comparator.comparing(PhotoFace::getCreatedAt).thenComparing(PhotoFace::getId))
                    .toList();
            if (remainingFaces.size() < 2) {
                remainingFaces.forEach(face -> face.setClusterId(null));
                faceRepository.saveAll(remainingFaces);
                clusterRepository.delete(cluster);
                log.debug("聚类剩余成员不足，已移除: ownerUserId={}, clusterId={}, remaining={}",
                        ownerUserId, clusterId, remainingFaces.size());
                continue;
            }
            cluster.setFaceCount(remainingFaces.size());
            if (cluster.getCoverFaceId() != null && removedIds.contains(cluster.getCoverFaceId())) {
                cluster.setCoverFaceId(remainingFaces.get(0).getId());
            }
            clusterRepository.save(cluster);
        }
    }
}
