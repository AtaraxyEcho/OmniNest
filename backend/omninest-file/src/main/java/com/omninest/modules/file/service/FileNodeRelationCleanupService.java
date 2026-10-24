package com.omninest.modules.file.service;

import com.omninest.common.cache.ReadThroughCache;
import com.omninest.modules.file.domain.ShareLink;
import com.omninest.modules.file.event.FileNodesDeletedEvent;
import com.omninest.modules.file.repository.FileAccessRecordRepository;
import com.omninest.modules.file.repository.FileContentRefRepository;
import com.omninest.modules.file.repository.FileFavoriteRepository;
import com.omninest.modules.file.repository.FileShareRecipientRepository;
import com.omninest.modules.file.repository.ShareLinkRepository;
import java.util.List;
import java.util.UUID;
import lombok.RequiredArgsConstructor;
import org.springframework.context.event.EventListener;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * 文件节点物理删除后的关联关系清理。
 *
 * <p>访问记录与收藏可能来自共享空间阶段的任意成员，必须按节点而不按所有者清理；
 * 只清所有者会留下指向已删除节点的行，最近访问列表映射时触发
 * {@code EntityNotFoundException}。分享链接同样要连同读穿透缓存一起失效。</p>
 *
 * @author OmniNest
 */
@Service
@RequiredArgsConstructor
public class FileNodeRelationCleanupService {
    private final FileAccessRecordRepository accessRecordRepository;
    private final FileFavoriteRepository favoriteRepository;
    private final ShareLinkRepository shareLinkRepository;
    private final FileShareRecipientRepository shareRecipientRepository;
    private final FileContentRefRepository contentRefRepository;
    private final ReadThroughCache readThroughCache;

    @EventListener
    @Transactional(rollbackFor = Exception.class)
    public void handleFileNodesDeleted(FileNodesDeletedEvent event) {
        if (event.fileNodeIds() == null || event.fileNodeIds().isEmpty()) {
            return;
        }
        List<UUID> fileNodeIds = List.copyOf(event.fileNodeIds());
        contentRefRepository.deleteByFileNodeIdIn(fileNodeIds);
        accessRecordRepository.deleteByFileNode_IdIn(fileNodeIds);
        favoriteRepository.deleteByFileNode_IdIn(fileNodeIds);

        List<ShareLink> shares = shareLinkRepository.findByResourceIdIn(fileNodeIds);
        if (!shares.isEmpty()) {
            List<UUID> shareLinkIds = shares.stream().map(ShareLink::getId).toList();
            shareRecipientRepository.deleteByShareLink_IdIn(shareLinkIds);
            shareLinkRepository.deleteAll(shares);
            shares.forEach(share ->
                    readThroughCache.invalidate("omninest:share:link:" + share.getTokenHash()));
        }
    }
}
