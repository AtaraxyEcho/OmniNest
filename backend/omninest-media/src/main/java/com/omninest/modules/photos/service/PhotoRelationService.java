package com.omninest.modules.photos.service;

import com.omninest.modules.photos.dto.PhotoDtos.PhotoRelationEdgeDto;
import com.omninest.modules.photos.dto.PhotoDtos.PhotoRelationNodeDto;
import com.omninest.modules.photos.dto.PhotoDtos.PhotoRelationsDto;
import com.omninest.modules.photos.repository.PhotoItemRepository;
import com.omninest.modules.photos.repository.PhotoRelationEdgeProjection;
import com.omninest.modules.photos.repository.PhotoRelationNodeProjection;
import java.time.ZoneId;
import java.util.ArrayList;
import java.util.List;
import java.util.UUID;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * 关系图谱边聚合服务：按实体对统计共现照片数。
 *
 * <p>节点（相册/时间分组/地点分组）由客户端既有的列表接口提供，
 * 本服务只输出实体之间的边；每类实体对的边数上限为 {@link #MAX_EDGES_PER_PAIR}，
 * 达到上限即标记截断。时间分组 key 与分组接口保持同一格式（YYYY-MM，按服务器时区）。</p>
 *
 * @author OmniNest
 */
@Service
@RequiredArgsConstructor
public class PhotoRelationService {
    private static final int MAX_EDGES_PER_PAIR = 250;
    private static final int MAX_NODES_PER_TYPE = 400;

    private final PhotoItemRepository photoItemRepository;

    /**
     * 统计当前用户照片库中各实体对的关系边。
     *
     * @param ownerUserId 所有者用户 ID
     * @return 关系边集合与截断标记
     */
    @Transactional(readOnly = true)
    public PhotoRelationsDto relations(UUID ownerUserId) {
        String zoneId = ZoneId.systemDefault().getId();
        List<PhotoRelationNodeDto> nodes = new ArrayList<>();
        List<PhotoRelationEdgeDto> edges = new ArrayList<>();
        boolean truncated = false;
        truncated |= appendNodes(nodes,
                photoItemRepository.findAlbumRelationNodes(ownerUserId, MAX_NODES_PER_TYPE), "ALBUM");
        truncated |= appendNodes(nodes,
                photoItemRepository.findTimeRelationNodes(ownerUserId, zoneId, MAX_NODES_PER_TYPE), "TIME");
        truncated |= appendNodes(nodes,
                photoItemRepository.findLocationRelationNodes(ownerUserId, MAX_NODES_PER_TYPE), "LOCATION");
        truncated |= append(edges,
                photoItemRepository.findAlbumAlbumRelationEdges(ownerUserId, MAX_EDGES_PER_PAIR),
                "ALBUM", "ALBUM");
        truncated |= append(edges,
                photoItemRepository.findAlbumTimeRelationEdges(ownerUserId, zoneId, MAX_EDGES_PER_PAIR),
                "ALBUM", "TIME");
        truncated |= append(edges,
                photoItemRepository.findAlbumLocationRelationEdges(ownerUserId, MAX_EDGES_PER_PAIR),
                "ALBUM", "LOCATION");
        truncated |= append(edges,
                photoItemRepository.findTimeLocationRelationEdges(ownerUserId, zoneId, MAX_EDGES_PER_PAIR),
                "TIME", "LOCATION");
        return new PhotoRelationsDto(List.copyOf(nodes), List.copyOf(edges), truncated);
    }

    private boolean append(
            List<PhotoRelationEdgeDto> target,
            List<PhotoRelationEdgeProjection> rows,
            String sourceType,
            String targetType
    ) {
        for (PhotoRelationEdgeProjection row : rows) {
            target.add(new PhotoRelationEdgeDto(
                    sourceType,
                    row.getSourceKey(),
                    targetType,
                    row.getTargetKey(),
                    row.getWeight()
            ));
        }
        return rows.size() >= MAX_EDGES_PER_PAIR;
    }

    private boolean appendNodes(
            List<PhotoRelationNodeDto> target,
            List<PhotoRelationNodeProjection> rows,
            String type
    ) {
        for (PhotoRelationNodeProjection row : rows) {
            target.add(new PhotoRelationNodeDto(type, row.getKey(), row.getLabel(), row.getWeight()));
        }
        return rows.size() >= MAX_NODES_PER_TYPE;
    }
}
