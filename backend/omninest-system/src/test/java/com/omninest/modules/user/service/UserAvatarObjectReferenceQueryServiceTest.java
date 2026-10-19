package com.omninest.modules.user.service;

import com.omninest.modules.user.repository.AuthUserRepository;
import com.omninest.modules.user.util.UserAvatarObjectKeys;
import java.util.List;
import java.util.Set;
import java.util.UUID;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.Mockito;
import org.mockito.junit.jupiter.MockitoExtension;
import org.assertj.core.api.Assertions;

/**
 * 头像对象引用查询测试。
 *
 * @author OmniNest
 */
@ExtendWith(MockitoExtension.class)
class UserAvatarObjectReferenceQueryServiceTest {

    private static final UUID USER_ID = UUID.fromString("aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa");

    @Mock
    private AuthUserRepository authUserRepository;

    @Test
    void returnsOnlyAvatarObjectsReferencedByUserProfiles() {
        String referencedAvatar = UserAvatarObjectKeys.objectKey(USER_ID, UUID.randomUUID());
        String orphanAvatar = UserAvatarObjectKeys.objectKey(USER_ID, UUID.randomUUID());
        String derivedAsset = "derived/photo/thumbnail.webp";
        UUID referencedAvatarId = UserAvatarObjectKeys.parseAvatarFileId(referencedAvatar);
        Mockito.when(authUserRepository.findExistingAvatarFileIds(Set.of(
                        UserAvatarObjectKeys.parseAvatarFileId(referencedAvatar),
                        UserAvatarObjectKeys.parseAvatarFileId(orphanAvatar))))
                .thenReturn(List.of(referencedAvatarId));
        UserAvatarObjectReferenceQueryService service = new UserAvatarObjectReferenceQueryService(
                authUserRepository
        );

        Set<String> result = service.findReferencedObjectKeys(Set.of(
                referencedAvatar,
                orphanAvatar,
                derivedAsset
        ));

        Assertions.assertThat(result).containsExactly(referencedAvatar);
    }

    @Test
    void treatsLegacyExtensionKeysAsUnreferenced() {
        UserAvatarObjectReferenceQueryService service = new UserAvatarObjectReferenceQueryService(
                authUserRepository
        );

        Set<String> result = service.findReferencedObjectKeys(Set.of(
                "avatars/" + USER_ID + "/avatar.jpg",
                "avatars/" + USER_ID + "/avatar.webp"
        ));

        // 旧扩展名键不再被任何用户资料指向，必须交由孤儿清理回收，且不能进数据库查询。
        Assertions.assertThat(result).isEmpty();
        Mockito.verifyNoInteractions(authUserRepository);
    }

    @Test
    void ignoresCandidatesOutsideAvatarPrefix() {
        UserAvatarObjectReferenceQueryService service = new UserAvatarObjectReferenceQueryService(
                authUserRepository
        );

        Set<String> result = service.findReferencedObjectKeys(Set.of("derived/photo/thumbnail.webp"));

        Assertions.assertThat(result).isEmpty();
        Mockito.verifyNoInteractions(authUserRepository);
    }

    @Test
    void parsesAvatarFileIdFromObjectKeyOnly() {
        UUID avatarFileId = UUID.randomUUID();

        Assertions.assertThat(UserAvatarObjectKeys.parseAvatarFileId(
                UserAvatarObjectKeys.objectKey(USER_ID, avatarFileId))).isEqualTo(avatarFileId);
        Assertions.assertThat(UserAvatarObjectKeys.parseAvatarFileId("avatars/" + USER_ID + "/avatar.png"))
                .isNull();
        Assertions.assertThat(UserAvatarObjectKeys.parseAvatarFileId(null)).isNull();
        Assertions.assertThat(UserAvatarObjectKeys.parseAvatarFileId("derived/photo/thumb.webp")).isNull();
    }
}
