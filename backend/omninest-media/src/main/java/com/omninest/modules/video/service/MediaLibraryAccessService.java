package com.omninest.modules.video.service;

import com.omninest.common.api.PageResponse;
import com.omninest.common.enums.ErrorCode;
import com.omninest.common.error.BusinessException;
import com.omninest.common.security.Permissions;
import com.omninest.modules.file.domain.StorageLocation;
import com.omninest.modules.file.service.StorageLocationService;
import com.omninest.modules.user.domain.UserStatus;
import com.omninest.modules.user.dto.UserDirectoryDtos.UserAuthorizationProfile;
import com.omninest.modules.user.dto.UserDirectoryDtos.UserDirectoryEntry;
import com.omninest.modules.user.service.UserDirectoryQueryService;
import com.omninest.modules.video.domain.MediaLibraryAccess;
import com.omninest.modules.video.domain.MediaLibraryVisibility;
import com.omninest.modules.video.domain.VideoLibrarySource;
import com.omninest.modules.video.dto.MediaLibraryAccessDtos.MediaLibraryAccessDto;
import com.omninest.modules.video.dto.MediaLibraryAccessDtos.UpdateMediaLibraryAccessRequest;
import com.omninest.modules.video.repository.MediaLibraryAccessRepository;
import com.omninest.modules.video.repository.VideoLibrarySourceRepository;
import java.time.Instant;
import java.util.HashSet;
import java.util.List;
import java.util.Set;
import java.util.UUID;
import java.util.stream.Collectors;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * 统一处理媒体库管理和消费授权。
 *
 * @author OmniNest
 */
@Service
@RequiredArgsConstructor
public class MediaLibraryAccessService {
    private static final Set<String> MEMBER_ROLES = Set.of("MEMBER", "ADMIN", "SUPER_ADMIN");
    private static final String SYSTEM_SCOPE = "SYSTEM";

    private final VideoLibrarySourceRepository sourceRepository;
    private final MediaLibraryAccessRepository accessRepository;
    private final UserDirectoryQueryService userDirectoryQueryService;
    private final StorageLocationService storageLocationService;

    /** 校验媒体库管理权限。 */
    @Transactional(readOnly = true)
    public void requireManagePermission(UUID operatorUserId) {
        requirePermission(operatorUserId, Permissions.MEDIA_LIBRARY_MANAGE);
    }

    /**
     * 校验系统配置管理权限，用于挂载直达创建存储位置的分支；
     * 该分支能力超出媒体库管理权限，需以数据库授权档案单独把关。
     */
    @Transactional(readOnly = true)
    public void requireSystemConfigManage(UUID operatorUserId) {
        requirePermission(operatorUserId, Permissions.SYSTEM_CONFIG_MANAGE);
    }

    /** 校验媒体消费权限和账号状态。 */
    @Transactional(readOnly = true)
    public void requireReadPermission(UUID requesterUserId) {
        requirePermission(requesterUserId, Permissions.MEDIA_READ);
    }

    /** 删除来源的显式用户授权，来源删除由来源服务在同一事务中调用。 */
    @Transactional(rollbackFor = Exception.class)
    public void deleteForSource(UUID librarySourceId) {
        accessRepository.deleteByLibrarySourceId(librarySourceId);
    }

    /** 校验媒体库管理权限并返回来源。 */
    @Transactional(readOnly = true)
    public VideoLibrarySource requireManage(UUID operatorUserId, UUID librarySourceId) {
        requirePermission(operatorUserId, Permissions.MEDIA_LIBRARY_MANAGE);
        return requireSource(librarySourceId);
    }

    /** 校验媒体库读取权限并返回来源。 */
    @Transactional(readOnly = true)
    public VideoLibrarySource requireRead(UUID requesterUserId, UUID librarySourceId) {
        UserAuthorizationProfile profile = requirePermission(requesterUserId, Permissions.MEDIA_READ);
        VideoLibrarySource source = requireSource(librarySourceId);
        if (!source.isEnabled() || !canRead(profile, source)) {
            throw new BusinessException(ErrorCode.FORBIDDEN, "无权访问该媒体库");
        }
        return source;
    }

    /** 查询用户可读取的本地媒体库 ID。 */
    @Transactional(readOnly = true)
    public Set<UUID> findReadableLibraryIds(UUID requesterUserId) {
        UserAuthorizationProfile profile = requirePermission(requesterUserId, Permissions.MEDIA_READ);
        Set<UUID> selectedLibraryIds = accessRepository.findByUserId(requesterUserId).stream()
                .map(MediaLibraryAccess::getLibrarySourceId)
                .collect(Collectors.toUnmodifiableSet());
        Set<UUID> result = new HashSet<>();
        for (VideoLibrarySource source : sourceRepository.findByEnabledTrueOrderByNameAsc()) {
            if (canRead(profile, source, selectedLibraryIds)) {
                result.add(source.getId());
            }
        }
        return Set.copyOf(result);
    }

    /** 查询媒体库当前访问设置。 */
    @Transactional(readOnly = true)
    public MediaLibraryAccessDto details(UUID operatorUserId, UUID librarySourceId) {
        VideoLibrarySource source = requireManage(operatorUserId, librarySourceId);
        return toDto(source);
    }

    /** 原子替换媒体库可见性和显式用户授权。 */
    @Transactional(rollbackFor = Exception.class)
    public MediaLibraryAccessDto replaceSelectedUsers(
            UUID operatorUserId,
            UUID librarySourceId,
            UpdateMediaLibraryAccessRequest request
    ) {
        VideoLibrarySource source = requireManage(operatorUserId, librarySourceId);
        if (source.getVersion() != request.expectedVersion()) {
            throw new BusinessException(ErrorCode.CONFLICT, "媒体库访问设置已被其他管理员修改，请刷新后重试");
        }
        MediaLibraryVisibility visibility = request.visibilityType();
        requireShareableStorage(source, visibility);
        Set<UUID> selectedUsers = visibility == MediaLibraryVisibility.SELECTED_USERS
                ? Set.copyOf(request.userIds())
                : Set.of();
        for (UUID userId : selectedUsers) {
            UserAuthorizationProfile profile = userDirectoryQueryService.requireAuthorizationProfile(userId);
            if (!UserStatus.ACTIVE.getValue().equals(profile.status())
                    || !profile.permissions().contains(Permissions.MEDIA_READ)) {
                throw new BusinessException(ErrorCode.PARAM_ERROR, "授权用户不存在、已禁用或缺少媒体读取权限");
            }
        }
        accessRepository.deleteByLibrarySourceId(librarySourceId);
        if (!selectedUsers.isEmpty()) {
            List<MediaLibraryAccess> accesses = selectedUsers.stream()
                    .map(userId -> newAccess(librarySourceId, userId, operatorUserId))
                    .toList();
            accessRepository.saveAll(accesses);
        }
        source.setVisibilityType(visibility.name());
        source.setUpdatedAt(Instant.now());
        VideoLibrarySource saved = sourceRepository.saveAndFlush(source);
        return toDto(saved);
    }

    /** 查询可供媒体库授权选择的活动用户。 */
    @Transactional(readOnly = true)
    public PageResponse<UserDirectoryEntry> userCandidates(
            UUID operatorUserId,
            String query,
            int page,
            int size
    ) {
        requirePermission(operatorUserId, Permissions.MEDIA_LIBRARY_MANAGE);
        return userDirectoryQueryService.findActiveUsers(query, page, size);
    }

    /** 检查用户能否读取来源，不抛出异常。 */
    @Transactional(readOnly = true)
    public boolean canRead(UUID requesterUserId, VideoLibrarySource source) {
        if (source == null || !source.isEnabled()) {
            return false;
        }
        try {
            return canRead(requirePermission(requesterUserId, Permissions.MEDIA_READ), source);
        } catch (BusinessException exception) {
            return false;
        }
    }

    private boolean canRead(UserAuthorizationProfile profile, VideoLibrarySource source) {
        return canRead(profile, source, null);
    }

    private boolean canRead(
            UserAuthorizationProfile profile,
            VideoLibrarySource source,
            Set<UUID> selectedLibraryIds
    ) {
        if (source.getOwnerUserId().equals(profile.id())) {
            return true;
        }
        MediaLibraryVisibility visibility = MediaLibraryVisibility.from(source.getVisibilityType());
        return switch (visibility) {
            case PRIVATE -> false;
            case SELECTED_USERS -> selectedLibraryIds == null
                    ? accessRepository.existsByLibrarySourceIdAndUserId(source.getId(), profile.id())
                    : selectedLibraryIds.contains(source.getId());
            case ALL_MEMBERS -> profile.roles().stream().anyMatch(MEMBER_ROLES::contains);
        };
    }

    private UserAuthorizationProfile requirePermission(UUID userId, String permission) {
        UserAuthorizationProfile profile = userDirectoryQueryService.requireAuthorizationProfile(userId);
        if (!UserStatus.ACTIVE.getValue().equals(profile.status()) || !profile.permissions().contains(permission)) {
            throw new BusinessException(ErrorCode.FORBIDDEN, "当前用户没有所需权限");
        }
        return profile;
    }

    private void requireShareableStorage(VideoLibrarySource source, MediaLibraryVisibility visibility) {
        if (visibility == MediaLibraryVisibility.PRIVATE) {
            return;
        }
        StorageLocation location = storageLocationService.requireLocationForBusiness(source.getStorageLocationId());
        if (!SYSTEM_SCOPE.equals(location.getScopeType())) {
            throw new BusinessException(ErrorCode.FORBIDDEN, "用户级存储位置不能共享给其他用户");
        }
    }

    private VideoLibrarySource requireSource(UUID librarySourceId) {
        return sourceRepository.findById(librarySourceId)
                .orElseThrow(() -> new BusinessException(ErrorCode.MEDIA_NOT_FOUND, "媒体库不存在"));
    }

    private MediaLibraryAccess newAccess(UUID librarySourceId, UUID userId, UUID operatorUserId) {
        MediaLibraryAccess access = new MediaLibraryAccess();
        access.setLibrarySourceId(librarySourceId);
        access.setUserId(userId);
        access.setCreatedBy(operatorUserId);
        return access;
    }

    private MediaLibraryAccessDto toDto(VideoLibrarySource source) {
        Set<UUID> selectedUserIds = accessRepository.findByLibrarySourceIdOrderByCreatedAtAsc(source.getId()).stream()
                .map(MediaLibraryAccess::getUserId)
                .collect(Collectors.toUnmodifiableSet());
        return new MediaLibraryAccessDto(
                source.getId(),
                MediaLibraryVisibility.from(source.getVisibilityType()),
                selectedUserIds,
                source.getVersion()
        );
    }
}
