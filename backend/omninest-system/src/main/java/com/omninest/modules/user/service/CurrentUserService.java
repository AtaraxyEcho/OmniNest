package com.omninest.modules.user.service;

import com.omninest.common.cache.ReadThroughCache;
import com.omninest.common.enums.ErrorCode;
import com.omninest.common.error.BusinessException;
import com.omninest.common.security.CurrentUserContext;
import com.omninest.common.security.MalwareScanGateway;
import com.omninest.common.security.MalwareScanGateway.ScanResult;
import com.omninest.common.security.MalwareScanGateway.Status;
import com.omninest.common.storage.ObjectStorageBuckets;
import com.omninest.common.storage.ObjectStorageClient;
import com.omninest.common.storage.ObjectStorageKey;
import com.omninest.common.sync.SyncAction;
import com.omninest.common.sync.SyncEventCommand;
import com.omninest.common.sync.SyncScope;
import com.omninest.common.sync.UserSyncEventRecorder;
import com.omninest.modules.quota.port.UserProfileCacheEvictor;
import com.omninest.modules.user.domain.AuthActiveSession;
import com.omninest.modules.user.domain.UserStatus;
import com.omninest.modules.user.dto.AuthUserDto;
import com.omninest.modules.user.domain.AuthUser;
import com.omninest.modules.user.util.AuthUserMapper;
import com.omninest.modules.user.util.UserAvatarObjectKeys;
import com.omninest.modules.user.repository.ActiveSessionRepository;
import com.omninest.modules.user.repository.AuthUserRepository;
import com.omninest.modules.notification.port.NotificationPublisher;
import jakarta.annotation.PostConstruct;
import java.io.IOException;
import java.time.Duration;
import java.time.Instant;
import java.util.ArrayList;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.UUID;

import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.stereotype.Service;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.transaction.support.TransactionTemplate;
import org.springframework.web.multipart.MultipartFile;
import javax.imageio.ImageIO;
import javax.imageio.ImageReader;
import javax.imageio.stream.ImageInputStream;
import java.util.Iterator;

@Slf4j
@Service
@RequiredArgsConstructor
public class CurrentUserService implements UserProfileCacheEvictor {
    private final AuthUserRepository authUserRepository;
    private final ActiveSessionRepository activeSessionRepository;
    private final CurrentUserContext currentUserContext;
    private final PasswordEncoder passwordEncoder;
    private final PasswordPolicy passwordPolicy;
    private final ObjectStorageClient objectStorageClient;
    private final ObjectStorageBuckets objectStorageBuckets;
    private final NotificationPublisher notificationService;
    private final SessionRevocationService sessionRevocationService;
    private final UserSessionRevocationService userSessionRevocationService;
    private final ReadThroughCache readThroughCache;
    private final MalwareScanGateway malwareScanGateway;
    private final UserSyncEventRecorder syncEventRecorder;
    private final PlatformTransactionManager transactionManager;
    private TransactionTemplate transactionTemplate;

    @PostConstruct
    void initTransactionTemplate() {
        this.transactionTemplate = new TransactionTemplate(transactionManager);
    }

    private static final long MAX_AVATAR_SIZE = 5L * 1024 * 1024;
    private static final String PROFILE_CACHE_PREFIX = "omninest:user:profile:";

    @Transactional(rollbackFor = Exception.class)
    public AuthUserDto currentUser() {
        UUID userId = currentUserId();
        String cacheKey = PROFILE_CACHE_PREFIX + userId;
        return readThroughCache.getOrLoad(cacheKey, Duration.ofMinutes(5),
                () -> {
                    AuthUser profile = authUserRepository.findWithRolesAndPermissionsById(userId)
                            .orElseThrow(() -> new BusinessException(ErrorCode.UNAUTHORIZED, "当前用户不存在"));
                    return toDto(profile);
                },
                AuthUserDto.class);
    }

    /**
     * 驱逐用户资料缓存。
     *
     * <p>资料缓存含角色、权限与配额，TTL 五分钟内不会自愈。管理端改动这些字段时必须主动清除，
     * 否则被改动用户在缓存剩余有效期内读到的仍是旧资料。接口鉴权走 JWT claims，不受此缓存影响。</p>
     *
     * @param userId 用户标识
     */
    @Override
    public void evictProfileCache(UUID userId) {
        if (userId == null) {
            return;
        }
        readThroughCache.invalidate(PROFILE_CACHE_PREFIX + userId);
    }

    public UUID currentUserId() {
        return currentUserContext.requireCurrentUserId();
    }

    /**
     * 查询用户当前未撤销的活跃会话。
     *
     * @param userId 用户标识
     * @return 活跃会话列表
     */
    @Transactional(readOnly = true)
    public List<AuthActiveSession> activeSessions(UUID userId) {
        return activeSessionRepository.findByUserIdAndRevokedAtIsNullOrderByCreatedAtDesc(userId);
    }

    /**
     * 修改当前用户密码。
     *
     * @param userId 用户 ID
     * @param oldPassword 原密码
     * @param newPassword 新密码
     */
    @Transactional(rollbackFor = Exception.class)
    public void changePassword(UUID userId, String oldPassword, String newPassword) {
        AuthUser user = authUserRepository.findById(userId)
                .orElseThrow(() -> new BusinessException(ErrorCode.UNAUTHORIZED, "当前用户不存在"));
        if (!UserStatus.ACTIVE.getValue().equals(user.getStatus())) {
            throw new BusinessException(ErrorCode.UNAUTHORIZED, "当前用户不可用");
        }
        if (!passwordEncoder.matches(oldPassword, user.getPasswordHash())) {
            throw new BusinessException(ErrorCode.OLD_PASSWORD_INVALID, "原密码错误");
        }
        passwordPolicy.validate(user.getUsername(), newPassword);
        user.setPasswordHash(passwordEncoder.encode(newPassword));
        authUserRepository.save(user);
        evictProfileCache(userId);

        // 改密后撤销除当前会话外的全部活跃会话，阻断被盗 refresh 会话继续存活
        UUID currentSessionId = currentUserContext.currentSessionId();
        userSessionRevocationService.revokeAllExcept(userId, currentSessionId, "PASSWORD_CHANGED");

        // 发送密码修改通知
        notificationService.notifyOrLog(userId, "PASSWORD_CHANGED",
                "密码已修改", "您的账户密码已成功修改",
                Map.of("timestamp", Instant.now().toString()));
    }

    /**
     * 上传当前用户头像。
     *
     * <p>校验、ClamAV 扫描与 MinIO 上传都在事务外执行：它们串起来可达数秒，放在
     * {@code @Transactional} 里会让 API 的数据库连接整段被占住。落库与同步事件放在
     * 一个短事务内，同步事件记录器要求外层事务（MANDATORY 传播）。</p>
     *
     * @param userId 用户 ID
     * @param file 图片文件（jpg/png/webp，≤5MB）
     * @return presigned 下载 URL
     */
    public String uploadAvatar(UUID userId, MultipartFile file) {
        if (file == null || file.isEmpty() || file.getSize() <= 0 || file.getSize() > MAX_AVATAR_SIZE) {
            throw new BusinessException(ErrorCode.BAD_REQUEST, "头像文件大小不能超过 5MB");
        }
        String contentType = requireSafeAvatar(file);

        AuthUser user = authUserRepository.findById(userId)
                .orElseThrow(() -> new BusinessException(ErrorCode.UNAUTHORIZED, "当前用户不存在"));
        // 每次上传换一个新标识，对象键随之改变：旧头像对象既不会被读到，也不会因浏览器
        // 按同键缓存而停留在旧图。
        UUID oldAvatarFileId = user.getAvatarFileId();
        UUID avatarFileId = UUID.randomUUID();
        ObjectStorageKey storageKey = new ObjectStorageKey(
                objectStorageBuckets.derivedAssets(),
                UserAvatarObjectKeys.objectKey(userId, avatarFileId)
        );
        try {
            objectStorageClient.putObject(storageKey, file.getInputStream(), file.getSize(), contentType);
        } catch (IOException exception) {
            log.warn("读取头像上传内容失败: userId={}, errorType={}",
                    userId, exception.getClass().getSimpleName());
            throw new BusinessException(ErrorCode.BAD_REQUEST, "头像上传失败");
        }

        transactionTemplate.executeWithoutResult(status -> {
            AuthUser managed = authUserRepository.findById(userId)
                    .orElseThrow(() -> new BusinessException(ErrorCode.UNAUTHORIZED, "当前用户不存在"));
            managed.setAvatarFileId(avatarFileId);
            authUserRepository.save(managed);
            // 同一用户其他设备的会话资料（头像/显示名）经偏好作用域事件即时重拉。
            syncEventRecorder.record(new SyncEventCommand(
                    userId,
                    SyncScope.PREFERENCES,
                    "USER_PROFILE",
                    "USER_PROFILE",
                    SyncAction.UPDATED,
                    null,
                    Map.of()
            ));
        });
        evictProfileCache(userId);
        removeAvatarQuietly(userId, oldAvatarFileId);

        log.info("头像已上传: userId={}, assetType=AVATAR", userId);

        return objectStorageClient.createDownloadUrl(storageKey, Duration.ofHours(24)).toString();
    }

    /**
     * 旧头像不再被任何资料引用，提交新头像后删除其对象，避免每次换头像留下孤儿。
     */
    private void removeAvatarQuietly(UUID userId, UUID avatarFileId) {
        if (avatarFileId == null) {
            return;
        }
        try {
            objectStorageClient.removeObject(new ObjectStorageKey(
                    objectStorageBuckets.derivedAssets(),
                    UserAvatarObjectKeys.objectKey(userId, avatarFileId)
            ));
        } catch (RuntimeException exception) {
            log.warn("旧头像对象清理失败: userId={}, assetType=AVATAR, errorType={}",
                    userId, exception.getClass().getSimpleName());
        }
    }

    private String requireSafeAvatar(MultipartFile file) {
        String detectedType = inspectAvatar(file);
        try (var inputStream = file.getInputStream()) {
            ScanResult result = malwareScanGateway.scan(inputStream, file.getSize());
            if (result.status() == Status.CLEAN || result.status() == Status.SKIPPED) {
                return detectedType;
            }
            if (result.status() == Status.INFECTED) {
                throw new BusinessException(ErrorCode.FILE_SECURITY_REJECTED, "头像安全扫描未通过");
            }
            throw new BusinessException(ErrorCode.DEPENDENCY_UNAVAILABLE, "ClamAV 安全扫描不可用");
        } catch (IOException exception) {
            log.warn("读取待扫描头像失败: errorType={}", exception.getClass().getSimpleName());
            throw new BusinessException(ErrorCode.BAD_REQUEST, "无法读取头像内容");
        }
    }

    private String inspectAvatar(MultipartFile file) {
        try (ImageInputStream input = ImageIO.createImageInputStream(file.getInputStream())) {
            if (input == null) {
                throw new BusinessException(ErrorCode.BAD_REQUEST, "头像图片格式无效");
            }
            Iterator<ImageReader> readers = ImageIO.getImageReaders(input);
            if (!readers.hasNext()) {
                throw new BusinessException(ErrorCode.BAD_REQUEST, "头像图片格式无效");
            }
            ImageReader reader = readers.next();
            try {
                reader.setInput(input, true, true);
                int width = reader.getWidth(0);
                int height = reader.getHeight(0);
                long pixels = Math.multiplyExact((long) width, height);
                if (width <= 0 || height <= 0 || width > 10_000 || height > 10_000 || pixels > 40_000_000L) {
                    throw new BusinessException(ErrorCode.BAD_REQUEST, "头像图片尺寸超出限制");
                }
                return switch (reader.getFormatName().toLowerCase(Locale.ROOT)) {
                    case "jpeg", "jpg" -> "image/jpeg";
                    case "png" -> "image/png";
                    case "webp" -> "image/webp";
                    default -> throw new BusinessException(ErrorCode.BAD_REQUEST, "仅支持 JPG、PNG、WebP 格式");
                };
            } finally {
                reader.dispose();
            }
        } catch (BusinessException exception) {
            throw exception;
        } catch (Exception exception) {
            throw new BusinessException(ErrorCode.BAD_REQUEST, "头像图片检查失败");
        }
    }

    /**
     * 修改当前用户基础资料（显示昵称 / 邮箱）。
     *
     * <p>仅更新提供的字段；变更后失效资料缓存并广播 USER_PROFILE 同步
     * 事件，其他设备即时重拉。昵称与邮箱不出现在日志中。</p>
     *
     * @param userId 用户 ID
     * @param displayName 新显示昵称；null 表示不变
     * @param email 新邮箱；null 表示不变，空串表示清除
     * @return 更新后的用户资料
     */
    @Transactional(rollbackFor = Exception.class)
    public AuthUserDto updateProfile(UUID userId, String displayName, String email) {
        AuthUser user = authUserRepository.findById(userId)
                .orElseThrow(() -> new BusinessException(ErrorCode.UNAUTHORIZED, "当前用户不存在"));
        if (!UserStatus.ACTIVE.getValue().equals(user.getStatus())) {
            throw new BusinessException(ErrorCode.UNAUTHORIZED, "当前用户不可用");
        }
        String nextDisplayName = displayName == null ? null : normalizeDisplayName(displayName);
        String nextEmail = email == null ? null : normalizeEmail(email);

        List<String> changedFields = new ArrayList<>(2);
        if (nextDisplayName != null && !nextDisplayName.equals(user.getDisplayName())) {
            user.setDisplayName(nextDisplayName);
            changedFields.add("displayName");
        }
        if (nextEmail != null && !nextEmail.equals(user.getEmail() == null ? "" : user.getEmail())) {
            user.setEmail(nextEmail.isEmpty() ? null : nextEmail);
            changedFields.add("email");
        }
        if (changedFields.isEmpty()) {
            return currentUser();
        }
        authUserRepository.save(user);
        evictProfileCache(userId);
        log.info("用户资料已更新: userId={}, fields={}", userId, changedFields);
        syncEventRecorder.record(new SyncEventCommand(
                userId,
                SyncScope.PREFERENCES,
                "USER_PROFILE",
                "USER_PROFILE",
                SyncAction.UPDATED,
                null,
                Map.of()
        ));
        return authUserRepository.findWithRolesAndPermissionsById(userId)
                .map(this::toDto)
                .orElseThrow(() -> new BusinessException(ErrorCode.UNAUTHORIZED, "当前用户不存在"));
    }

    private String normalizeDisplayName(String displayName) {
        String trimmed = displayName.trim();
        if (trimmed.isEmpty() || trimmed.length() > 120) {
            throw new BusinessException(ErrorCode.PARAM_ERROR, "显示昵称长度须为 1-120 个字符");
        }
        return trimmed;
    }

    private String normalizeEmail(String email) {
        String trimmed = email.trim();
        if (trimmed.isEmpty()) {
            return trimmed;
        }
        if (trimmed.length() > 255 || !trimmed.matches("^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$")) {
            throw new BusinessException(ErrorCode.PARAM_ERROR, "邮箱格式不正确");
        }
        return trimmed.toLowerCase(Locale.ROOT);
    }

    /**
     * 撤销指定会话（主动登出其他设备）。
     * 先写入即时撤销状态，再持久化会话状态。
     *
     * @param userId 当前用户 ID
     * @param sessionId 会话 ID
     */
    @Transactional(rollbackFor = Exception.class)
    public void revokeSession(UUID userId, UUID sessionId) {
        AuthActiveSession session = activeSessionRepository.findByIdAndUserId(sessionId, userId)
                .orElseThrow(() -> new BusinessException(ErrorCode.NOT_FOUND, "会话不存在"));
        if (session.isRevoked()) {
            throw new BusinessException(ErrorCode.PARAM_ERROR, "会话已被撤销");
        }
        // 先更新即时撤销状态并同步落库会话状态（独立事务），任一后续失败都不会回滚吊销。
        sessionRevocationService.revokeSessionAndDeactivate(
                userId, sessionId, "用户主动撤销", Duration.ofDays(30));
    }

    private AuthUserDto toDto(AuthUser profile) {
        String avatarUrl = AuthUserMapper.resolveAvatarUrl(profile, objectStorageClient, objectStorageBuckets);
        return AuthUserMapper.toDto(profile, avatarUrl);
    }
}
