package com.omninest.modules.file.repository;

import com.omninest.modules.file.domain.FileNode;
import com.omninest.modules.file.domain.SpaceType;
import java.util.Collection;
import java.util.List;
import java.util.UUID;
import org.springframework.data.domain.Pageable;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

/**
 * 目录子树查询仓储：路径前缀翻页与按 {@code parent_id} 的层级读取。
 *
 * <p>从 {@link FileNodeRepository} 拆出，是因为节点主仓储已同时承担 CRUD、分享、版本与
 * 清理投影，继续按路径子树追加查询会让单文件超出项目的体积硬线。拆分口径按查询语义而不是
 * 按调用方：改名/移动的前缀重写与回收站恢复的层级收集同属「子树遍历」。</p>
 *
 * @author OmniNest
 */
public interface FileNodeSubtreeQueryRepository extends JpaRepository<FileNode, UUID> {

    /**
     * 按主键游标翻页读取共享空间某目录下的活动后代。
     *
     * <p>目录改名/移动只允许改写活动节点：回收站节点保留删除时的路径，恢复时由
     * {@code parent_id} 链重新计算。混入 {@code deleted = true} 会让用户在“删除 /docs →
     * 新建 /docs → 改名为 /archive”后，把回收站里旧 /docs 的子文件路径改成 /archive/...。</p>
     *
     * @param spaceType 空间类型
     * @param prefix 已转义的路径前缀
     * @param afterId 上一页最大节点 ID，首页传最小 UUID
     * @param limit 单批数量
     * @return 按 ID 升序的活动节点批次
     */
    @Query("select node from FileNode node where node.spaceType = :spaceType "
            + "and node.deleted = false "
            + "and node.normalizedPath like concat(:prefix, '%') escape '\\' "
            + "and node.id > :afterId order by node.id asc")
    List<FileNode> findActiveSubtreeBySpaceTypeAfterId(
            @Param("spaceType") SpaceType spaceType,
            @Param("prefix") String prefix,
            @Param("afterId") UUID afterId,
            Pageable limit
    );

    /**
     * 按主键游标翻页读取个人空间某目录下的活动后代。
     *
     * @param ownerUserId 所有者用户 ID
     * @param spaceType 空间类型
     * @param prefix 已转义的路径前缀
     * @param afterId 上一页最大节点 ID，首页传最小 UUID
     * @param limit 单批数量
     * @return 按 ID 升序的活动节点批次
     */
    @Query("select node from FileNode node where node.ownerUserId = :ownerUserId "
            + "and node.spaceType = :spaceType "
            + "and node.deleted = false "
            + "and node.normalizedPath like concat(:prefix, '%') escape '\\' "
            + "and node.id > :afterId order by node.id asc")
    List<FileNode> findActivePersonalSubtreeAfterId(
            @Param("ownerUserId") UUID ownerUserId,
            @Param("spaceType") SpaceType spaceType,
            @Param("prefix") String prefix,
            @Param("afterId") UUID afterId,
            Pageable limit
    );

    /**
     * 读取一组父目录下可恢复的已删除直接子节点。
     *
     * <p>回收站恢复按 {@code parent_id} 层级而非路径前缀收集子树：同一路径前缀下允许
     * 存在历史上多次单独删除的同名节点，按前缀收集会把它们全部复活并撞击唯一索引
     * {@code uniq_file_nodes_active_path_personal}。按父节点收集再按删除批次与同层
     * 同名去重，才能只还原随本次目录一起删除的节点。</p>
     *
     * @param spaceType 空间类型
     * @param parentIds 父节点 ID 集合
     * @return 按删除时间倒序（同层保留最新一次删除）的已删除子节点
     */
    @Query("select node from FileNode node where node.spaceType = :spaceType "
            + "and node.parentId in :parentIds "
            + "and node.deleted = true "
            + "and node.purgeState = com.omninest.modules.file.domain.FilePurgeState.NONE "
            + "order by node.deletedAt desc, node.id asc")
    List<FileNode> findRestorableChildrenByParentIds(
            @Param("spaceType") SpaceType spaceType,
            @Param("parentIds") Collection<UUID> parentIds
    );

    /**
     * 读取一组父目录下的活动直接子节点。
     *
     * <p>恢复前用于同层同名冲突判定：若同目录已存在活动同名节点，恢复该子节点必然违反
     * 唯一索引，应在恢复集合中跳过而不是让整棵目录恢复失败。</p>
     *
     * @param spaceType 空间类型
     * @param parentIds 父节点 ID 集合
     * @return 活动子节点
     */
    @Query("select node from FileNode node where node.spaceType = :spaceType "
            + "and node.parentId in :parentIds "
            + "and node.deleted = false")
    List<FileNode> findActiveChildrenByParentIds(
            @Param("spaceType") SpaceType spaceType,
            @Param("parentIds") Collection<UUID> parentIds
    );
}
