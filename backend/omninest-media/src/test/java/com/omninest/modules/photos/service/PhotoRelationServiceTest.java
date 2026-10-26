package com.omninest.modules.photos.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.anyInt;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;

import com.omninest.modules.photos.dto.PhotoDtos.PhotoRelationEdgeDto;
import com.omninest.modules.photos.dto.PhotoDtos.PhotoRelationNodeDto;
import com.omninest.modules.photos.dto.PhotoDtos.PhotoRelationsDto;
import com.omninest.modules.photos.repository.PhotoItemRepository;
import com.omninest.modules.photos.repository.PhotoRelationEdgeProjection;
import com.omninest.modules.photos.repository.PhotoRelationNodeProjection;
import java.util.List;
import java.util.UUID;
import java.util.stream.LongStream;
import org.junit.jupiter.api.Test;
import org.mockito.Mockito;

/**
 * 关系图谱边聚合服务测试。
 *
 * @author OmniNest
 */
class PhotoRelationServiceTest {
    private static final UUID OWNER_ID = UUID.fromString("10000000-0000-0000-0000-000000000001");

    private final PhotoItemRepository repository = Mockito.mock(PhotoItemRepository.class);
    private final com.omninest.modules.user.service.SystemInstanceConfigService systemInstanceConfigService =
            mock(com.omninest.modules.user.service.SystemInstanceConfigService.class);
    private final PhotoRelationService service = new PhotoRelationService(repository, systemInstanceConfigService);

    {
        when(systemInstanceConfigService.timeZone()).thenReturn(java.time.ZoneId.of("Asia/Shanghai"));
    }

    @Test
    void assemblesTypedEdgesFromRepositoryProjections() {
        when(repository.findAlbumRelationNodes(OWNER_ID, 400))
                .thenReturn(List.of(node("album-1", "旅行相册", 12)));
        when(repository.findTimeRelationNodes(eq(OWNER_ID), anyString(), anyInt()))
                .thenReturn(List.of(node("2024-05", null, 30)));
        when(repository.findLocationRelationNodes(OWNER_ID, 400)).thenReturn(List.of());
        when(repository.findAlbumAlbumRelationEdges(OWNER_ID, 250))
                .thenReturn(List.of(edge("album-1", "album-2", 3)));
        when(repository.findAlbumTimeRelationEdges(eq(OWNER_ID), anyString(), anyInt()))
                .thenReturn(List.of(edge("album-1", "2024-05", 7)));
        when(repository.findAlbumLocationRelationEdges(OWNER_ID, 250))
                .thenReturn(List.of());
        when(repository.findTimeLocationRelationEdges(eq(OWNER_ID), anyString(), anyInt()))
                .thenReturn(List.of(edge("2024-05", "杭州", 2)));

        PhotoRelationsDto result = service.relations(OWNER_ID);

        assertThat(result.truncated()).isFalse();
        assertThat(result.nodes()).containsExactly(
                new PhotoRelationNodeDto("ALBUM", "album-1", "旅行相册", 12),
                new PhotoRelationNodeDto("TIME", "2024-05", null, 30)
        );
        assertThat(result.edges()).containsExactly(
                new PhotoRelationEdgeDto("ALBUM", "album-1", "ALBUM", "album-2", 3),
                new PhotoRelationEdgeDto("ALBUM", "album-1", "TIME", "2024-05", 7),
                new PhotoRelationEdgeDto("TIME", "2024-05", "LOCATION", "杭州", 2)
        );
    }

    @Test
    void marksTruncatedWhenAnyPairReachesPerPairLimit() {
        List<PhotoRelationEdgeProjection> fullPage = LongStream.rangeClosed(1, 250)
                .mapToObj(index -> edge("album-" + index, "album-x" + index, 1))
                .toList();
        when(repository.findAlbumRelationNodes(OWNER_ID, 400)).thenReturn(List.of());
        when(repository.findTimeRelationNodes(eq(OWNER_ID), anyString(), anyInt())).thenReturn(List.of());
        when(repository.findLocationRelationNodes(OWNER_ID, 400)).thenReturn(List.of());
        when(repository.findAlbumAlbumRelationEdges(OWNER_ID, 250)).thenReturn(fullPage);
        when(repository.findAlbumTimeRelationEdges(eq(OWNER_ID), anyString(), anyInt()))
                .thenReturn(List.of());
        when(repository.findAlbumLocationRelationEdges(OWNER_ID, 250)).thenReturn(List.of());
        when(repository.findTimeLocationRelationEdges(eq(OWNER_ID), anyString(), anyInt()))
                .thenReturn(List.of());

        PhotoRelationsDto result = service.relations(OWNER_ID);

        assertThat(result.truncated()).isTrue();
        assertThat(result.edges()).hasSize(250);
    }

    private PhotoRelationEdgeProjection edge(String sourceKey, String targetKey, long weight) {
        return new PhotoRelationEdgeProjection() {
            @Override
            public String getSourceKey() {
                return sourceKey;
            }

            @Override
            public String getTargetKey() {
                return targetKey;
            }

            @Override
            public long getWeight() {
                return weight;
            }
        };
    }
    private PhotoRelationNodeProjection node(String key, String label, long weight) {
        return new PhotoRelationNodeProjection() {
            @Override
            public String getKey() {
                return key;
            }

            @Override
            public String getLabel() {
                return label;
            }

            @Override
            public long getWeight() {
                return weight;
            }
        };
    }
}
