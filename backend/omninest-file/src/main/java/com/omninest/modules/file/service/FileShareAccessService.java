package com.omninest.modules.file.service;

import com.omninest.common.cache.ReadThroughCache;
import com.omninest.common.enums.ErrorCode;
import com.omninest.common.error.BusinessException;
import com.omninest.common.ratelimit.RateLimitService;
import com.omninest.modules.file.domain.FileNode;
import com.omninest.modules.file.domain.NodeType;
import com.omninest.modules.file.domain.ShareLink;
import com.omninest.modules.file.domain.SourceType;
import com.omninest.modules.file.domain.SpaceType;
import com.omninest.modules.file.dto.AcceptShareRequest;
import com.omninest.modules.file.dto.FileDownloadUrlDto;
import com.omninest.modules.file.dto.FileShareAccessDto;
import com.omninest.modules.file.dto.FileSharePreviewDto;
import com.omninest.modules.file.dto.ShareAccessSessionDto;
import com.omninest.modules.file.repository.FileNodeRepository;
import com.omninest.modules.file.repository.ShareLinkRepository;
import com.omninest.modules.notification.port.NotificationPublisher;
import java.time.Duration;
import java.time.Instant;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * 分享访问服务。
 * 负责分享密码校验、公开访问/预览、短期会话访问与接受分享落盘。
 *
 * @author OmniNest
 */
@Slf4j
@Service
@RequiredArgsConstructor
public class FileShareAccessService {
    private final FileNodeRepository fileNodeRepository;
    private final ShareLinkRepository shareLinkRepository;
    private final PasswordEncoder passwordEncoder;
    private final RateLimitService rateLimitService;
    private final NotificationPublisher notificationService;
    private final FileQueryService fileQueryService;
    private final ResourceShareLinkService resourceShareLinkService;
    private final ReadThroughCache readThroughCache;
    private final FileNodeSupport fileNodeSupport;

    /**
     * 通过分享 token 与密码访问文件并消费一次访问次数。
     *
     * @param rawToken 分享明文 token
     * @param password 分享密码，可空
     * @return 分享文件访问结果
     */
    @Transactional(rollbackFor = Exception.class)
    public FileShareAccessDto shareAccess(String rawToken, String password) {
        String tokenHash = FileShareService.sha256(rawToken);
        requireShareRateLimit(tokenHash);
        ShareLink link = findShareLinkCached(tokenHash);
        if (link.getDisabledAt() != null) {
            throw new BusinessException(ErrorCode.CONFLICT, "分享链接已撤销");
        }
        if (link.getExpiresAt() != null && Instant.now().isAfter(link.getExpiresAt())) {
            throw new BusinessException(ErrorCode.CONFLICT, "分享链接已过期");
        }
        if (link.getPasswordHash() != null) {
            if (password == null || !passwordEncoder.matches(password, link.getPasswordHash())) {
                throw new BusinessException(ErrorCode.PASSWORD_INVALID, "密码错误");
            }
        }
        link = consumeShareAccess(link, tokenHash);

        FileNode node = fileNodeRepository.findByIdAndOwnerUserIdAndDeletedFalse(
                        link.getResourceId(),
                        link.getOwnerUserId()
                )
                .orElseThrow(() -> new BusinessException(ErrorCode.FILE_NOT_FOUND, "文件不存在或已被删除"));
        log.info(
                "分享链接被访问: shareId={}, accessCount={}, fileName={}",
                link.getId(),
                link.getAccessCount(),
                node.getName()
        );
        FileDownloadUrlDto downloadUrl = fileQueryService.createDownloadUrl(link.getOwnerUserId(), node.getId());

        // 发送分享被访问通知
        try {
            notificationService.create(link.getOwnerUserId(), "SHARE_ACCESSED",
                    "分享被访问", "有人访问了您分享的文件: " + node.getName(),
                    Map.of("shareId", link.getId().toString(), "fileName", node.getName()));
        } catch (Exception e) {
            log.warn("发送分享访问通知失败: shareId={}", link.getId(), e);
        }

        return new FileShareAccessDto(node.getName(), node.getMimeType(), node.getSizeBytes(),
                downloadUrl.downloadUrl(), link.getResourceType());
    }

    /**
     * 预览分享链接内容（公开端点，无需登录）。
     * 预览不消耗访问次数，仅校验密码和链接有效性。
     *
     * @param rawToken 分享明文 token
     * @param password 分享密码，可空
     * @return 分享预览信息
     */
    @Transactional(readOnly = true)
    public FileSharePreviewDto previewShare(String rawToken, String password) {
        String tokenHash = FileShareService.sha256(rawToken);
        requireShareRateLimit(tokenHash);
        ShareLink link = findShareLinkCached(tokenHash);
        if (link.getDisabledAt() != null) {
            throw new BusinessException(ErrorCode.CONFLICT, "分享链接已撤销");
        }
        if (link.getExpiresAt() != null && Instant.now().isAfter(link.getExpiresAt())) {
            throw new BusinessException(ErrorCode.CONFLICT, "分享链接已过期");
        }
        if (link.getMaxAccessCount() != null && link.getAccessCount() >= link.getMaxAccessCount()) {
            throw new BusinessException(ErrorCode.CONFLICT, "分享链接访问次数已达上限");
        }
        if (link.getPasswordHash() != null) {
            if (password == null || !passwordEncoder.matches(password, link.getPasswordHash())) {
                throw new BusinessException(ErrorCode.PASSWORD_INVALID, "密码错误");
            }
        }

        FileNode node = fileNodeRepository.findByIdAndOwnerUserIdAndDeletedFalse(
                        link.getResourceId(),
                        link.getOwnerUserId()
                )
                .orElseThrow(() -> new BusinessException(ErrorCode.FILE_NOT_FOUND, "文件不存在或已被删除"));

        return new FileSharePreviewDto(
                link.getId(),
                node.getName(),
                node.getMimeType(),
                node.getSizeBytes(),
                link.getResourceType(),
                link.getPasswordHash() != null
        );
    }

    /**
     * 接受分享，将文件保存到当前用户名下。
     *
     * @param userId  接受用户 ID
     * @param rawToken 分享明文 token
     * @param request 接受请求（目标目录与密码）
     */
    @Transactional(rollbackFor = Exception.class)
    public void acceptShare(UUID userId, String rawToken, AcceptShareRequest request) {
        String tokenHash = FileShareService.sha256(rawToken);
        requireShareRateLimit(tokenHash);
        ShareLink link = findShareLinkCached(tokenHash);
        if (link.getDisabledAt() != null) {
            throw new BusinessException(ErrorCode.CONFLICT, "分享链接已撤销");
        }
        if (link.getExpiresAt() != null && Instant.now().isAfter(link.getExpiresAt())) {
            throw new BusinessException(ErrorCode.CONFLICT, "分享链接已过期");
        }
        if (link.getPasswordHash() != null) {
            String pwd = request != null ? request.password() : null;
            if (pwd == null || !passwordEncoder.matches(pwd, link.getPasswordHash())) {
                throw new BusinessException(ErrorCode.PASSWORD_INVALID, "密码错误");
            }
        }

        link = consumeShareAccess(link, tokenHash);

        FileNode sourceNode = fileNodeRepository.findByIdAndOwnerUserIdAndDeletedFalse(
                        link.getResourceId(),
                        link.getOwnerUserId()
                )
                .orElseThrow(() -> new BusinessException(ErrorCode.FILE_NOT_FOUND, "源文件不存在或已被删除"));

        UUID targetParentId = request != null ? request.targetParentId() : null;
        if ("FOLDER".equals(link.getResourceType())) {
            acceptFolderShare(userId, sourceNode, targetParentId);
        } else {
            acceptFileShare(userId, sourceNode, targetParentId);
        }

        log.info("用户接受分享: userId={}, shareId={}, resourceType={}", userId, link.getId(), link.getResourceType());
    }

    /**
     * 校验文件分享密码并签发短期会话。
     *
     * @param rawToken       分享明文 token
     * @param password       分享密码
     * @param clientAddress  客户端地址
     * @return 短期会话信息
     */
    @Transactional(readOnly = true)
    public ShareAccessSessionDto issueShareSession(String rawToken, String password, String clientAddress) {
        return resourceShareLinkService.issueAnySession(rawToken, password, clientAddress);
    }

    /**
     * 使用短期会话访问分享文件并消费一次访问次数。
     *
     * @param rawToken     分享明文 token
     * @param sessionToken 短期会话 token
     * @return 分享文件访问结果
     */
    @Transactional(rollbackFor = Exception.class)
    public FileShareAccessDto shareAccessSession(String rawToken, String sessionToken) {
        String tokenHash = FileShareService.sha256(rawToken);
        requireShareRateLimit(tokenHash);
        resourceShareLinkService.authorizeAnySession(rawToken, sessionToken);
        ShareLink link = findShareLinkCached(tokenHash);
        FileNode node = fileNodeRepository.findByIdAndOwnerUserIdAndDeletedFalse(
                        link.getResourceId(), link.getOwnerUserId())
                .orElseThrow(() -> new BusinessException(ErrorCode.FILE_NOT_FOUND, "文件不存在或已被删除"));
        FileDownloadUrlDto downloadUrl = fileQueryService.createDownloadUrl(link.getOwnerUserId(), node.getId());
        return new FileShareAccessDto(
                node.getName(), node.getMimeType(), node.getSizeBytes(),
                downloadUrl.downloadUrl(), link.getResourceType());
    }

    /**
     * 使用短期会话预览文件分享，不接受 URL 密码。
     *
     * @param rawToken     分享明文 token
     * @param sessionToken 短期会话 token
     * @return 分享预览信息
     */
    @Transactional(readOnly = true)
    public FileSharePreviewDto previewShareSession(String rawToken, String sessionToken) {
        String tokenHash = FileShareService.sha256(rawToken);
        requireShareRateLimit(tokenHash);
        resourceShareLinkService.requireAnySession(rawToken, sessionToken);
        ShareLink link = findShareLinkCached(tokenHash);
        FileNode node = fileNodeRepository.findByIdAndOwnerUserIdAndDeletedFalse(
                        link.getResourceId(), link.getOwnerUserId())
                .orElseThrow(() -> new BusinessException(ErrorCode.FILE_NOT_FOUND, "文件不存在或已被删除"));
        return new FileSharePreviewDto(
                link.getId(), node.getName(), node.getMimeType(), node.getSizeBytes(),
                link.getResourceType(), link.getPasswordHash() != null
        );
    }

    /**
     * 使用短期会话接受文件分享。
     *
     * @param userId       接受用户 ID
     * @param rawToken     分享明文 token
     * @param sessionToken 短期会话 token
     * @param request      接受请求
     */
    @Transactional(rollbackFor = Exception.class)
    public void acceptShareSession(
            UUID userId,
            String rawToken,
            String sessionToken,
            AcceptShareRequest request
    ) {
        String tokenHash = FileShareService.sha256(rawToken);
        requireShareRateLimit(tokenHash);
        resourceShareLinkService.authorizeAnySession(rawToken, sessionToken);
        ShareLink link = findShareLinkCached(tokenHash);
        FileNode sourceNode = fileNodeRepository.findByIdAndOwnerUserIdAndDeletedFalse(
                        link.getResourceId(), link.getOwnerUserId())
                .orElseThrow(() -> new BusinessException(ErrorCode.FILE_NOT_FOUND, "源文件不存在或已被删除"));
        UUID targetParentId = request != null ? request.targetParentId() : null;
        if ("FOLDER".equals(link.getResourceType())) {
            acceptFolderShare(userId, sourceNode, targetParentId);
        } else {
            acceptFileShare(userId, sourceNode, targetParentId);
        }
    }

    private void requireShareRateLimit(String tokenHash) {
        if (!rateLimitService.tryAcquire("share:" + tokenHash, 10, Duration.ofMinutes(1))) {
            throw new BusinessException(ErrorCode.RATE_LIMITED, "访问过于频繁，请稍后再试");
        }
    }

    private void acceptFileShare(UUID userId, FileNode source, UUID targetParentId) {
        if (source.getCurrentObjectId() != null) {
            fileNodeRepository.findActiveByOwnerUserIdAndObjectId(userId, source.getCurrentObjectId())
                    .ifPresent(existing -> {
                        throw new BusinessException(ErrorCode.CONFLICT, "文件已存在，请先彻底删除后再保存");
                    });
        }
        FileNode targetParent = null;
        if (targetParentId != null) {
            targetParent = fileNodeRepository.findByIdAndOwnerUserIdAndDeletedFalse(targetParentId, userId)
                    .orElseThrow(() -> new BusinessException(ErrorCode.FILE_NOT_FOUND, "目标文件夹不存在"));
        }
        FileNode newNode = new FileNode();
        newNode.setOwnerUserId(userId);
        newNode.setParentId(targetParent != null ? targetParent.getId() : null);
        newNode.setNodeType(source.getNodeType());
        newNode.setName(source.getName());
        newNode.setNormalizedPath(fileNodeSupport.resolveChildPath(targetParent, source.getName()));
        newNode.setMimeType(source.getMimeType());
        newNode.setSizeBytes(source.getSizeBytes());
        newNode.setCurrentObjectId(source.getCurrentObjectId());
        newNode.setSourceType(SourceType.SHARE.getValue());
        newNode.setShared(false);
        newNode.setSpaceType(SpaceType.PERSONAL);
        fileNodeRepository.save(newNode);
    }

    private void acceptFolderShare(UUID userId, FileNode sourceFolder, UUID targetParentId) {
        FileNode targetParent = null;
        if (targetParentId != null) {
            targetParent = fileNodeRepository.findByIdAndOwnerUserIdAndDeletedFalse(targetParentId, userId)
                    .orElseThrow(() -> new BusinessException(ErrorCode.FILE_NOT_FOUND, "目标文件夹不存在"));
        }
        FileNode newFolder = new FileNode();
        newFolder.setOwnerUserId(userId);
        newFolder.setParentId(targetParent != null ? targetParent.getId() : null);
        newFolder.setNodeType(NodeType.FOLDER.getValue());
        newFolder.setName(sourceFolder.getName());
        newFolder.setNormalizedPath(fileNodeSupport.resolveChildPath(targetParent, sourceFolder.getName()));
        newFolder.setSizeBytes(0L);
        newFolder.setSourceType(SourceType.SHARE.getValue());
        newFolder.setShared(false);
        newFolder.setSpaceType(SpaceType.PERSONAL);
        FileNode savedFolder = fileNodeRepository.save(newFolder);

        List<FileNode> descendants = fileNodeRepository
                .findDescendantsByPrefixOrdered(
                        sourceFolder.getOwnerUserId(), sourceFolder.getNormalizedPath() + "/");

        Map<String, FileNode> pathToNewNode = new LinkedHashMap<>();
        pathToNewNode.put(sourceFolder.getNormalizedPath(), savedFolder);

        for (FileNode child : descendants) {
            String relativePath = child.getNormalizedPath().substring(sourceFolder.getNormalizedPath().length());
            String[] segments = relativePath.split("/");
            FileNode parentNode = savedFolder;
            StringBuilder currentPath = new StringBuilder(sourceFolder.getNormalizedPath());

            for (int i = 0; i < segments.length - 1; i++) {
                currentPath.append("/").append(segments[i]);
                parentNode = pathToNewNode.get(currentPath.toString());
                if (parentNode == null) {
                    break;
                }
            }

            FileNode newChild = new FileNode();
            newChild.setOwnerUserId(userId);
            newChild.setParentId(parentNode != null ? parentNode.getId() : null);
            newChild.setNodeType(child.getNodeType());
            newChild.setName(child.getName());
            newChild.setNormalizedPath(fileNodeSupport.resolveChildPath(parentNode, child.getName()));
            newChild.setMimeType(child.getMimeType());
            newChild.setSizeBytes(child.getSizeBytes());
            newChild.setCurrentObjectId(child.getCurrentObjectId());
            newChild.setSourceType(SourceType.SHARE.getValue());
            newChild.setShared(false);
            newChild.setSpaceType(SpaceType.PERSONAL);
            FileNode savedChild = fileNodeRepository.save(newChild);
            pathToNewNode.put(child.getNormalizedPath(), savedChild);
        }
    }

    /**
     * 缓存旁路模式查找分享链接（缓存 5 分钟）。
     */
    private ShareLink findShareLinkCached(String tokenHash) {
        String cacheKey = "omninest:share:link:" + tokenHash;
        return readThroughCache.getOrLoad(cacheKey, Duration.ofMinutes(5),
                () -> shareLinkRepository.findByTokenHash(tokenHash)
                        .orElseThrow(() -> new BusinessException(ErrorCode.FILE_NOT_FOUND, "分享链接不存在")),
                ShareLink.class);
    }

    private ShareLink consumeShareAccess(ShareLink cachedLink, String tokenHash) {
        Instant now = Instant.now();
        if (shareLinkRepository.consumeAccess(cachedLink.getId(), now) == 0) {
            ShareLink current = shareLinkRepository.findById(cachedLink.getId())
                    .orElseThrow(() -> new BusinessException(ErrorCode.FILE_NOT_FOUND, "分享链接不存在"));
            if (current.getDisabledAt() != null) {
                throw new BusinessException(ErrorCode.CONFLICT, "分享链接已撤销");
            }
            if (current.getExpiresAt() != null && !current.getExpiresAt().isAfter(now)) {
                throw new BusinessException(ErrorCode.CONFLICT, "分享链接已过期");
            }
            throw new BusinessException(ErrorCode.CONFLICT, "分享链接访问次数已达上限");
        }
        readThroughCache.invalidate("omninest:share:link:" + tokenHash);
        return shareLinkRepository.findById(cachedLink.getId())
                .orElseThrow(() -> new BusinessException(ErrorCode.FILE_NOT_FOUND, "分享链接不存在"));
    }
}
