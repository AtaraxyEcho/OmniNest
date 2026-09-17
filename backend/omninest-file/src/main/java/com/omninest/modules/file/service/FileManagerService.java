package com.omninest.modules.file.service;

import com.omninest.common.cache.ReadThroughCache;
import com.omninest.common.enums.ErrorCode;
import com.omninest.common.error.BusinessException;
import com.omninest.common.ratelimit.RateLimitService;
import com.omninest.common.storage.ObjectStorageClient;
import com.omninest.common.storage.ObjectStorageKey;
import com.omninest.common.sync.SyncAction;
import com.omninest.common.sync.SyncEventCommand;
import com.omninest.common.sync.SyncScope;
import com.omninest.common.sync.UserSyncEventRecorder;
import com.omninest.common.user.UserAccountQuery;
import com.omninest.modules.file.domain.ExternalStorageStatus;
import com.omninest.modules.file.domain.FileAccessRecord;
import com.omninest.modules.file.domain.FileFavorite;
import com.omninest.modules.file.domain.FileNode;
import com.omninest.modules.file.domain.FileNodePermission;
import com.omninest.modules.file.domain.FileObject;
import com.omninest.modules.file.domain.FilePermission;
import com.omninest.modules.file.domain.FileShareRecipient;
import com.omninest.modules.file.domain.FileUploadSession;
import com.omninest.modules.file.domain.NodeType;
import com.omninest.modules.file.domain.ShareLink;
import com.omninest.modules.file.domain.SourceType;
import com.omninest.modules.file.domain.SpaceType;
import com.omninest.modules.file.domain.StorageExternalAccount;
import com.omninest.modules.file.dto.AcceptShareRequest;
import com.omninest.modules.file.dto.CreateExternalStorageRequest;
import com.omninest.modules.file.dto.CreateShareLinkRequest;
import com.omninest.modules.file.dto.ExternalStorageAccountDto;
import com.omninest.modules.file.dto.FileDownloadUrlDto;
import com.omninest.modules.file.dto.FileNodeDto;
import com.omninest.modules.file.dto.FilePermissionDto;
import com.omninest.modules.file.dto.FileShareAccessDto;
import com.omninest.modules.file.dto.FileShareLinkDto;
import com.omninest.modules.file.dto.FileSharePreviewDto;
import com.omninest.modules.file.dto.FileSharedItemDto;
import com.omninest.modules.file.dto.FileUploadQueueItemDto;
import com.omninest.modules.file.dto.PermissionRequest;
import com.omninest.modules.file.dto.ShareAccessSessionDto;
import com.omninest.modules.file.dto.SharedFileDto;
import com.omninest.modules.file.dto.UpdateExternalStorageRequest;
import com.omninest.modules.file.repository.FileAccessRecordRepository;
import com.omninest.modules.file.repository.FileFavoriteRepository;
import com.omninest.modules.file.repository.FileNodeRepository;
import com.omninest.modules.file.repository.FileObjectRepository;
import com.omninest.modules.file.repository.FileVersionRepository;
import com.omninest.modules.file.dto.FileVersionDto;
import com.omninest.modules.file.domain.FileVersion;
import com.omninest.modules.file.repository.FileShareRecipientRepository;
import com.omninest.modules.file.repository.FileUploadSessionRepository;
import com.omninest.modules.file.repository.ShareLinkRepository;
import com.omninest.modules.file.repository.StorageExternalAccountRepository;
import com.omninest.modules.notification.port.NotificationPublisher;
import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.security.SecureRandom;
import java.time.Duration;
import java.time.Instant;
import java.util.ArrayList;
import java.util.Collection;
import java.util.HexFormat;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Objects;
import java.util.UUID;
import java.util.stream.Collectors;
import java.util.zip.ZipEntry;
import java.util.zip.ZipOutputStream;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.PageImpl;
import org.springframework.data.domain.Pageable;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * 文件扩展操作、收藏、分享与外部存储管理服务。
 *
 * @author OmniNest
 */
@Slf4j
@Service
@RequiredArgsConstructor
public class FileManagerService {
    private final FileNodeRepository fileNodeRepository;
    private final FileAccessRecordRepository accessRecordRepository;
    private final FileFavoriteRepository favoriteRepository;
    private final ShareLinkRepository shareLinkRepository;
    private final FileShareRecipientRepository shareRecipientRepository;
    private final FileUploadSessionRepository uploadSessionRepository;
    private final StorageExternalAccountRepository externalAccountRepository;
    private final UserAccountQuery userAccountQuery;
    private final FileObjectRepository fileObjectRepository;
    private final FileVersionRepository fileVersionRepository;
    private final FileContentChangePublisher fileContentChangePublisher;
    private final ObjectStorageClient objectStorageClient;
    private final PasswordEncoder passwordEncoder;
    private final FileQueryService fileQueryService;
    private final FilePermissionService filePermissionService;
    private final RateLimitService rateLimitService;
    private final NotificationPublisher notificationService;
    private final ExternalStorageService externalStorageService;
    private final ExternalStorageCredentialService externalStorageCredentialService;
    private final ReadThroughCache readThroughCache;
    private final UserSyncEventRecorder syncEventRecorder;
    private final ResourceShareLinkService resourceShareLinkService;

    @Transactional(readOnly = true)
    public List<FileNodeDto> listRecentFiles(UUID ownerUserId) {
        return accessRecordRepository.findTop50ByOwnerUserIdOrderByLastAccessedAtDesc(ownerUserId)
                .stream()
                .map(FileAccessRecord::getFileNode)
                .filter(node -> node != null && !node.isDeleted() && node.getSpaceType() != SpaceType.SHARED)
                .map(this::toNodeDto)
                .toList();
    }

    @Transactional(rollbackFor = Exception.class)
    public void recordAccess(UUID ownerUserId, UUID fileId) {
        FileNode node = findVisibleNode(ownerUserId, fileId);
        FileAccessRecord record = accessRecordRepository.findByOwnerUserIdAndFileNode_Id(ownerUserId, fileId)
                .orElseGet(() -> {
                    FileAccessRecord created = new FileAccessRecord();
                    created.setOwnerUserId(ownerUserId);
                    created.setFileNode(node);
                    return created;
                });
        record.setLastAccessedAt(Instant.now());
        record.setAccessCount(record.getAccessCount() + 1);
        accessRecordRepository.save(record);
    }

    @Transactional(readOnly = true)
    public Page<FileNodeDto> listFavoriteFilesPage(UUID ownerUserId, int page, int size) {
        Pageable pageable = FilePageRequests.of(page, size);
        Page<UUID> favoriteNodeIds = favoriteRepository.findFavoriteNodeIds(ownerUserId, pageable);
        if (favoriteNodeIds.isEmpty()) {
            return new PageImpl<>(List.of(), pageable, favoriteNodeIds.getTotalElements());
        }
        Map<UUID, FileNode> nodesById = fileNodeRepository.findAllById(favoriteNodeIds.getContent())
                .stream()
                .filter(node -> !node.isDeleted())
                .collect(Collectors.toMap(FileNode::getId, node -> node, (left, right) -> left, LinkedHashMap::new));
        List<FileNodeDto> items = favoriteNodeIds.getContent()
                .stream()
                .map(nodesById::get)
                .filter(Objects::nonNull)
                .map(this::toNodeDto)
                .toList();
        return new PageImpl<>(items, pageable, favoriteNodeIds.getTotalElements());
    }

    @Transactional(readOnly = true)
    public Page<FileSharedItemDto> listSharedWithMePage(UUID ownerUserId, int page, int size) {
        Pageable pageable = FilePageRequests.of(page, size);
        Page<FileShareRecipient> recipientPage =
                shareRecipientRepository.findByRecipientUserIdOrderByCreatedAtDesc(ownerUserId, pageable);
        if (recipientPage.isEmpty()) {
            return new PageImpl<>(List.of(), pageable, recipientPage.getTotalElements());
        }
        List<FileShareRecipient> recipients = recipientPage.getContent();
        List<UUID> resourceIds = recipients.stream()
                .map(FileShareRecipient::getShareLink)
                .filter(Objects::nonNull)
                .filter(share -> share.getDisabledAt() == null)
                .filter(share -> NodeType.FILE.getValue().equals(share.getResourceType()))
                .map(ShareLink::getResourceId)
                .distinct()
                .toList();
        Map<UUID, FileNode> nodesById = resourceIds.isEmpty()
                ? Map.of()
                : fileNodeRepository.findAllById(resourceIds)
                        .stream()
                        .filter(node -> !node.isDeleted())
                        .collect(Collectors.toMap(FileNode::getId, node -> node, (l, r) -> l, LinkedHashMap::new));
        List<FileSharedItemDto> items = recipients.stream()
                .map(recipient -> toSharedItemDto(recipient, nodesById))
                .flatMap(List::stream)
                .toList();
        return new PageImpl<>(items, pageable, recipientPage.getTotalElements());
    }

    @Transactional(readOnly = true)
    public Page<FileShareLinkDto> listMySharesPage(UUID ownerUserId, int page, int size) {
        Pageable pageable = FilePageRequests.of(page, size);
        Page<ShareLink> sharePage = shareLinkRepository.findActiveByOwnerPage(ownerUserId, pageable);
        if (sharePage.isEmpty()) {
            return new PageImpl<>(List.of(), pageable, sharePage.getTotalElements());
        }
        List<UUID> resourceIds = sharePage.getContent()
                .stream()
                .map(ShareLink::getResourceId)
                .distinct()
                .toList();
        Map<UUID, String> namesById = resourceIds.isEmpty()
                ? Map.of()
                : fileNodeRepository.findAllById(resourceIds)
                        .stream()
                        .collect(Collectors.toMap(FileNode::getId, FileNode::getName, (l, r) -> l, LinkedHashMap::new));
        List<FileShareLinkDto> items = sharePage.getContent()
                .stream()
                .map(share -> toShareDto(share, null, null, namesById))
                .toList();
        return new PageImpl<>(items, pageable, sharePage.getTotalElements());
    }

    @Transactional(readOnly = true)
    public Page<SharedFileDto> listSharedFilesPage(UUID userId, int page, int size) {
        Pageable pageable = FilePageRequests.of(page, size);
        Page<FileNode> sharedPage = fileNodeRepository.findSharedFilesVisiblePage(userId, pageable);
        if (sharedPage.isEmpty()) {
            return new PageImpl<>(List.of(), pageable, sharedPage.getTotalElements());
        }
        List<FileNode> sharedNodes = sharedPage.getContent();
        List<UUID> fileIds = sharedNodes.stream().map(FileNode::getId).toList();
        Map<UUID, FilePermission> perms = filePermissionService.resolvePermissions(fileIds, userId);
        List<UUID> ownerIds = sharedNodes.stream().map(FileNode::getOwnerUserId).distinct().toList();
        Map<UUID, String> ownerNames = userAccountQuery.findUsernames(ownerIds);
        List<SharedFileDto> items = sharedNodes.stream()
                .filter(n -> perms.getOrDefault(n.getId(), FilePermission.denyAll()).allowView())
                .map(n -> toSharedFileDto(
                        n,
                        perms.get(n.getId()),
                        ownerNames.getOrDefault(n.getOwnerUserId(), "未知用户")
                ))
                .toList();
        return new PageImpl<>(items, pageable, sharedPage.getTotalElements());
    }

    @Transactional(rollbackFor = Exception.class)
    public FileNodeDto addFavorite(UUID ownerUserId, UUID fileId) {
        FileNode node = findVisibleNode(ownerUserId, fileId);
        boolean created = !favoriteRepository.existsByOwnerUserIdAndFileNode_Id(ownerUserId, fileId);
        if (created) {
            FileFavorite favorite = new FileFavorite();
            favorite.setOwnerUserId(ownerUserId);
            favorite.setFileNode(node);
            favoriteRepository.save(favorite);
            recordFileEvent(ownerUserId, fileId, Map.of("favorite", true));
        }
        return toNodeDto(node);
    }

    @Transactional(rollbackFor = Exception.class)
    public void removeFavorite(UUID ownerUserId, UUID fileId) {
        favoriteRepository.findByOwnerUserIdAndFileNode_Id(ownerUserId, fileId)
                .ifPresent(favorite -> {
                    favoriteRepository.delete(favorite);
                    recordFileEvent(ownerUserId, fileId, Map.of("favorite", false));
                });
    }

    /**
     * 批量添加收藏（幂等，已收藏的跳过）
     */
    @Transactional(rollbackFor = Exception.class)
    public List<FileNodeDto> batchAddFavorites(UUID ownerUserId, List<UUID> fileIds) {
        List<FileNode> nodes = fileNodeRepository.findByOwnerUserIdAndIdInAndDeletedFalse(ownerUserId, fileIds);
        int createdCount = 0;
        for (FileNode node : nodes) {
            if (!favoriteRepository.existsByOwnerUserIdAndFileNode_Id(ownerUserId, node.getId())) {
                FileFavorite favorite = new FileFavorite();
                favorite.setOwnerUserId(ownerUserId);
                favorite.setFileNode(node);
                favoriteRepository.save(favorite);
                createdCount++;
            }
        }
        if (createdCount > 0) {
            recordFileLibraryInvalidation(ownerUserId, createdCount);
        }
        return nodes.stream().map(this::toNodeDto).toList();
    }

    /**
     * 批量取消收藏
     */
    @Transactional(rollbackFor = Exception.class)
    public void batchRemoveFavorites(UUID ownerUserId, List<UUID> fileIds) {
        favoriteRepository.deleteByOwnerUserIdAndFileNode_IdIn(ownerUserId, fileIds);
        if (!fileIds.isEmpty()) {
            recordFileLibraryInvalidation(ownerUserId, fileIds.size());
        }
    }

    @Transactional(readOnly = true)
    public List<FileSharedItemDto> listSharedWithMe(UUID ownerUserId) {
        return listSharedWithMePage(ownerUserId, 0, FilePageRequests.MAX_SIZE).getContent();
    }

    @Transactional(readOnly = true)
    public List<FileShareLinkDto> listMyShares(UUID ownerUserId) {
        return listMySharesPage(ownerUserId, 0, FilePageRequests.MAX_SIZE).getContent();
    }

    @Transactional(rollbackFor = Exception.class)
    public FileShareLinkDto createShare(UUID ownerUserId, CreateShareLinkRequest request) {
        String resourceType = normalizeResourceType(request.resourceType());

        FileNode node = findActiveNode(ownerUserId, request.resourceId());
        requireShareable(node);
        String rawToken = UUID.randomUUID().toString().replace("-", "");
        ShareLink share = new ShareLink();
        share.setOwnerUserId(ownerUserId);
        share.setResourceType(resourceType);
        share.setResourceId(node.getId());
        share.setTokenHash(sha256(rawToken));
        share.setExpiresAt(request.expiresAt());
        share.setMaxAccessCount(request.maxAccessCount());

        String generatedPassword = null;
        if (request.password() != null && !request.password().isBlank()) {
            share.setPasswordHash(passwordEncoder.encode(request.password()));
        } else if (request.generatePassword()) {
            generatedPassword = generateRandomPassword(6);
            share.setPasswordHash(passwordEncoder.encode(generatedPassword));
        }

        ShareLink saved = shareLinkRepository.save(share);
        log.info("创建分享链接: shareId={}, ownerUserId={}, resourceType={}, resourceId={}",
                saved.getId(), ownerUserId, resourceType, node.getId());
        List<UUID> recipients = request.recipientUserIds() == null ? List.of() : request.recipientUserIds();
        if (!recipients.isEmpty()) {
            List<FileShareRecipient> recipientEntities = recipients.stream()
                    .map(recipientUserId -> {
                        FileShareRecipient recipient = new FileShareRecipient();
                        recipient.setShareLink(saved);
                        recipient.setRecipientUserId(recipientUserId);
                        return recipient;
                    })
                    .toList();
            shareRecipientRepository.saveAll(recipientEntities);
        }
        recordShareEvent(ownerUserId, saved.getId());
        recipients.forEach(recipientUserId -> recordShareEvent(recipientUserId, saved.getId()));
        return toShareDto(saved, rawToken, generatedPassword);
    }

    @Transactional(rollbackFor = Exception.class)
    public void revokeShare(UUID ownerUserId, UUID shareId) {
        ShareLink share = shareLinkRepository.findByIdAndOwnerUserId(shareId, ownerUserId)
                .orElseThrow(() -> new BusinessException(ErrorCode.NOT_FOUND, "分享链接不存在"));
        List<UUID> recipientUserIds = shareRecipientRepository.findByShareLink_Id(shareId)
                .stream()
                .map(FileShareRecipient::getRecipientUserId)
                .toList();
        share.setDisabledAt(Instant.now());
        shareLinkRepository.save(share);
        recordShareEvent(ownerUserId, shareId);
        recipientUserIds.forEach(recipientUserId -> recordShareEvent(recipientUserId, shareId));
        log.info("撤销分享链接: shareId={}, ownerUserId={}", shareId, ownerUserId);
        // 清除分享链接缓存
        readThroughCache.invalidate("omninest:share:link:" + share.getTokenHash());
    }

    @Transactional(rollbackFor = Exception.class)
    public FileShareAccessDto shareAccess(String rawToken, String password) {
        String tokenHash = sha256(rawToken);
        if (!rateLimitService.tryAcquire("share:" + tokenHash, 10, Duration.ofMinutes(1))) {
            throw new BusinessException(ErrorCode.RATE_LIMITED, "访问过于频繁，请稍后再试");
        }
        ShareLink link = findShareLinkCached(tokenHash);
        if (link.getDisabledAt() != null) {
            throw new BusinessException(ErrorCode.CONFLICT, "分享链接已撤销");
        }
        if (link.getExpiresAt() != null && Instant.now().isAfter(link.getExpiresAt())) {
            throw new BusinessException(ErrorCode.CONFLICT, "分享链接已过期");
        }
        if (link.getPasswordHash() != null) {
            if (password == null || !passwordEncoder.matches(password, link.getPasswordHash())) {
                throw new BusinessException(ErrorCode.UNAUTHORIZED, "密码错误");
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
     */
    @Transactional(readOnly = true)
    public FileSharePreviewDto previewShare(String rawToken, String password) {
        String tokenHash = sha256(rawToken);
        if (!rateLimitService.tryAcquire("share:" + tokenHash, 10, Duration.ofMinutes(1))) {
            throw new BusinessException(ErrorCode.RATE_LIMITED, "访问过于频繁，请稍后再试");
        }
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
                throw new BusinessException(ErrorCode.UNAUTHORIZED, "密码错误");
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
     */
    @Transactional(rollbackFor = Exception.class)
    public void acceptShare(UUID userId, String rawToken, AcceptShareRequest request) {
        String tokenHash = sha256(rawToken);
        if (!rateLimitService.tryAcquire("share:" + tokenHash, 10, Duration.ofMinutes(1))) {
            throw new BusinessException(ErrorCode.RATE_LIMITED, "访问过于频繁，请稍后再试");
        }
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
                throw new BusinessException(ErrorCode.UNAUTHORIZED, "密码错误");
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
        newNode.setNormalizedPath(resolveChildPath(targetParent, source.getName()));
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
        newFolder.setNormalizedPath(resolveChildPath(targetParent, sourceFolder.getName()));
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
            newChild.setNormalizedPath(resolveChildPath(parentNode, child.getName()));
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

    private String resolveChildPath(FileNode parent, String childName) {
        if (parent == null) {
            return "/" + childName;
        }
        return parent.getNormalizedPath() + "/" + childName;
    }

    /**
     * 复制文件或文件夹到目标位置。
     * 文件夹复制为浅复制（仅复制节点结构，不递归复制子文件）。
     *
     * @param userId         用户 ID
     * @param sourceId       源文件/文件夹 ID
     * @param targetParentId 目标父文件夹 ID，null 表示复制到根目录
     * @return 新创建的文件节点
     */
    @Transactional(rollbackFor = Exception.class)
    public FileNodeDto copyNode(UUID userId, UUID sourceId, UUID targetParentId) {
        FileNode source = findActiveNode(userId, sourceId);
        requireShareable(source);
        FileNode targetParent = resolveCopyTargetParent(userId, targetParentId);
        UUID resolvedParentId = targetParent != null ? targetParent.getId() : null;

        // 校验源文件和目标在同一空间
        if (targetParent != null && source.getSpaceType() != targetParent.getSpaceType()) {
            throw new BusinessException(ErrorCode.FORBIDDEN, "不能在不同空间之间复制文件");
        }
        if (sameNameExists(userId, resolvedParentId, source.getName())) {
            throw new BusinessException(ErrorCode.CONFLICT, "目标目录下已存在同名文件");
        }

        FileNode copy = new FileNode();
        copy.setOwnerUserId(userId);
        copy.setParentId(resolvedParentId);
        copy.setNodeType(source.getNodeType());
        copy.setName(source.getName());
        copy.setNormalizedPath(resolveChildPath(targetParent, source.getName()));
        copy.setMimeType(source.getMimeType());
        copy.setSizeBytes(source.getSizeBytes());
        copy.setCurrentObjectId(source.getCurrentObjectId());
        copy.setSpaceType(source.getSpaceType());
        if (source.getSpaceType() == SpaceType.SHARED) {
            copy.setUploadedBy(userId);
        }

        FileNode saved = fileNodeRepository.save(copy);
        log.info("文件复制完成: sourceId={}, copyId={}, ownerUserId={}", sourceId, saved.getId(), userId);
        return toNodeDto(saved);
    }



    /**
     * 将文件当前对象保存为历史版本，并把已上传的新对象设为当前对象。
     *
     * @param ownerUserId 文件所有者
     * @param fileNodeId 文件节点 ID
     * @param newObjectId 新对象 ID（已持久化）
     * @param newObjectSizeBytes 新对象大小（字节）
     * @param remark 版本备注，可空
     * @return 文件节点最新状态
     */
    @Transactional(rollbackFor = Exception.class)
    public FileNodeDto saveNewVersion(
            UUID ownerUserId,
            UUID fileNodeId,
            UUID newObjectId,
            long newObjectSizeBytes,
            String remark
    ) {
        FileNode node = fileNodeRepository
                .findOwnedForUpdate(fileNodeId, ownerUserId)
                .filter(existing -> !existing.isDeleted())
                .orElseThrow(() -> new BusinessException(ErrorCode.FILE_NOT_FOUND, "文件不存在"));
        if (node.getCurrentObjectId() == null) {
            throw new BusinessException(ErrorCode.VALIDATION_FAILED, "该文件没有可版本化的当前内容");
        }
        FileObject newObject = fileObjectRepository.findById(newObjectId)
                .orElseThrow(() -> new BusinessException(ErrorCode.NOT_FOUND, "文件对象不存在"));
        if (!isObjectOwnedByUser(newObject, ownerUserId)) {
            throw new BusinessException(ErrorCode.FORBIDDEN, "文件对象不属于当前用户");
        }
        rejectObjectAliasedToOtherNode(ownerUserId, fileNodeId, newObject.getId());
        // 入口晋升的 asVersion 对象已落到 users/{uid}/...，会话结果可能尚未回写；
        // 仅对仍处于 uploads/ 暂存前缀的对象强制「必须来自本次上传会话」。
        String newObjectKey = newObject.getObjectKey() == null ? "" : newObject.getObjectKey();
        if (newObjectKey.startsWith("uploads/")
                && uploadSessionRepository
                        .findFirstByOwnerUserIdAndResultObjectId(ownerUserId, newObjectId)
                        .isEmpty()) {
            throw new BusinessException(ErrorCode.FORBIDDEN, "文件对象必须来自本次上传会话");
        }
        if (newObjectSizeBytes > 0 && newObjectSizeBytes != newObject.getSizeBytes()) {
            throw new BusinessException(ErrorCode.VALIDATION_FAILED, "文件对象大小与声明不一致");
        }
        int nextVersionNo = fileVersionRepository.findMaxVersionNo(fileNodeId) + 1;
        FileVersion version = new FileVersion();
        version.setFileNodeId(fileNodeId);
        version.setObjectId(node.getCurrentObjectId());
        version.setVersionNo(nextVersionNo);
        version.setChangeType("EDIT");
        version.setCreatedBy(ownerUserId);
        version.setRemark(remark);
        fileVersionRepository.save(version);

        node.setCurrentObjectId(newObject.getId());
        node.setSizeBytes(newObject.getSizeBytes());
        if (newObject.getMimeType() != null && !newObject.getMimeType().isBlank()) {
            node.setMimeType(newObject.getMimeType());
        }
        node.setUpdatedAt(Instant.now());
        FileNode saved = fileNodeRepository.save(node);
        fileContentChangePublisher.publish(saved, newObject, ownerUserId);
        recordFileEvent(ownerUserId, fileNodeId, Map.of("version", nextVersionNo));
        return toNodeDto(saved);
    }

    private void rejectObjectAliasedToOtherNode(UUID ownerUserId, UUID fileNodeId, UUID objectId) {
        fileNodeRepository.findActiveByOwnerUserIdAndObjectId(ownerUserId, objectId)
                .filter(existing -> !existing.getId().equals(fileNodeId))
                .ifPresent(existing -> {
                    throw new BusinessException(ErrorCode.FORBIDDEN, "文件对象已被其他文件使用");
                });
    }

    /**
     * 查询文件版本历史（新版本在前），当前对象补充为一条 CURRENT 条目。
     *
     * @param ownerUserId 文件所有者
     * @param fileNodeId 文件节点 ID
     * @return 版本条目列表
     */
    @Transactional(readOnly = true)
    public List<FileVersionDto> listVersions(UUID ownerUserId, UUID fileNodeId) {
        FileNode node = findActiveNode(ownerUserId, fileNodeId);
        List<FileVersion> versions = fileVersionRepository.findByFileNodeIdOrderByVersionNoDesc(fileNodeId);
        List<FileVersionDto> items = new ArrayList<>();
        for (FileVersion version : versions) {
            FileObject object = fileObjectRepository.findById(version.getObjectId()).orElse(null);
            items.add(new FileVersionDto(
                    version.getId(),
                    version.getVersionNo(),
                    version.getObjectId(),
                    version.getChangeType(),
                    object == null ? 0L : object.getSizeBytes(),
                    version.getCreatedBy(),
                    version.getCreatedAt(),
                    version.getObjectId().equals(node.getCurrentObjectId()),
                    version.getRemark()
            ));
        }
        if (node.getCurrentObjectId() != null
                && versions.stream().noneMatch(v -> v.getObjectId().equals(node.getCurrentObjectId()))) {
            FileObject current = fileObjectRepository.findById(node.getCurrentObjectId()).orElse(null);
            if (current != null) {
                items.add(0, new FileVersionDto(
                        null,
                        versions.isEmpty() ? 1 : versions.get(0).getVersionNo() + 1,
                        current.getId(),
                        "CURRENT",
                        current.getSizeBytes(),
                        node.getOwnerUserId(),
                        current.getCreatedAt(),
                        true,
                        null
                ));
            }
        }
        return List.copyOf(items);
    }

    /**
     * 恢复历史版本：把恢复前的当前对象存为 RESTORE 版本行，再把历史版本对象设为当前对象。
     *
     * @param ownerUserId 文件所有者
     * @param fileNodeId 文件节点 ID
     * @param versionId 版本行 ID
     * @return 文件节点最新状态
     */
    @Transactional(rollbackFor = Exception.class)
    public FileNodeDto restoreVersion(UUID ownerUserId, UUID fileNodeId, UUID versionId) {
        FileNode node = fileNodeRepository
                .findOwnedForUpdate(fileNodeId, ownerUserId)
                .filter(existing -> !existing.isDeleted())
                .orElseThrow(() -> new BusinessException(ErrorCode.FILE_NOT_FOUND, "文件不存在"));
        FileVersion version = fileVersionRepository.findById(versionId)
                .orElseThrow(() -> new BusinessException(ErrorCode.NOT_FOUND, "版本不存在"));
        if (!version.getFileNodeId().equals(fileNodeId)) {
            throw new BusinessException(ErrorCode.VALIDATION_FAILED, "版本与文件不匹配");
        }
        if (version.getObjectId().equals(node.getCurrentObjectId())) {
            return toNodeDto(node);
        }
        if (node.getCurrentObjectId() == null) {
            throw new BusinessException(ErrorCode.VALIDATION_FAILED, "当前文件没有可备份的内容，无法恢复历史版本");
        }
        int nextVersionNo = fileVersionRepository.findMaxVersionNo(fileNodeId) + 1;
        FileVersion history = new FileVersion();
        history.setFileNodeId(fileNodeId);
        history.setObjectId(node.getCurrentObjectId());
        history.setVersionNo(nextVersionNo);
        history.setChangeType("RESTORE");
        history.setCreatedBy(ownerUserId);
        fileVersionRepository.save(history);

        FileObject restoredObject = fileObjectRepository.findById(version.getObjectId())
                .orElseThrow(() -> new BusinessException(ErrorCode.NOT_FOUND, "版本对象不存在"));
        node.setCurrentObjectId(restoredObject.getId());
        node.setSizeBytes(restoredObject.getSizeBytes());
        if (restoredObject.getMimeType() != null && !restoredObject.getMimeType().isBlank()) {
            node.setMimeType(restoredObject.getMimeType());
        }
        node.setUpdatedAt(Instant.now());
        FileNode saved = fileNodeRepository.save(node);
        fileContentChangePublisher.publish(saved, restoredObject, ownerUserId);
        recordFileEvent(ownerUserId, fileNodeId, Map.of("restoredTo", version.getVersionNo()));
        return toNodeDto(saved);
    }

    private boolean sameNameExists(UUID ownerUserId, UUID parentId, String name) {
        if (parentId == null) {
            return fileNodeRepository.existsByOwnerUserIdAndParentIdIsNullAndNameAndDeletedFalse(ownerUserId, name);
        }
        return fileNodeRepository.existsByOwnerUserIdAndParentIdAndNameAndDeletedFalse(ownerUserId, parentId, name);
    }

    private boolean isObjectOwnedByUser(FileObject object, UUID ownerUserId) {
        String objectKey = object.getObjectKey();
        if (objectKey == null || objectKey.isBlank()) {
            return false;
        }
        // 直传暂存键与晋升后的用户受管键均表示归属该用户。
        return objectKey.startsWith("uploads/" + ownerUserId + "/")
                || objectKey.startsWith("users/" + ownerUserId + "/");
    }

    /**
     * 验证并获取复制目标父文件夹。
     * 与 resolveParent 不同，允许 targetParentId 为 null（复制到根目录）。
     */
    private FileNode resolveCopyTargetParent(UUID ownerUserId, UUID targetParentId) {
        if (targetParentId == null) {
            return null;
        }
        FileNode parent = fileNodeRepository.findByIdAndOwnerUserIdAndDeletedFalse(targetParentId, ownerUserId)
                .orElseThrow(() -> new BusinessException(ErrorCode.FILE_NOT_FOUND, "目标文件夹不存在"));
        if (!NodeType.FOLDER.getValue().equals(parent.getNodeType())) {
            throw new BusinessException(ErrorCode.FILE_PATH_INVALID, "目标父级必须是文件夹");
        }
        return parent;
    }

    private static final String RANDOM_PASSWORD_CHARS =
            "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789";

    private String generateRandomPassword(int length) {
        SecureRandom random = new SecureRandom();
        StringBuilder sb = new StringBuilder(length);
        for (int i = 0; i < length; i++) {
            sb.append(RANDOM_PASSWORD_CHARS.charAt(random.nextInt(RANDOM_PASSWORD_CHARS.length())));
        }
        return sb.toString();
    }

    /** 校验文件分享密码并签发短期会话。 */
    @Transactional(readOnly = true)
    public ShareAccessSessionDto issueShareSession(String rawToken, String password, String clientAddress) {
        return resourceShareLinkService.issueAnySession(rawToken, password, clientAddress);
    }

    /** 使用短期会话访问分享文件并消费一次访问次数。 */
    @Transactional(rollbackFor = Exception.class)
    public FileShareAccessDto shareAccessSession(String rawToken, String sessionToken) {
        String tokenHash = sha256(rawToken);
        if (!rateLimitService.tryAcquire("share:" + tokenHash, 10, Duration.ofMinutes(1))) {
            throw new BusinessException(ErrorCode.RATE_LIMITED, "访问过于频繁，请稍后再试");
        }
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

    /** 使用短期会话预览文件分享，不接受 URL 密码。 */
    @Transactional(readOnly = true)
    public FileSharePreviewDto previewShareSession(String rawToken, String sessionToken) {
        String tokenHash = sha256(rawToken);
        if (!rateLimitService.tryAcquire("share:" + tokenHash, 10, Duration.ofMinutes(1))) {
            throw new BusinessException(ErrorCode.RATE_LIMITED, "访问过于频繁，请稍后再试");
        }
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

    /** 使用短期会话接受文件分享。 */
    @Transactional(rollbackFor = Exception.class)
    public void acceptShareSession(
            UUID userId,
            String rawToken,
            String sessionToken,
            AcceptShareRequest request
    ) {
        String tokenHash = sha256(rawToken);
        if (!rateLimitService.tryAcquire("share:" + tokenHash, 10, Duration.ofMinutes(1))) {
            throw new BusinessException(ErrorCode.RATE_LIMITED, "访问过于频繁，请稍后再试");
        }
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

    @Transactional(readOnly = true)
    public List<FileUploadQueueItemDto> listUploadQueue(UUID ownerUserId) {
        return uploadSessionRepository.findByOwnerUserIdOrderByUpdatedAtDesc(ownerUserId)
                .stream()
                .map(this::toUploadQueueItemDto)
                .toList();
    }

    @Transactional(readOnly = true)
    public List<ExternalStorageAccountDto> listExternalAccounts(UUID ownerUserId) {
        return externalAccountRepository.findByOwnerUserIdOrderByCreatedAtDesc(ownerUserId)
                .stream()
                .map(this::toExternalAccountDto)
                .toList();
    }

    @Transactional(rollbackFor = Exception.class)
    public ExternalStorageAccountDto createExternalAccount(UUID ownerUserId, CreateExternalStorageRequest request) {
        StorageExternalAccount account = new StorageExternalAccount();
        account.setOwnerUserId(ownerUserId);
        account.setProvider(ExternalStorageProviders.requireAllowed(request.provider()));
        account.setDisplayName(request.displayName().trim());
        account.setEncryptedCredentials(externalStorageCredentialService.encrypt(request.encryptedCredentials()));
        return toExternalAccountDto(externalAccountRepository.save(account));
    }

    /**
     * 更新外部存储：修改显示名称和凭据，凭据变更时重建 rclone remote。
     *
     * @param ownerUserId 所有者用户 ID
     * @param accountId 外部存储账户 ID
     * @param request 更新请求
     * @return 更新后的外部存储安全展示信息
     */
    @Transactional(rollbackFor = Exception.class)
    public ExternalStorageAccountDto updateExternalAccount(UUID ownerUserId, UUID accountId,
                                                           UpdateExternalStorageRequest request) {
        StorageExternalAccount account = externalAccountRepository.findByIdAndOwnerUserId(accountId, ownerUserId)
                .orElseThrow(() -> new BusinessException(ErrorCode.NOT_FOUND, "外部存储不存在"));

        String existingJson = externalStorageCredentialService.decryptToJson(account.getEncryptedCredentials());
        String mergedJson = ExternalStorageCredentialCodec.mergeForUpdate(
                existingJson,
                request.encryptedCredentials()
        );
        boolean credentialsChanged = !mergedJson.equals(existingJson);
        account.setDisplayName(request.displayName().trim());
        if (credentialsChanged) {
            account.setEncryptedCredentials(externalStorageCredentialService.encrypt(mergedJson));
        } else if (externalStorageCredentialService.isLegacyPlaintext(account.getEncryptedCredentials())) {
            account.setEncryptedCredentials(externalStorageCredentialService.encrypt(mergedJson));
        }

        if (credentialsChanged) {
            externalStorageService.deactivateRemote(account);
            if (ExternalStorageStatus.ACTIVE.getValue().equals(account.getStatus())) {
                externalStorageService.activateRemote(account);
            }
        }

        return toExternalAccountDto(externalAccountRepository.save(account));
    }

    @Transactional(rollbackFor = Exception.class)
    public void disableExternalAccount(UUID ownerUserId, UUID accountId) {
        StorageExternalAccount account = externalAccountRepository.findByIdAndOwnerUserId(accountId, ownerUserId)
                .orElseThrow(() -> new BusinessException(ErrorCode.NOT_FOUND, "外部存储不存在"));
        externalStorageService.deactivateRemote(account);
        account.setStatus(ExternalStorageStatus.DISABLED.getValue());
        externalAccountRepository.save(account);
    }

    /**
     * 删除外部存储挂载：清理 rclone remote → 删除数据库记录。
     */
    @Transactional(rollbackFor = Exception.class)
    public void deleteExternalAccount(UUID ownerUserId, UUID accountId) {
        StorageExternalAccount account = externalAccountRepository.findByIdAndOwnerUserId(accountId, ownerUserId)
                .orElseThrow(() -> new BusinessException(ErrorCode.NOT_FOUND, "外部存储不存在"));
        externalStorageService.deactivateRemote(account);
        externalAccountRepository.delete(account);
    }

    private FileNode findActiveNode(UUID ownerUserId, UUID fileId) {
        return fileNodeRepository.findByIdAndOwnerUserIdAndDeletedFalse(fileId, ownerUserId)
                .orElseThrow(() -> new BusinessException(ErrorCode.FILE_NOT_FOUND, "文件不存在"));
    }

    /**
     * 查找用户可见的文件（个人空间或共享空间）。
     * 用于收藏、最近访问等需要访问共享空间文件的场景。
     */
    private FileNode findVisibleNode(UUID userId, UUID fileId) {
        // 先查个人空间
        return fileNodeRepository.findByIdAndOwnerUserIdAndDeletedFalse(fileId, userId)
                .orElseGet(() -> // 再查共享空间
                        fileNodeRepository.findByIdAndSpaceTypeAndDeletedFalse(fileId, SpaceType.SHARED)
                                .orElseThrow(() -> new BusinessException(ErrorCode.FILE_NOT_FOUND, "文件不存在")));
    }

    private List<FileSharedItemDto> toSharedItemDto(FileShareRecipient recipient) {
        return toSharedItemDto(recipient, Map.of());
    }

    private List<FileSharedItemDto> toSharedItemDto(
            FileShareRecipient recipient,
            Map<UUID, FileNode> nodesById) {
        ShareLink share = recipient.getShareLink();
        if (share == null
                || share.getDisabledAt() != null
                || !NodeType.FILE.getValue().equals(share.getResourceType())) {
            return List.of();
        }
        FileNode file = nodesById.get(share.getResourceId());
        if (file == null || file.isDeleted() || !share.getOwnerUserId().equals(file.getOwnerUserId())) {
            return List.of();
        }
        return List.of(new FileSharedItemDto(
                share.getId(),
                toNodeDto(file),
                share.getOwnerUserId(),
                recipient.getCreatedAt(),
                share.getExpiresAt()
        ));
    }

    private FileShareLinkDto toShareDto(ShareLink share, String rawToken, String generatedPassword) {
        String resourceName = fileNodeRepository.findByIdAndOwnerUserId(share.getResourceId(), share.getOwnerUserId())
                .map(FileNode::getName)
                .orElse("已删除文件");
        return toShareDto(share, rawToken, generatedPassword, Map.of(share.getResourceId(), resourceName));
    }

    private FileShareLinkDto toShareDto(
            ShareLink share,
            String rawToken,
            String generatedPassword,
            Map<UUID, String> namesById) {
        String resourceName = namesById.getOrDefault(share.getResourceId(), "已删除文件");
        return new FileShareLinkDto(
                share.getId(),
                share.getResourceType(),
                share.getResourceId(),
                resourceName,
                rawToken == null ? share.getTokenHash().substring(0, 12) : rawToken,
                resolveShareStatus(share),
                share.getMaxAccessCount(),
                share.getAccessCount(),
                share.getExpiresAt(),
                share.getDisabledAt(),
                share.getCreatedAt(),
                generatedPassword
        );
    }

    private FileUploadQueueItemDto toUploadQueueItemDto(FileUploadSession session) {
        return new FileUploadQueueItemDto(
                session.getId(),
                session.getUploadId(),
                session.getTargetParentId(),
                session.getFileName(),
                session.getTotalSizeBytes(),
                session.getPartSizeBytes(),
                session.getTotalParts(),
                session.getUploadedParts(),
                session.getStatus(),
                session.getExpiresAt(),
                session.getUpdatedAt()
        );
    }

    private ExternalStorageAccountDto toExternalAccountDto(StorageExternalAccount account) {
        String credentialsJson = externalStorageCredentialService.decryptToJson(account.getEncryptedCredentials());
        return new ExternalStorageAccountDto(
                account.getId(),
                account.getProvider(),
                account.getDisplayName(),
                ExternalStorageCredentialCodec.extractEditableMetadata(
                        account.getProvider(),
                        credentialsJson
                ),
                account.getEncryptedCredentials() != null && !account.getEncryptedCredentials().isBlank(),
                account.getStatus(),
                account.getLastErrorCode(),
                account.getLastCheckedAt(),
                account.getCreatedAt(),
                account.getUpdatedAt()
        );
    }

    private FileNodeDto toNodeDto(FileNode node) {
        return new FileNodeDto(
                node.getId(),
                node.getParentId(),
                node.getNodeType(),
                node.getName(),
                node.getNormalizedPath(),
                node.getMimeType(),
                node.getSizeBytes(),
                node.isShared(),
                node.getSharedAt(),
                node.getUpdatedAt(),
                node.getSpaceType() != null ? node.getSpaceType().getValue() : "PERSONAL",
                node.getUploadedBy()
        );
    }

    private String normalizeResourceType(String resourceType) {
        if (resourceType == null || resourceType.isBlank()) {
            return "FILE";
        }
        String normalized = resourceType.trim().toUpperCase(Locale.ROOT);
        if (!"FILE".equals(normalized) && !"FOLDER".equals(normalized) && !"PHOTO_ALBUM".equals(normalized)) {
            throw new BusinessException(ErrorCode.BAD_REQUEST, "分享资源类型不合法");
        }
        return normalized;
    }

    private String resolveShareStatus(ShareLink share) {
        if (share.getDisabledAt() != null) {
            return "REVOKED";
        }
        if (share.getExpiresAt() != null && share.getExpiresAt().isBefore(Instant.now())) {
            return "EXPIRED";
        }
        if (share.getMaxAccessCount() != null && share.getAccessCount() >= share.getMaxAccessCount()) {
            return "EXHAUSTED";
        }
        return "ACTIVE";
    }

    /**
     * 将多个文件打包为 ZIP 流式下载。
     * 跳过文件夹节点和无对象数据的文件。
     *
     * @param userId  用户 ID
     * @param fileIds 要打包的文件 ID 列表
     * @param out     输出流
     */
    public void packAsZip(UUID userId, List<String> fileIds, OutputStream out) {
        try (ZipOutputStream zip = new ZipOutputStream(out)) {
            for (String fileId : fileIds) {
                FileNode node = fileNodeRepository.findByIdAndOwnerUserId(UUID.fromString(fileId), userId)
                        .orElseThrow(() -> new BusinessException(ErrorCode.FILE_NOT_FOUND, "文件不存在: " + fileId));
                // 跳过文件夹
                if (NodeType.FOLDER.getValue().equals(node.getNodeType())) {
                    continue;
                }
                // 无对象数据则跳过
                if (node.getCurrentObjectId() == null) {
                    continue;
                }
                FileObject obj = fileObjectRepository.findById(node.getCurrentObjectId()).orElse(null);
                if (obj == null) {
                    continue;
                }
                zip.putNextEntry(new ZipEntry(node.getName()));
                try (InputStream in = objectStorageClient.getObject(
                        new ObjectStorageKey(obj.getBucketName(), obj.getObjectKey()))) {
                    byte[] buffer = new byte[8192];
                    int len;
                    while ((len = in.read(buffer)) > 0) {
                        zip.write(buffer, 0, len);
                    }
                }
                zip.closeEntry();
            }
        } catch (IOException e) {
            log.error("ZIP 打包失败", e);
            throw new BusinessException(ErrorCode.INTERNAL_ERROR, "文件打包失败");
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

    private String sha256(String value) {
        try {
            MessageDigest digest = MessageDigest.getInstance("SHA-256");
            return HexFormat.of().formatHex(digest.digest(value.getBytes(StandardCharsets.UTF_8)));
        } catch (NoSuchAlgorithmException exception) {
            throw new IllegalStateException("SHA-256 算法不可用", exception);
        }
    }

    // ─── 共享管理 ───

    /**
     * 切换文件共享状态。
     * 取消共享时同时清理权限记录。
     */
    @Transactional(rollbackFor = Exception.class)
    public void toggleShared(UUID ownerUserId, UUID fileId) {
        FileNode node = findOwnedNode(ownerUserId, fileId);
        requireShareable(node);
        node.setShared(!node.isShared());
        node.setSharedAt(node.isShared() ? Instant.now() : null);
        fileNodeRepository.save(node);
        if (!node.isShared()) {
            filePermissionService.clearPermissions(fileId);
        }
        recordFileEvent(ownerUserId, fileId, Map.of("shared", node.isShared()));
        log.info("文件共享状态切换: fileId={}, shared={}", fileId, node.isShared());
    }

    /**
     * 文件夹级联共享。
     * 将文件夹及其所有子文件标记为共享。
     */
    @Transactional(rollbackFor = Exception.class)
    public void toggleSharedRecursive(UUID ownerUserId, UUID folderId, boolean shared) {
        FileNode folder = findOwnedNode(ownerUserId, folderId);
        if (!NodeType.FOLDER.getValue().equals(folder.getNodeType())) {
            throw new BusinessException(ErrorCode.BAD_REQUEST, "仅支持文件夹级联共享");
        }
        List<FileNode> descendants = fileNodeRepository
                .findByOwnerUserIdAndNormalizedPathStartingWithAndDeletedFalse(ownerUserId, folder.getNormalizedPath());
        Instant now = Instant.now();
        for (FileNode node : descendants) {
            node.setShared(shared);
            node.setSharedAt(shared ? now : null);
        }
        folder.setShared(shared);
        folder.setSharedAt(shared ? now : null);
        fileNodeRepository.saveAll(descendants);
        fileNodeRepository.save(folder);
        if (!shared) {
            List<UUID> allIds = new ArrayList<>(descendants.stream().map(FileNode::getId).toList());
            allIds.add(folderId);
            filePermissionService.clearPermissionsBatch(allIds);
        }
        recordFileLibraryInvalidation(ownerUserId, descendants.size() + 1);
        log.info("文件夹级联共享: folderId={}, shared={}, 影响{}个节点", folderId, shared, descendants.size());
    }

    /**
     * 获取用户可见的所有共享文件（非自己拥有的）。
     */
    @Transactional(readOnly = true)
    public List<SharedFileDto> listSharedFiles(UUID userId) {
        return listSharedFilesPage(userId, 0, FilePageRequests.MAX_SIZE).getContent();
    }

    /**
     * 设置文件的全局默认权限（仅文件拥有者可操作）。
     */
    @Transactional(rollbackFor = Exception.class)
    public void setGlobalPermission(UUID ownerUserId, UUID fileId, PermissionRequest request) {
        requireShareable(findOwnedNode(ownerUserId, fileId));
        filePermissionService.setGlobalPermission(
                fileId,
                request.allowDownload(),
                request.allowShare(),
                request.allowEdit()
        );
        recordPermissionEvent(ownerUserId, fileId);
    }

    /**
     * 设置文件对特定用户的权限覆盖（仅文件拥有者可操作）。
     */
    @Transactional(rollbackFor = Exception.class)
    public void setUserPermission(UUID ownerUserId, UUID fileId, UUID granteeUserId, PermissionRequest request) {
        requireShareable(findOwnedNode(ownerUserId, fileId));
        filePermissionService.setUserPermission(
                fileId,
                granteeUserId,
                request.allowDownload(),
                request.allowShare(),
                request.allowEdit()
        );
        recordPermissionEvent(ownerUserId, fileId);
        recordPermissionEvent(granteeUserId, fileId);
    }

    /**
     * 删除特定用户的权限覆盖。
     */
    @Transactional(rollbackFor = Exception.class)
    public void removeUserPermission(UUID ownerUserId, UUID fileId, UUID granteeUserId) {
        findOwnedNode(ownerUserId, fileId);
        filePermissionService.removeUserPermission(fileId, granteeUserId);
        recordPermissionEvent(ownerUserId, fileId);
        recordPermissionEvent(granteeUserId, fileId);
    }

    /**
     * 查看文件的所有权限配置（包括全局默认和各用户覆盖）。
     */
    @Transactional(readOnly = true)
    public List<FilePermissionDto> listPermissions(UUID ownerUserId, UUID fileId) {
        findOwnedNode(ownerUserId, fileId);
        return filePermissionService.listAllPermissions(fileId).stream()
                .map(p -> new FilePermissionDto(
                        p.getFileNodeId(),
                        p.getGranteeUserId(),
                        resolveGranteeUsername(p.getGranteeUserId()),
                        p.isAllowView(),
                        p.isAllowDownload(),
                        p.isAllowShare(),
                        p.isAllowEdit()
                ))
                .toList();
    }

    private String resolveGranteeUsername(UUID granteeUserId) {
        if (granteeUserId == null) {
            return null;
        }
        return userAccountQuery.findUsername(granteeUserId)
                .orElse("未知用户");
    }

    private FileNode findOwnedNode(UUID ownerUserId, UUID fileId) {
        return fileNodeRepository.findByIdAndOwnerUserIdAndDeletedFalse(fileId, ownerUserId)
                .orElseThrow(() -> new BusinessException(ErrorCode.NOT_FOUND, "文件不存在"));
    }

    private void requireShareable(FileNode node) {
        if (SourceType.LOCAL_FILESYSTEM.getValue().equals(node.getSourceType())) {
            throw new BusinessException(ErrorCode.FORBIDDEN, "本地只读影视库文件不支持该文件操作");
        }
    }

    private SharedFileDto toSharedFileDto(FileNode node, FilePermission permission, String ownerUsername) {
        return new SharedFileDto(
                toNodeDto(node),
                node.getOwnerUserId(),
                ownerUsername,
                permission != null ? permission : FilePermission.denyAll(),
                node.getSharedAt()
        );
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

    private void recordFileEvent(UUID ownerUserId, UUID fileId, Map<String, Object> hints) {
        syncEventRecorder.record(new SyncEventCommand(
                ownerUserId,
                SyncScope.FILES,
                "FILE_NODE",
                fileId.toString(),
                SyncAction.UPDATED,
                null,
                hints
        ));
    }

    private void recordFileLibraryInvalidation(UUID ownerUserId, int count) {
        syncEventRecorder.record(new SyncEventCommand(
                ownerUserId,
                SyncScope.FILES,
                "FILE_LIBRARY",
                null,
                SyncAction.INVALIDATED,
                null,
                Map.of("count", count)
        ));
    }

    private void recordShareEvent(UUID recipientUserId, UUID shareId) {
        syncEventRecorder.record(new SyncEventCommand(
                recipientUserId,
                SyncScope.FILES,
                "FILE_SHARE",
                shareId == null ? null : shareId.toString(),
                SyncAction.PERMISSION_CHANGED,
                null,
                Map.of()
        ));
    }

    private void recordPermissionEvent(UUID recipientUserId, UUID fileId) {
        syncEventRecorder.record(new SyncEventCommand(
                recipientUserId,
                SyncScope.FILES,
                "FILE_PERMISSION",
                fileId.toString(),
                SyncAction.PERMISSION_CHANGED,
                null,
                Map.of()
        ));
    }
}
