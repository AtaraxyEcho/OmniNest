package com.omninest.modules.reader.repository;

import com.omninest.modules.reader.domain.ReaderPage;
import java.util.Collection;
import java.util.List;
import java.util.UUID;
import org.springframework.data.jpa.repository.JpaRepository;

/**
 * 漫画页面仓储。
 */
public interface ReaderPageRepository extends JpaRepository<ReaderPage, UUID> {

    /** 按阅读条目 ID 查询所有页面，按页面索引升序。 */
    List<ReaderPage> findByReaderItemIdOrderByPageIndex(UUID readerItemId);

    /** 按来源文件 ID 查询所有页面。 */
    List<ReaderPage> findBySourceId(UUID sourceId);

    /** 按目录节点 ID 查询所有页面。 */
    List<ReaderPage> findByCatalogNodeId(UUID catalogNodeId);

    /** 按来源文件 ID 删除所有页面。 */
    void deleteBySourceId(UUID sourceId);

    /** 批量按阅读条目 ID 删除所有页面。 */
    void deleteByReaderItemIdIn(Collection<UUID> readerItemIds);

    /** 统计阅读条目的页面总数。 */
    long countByReaderItemId(UUID readerItemId);
}
