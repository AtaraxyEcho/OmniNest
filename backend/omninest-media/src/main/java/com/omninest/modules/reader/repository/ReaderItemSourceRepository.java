package com.omninest.modules.reader.repository;

import com.omninest.modules.file.domain.SpaceType;
import com.omninest.modules.reader.domain.ReaderItem;
import com.omninest.modules.reader.domain.ReaderItemSource;
import java.util.Collection;
import java.util.List;
import java.util.Optional;
import java.util.UUID;
import org.springframework.data.domain.Pageable;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

/**
 * 漫画来源仓储。
 */
public interface ReaderItemSourceRepository extends JpaRepository<ReaderItemSource, UUID> {

    /** 按阅读条目 ID 查询所有来源文件。 */
    List<ReaderItemSource> findByReaderItemId(UUID readerItemId);

    /** 按阅读条目 ID 统计来源数量。 */
    long countByReaderItemId(UUID readerItemId);

    /**
     * 按阅读条目和文件节点查询唯一来源。
     *
     * @param readerItemId 阅读条目 ID
     * @param fileNodeId 文件节点 ID
     * @return 已存在的来源
     */
    Optional<ReaderItemSource> findByReaderItemIdAndFileNodeId(UUID readerItemId, UUID fileNodeId);

    /** 批量按阅读条目 ID 查询来源文件。 */
    List<ReaderItemSource> findByReaderItemIdIn(Collection<UUID> readerItemIds);

    /** 按文件节点批量查询来源文件。 */
    List<ReaderItemSource> findByFileNodeIdIn(Collection<UUID> fileNodeIds);

    /**
     * 批量查询已作为来源使用的文件节点，范围含当前用户自己的条目与共享空间条目。
     *
     * <p>多卷漫画并入共享作品后，分卷文件不再属于任何一个用户的个人清单；只按条目创建者过滤
     * 会让其他成员看到重复的"待导入"候选。
     */
    @Query("""
            select distinct source.fileNodeId
            from ReaderItemSource source
            join ReaderItem item on source.readerItemId = item.id
            join FileNode f on item.fileNodeId = f.id
            where f.deleted = false
              and (item.ownerUserId = :ownerUserId
                   or (:sharedType is not null and f.spaceType = :sharedType))
              and source.fileNodeId in :fileNodeIds
            """)
    List<UUID> findImportedFileNodeIds(
            @Param("ownerUserId") UUID ownerUserId,
            @Param("fileNodeIds") Collection<UUID> fileNodeIds,
            @Param("sharedType") SpaceType sharedType
    );

    /**
     * 查询可见条目下所有来源的内容哈希，用于识别已并入共享漫画的分卷重复上传。
     */
    @Query("""
            select distinct source.contentHash
            from ReaderItemSource source
            join ReaderItem item on source.readerItemId = item.id
            join FileNode f on item.fileNodeId = f.id
            where f.deleted = false
              and source.contentHash is not null
              and (item.ownerUserId = :ownerUserId
                   or (:sharedType is not null and f.spaceType = :sharedType))
            """)
    List<String> findVisibleSourceContentHashes(
            @Param("ownerUserId") UUID ownerUserId,
            @Param("sharedType") SpaceType sharedType
    );

    /**
     * 按来源内容哈希查找所属条目，供分卷二次上传时定位已有的多源作品。
     */
    @Query("""
            select item
            from ReaderItemSource source
            join ReaderItem item on source.readerItemId = item.id
            where source.contentHash = :contentHash
            order by item.updatedAt desc
            """)
    List<ReaderItem> findItemsBySourceContentHash(@Param("contentHash") String contentHash);

    /**
     * 按游标取下一段待对账的漫画条目 ID。
     *
     * <p>主文件已进回收站的条目不在范围内：那些条目的派生数据由清理链路负责。
     * 游标用 UUID 字典序推进，扫到尾段后由调用方归回零值从头巡检；用 nil UUID 而不是
     * null 参数，避免 "参数为空则不加条件" 的写法在 Hibernate 里推断不出类型。
     *
     * @param contentKind 条目内容形态
     * @param afterId     上一轮最后一个条目 ID，从头开始时传 nil UUID
     * @param pageable    分页参数（只取页大小）
     * @return 条目 ID，按字典序升序
     */
    @Query("""
            select distinct source.readerItemId
            from ReaderItemSource source
            join ReaderItem item on source.readerItemId = item.id
            join FileNode f on item.fileNodeId = f.id
            where f.deleted = false
              and item.contentKind = :contentKind
              and source.readerItemId > :afterId
            order by source.readerItemId
            """)
    List<UUID> findComicItemIdsAfter(
            @Param("contentKind") String contentKind,
            @Param("afterId") UUID afterId,
            Pageable pageable
    );

    /** 按阅读条目 ID 删除所有来源文件。 */
    void deleteByReaderItemId(UUID readerItemId);

    /** 批量按阅读条目 ID 删除所有来源文件。 */
    void deleteByReaderItemIdIn(Collection<UUID> readerItemIds);
}
