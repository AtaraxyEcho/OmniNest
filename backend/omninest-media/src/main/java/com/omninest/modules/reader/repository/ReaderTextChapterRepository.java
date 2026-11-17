package com.omninest.modules.reader.repository;

import com.omninest.modules.reader.domain.ReaderTextChapter;
import java.util.Collection;
import java.util.List;
import java.util.Optional;
import java.util.UUID;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Modifying;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;
import org.springframework.transaction.annotation.Transactional;

/**
 * 文本书籍章节清单仓储。
 *
 * @author OmniNest
 */
public interface ReaderTextChapterRepository extends JpaRepository<ReaderTextChapter, UUID> {

    /**
     * 按稳定章节顺序读取清单。
     *
     * @param readerItemId 阅读条目 ID
     * @return 章节清单
     */
    List<ReaderTextChapter> findByReaderItemIdOrderByChapterIndex(UUID readerItemId);

    /**
     * 按章节顺序定位单章清单。
     *
     * @param readerItemId 阅读条目 ID
     * @param chapterIndex 章节顺序
     * @return 章节清单，不存在时为空
     */
    Optional<ReaderTextChapter> findByReaderItemIdAndChapterIndex(UUID readerItemId, int chapterIndex);

    /**
     * 删除条目的旧章节清单。
     *
     * @param readerItemId 阅读条目 ID
     */
    void deleteByReaderItemId(UUID readerItemId);

    /**
     * 批量删除条目的章节清单。
     *
     * @param readerItemIds 阅读条目 ID 集合
     */
    void deleteByReaderItemIdIn(Collection<UUID> readerItemIds);

    /**
     * 批量读取多个条目的章节清单，供删除时收集派生资产引用。
     *
     * @param readerItemIds 阅读条目 ID 集合
     * @return 章节清单
     */
    List<ReaderTextChapter> findByReaderItemIdIn(Collection<UUID> readerItemIds);

    /**
     * 按版本条件写入本章正文派生节点。
     *
     * <p>派生过程跨越多次对象存储写入，期间清单可能被并发重建；直接覆盖会把新清单的
     * 行指向另一版本的正文文件，因此必须带版本号条件并让调用方感知 0 行。
     *
     * @param id 章节 ID
     * @param fileNodeId 派生节点 ID
     * @param expectedVersion 读取清单时的版本号
     * @return 更新行数，0 表示清单已被重建
     */
    @Modifying
    @Transactional
    @Query("update ReaderTextChapter c set c.contentFileNodeId = :fileNodeId, "
            + "c.version = c.version + 1 where c.id = :id and c.version = :expectedVersion")
    int updateContentFileNode(
            @Param("id") UUID id,
            @Param("fileNodeId") UUID fileNodeId,
            @Param("expectedVersion") long expectedVersion
    );
}
