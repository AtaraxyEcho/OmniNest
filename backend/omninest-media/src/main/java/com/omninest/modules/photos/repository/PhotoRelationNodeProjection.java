package com.omninest.modules.photos.repository;

/**
 * 关系图谱节点聚合投影：一个实体及其照片数量。label 可为空（时间/地点节点由前端用 key 展示）。
 *
 * @author OmniNest
 */
public interface PhotoRelationNodeProjection {
    String getKey();

    String getLabel();

    long getWeight();
}
