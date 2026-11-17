package com.omninest.modules.file.service;

import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import com.omninest.common.cache.ReadThroughCache;
import com.omninest.modules.file.domain.ShareLink;
import com.omninest.modules.file.event.FileNodesDeletedEvent;
import com.omninest.modules.file.repository.FileAccessRecordRepository;
import com.omninest.modules.file.repository.FileContentRefRepository;
import com.omninest.modules.file.repository.FileFavoriteRepository;
import com.omninest.modules.file.repository.FileShareRecipientRepository;
import com.omninest.modules.file.repository.ShareLinkRepository;
import java.time.Instant;
import java.util.List;
import java.util.UUID;
import org.junit.jupiter.api.Test;

class FileNodeRelationCleanupServiceTest {
    private static final UUID OWNER_ID = UUID.fromString("10000000-0000-0000-0000-000000000001");
    private static final UUID OTHER_USER_ID = UUID.fromString("10000000-0000-0000-0000-000000000002");
    private static final UUID FILE_ID = UUID.fromString("20000000-0000-0000-0000-000000000001");
    private static final UUID SHARE_ID = UUID.fromString("30000000-0000-0000-0000-000000000001");
    private static final String TOKEN_HASH =
            "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef";

    private final FileAccessRecordRepository accessRecordRepository =
            mock(FileAccessRecordRepository.class);
    private final FileFavoriteRepository favoriteRepository =
            mock(FileFavoriteRepository.class);
    private final ShareLinkRepository shareLinkRepository =
            mock(ShareLinkRepository.class);
    private final FileShareRecipientRepository shareRecipientRepository =
            mock(FileShareRecipientRepository.class);
    private final FileContentRefRepository contentRefRepository =
            mock(FileContentRefRepository.class);
    private final ReadThroughCache readThroughCache = mock(ReadThroughCache.class);
    private final FileNodeRelationCleanupService cleanupService = new FileNodeRelationCleanupService(
            accessRecordRepository,
            favoriteRepository,
            shareLinkRepository,
            shareRecipientRepository,
            contentRefRepository,
            readThroughCache
    );

    @Test
    void removesFileScopedRelationsWhenNodesAreDeleted() {
        ShareLink share = new ShareLink();
        share.setId(SHARE_ID);
        share.setOwnerUserId(OTHER_USER_ID);
        share.setResourceType("FILE");
        share.setResourceId(FILE_ID);
        share.setTokenHash(TOKEN_HASH);
        when(shareLinkRepository.findByResourceIdIn(List.of(FILE_ID)))
                .thenReturn(List.of(share));

        cleanupService.handleFileNodesDeleted(new FileNodesDeletedEvent(
                OWNER_ID,
                List.of(FILE_ID),
                Instant.parse("2026-05-21T12:00:00Z")
        ));

        // 共享空间阶段的访问/收藏可能属于任何成员，物理删除后必须按节点全部清理
        verify(accessRecordRepository).deleteByFileNode_IdIn(List.of(FILE_ID));
        verify(favoriteRepository).deleteByFileNode_IdIn(List.of(FILE_ID));
        verify(contentRefRepository).deleteByFileNodeIdIn(List.of(FILE_ID));
        verify(shareRecipientRepository).deleteByShareLink_IdIn(List.of(SHARE_ID));
        verify(shareLinkRepository).deleteAll(List.of(share));
        verify(readThroughCache).invalidate("omninest:share:link:" + TOKEN_HASH);
    }
}
