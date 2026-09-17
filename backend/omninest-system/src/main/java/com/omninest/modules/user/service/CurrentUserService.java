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
import com.omninest.modules.user.domain.AuthActiveSession;
import com.omninest.modules.user.dto.AuthUserDto;
import com.omninest.modules.user.domain.AuthUser;
import com.omninest.modules.user.util.AuthUserMapper;
import com.omninest.modules.user.repository.ActiveSessionRepository;
import com.omninest.modules.user.repository.AuthUserRepository;
import com.omninest.modules.notification.port.NotificationPublisher;
import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.time.Duration;
import java.time.Instant;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.UUID;

import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.multipart.MultipartFile;
import javax.imageio.ImageIO;
import javax.imageio.ImageReader;
import javax.imageio.stream.ImageInputStream;
import java.util.Iterator;

@Slf4j
@Service
@RequiredArgsConstructor
public class CurrentUserService {
    private final AuthUserRepository authUserRepository;
    private final ActiveSessionRepository activeSessionRepository;
    private final CurrentUserContext currentUserContext;
    private final PasswordEncoder passwordEncoder;
    private final PasswordPolicy passwordPolicy;
    private final ObjectStorageClient objectStorageClient;
    private final ObjectStorageBuckets objectStorageBuckets;
    private final NotificationPublisher notificationService;
    private final SessionRevocationService sessionRevocationService;
    private final ReadThroughCache readThroughCache;
    private final MalwareScanGateway malwareScanGateway;

    private static final long MAX_AVATAR_SIZE = 5L * 1024 * 1024;

    @Transactional(rollbackFor = Exception.class)
    public AuthUserDto currentUser() {
        UUID userId = currentUserId();
        String cacheKey = "omninest:user:profile:" + userId;
        return readThroughCache.getOrLoad(cacheKey, Duration.ofMinutes(5),
                () -> {
                    AuthUser profile = authUserRepository.findWithRolesAndPermissionsById(userId)
                            .orElseThrow(() -> new BusinessException(ErrorCode.UNAUTHORIZED, "当前用户不存在"));
                    return toDto(profile);
                },
                AuthUserDto.class);
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
        if (!passwordEncoder.matches(oldPassword, user.getPasswordHash())) {
            throw new BusinessException(ErrorCode.BAD_REQUEST, "原密码错误");
        }
        passwordPolicy.validate(user.getUsername(), newPassword);
        user.setPasswordHash(passwordEncoder.encode(newPassword));
        authUserRepository.save(user);
        readThroughCache.invalidate("omninest:user:profile:" + userId);

        // 发送密码修改通知
        notificationService.notifyOrLog(userId, "PASSWORD_CHANGED",
                "密码已修改", "您的账户密码已成功修改",
                Map.of("timestamp", Instant.now().toString()));
    }

    /**
     * 上传当前用户头像。
     *
     * @param userId 用户 ID
     * @param file 图片文件（jpg/png/webp，≤5MB）
     * @return presigned 下载 URL
     */
    @Transactional(rollbackFor = Exception.class)
    public String uploadAvatar(UUID userId, MultipartFile file) {
        if (file == null || file.isEmpty() || file.getSize() <= 0 || file.getSize() > MAX_AVATAR_SIZE) {
            throw new BusinessException(ErrorCode.BAD_REQUEST, "头像文件大小不能超过 5MB");
        }
        String contentType = requireSafeAvatar(file);

        // 生成对象 key（覆盖式更新）
        String ext = switch (contentType) {
            case "image/jpeg" -> "jpg";
            case "image/png" -> "png";
            case "image/webp" -> "webp";
            default -> "bin";
        };
        String bucket = objectStorageBuckets.derivedAssets();
        String objectKey = "avatars/" + userId + "/avatar." + ext;
        ObjectStorageKey storageKey = new ObjectStorageKey(bucket, objectKey);

        // 上传到 MinIO
        try {
            objectStorageClient.putObject(storageKey, file.getInputStream(), file.getSize(), contentType);
        } catch (IOException e) {
            log.warn("读取头像上传内容失败: userId={}, errorType={}", userId, e.getClass().getSimpleName());
            throw new BusinessException(ErrorCode.BAD_REQUEST, "头像上传失败");
        }

        // 保存 avatarFileId（使用 objectKey 的 hashCode 作为标识）
        AuthUser user = authUserRepository.findById(userId)
                .orElseThrow(() -> new BusinessException(ErrorCode.UNAUTHORIZED, "当前用户不存在"));
        user.setAvatarFileId(UUID.nameUUIDFromBytes(objectKey.getBytes(StandardCharsets.UTF_8)));
        authUserRepository.save(user);
        readThroughCache.invalidate("omninest:user:profile:" + userId);

        log.info("头像已上传: userId={}, assetType=AVATAR", userId);

        // 返回 presigned 下载 URL
        return objectStorageClient.createDownloadUrl(storageKey, Duration.ofHours(24)).toString();
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
        // 先更新即时撤销状态
        sessionRevocationService.revokeSession(userId, sessionId, Duration.ofDays(30));
        // 再持久化会话状态
        activeSessionRepository.revokeBySessionId(sessionId, "用户主动撤销");
    }

    private AuthUserDto toDto(AuthUser profile) {
        String avatarUrl = AuthUserMapper.resolveAvatarUrl(profile, objectStorageClient, objectStorageBuckets);
        return AuthUserMapper.toDto(profile, avatarUrl);
    }
}
