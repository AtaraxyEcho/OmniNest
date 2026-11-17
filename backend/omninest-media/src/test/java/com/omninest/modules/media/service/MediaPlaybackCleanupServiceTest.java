package com.omninest.modules.media.service;

import com.omninest.modules.media.domain.MediaPlaybackType;
import com.omninest.modules.media.repository.MediaPlaybackProgressRepository;
import java.util.List;
import java.util.UUID;
import org.junit.jupiter.api.Test;
import org.mockito.Mockito;

/**
 * 统一媒体播放进度清理服务测试。
 *
 * @author OmniNest
 */
class MediaPlaybackCleanupServiceTest {
    private final MediaPlaybackProgressRepository repository =
            Mockito.mock(MediaPlaybackProgressRepository.class);
    private final MediaPlaybackCleanupService service = new MediaPlaybackCleanupService(repository);

    @Test
    void deleteOwnedUsesStableMediaTypeValue() {
        UUID ownerUserId = UUID.randomUUID();
        List<String> mediaKeys = List.of("video-1", "video-2");

        service.deleteOwned(ownerUserId, MediaPlaybackType.VIDEO, mediaKeys);

        Mockito.verify(repository).deleteByOwnerUserIdAndMediaTypeAndMediaKeyIn(
                ownerUserId,
                MediaPlaybackType.VIDEO.value(),
                mediaKeys
        );
    }

    @Test
    void deleteAllUsersIgnoresEmptyKeys() {
        service.deleteAllUsers(MediaPlaybackType.MUSIC, List.of());

        Mockito.verifyNoInteractions(repository);
    }
}
