package com.omninest.modules.photos.service;

import static org.assertj.core.api.Assertions.assertThat;

import com.omninest.modules.photos.domain.PhotoFace;
import com.omninest.modules.photos.domain.PhotoFaceCluster;
import com.omninest.modules.photos.repository.PhotoFaceClusterRepository;
import com.omninest.modules.photos.repository.PhotoFaceRepository;
import java.time.Instant;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;
import org.mockito.Mockito;

/**
 * 人脸聚类维护服务测试：聚类重建的原子落库与人脸删除后的归属维护。
 *
 * @author OmniNest
 */
class PhotoFaceClusterMaintenanceServiceTest {

    private PhotoFaceRepository faceRepository;
    private PhotoFaceClusterRepository clusterRepository;
    private PhotoFaceClusterMaintenanceService service;

    @BeforeEach
    void setUp() {
        faceRepository = Mockito.mock(PhotoFaceRepository.class);
        clusterRepository = Mockito.mock(PhotoFaceClusterRepository.class);
        service = new PhotoFaceClusterMaintenanceService(faceRepository, clusterRepository);
    }

    @Test
    void replaceClustersClearsStaleAssignmentsAndCreatesClustersForGroupsOfTwo() {
        UUID ownerUserId = UUID.randomUUID();
        UUID staleClusterId = UUID.randomUUID();
        PhotoFace first = face(ownerUserId, staleClusterId);
        PhotoFace second = face(ownerUserId, staleClusterId);
        PhotoFace noise = face(ownerUserId, staleClusterId);
        PhotoFaceCluster oldCluster = new PhotoFaceCluster();
        oldCluster.setId(staleClusterId);
        oldCluster.setOwnerUserId(ownerUserId);
        oldCluster.setFaceCount(3);

        Mockito.when(clusterRepository.findByOwnerUserIdOrderByFaceCountDesc(ownerUserId))
                .thenReturn(List.of(oldCluster));
        Mockito.when(clusterRepository.save(Mockito.any(PhotoFaceCluster.class)))
                .thenAnswer(invocation -> {
                    PhotoFaceCluster cluster = invocation.getArgument(0);
                    cluster.setId(UUID.randomUUID());
                    return cluster;
                });

        int created = service.replaceClusters(
                ownerUserId,
                List.of(first, second, noise),
                Map.of(0, List.of(first.getId(), second.getId()))
        );

        assertThat(created).isEqualTo(1);
        assertThat(first.getClusterId()).isNotNull();
        assertThat(second.getClusterId()).isEqualTo(first.getClusterId());
        assertThat(noise.getClusterId()).isNull();
        Mockito.verify(clusterRepository).deleteAll(List.of(oldCluster));
        Mockito.verify(faceRepository).clearClusterIdsByOwnerUserId(ownerUserId);
        Mockito.verify(faceRepository).saveAll(Mockito.argThat(faces -> {
            List<PhotoFace> assigned = new java.util.ArrayList<>();
            faces.forEach(assigned::add);
            return assigned.size() == 2
                    && assigned.stream().allMatch(face -> face.getClusterId() != null);
        }));
        Mockito.verify(clusterRepository).save(Mockito.argThat(cluster ->
                cluster.getFaceCount() == 2
                        && cluster.getCoverFaceId().equals(first.getId())));
    }

    @Test
    void replaceClustersSkipsGroupsSmallerThanTwo() {
        UUID ownerUserId = UUID.randomUUID();
        PhotoFace single = face(ownerUserId, null);

        int created = service.replaceClusters(
                ownerUserId,
                List.of(single),
                Map.of(0, List.of(single.getId()))
        );

        assertThat(created).isZero();
        assertThat(single.getClusterId()).isNull();
        Mockito.verify(clusterRepository).findByOwnerUserIdOrderByFaceCountDesc(ownerUserId);
        Mockito.verify(clusterRepository, Mockito.never()).save(Mockito.any(PhotoFaceCluster.class));
    }

    @Test
    void onFacesRemovedRefreshesCountAndKeepsCoverWhenCoverSurvives() {
        UUID ownerUserId = UUID.randomUUID();
        UUID clusterId = UUID.randomUUID();
        PhotoFace cover = face(ownerUserId, clusterId);
        PhotoFace survivor = face(ownerUserId, clusterId);
        PhotoFace removed = face(ownerUserId, clusterId);
        PhotoFaceCluster cluster = new PhotoFaceCluster();
        cluster.setId(clusterId);
        cluster.setOwnerUserId(ownerUserId);
        cluster.setCoverFaceId(cover.getId());
        cluster.setFaceCount(3);

        Mockito.when(clusterRepository.findByIdAndOwnerUserId(clusterId, ownerUserId))
                .thenReturn(java.util.Optional.of(cluster));
        Mockito.when(faceRepository.findByClusterId(clusterId))
                .thenReturn(List.of(cover, survivor));

        service.onFacesRemoved(ownerUserId, List.of(removed));

        Mockito.verify(clusterRepository).save(Mockito.argThat(saved ->
                saved.getFaceCount() == 2
                        && saved.getCoverFaceId().equals(cover.getId())));
        Mockito.verify(clusterRepository, Mockito.never()).delete(Mockito.any(PhotoFaceCluster.class));
    }

    @Test
    void onFacesRemovedReassignsCoverToEarliestSurvivor() {
        UUID ownerUserId = UUID.randomUUID();
        UUID clusterId = UUID.randomUUID();
        PhotoFace removedCover = face(ownerUserId, clusterId);
        PhotoFace laterSurvivor = face(ownerUserId, clusterId);
        PhotoFace earliestSurvivor = face(ownerUserId, clusterId);
        earliestSurvivor.setCreatedAt(Instant.now().minusSeconds(60));
        PhotoFaceCluster cluster = new PhotoFaceCluster();
        cluster.setId(clusterId);
        cluster.setOwnerUserId(ownerUserId);
        cluster.setCoverFaceId(removedCover.getId());
        cluster.setFaceCount(3);

        Mockito.when(clusterRepository.findByIdAndOwnerUserId(clusterId, ownerUserId))
                .thenReturn(java.util.Optional.of(cluster));
        Mockito.when(faceRepository.findByClusterId(clusterId))
                .thenReturn(List.of(laterSurvivor, earliestSurvivor));

        service.onFacesRemoved(ownerUserId, List.of(removedCover));

        Mockito.verify(clusterRepository).save(Mockito.argThat(saved ->
                saved.getFaceCount() == 2
                        && saved.getCoverFaceId().equals(earliestSurvivor.getId())));
    }

    @Test
    void onFacesRemovedDeletesClusterWhenFewerThanTwoMembersRemain() {
        UUID ownerUserId = UUID.randomUUID();
        UUID clusterId = UUID.randomUUID();
        PhotoFace removedFirst = face(ownerUserId, clusterId);
        PhotoFace removedSecond = face(ownerUserId, clusterId);
        PhotoFace lastSurvivor = face(ownerUserId, clusterId);
        PhotoFaceCluster cluster = new PhotoFaceCluster();
        cluster.setId(clusterId);
        cluster.setOwnerUserId(ownerUserId);
        cluster.setCoverFaceId(removedFirst.getId());
        cluster.setFaceCount(3);

        Mockito.when(clusterRepository.findByIdAndOwnerUserId(clusterId, ownerUserId))
                .thenReturn(java.util.Optional.of(cluster));
        Mockito.when(faceRepository.findByClusterId(clusterId))
                .thenReturn(List.of(lastSurvivor));

        service.onFacesRemoved(ownerUserId, List.of(removedFirst, removedSecond));

        @SuppressWarnings("unchecked")
        ArgumentCaptor<Iterable<PhotoFace>> faceCaptor = ArgumentCaptor.forClass(Iterable.class);
        Mockito.verify(faceRepository).saveAll(faceCaptor.capture());
        for (PhotoFace face : faceCaptor.getValue()) {
            assertThat(face.getClusterId()).isNull();
        }
        Mockito.verify(clusterRepository).findByIdAndOwnerUserId(clusterId, ownerUserId);
        Mockito.verify(clusterRepository).delete(cluster);
        Mockito.verifyNoMoreInteractions(clusterRepository);
    }

    @Test
    void onFacesRemovedIgnoresFacesWithoutClusterAssignment() {
        UUID ownerUserId = UUID.randomUUID();
        PhotoFace unassigned = face(ownerUserId, null);

        service.onFacesRemoved(ownerUserId, List.of(unassigned));

        Mockito.verifyNoInteractions(faceRepository, clusterRepository);
    }

    private PhotoFace face(UUID ownerUserId, UUID clusterId) {
        PhotoFace face = new PhotoFace();
        face.setId(UUID.randomUUID());
        face.setPhotoId(UUID.randomUUID());
        face.setOwnerUserId(ownerUserId);
        face.setClusterId(clusterId);
        face.setCreatedAt(Instant.now());
        return face;
    }
}
