package com.omninest.modules.file.repository;

import com.omninest.modules.file.domain.FileShareRecipient;
import java.util.Collection;
import java.util.List;
import java.util.UUID;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import org.springframework.data.jpa.repository.EntityGraph;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

/**
 * 文件分享接收人关系仓储。
 *
 * @author OmniNest
 */
public interface FileShareRecipientRepository extends JpaRepository<FileShareRecipient, UUID> {
    List<FileShareRecipient> findByRecipientUserIdOrderByCreatedAtDesc(UUID recipientUserId);

    @EntityGraph(attributePaths = "shareLink")
    Page<FileShareRecipient> findByRecipientUserIdOrderByCreatedAtDesc(
            UUID recipientUserId,
            Pageable pageable);

    /**
     * 分页查询接收人仍然可见的分享。
     *
     * <p>已撤销的链接与已软删/易主的资源必须在 SQL 层过滤：先分页再在内存
     * 丢弃条目会让返回条数少于 size，且 totalElements 含被丢弃项，前端
     * 按总数续载会永远拉不到尽头。</p>
     *
     * @param recipientUserId 接收人用户标识
     * @param pageable 分页参数
     * @return 可见分享分页
     */
    @Query(value = """
            SELECT r FROM FileShareRecipient r
            JOIN FETCH r.shareLink s
            WHERE r.recipientUserId = :recipientUserId
              AND s.disabledAt IS NULL
              AND (s.expiresAt IS NULL OR s.expiresAt > CURRENT_TIMESTAMP)
              AND EXISTS (
                  SELECT n.id FROM FileNode n
                  WHERE n.id = s.resourceId
                    AND n.deleted = false
                    AND n.ownerUserId = s.ownerUserId
              )
            ORDER BY r.createdAt DESC
            """,
            countQuery = """
            SELECT COUNT(r) FROM FileShareRecipient r
            JOIN r.shareLink s
            WHERE r.recipientUserId = :recipientUserId
              AND s.disabledAt IS NULL
              AND (s.expiresAt IS NULL OR s.expiresAt > CURRENT_TIMESTAMP)
              AND EXISTS (
                  SELECT n.id FROM FileNode n
                  WHERE n.id = s.resourceId
                    AND n.deleted = false
                    AND n.ownerUserId = s.ownerUserId
              )
            """)
    Page<FileShareRecipient> findActiveVisibleByRecipientUserIdPage(
            @Param("recipientUserId") UUID recipientUserId,
            Pageable pageable);

    /**
     * 查询指定分享的接收人关系。
     *
     * @param shareLinkId 分享标识
     * @return 接收人关系列表
     */
    List<FileShareRecipient> findByShareLink_Id(UUID shareLinkId);

    /**
     * 判断某条分享是否定向给过该用户，作为接收人浏览子项的授权依据。
     *
     * @param shareLinkId      分享标识
     * @param recipientUserId  接收人用户标识
     * @return 是否存在接收人关系
     */
    boolean existsByShareLink_IdAndRecipientUserId(UUID shareLinkId, UUID recipientUserId);

    void deleteByShareLink_Id(UUID shareLinkId);

    void deleteByShareLink_IdIn(Collection<UUID> shareLinkIds);
}
