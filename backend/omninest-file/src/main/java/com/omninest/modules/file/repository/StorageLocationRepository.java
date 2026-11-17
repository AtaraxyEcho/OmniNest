package com.omninest.modules.file.repository;

import com.omninest.modules.file.domain.StorageLocation;
import java.util.List;
import java.util.Optional;
import java.util.UUID;
import org.springframework.data.jpa.repository.JpaRepository;

/**
 * 存储位置元数据仓储。
 *
 * @author OmniNest
 */
public interface StorageLocationRepository extends JpaRepository<StorageLocation, UUID> {

    /**
     * 按名称排序读取全部存储位置。
     *
     * @return 存储位置列表
     */
    List<StorageLocation> findAllByOrderByNameAsc();

    /**
     * 判断相同挂载、根目录和作用域的存储位置是否存在。
     *
     * @param mountKey 挂载键
     * @param relativeRoot 相对根目录
     * @param scopeType 作用域类型
     * @param scopeId 作用域 ID
     * @return 存在时返回 true
     */
    boolean existsByMountKeyAndRelativeRootAndScopeTypeAndScopeId(
            String mountKey,
            String relativeRoot,
            String scopeType,
            UUID scopeId
    );

    /**
     * 判断相同挂载与根目录的系统级存储位置是否存在；系统作用域 scope_id 为 NULL，
     * 等值派生查询无法匹配，必须使用 IsNull 变体。
     *
     * @param mountKey 挂载键
     * @param relativeRoot 相对根目录
     * @param scopeType 作用域类型
     * @return 存在时返回 true
     */
    boolean existsByMountKeyAndRelativeRootAndScopeTypeAndScopeIdIsNull(
            String mountKey,
            String relativeRoot,
            String scopeType
    );

    /**
     * 查询相同挂载与根目录的系统级存储位置；系统作用域 scope_id 为 NULL，
     * 必须使用 IsNull 变体。
     *
     * @param mountKey 挂载键
     * @param relativeRoot 相对根目录
     * @param scopeType 作用域类型
     * @return 命中的存储位置
     */
    Optional<StorageLocation> findFirstByMountKeyAndRelativeRootAndScopeTypeAndScopeIdIsNull(
            String mountKey,
            String relativeRoot,
            String scopeType
    );

    /**
     * 按挂载键列出全部存储位置，供跨位置物理路径冲突检查使用。
     *
     * @param mountKey 挂载键
     * @return 同挂载键的存储位置列表
     */
    List<StorageLocation> findByMountKey(String mountKey);
}
