package com.omninest.modules.user.service;

import com.omninest.modules.user.repository.AuthUserRepository;
import com.omninest.modules.user.util.UserAvatarObjectKeys;
import java.util.Collection;
import java.util.HashMap;
import java.util.HashSet;
import java.util.Map;
import java.util.Set;
import java.util.UUID;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * 基于用户资料中的头像文件标识实现对象引用查询。
 *
 * @author OmniNest
 */
@Service
@RequiredArgsConstructor
public class UserAvatarObjectReferenceQueryService implements UserAvatarObjectReferenceQuery {

    private final AuthUserRepository authUserRepository;

    /**
     * 查询候选对象键中仍被用户头像引用的键。
     *
     * <p>头像对象键是 {@code avatars/{userId}/{avatarFileId}}，末段就是
     * {@code auth_users.avatar_file_id}；不符合该形状（含旧的 {@code avatar.{ext}}）的键
     * 不再被视为在用，交给孤儿清理回收。</p>
     *
     * @param objectKeys 候选对象键
     * @return 已引用对象键
     */
    @Override
    @Transactional(readOnly = true)
    public Set<String> findReferencedObjectKeys(Collection<String> objectKeys) {
        if (objectKeys == null || objectKeys.isEmpty()) {
            return Set.of();
        }
        Map<UUID, String> objectKeysByAvatarId = new HashMap<>();
        for (String objectKey : objectKeys) {
            UUID avatarFileId = UserAvatarObjectKeys.parseAvatarFileId(objectKey);
            if (avatarFileId != null) {
                objectKeysByAvatarId.put(avatarFileId, objectKey);
            }
        }
        if (objectKeysByAvatarId.isEmpty()) {
            return Set.of();
        }
        Set<String> referencedObjectKeys = new HashSet<>();
        for (UUID avatarFileId : authUserRepository.findExistingAvatarFileIds(objectKeysByAvatarId.keySet())) {
            String objectKey = objectKeysByAvatarId.get(avatarFileId);
            if (objectKey != null) {
                referencedObjectKeys.add(objectKey);
            }
        }
        return Set.copyOf(referencedObjectKeys);
    }
}
