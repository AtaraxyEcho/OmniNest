package com.omninest.modules.user.repository;

import jakarta.persistence.EntityManager;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Repository;

/**
 * 管理端删除用户前的业务内容占用核查仓库 — 跨模块无实体依赖，使用原生 SQL 计数。
 *
 * <p>数据库不设外键，用户是否仍持有业务内容只能按关键表的 user 维度列计数判断。
 * 核查范围是各模块承载用户所有权的内容表；观看历史、进度、收藏等活动类记录
 * 不阻塞删除，属于已声明的残余风险。</p>
 *
 * @author OmniNest
 */
@Repository
@RequiredArgsConstructor
public class AdminUserContentGuardRepository {

    /**
     * 业务内容计数列顺序，与 {@link #CONTENT_COUNT_SQL} 的投影列一一对应。
     */
    private static final List<String> CONTENT_LABELS = List.of(
            "文件",
            "照片",
            "相册",
            "阅读库",
            "歌单",
            "视频合集",
            "分享",
            "背景素材",
            "离线下载",
            "外部存储",
            "集成账号",
            "内容资产"
    );

    private static final String CONTENT_COUNT_SQL = """
            select
              (select count(*) from omni.file_nodes where owner_user_id = :userId),
              (select count(*) from omni.photo_items where owner_user_id = :userId),
              (select count(*) from omni.photo_albums where owner_user_id = :userId),
              (select count(*) from omni.reader_items where owner_user_id = :userId),
              (select count(*) from omni.music_playlists where owner_user_id = :userId),
              (select count(*) from omni.media_video_collections where owner_user_id = :userId),
              (select count(*) from omni.share_links where owner_user_id = :userId),
              (select count(*) from omni.backdrop_assets where owner_user_id = :userId),
              (select count(*) from omni.download_offline_tasks where owner_user_id = :userId),
              (select count(*) from omni.storage_external_accounts where owner_user_id = :userId),
              (select count(*) from omni.integration_accounts where owner_user_id = :userId),
              (select count(*) from omni.content_assets where owner_user_id = :userId)
            """;

    private final EntityManager entityManager;

    /**
     * 统计用户在各关键内容表中的占用，仅返回数量大于零的项。
     *
     * @param userId 用户标识
     * @return 内容标签到记录数的映射，空账户返回空映射
     */
    public Map<String, Long> countOwnedContent(UUID userId) {
        Object[] row = (Object[]) entityManager
                .createNativeQuery(CONTENT_COUNT_SQL)
                .setParameter("userId", userId)
                .getSingleResult();
        Map<String, Long> owned = new LinkedHashMap<>();
        for (int index = 0; index < CONTENT_LABELS.size(); index++) {
            long count = ((Number) row[index]).longValue();
            if (count > 0) {
                owned.put(CONTENT_LABELS.get(index), count);
            }
        }
        return owned;
    }
}
