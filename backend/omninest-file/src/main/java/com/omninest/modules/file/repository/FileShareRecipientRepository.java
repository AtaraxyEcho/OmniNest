package com.omninest.modules.file.repository;

import com.omninest.modules.file.domain.FileShareRecipient;
import java.util.Collection;
import java.util.List;
import java.util.UUID;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import org.springframework.data.jpa.repository.EntityGraph;
import org.springframework.data.jpa.repository.JpaRepository;

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
