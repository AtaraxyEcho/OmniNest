package com.omninest.modules.file.service;

import com.omninest.common.enums.ErrorCode;
import com.omninest.common.error.BusinessException;
import com.omninest.common.ratelimit.RateLimitService;
import com.omninest.common.security.CredentialCipher;
import com.omninest.modules.file.domain.ShareLink;
import com.omninest.modules.file.dto.ResourceShareLinkDto;
import com.omninest.modules.file.dto.ShareAccessSessionDto;
import com.omninest.modules.file.repository.ShareLinkRepository;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.time.Duration;
import java.time.Instant;
import java.util.HexFormat;
import java.util.List;
import java.util.UUID;
import lombok.RequiredArgsConstructor;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * 通用资源分享链接应用服务。
 *
 * @author OmniNest
 */
@Service
@RequiredArgsConstructor
public class ResourceShareLinkService {

    private final ShareLinkRepository shareLinkRepository;
    private final PasswordEncoder passwordEncoder;
    private final ShareAccessSessionService shareAccessSessionService;
    private final RateLimitService rateLimitService;
    private final CredentialCipher credentialCipher;

    /**
     * 校验密码并创建短期会话，不消费分享访问次数。
     */
    @Transactional(readOnly = true)
    public ShareAccessSessionDto issueSession(
            String rawToken,
            String password,
            String expectedResourceType,
            String clientAddress
    ) {
        String tokenHash = sha256(rawToken);
        requireAuthenticationRateLimit(tokenHash, clientAddress);
        ShareLink link = requireValidLink(tokenHash, expectedResourceType);
        verifyPassword(link, password);
        ShareAccessSessionService.IssuedSession session = shareAccessSessionService.issue(
                tokenHash,
                expectedResourceType,
                link.getExpiresAt()
        );
        return new ShareAccessSessionDto(session.token(), session.expiresAt());
    }

    /** 校验密码、消费一次访问次数并创建短期会话。 */
    @Transactional(rollbackFor = Exception.class)
    public ShareAccessSessionDto issueConsumedSession(
            String rawToken,
            String password,
            String expectedResourceType,
            String clientAddress
    ) {
        String tokenHash = sha256(rawToken);
        requireAuthenticationRateLimit(tokenHash, clientAddress);
        ShareLink link = requireValidLink(tokenHash, expectedResourceType);
        verifyPassword(link, password);
        consume(link);
        ShareAccessSessionService.IssuedSession session = shareAccessSessionService.issue(
                tokenHash,
                expectedResourceType,
                link.getExpiresAt()
        );
        return new ShareAccessSessionDto(session.token(), session.expiresAt());
    }

    /** 为文件分享创建会话，资源类型由数据库中的分享链接决定。 */
    @Transactional(readOnly = true)
    public ShareAccessSessionDto issueAnySession(
            String rawToken,
            String password,
            String clientAddress
    ) {
        String tokenHash = sha256(rawToken);
        requireAuthenticationRateLimit(tokenHash, clientAddress);
        ShareLink link = requireValidLink(tokenHash, null);
        verifyPassword(link, password);
        ShareAccessSessionService.IssuedSession session = shareAccessSessionService.issue(
                tokenHash,
                link.getResourceType(),
                link.getExpiresAt()
        );
        return new ShareAccessSessionDto(session.token(), session.expiresAt());
    }

    /** 校验会话并消费一次分享访问次数。 */
    @Transactional(rollbackFor = Exception.class)
    public ResourceShareLinkDto authorizeSession(
            String rawToken,
            String sessionToken,
            String expectedResourceType
    ) {
        String tokenHash = sha256(rawToken);
        requireSessionRateLimit(tokenHash);
        ShareLink link = requireValidLink(tokenHash, expectedResourceType);
        shareAccessSessionService.require(sessionToken, tokenHash, expectedResourceType);
        consume(link);
        ShareLink consumed = shareLinkRepository.findById(link.getId())
                .orElseThrow(() -> new BusinessException(ErrorCode.NOT_FOUND, "分享链接不存在"));
        return toDto(consumed, null);
    }

    /** 校验会话但不消费访问次数，供公开预览使用。 */
    @Transactional(readOnly = true)
    public ResourceShareLinkDto requireSession(
            String rawToken,
            String sessionToken,
            String expectedResourceType
    ) {
        String tokenHash = sha256(rawToken);
        requireSessionRateLimit(tokenHash);
        ShareLink link = requireValidLink(tokenHash, expectedResourceType);
        shareAccessSessionService.require(sessionToken, tokenHash, expectedResourceType);
        return toDto(link, null);
    }

    /** 校验文件分享会话，资源类型由分享链接决定。 */
    @Transactional(readOnly = true)
    public ResourceShareLinkDto requireAnySession(String rawToken, String sessionToken) {
        String tokenHash = sha256(rawToken);
        requireSessionRateLimit(tokenHash);
        ShareLink link = requireValidLink(tokenHash, null);
        shareAccessSessionService.require(sessionToken, tokenHash, link.getResourceType());
        return toDto(link, null);
    }

    /** 校验并消费文件分享会话。 */
    @Transactional(rollbackFor = Exception.class)
    public ResourceShareLinkDto authorizeAnySession(String rawToken, String sessionToken) {
        String tokenHash = sha256(rawToken);
        requireSessionRateLimit(tokenHash);
        ShareLink link = requireValidLink(tokenHash, null);
        shareAccessSessionService.require(sessionToken, tokenHash, link.getResourceType());
        consume(link);
        ShareLink consumed = shareLinkRepository.findById(link.getId())
                .orElseThrow(() -> new BusinessException(ErrorCode.NOT_FOUND, "分享链接不存在"));
        return toDto(consumed, null);
    }

    /**
     * 创建资源分享链接。
     *
     * @param ownerUserId 所有者用户 ID
     * @param resourceType 资源类型
     * @param resourceId 资源 ID
     * @param password 可选访问密码
     * @param expiresAt 可选过期时间
     * @param maxAccessCount 可选最大访问次数
     * @return 分享链接描述符
     */
    @Transactional(rollbackFor = Exception.class)
    public ResourceShareLinkDto create(
            UUID ownerUserId,
            String resourceType,
            UUID resourceId,
            String password,
            Instant expiresAt,
            Integer maxAccessCount) {
        return create(
                ownerUserId,
                resourceType,
                resourceId,
                password,
                expiresAt,
                maxAccessCount,
                true,
                true
        );
    }

    /**
     * 创建资源分享链接，可附带照片分享策略。
     *
     * @param includeLocation 公开访问是否包含位置（非照片类型忽略）
     * @param originalQuality 公开访问是否签发原图（非照片类型忽略）
     */
    @Transactional(rollbackFor = Exception.class)
    public ResourceShareLinkDto create(
            UUID ownerUserId,
            String resourceType,
            UUID resourceId,
            String password,
            Instant expiresAt,
            Integer maxAccessCount,
            boolean includeLocation,
            boolean originalQuality) {
        String rawToken = UUID.randomUUID().toString().replace("-", "");
        ShareLink share = new ShareLink();
        share.setOwnerUserId(ownerUserId);
        share.setResourceType(resourceType);
        share.setResourceId(resourceId);
        share.setTokenHash(sha256(rawToken));
        // 密文令牌支持所有者日后重新复制链接地址；公开校验仍是哈希比对。
        share.setTokenCipher(credentialCipher.encrypt(rawToken));
        share.setExpiresAt(expiresAt);
        share.setMaxAccessCount(maxAccessCount);
        share.setIncludeLocation(includeLocation);
        share.setOriginalQuality(originalQuality);
        if (password != null && !password.isBlank()) {
            share.setPasswordHash(passwordEncoder.encode(password));
        }
        return toDto(shareLinkRepository.save(share), rawToken);
    }

    /**
     * 列出所有者指定资源仍有效的分享链接。
     *
     * 已撤销（{@code disabledAt} 非空）的链接不返回：撤销是软删除，公开访问
     * 依据同一字段拒绝，管理界面同样不应再显示它们。资源级链接数量级很小，
     * 在此过滤即可，无需新增仓储查询方法。
     *
     * 令牌以密文回传解密后的明文，使所有者能重新复制既有链接地址；公开访问
     * 路径不经过本方法，不暴露令牌。
     *
     * @param ownerUserId 所有者用户 ID
     * @param resourceId 资源 ID
     * @return 仍有效的分享链接描述符列表
     */
    @Transactional(readOnly = true)
    public List<ResourceShareLinkDto> list(UUID ownerUserId, UUID resourceId) {
        return shareLinkRepository.findByOwnerUserIdAndResourceIdIn(ownerUserId, List.of(resourceId))
                .stream()
                .filter(link -> link.getDisabledAt() == null)
                .map(link -> toDto(link, revealToken(link)))
                .toList();
    }

    /**
     * 解密链接的明文令牌；历史数据或密钥不可用时返回 null，调用方按"无地址"处理。
     */
    private String revealToken(ShareLink link) {
        String cipher = link.getTokenCipher();
        if (cipher == null || cipher.isBlank()) {
            return null;
        }
        try {
            return credentialCipher.decrypt(cipher);
        } catch (RuntimeException error) {
            return null;
        }
    }

    /**
     * 撤销所有者的分享链接。
     *
     * @param ownerUserId 所有者用户 ID
     * @param shareId 分享链接 ID
     */
    @Transactional(rollbackFor = Exception.class)
    public void revoke(UUID ownerUserId, UUID shareId) {
        ShareLink share = shareLinkRepository.findByIdAndOwnerUserId(shareId, ownerUserId)
                .orElseThrow(() -> new BusinessException(ErrorCode.NOT_FOUND, "分享链接不存在"));
        share.setDisabledAt(Instant.now());
        shareLinkRepository.save(share);
    }

    /**
     * 一次性撤销指定资源的全部有效分享链接。
     *
     * 单条批量更新为全有或全无，因此结果是撤销条数而非逐项状态。
     * 调用方必须已完成资源归属校验：批量更新按资源 ID 生效，不重复校验所有者。
     *
     * @param resourceId 资源 ID
     * @return 被撤销的链接条数
     */
    @Transactional(rollbackFor = Exception.class)
    public int revokeAll(UUID resourceId) {
        List<ShareLink> active = shareLinkRepository.findByResourceIdAndDisabledAtIsNull(resourceId);
        if (active.isEmpty()) {
            return 0;
        }
        shareLinkRepository.disableByResourceId(resourceId, Instant.now());
        return active.size();
    }

    /**
     * 校验公开分享访问并原子增加访问次数。
     *
     * @param rawToken 原始分享令牌
     * @param password 可选访问密码
     * @param expectedResourceType 期望的资源类型
     * @return 已授权的分享链接描述符
     */
    @Transactional(rollbackFor = Exception.class)
    public ResourceShareLinkDto authorize(String rawToken, String password, String expectedResourceType) {
        ShareLink link = requireValidLink(sha256(rawToken), expectedResourceType);
        verifyPassword(link, password);
        consume(link);
        ShareLink consumed = shareLinkRepository.findById(link.getId())
                .orElseThrow(() -> new BusinessException(ErrorCode.NOT_FOUND, "分享链接不存在"));
        return toDto(consumed, null);
    }

    private ShareLink requireValidLink(String tokenHash, String expectedResourceType) {
        ShareLink link = shareLinkRepository.findByTokenHash(tokenHash)
                .filter(candidate -> expectedResourceType == null || expectedResourceType.equals(candidate.getResourceType()))
                .orElseThrow(() -> new BusinessException(ErrorCode.NOT_FOUND, "分享链接不存在"));
        if (link.getDisabledAt() != null) {
            throw new BusinessException(ErrorCode.BAD_REQUEST, "分享链接已撤销");
        }
        if (link.getExpiresAt() != null && link.getExpiresAt().isBefore(Instant.now())) {
            throw new BusinessException(ErrorCode.BAD_REQUEST, "分享链接已过期");
        }
        return link;
    }

    private void verifyPassword(ShareLink link, String password) {
        if (link.getPasswordHash() != null
                && (password == null || !passwordEncoder.matches(password, link.getPasswordHash()))) {
            throw new BusinessException(ErrorCode.BAD_REQUEST, "密码错误");
        }
    }

    private void requireAuthenticationRateLimit(String tokenHash, String clientAddress) {
        if (!rateLimitService.tryAcquire("share-auth:token:" + tokenHash, 10, Duration.ofMinutes(1))
                || (clientAddress != null
                && !rateLimitService.tryAcquire(
                "share-auth:ip:" + sha256(clientAddress), 30, Duration.ofMinutes(1)))) {
            throw new BusinessException(ErrorCode.RATE_LIMITED, "访问过于频繁，请稍后再试");
        }
    }

    private void requireSessionRateLimit(String tokenHash) {
        if (!rateLimitService.tryAcquire(
                "share-session:token:" + tokenHash,
                120,
                Duration.ofMinutes(1))) {
            throw new BusinessException(ErrorCode.RATE_LIMITED, "访问过于频繁，请稍后再试");
        }
    }

    private void consume(ShareLink link) {
        Instant now = Instant.now();
        if (shareLinkRepository.consumeAccess(link.getId(), now) == 0) {
            throw new BusinessException(ErrorCode.BAD_REQUEST, "分享链接访问次数已达上限");
        }
    }

    private ResourceShareLinkDto toDto(ShareLink share, String rawToken) {
        return new ResourceShareLinkDto(
                share.getId(),
                rawToken,
                share.getResourceType(),
                share.getResourceId(),
                share.getExpiresAt(),
                share.getMaxAccessCount(),
                share.getAccessCount(),
                share.isIncludeLocation(),
                share.isOriginalQuality(),
                share.getCreatedAt()
        );
    }

    private String sha256(String value) {
        try {
            MessageDigest digest = MessageDigest.getInstance("SHA-256");
            return HexFormat.of().formatHex(digest.digest(value.getBytes(StandardCharsets.UTF_8)));
        } catch (NoSuchAlgorithmException exception) {
            throw new IllegalStateException("SHA-256 算法不可用", exception);
        }
    }
}
