package com.omninest.modules.photos.repository;

/**
 * 关系图谱边聚合投影：一对实体之间的共现照片数。
 *
 * @author OmniNest
 */
public interface PhotoRelationEdgeProjection {
    String getSourceKey();

    String getTargetKey();

    long getWeight();
}
