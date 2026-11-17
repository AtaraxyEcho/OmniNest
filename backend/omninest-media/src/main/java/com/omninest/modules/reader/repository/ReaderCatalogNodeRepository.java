package com.omninest.modules.reader.repository;

import com.omninest.modules.reader.domain.ReaderCatalogNode;
import java.util.Collection;
import java.util.List;
import java.util.UUID;
import org.springframework.data.jpa.repository.JpaRepository;

/**
 * 漫画目录节点仓储。
 */
public interface ReaderCatalogNodeRepository extends JpaRepository<ReaderCatalogNode, UUID> {

    /** 按阅读条目 ID 查询所有目录节点，按排序索引升序。 */
    List<ReaderCatalogNode> findByReaderItemIdOrderBySortIndex(UUID readerItemId);

    /** 按阅读条目 ID 和父节点 ID 查询子节点，按排序索引升序。 */
    List<ReaderCatalogNode> findByReaderItemIdAndParentIdOrderBySortIndex(UUID readerItemId, UUID parentId);

    /** 按阅读条目 ID 删除所有目录节点。 */
    void deleteByReaderItemId(UUID readerItemId);

    /** 批量按阅读条目 ID 删除所有目录节点。 */
    void deleteByReaderItemIdIn(Collection<UUID> readerItemIds);
}
