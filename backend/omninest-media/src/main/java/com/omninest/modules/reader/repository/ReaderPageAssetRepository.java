package com.omninest.modules.reader.repository;

import com.omninest.modules.reader.domain.ReaderPageAsset;
import java.util.Collection;
import java.util.List;
import java.util.Optional;
import java.util.UUID;
import org.springframework.data.jpa.repository.JpaRepository;



/**
 * 漫画页面派生资源仓储。
 *
 * @author OmniNest
 */
public interface ReaderPageAssetRepository extends JpaRepository<ReaderPageAsset, UUID> {

    /**
     * 查询指定页面在指定清单版本下的派生资源。
     *
     * @param pageId 页面 ID
     * @param manifestVersion 清单版本
     * @return 派生资源
     */
    Optional<ReaderPageAsset> findByPageIdAndManifestVersion(UUID pageId, int manifestVersion);

    /**
     * 查询指定页面最新的派生资源。
     *
     * @param pageId 页面 ID
     * @return 最新派生资源
     */
    Optional<ReaderPageAsset> findFirstByPageIdOrderByManifestVersionDesc(UUID pageId);

    /**
     * 批量查询阅读条目下的派生资源。
     *
     * @param readerItemIds 阅读条目 ID 集合
     * @return 派生资源列表
     */
    List<ReaderPageAsset> findByReaderItemIdIn(Collection<UUID> readerItemIds);

    /**
     * 查询来源下的所有派生资源。
     *
     * @param sourceId 来源 ID
     * @return 派生资源列表
     */
    List<ReaderPageAsset> findBySourceId(UUID sourceId);

    /**
     * 删除来源下的所有派生资源。
     *
     * @param sourceId 来源 ID
     */
    void deleteBySourceId(UUID sourceId);

    /**
     * 批量删除阅读条目下的派生资源记录。
     *
     * @param readerItemIds 阅读条目 ID 集合
     */
    void deleteByReaderItemIdIn(Collection<UUID> readerItemIds);

    /**
     * 批量查询仍被页面资产引用的派生 FileNode。
     *
     * @param fileNodeIds 候选派生 FileNode ID
     * @return 仍被引用的派生资产
     */
    List<ReaderPageAsset> findByFileNodeIdIn(Collection<UUID> fileNodeIds);

    /**
     * 判断派生 FileNode 是否仍被页面资产引用。
     *
     * @param fileNodeId 派生 FileNode ID
     * @return 是否存在引用
     */
    boolean existsByFileNodeId(UUID fileNodeId);
}
