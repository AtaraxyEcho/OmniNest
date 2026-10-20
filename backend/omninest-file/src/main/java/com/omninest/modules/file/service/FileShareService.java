package com.omninest.modules.file.service;

import com.omninest.common.cache.ReadThroughCache;
import com.omninest.common.enums.ErrorCode;
import com.omninest.common.error.BusinessException;
import com.omninest.common.security.CredentialCipher;
import com.omninest.common.user.UserAccountQuery;
import com.omninest.common.util.LikePatterns;
import com.omninest.modules.file.domain.FileNode;
import com.omninest.modules.file.domain.FilePermission;
import com.omninest.modules.file.domain.FileShareRecipient;
import com.omninest.modules.file.domain.NodeType;
import com.omninest.modules.file.domain.ShareLink;
import com.omninest.modules.file.dto.AdminFileShareLinkDto;
import com.omninest.modules.file.dto.CreateShareLinkRequest;
import com.omninest.modules.file.dto.FilePermissionDto;
import com.omninest.modules.file.dto.FileShareLinkDto;
import com.omninest.modules.file.dto.FileSharedItemDto;
import com.omninest.modules.file.dto.PermissionRequest;
import com.omninest.modules.file.dto.SharedFileDto;
import com.omninest.modules.file.dto.UpdateShareLinkRequest;
import com.omninest.modules.file.repository.FileNodeRepository;
import com.omninest.modules.file.repository.FileShareRecipientRepository;
import com.omninest.modules.file.repository.ShareLinkRepository;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.security.SecureRandom;
import java.time.Instant;
import java.util.ArrayList;
import java.util.HexFormat;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Objects;
import java.util.UUID;
import java.util.stream.Collectors;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.PageImpl;
import org.springframework.data.domain.Pageable;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * 分享链接管理服务。
 * 负责分享创建、撤销、列表查询、共享开关与权限配置。
 *
 * @author OmniNest
 */
@Slf4j
@Service
@RequiredArgsConstructor
public class FileShareService {
    private final FileNodeRepository fileNodeRepository;
    private final ShareLinkRepository shareLinkRepository;
    private final FileShareRecipientRepository shareRecipientRepository;
    private final PasswordEncoder passwordEncoder;
    private final FilePermissionService filePermissionService;
    private final UserAccountQuery userAccountQuery;
    private final FileNodeSupport fileNodeSupport;
    private final FileSyncEventWriter syncEventWriter;
    private final ReadThroughCache readThroughCache;
    private final CredentialCipher credentialCipher;

    /**
     * 分页查询收到的分享。
     *
     * @param ownerUserId 用户 ID
     * @param page        页码（从 0 开始）
     * @param size        每页条数
     * @return 收到的分享分页
     */
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

    /**
     * 分页查询我创建的分享。
     *
     * @param ownerUserId 用户 ID
     * @param page        页码（从 0 开始）
     * @param size        每页条数
     * @return 我的分享分页
     */
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

    /**
     * 分页查询共享空间中可见的共享文件。
     *
     * @param userId 用户 ID
     * @param page   页码（从 0 开始）
     * @param size   每页条数
     * @return 共享文件分页
     */
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

    /**
     * 查询收到的分享（全量）。
     *
     * @param ownerUserId 用户 ID
     * @return 收到的分享列表
     */
    @Transactional(readOnly = true)
    public List<FileSharedItemDto> listSharedWithMe(UUID ownerUserId) {
        return listSharedWithMePage(ownerUserId, 0, FilePageRequests.MAX_SIZE).getContent();
    }

    /**
     * 查询我创建的分享（全量）。
     *
     * @param ownerUserId 用户 ID
     * @return 我的分享列表
     */
    @Transactional(readOnly = true)
    public List<FileShareLinkDto> listMyShares(UUID ownerUserId) {
        return listMySharesPage(ownerUserId, 0, FilePageRequests.MAX_SIZE).getContent();
    }

    /**
     * 获取用户可见的所有共享文件（非自己拥有的）。
     *
     * @param userId 用户 ID
     * @return 共享文件列表
     */
    @Transactional(readOnly = true)
    public List<SharedFileDto> listSharedFiles(UUID userId) {
        return listSharedFilesPage(userId, 0, FilePageRequests.MAX_SIZE).getContent();
    }

    /**
     * 分页查询全站未撤销的分享链接，附所有者身份，供管理端治理。
     *
     * @param page 页码（从 0 开始）
     * @param size 每页条数
     * @return 全站分享分页
     */
    @Transactional(readOnly = true)
    public Page<AdminFileShareLinkDto> listAllSharesPage(int page, int size) {
        Pageable pageable = FilePageRequests.of(page, size);
        Page<ShareLink> sharePage = shareLinkRepository.findAllActivePage(pageable);
        if (sharePage.isEmpty()) {
            return new PageImpl<>(List.of(), pageable, sharePage.getTotalElements());
        }
        List<UUID> resourceIds = sharePage.getContent()
                .stream()
                .map(ShareLink::getResourceId)
                .distinct()
                .toList();
        Map<UUID, String> namesById = fileNodeRepository.findAllById(resourceIds)
                .stream()
                .collect(Collectors.toMap(
                        FileNode::getId, FileNode::getName, (l, r) -> l, LinkedHashMap::new));
        List<UUID> ownerIds = sharePage.getContent()
                .stream()
                .map(ShareLink::getOwnerUserId)
                .distinct()
                .toList();
        Map<UUID, String> ownerNames = userAccountQuery.findUsernames(ownerIds);
        List<AdminFileShareLinkDto> items = sharePage.getContent()
                .stream()
                .map(share -> new AdminFileShareLinkDto(
                        share.getId(),
                        share.getOwnerUserId(),
                        ownerNames.getOrDefault(share.getOwnerUserId(), "未知用户"),
                        share.getResourceType(),
                        share.getResourceId(),
                        namesById.getOrDefault(share.getResourceId(), "已删除文件"),
                        resolveShareStatus(share),
                        share.getMaxAccessCount(),
                        share.getAccessCount(),
                        share.getExpiresAt(),
                        share.getDisabledAt(),
                        share.getCreatedAt()
                ))
                .toList();
        return new PageImpl<>(items, pageable, sharePage.getTotalElements());
    }

    /**
     * 创建分享链接。
     *
     * @param ownerUserId 用户 ID
     * @param request     创建请求
     * @return 分享链接信息（含明文 token 与生成密码）
     */
    @Transactional(rollbackFor = Exception.class)
    public FileShareLinkDto createShare(UUID ownerUserId, CreateShareLinkRequest request) {
        String resourceType = normalizeResourceType(request.resourceType());

        FileNode node = fileNodeSupport.findActiveNode(ownerUserId, request.resourceId());
        fileNodeSupport.requireShareable(node);
        String rawToken = UUID.randomUUID().toString().replace("-", "");
        ShareLink share = new ShareLink();
        share.setOwnerUserId(ownerUserId);
        share.setResourceType(resourceType);
        share.setResourceId(node.getId());
        share.setTokenHash(sha256(rawToken));
        // 密文令牌支持所有者日后重新复制链接地址；公开校验仍走哈希比对。
        share.setTokenCipher(credentialCipher.encrypt(rawToken));
        share.setExpiresAt(request.parsedExpiresAt());
        share.setMaxAccessCount(request.maxAccessCount());

        String generatedPassword = null;
        if (request.password() != null && !request.password().isBlank()) {
            share.setPasswordHash(passwordEncoder.encode(request.password()));
        } else if (request.generatePassword()) {
            generatedPassword = generateRandomPassword(10);
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
        syncEventWriter.recordShareEvent(ownerUserId, saved.getId());
        recipients.forEach(recipientUserId -> syncEventWriter.recordShareEvent(recipientUserId, saved.getId()));
        return toShareDto(saved, rawToken, generatedPassword);
    }

    /**
     * 修改分享链接的密码、有效期与访问次数上限。
     *
     * <p>令牌与资源不变：编辑设置不能让已经发出去的地址失效。三个字段传 null 表示保持原值；
     * 密码传空白串表示清除密码，过期时间传空白串表示改为长期有效，次数上限传 0 表示不限次数。</p>
     *
     * @param ownerUserId 所有者用户 ID
     * @param shareId     分享链接 ID
     * @param request     更新请求
     * @return 更新后的分享链接信息（不含明文令牌以外的凭据）
     */
    @Transactional(rollbackFor = Exception.class)
    public FileShareLinkDto updateShare(UUID ownerUserId, UUID shareId, UpdateShareLinkRequest request) {
        ShareLink share = shareLinkRepository.findByIdAndOwnerUserId(shareId, ownerUserId)
                .orElseThrow(() -> new BusinessException(ErrorCode.NOT_FOUND, "分享链接不存在"));
        if (share.getDisabledAt() != null) {
            throw new BusinessException(ErrorCode.BAD_REQUEST, "分享链接已撤销");
        }
        Instant expiresAt = request.parsedExpiresAt();
        if (expiresAt != null && expiresAt.isBefore(Instant.now())) {
            throw new BusinessException(ErrorCode.PARAM_ERROR, "过期时间必须晚于当前时间");
        }
        Integer maxAccessCount = request.maxAccessCount();
        if (maxAccessCount != null && maxAccessCount < 0) {
            throw new BusinessException(ErrorCode.PARAM_ERROR, "访问次数上限不能为负数");
        }
        if (maxAccessCount != null && maxAccessCount > 0 && share.getAccessCount() > maxAccessCount) {
            throw new BusinessException(
                    ErrorCode.PARAM_ERROR,
                    "访问次数上限不能低于已访问次数 " + share.getAccessCount()
            );
        }
        if (request.expiresAt() != null) {
            share.setExpiresAt(expiresAt);
        }
        if (maxAccessCount != null) {
            share.setMaxAccessCount(maxAccessCount > 0 ? maxAccessCount : null);
        }
        if (request.password() != null) {
            share.setPasswordHash(
                    request.password().isBlank() ? null : passwordEncoder.encode(request.password()));
        }
        ShareLink saved = shareLinkRepository.save(share);
        readThroughCache.invalidate("omninest:share:link:" + saved.getTokenHash());
        syncEventWriter.recordShareEvent(ownerUserId, saved.getId());
        log.info("更新分享链接设置: shareId={}, ownerUserId={}, 密码变更={}, expiresAt={}, maxAccessCount={}",
                saved.getId(), ownerUserId, request.password() != null,
                saved.getExpiresAt(), saved.getMaxAccessCount());
        return toShareDto(saved, null, null);
    }

    /**
     * 撤销分享链接。
     *
     * @param ownerUserId 用户 ID
     * @param shareId     分享链接 ID
     */
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
        syncEventWriter.recordShareEvent(ownerUserId, shareId);
        recipientUserIds.forEach(recipientUserId -> syncEventWriter.recordShareEvent(recipientUserId, shareId));
        log.info("撤销分享链接: shareId={}, ownerUserId={}", shareId, ownerUserId);
        readThroughCache.invalidate("omninest:share:link:" + share.getTokenHash());
    }

    /**
     * 切换文件共享状态。
     * 取消共享时同时清理权限记录。
     *
     * @param ownerUserId 用户 ID
     * @param fileId      文件节点 ID
     */
    @Transactional(rollbackFor = Exception.class)
    public void toggleShared(UUID ownerUserId, UUID fileId) {
        FileNode node = fileNodeSupport.findOwnedNode(ownerUserId, fileId);
        fileNodeSupport.requireShareable(node);
        node.setShared(!node.isShared());
        node.setSharedAt(node.isShared() ? Instant.now() : null);
        fileNodeRepository.save(node);
        if (!node.isShared()) {
            filePermissionService.clearPermissions(fileId);
        }
        syncEventWriter.recordFileEvent(ownerUserId, fileId, Map.of("shared", node.isShared()));
        log.info("文件共享状态切换: fileId={}, shared={}", fileId, node.isShared());
    }

    /**
     * 文件夹级联共享。
     * 将文件夹及其所有子文件标记为共享。
     *
     * @param ownerUserId 用户 ID
     * @param folderId    文件夹 ID
     * @param shared      是否共享
     */
    @Transactional(rollbackFor = Exception.class)
    public void toggleSharedRecursive(UUID ownerUserId, UUID folderId, boolean shared) {
        FileNode folder = fileNodeSupport.findOwnedNode(ownerUserId, folderId);
        if (!NodeType.FOLDER.getValue().equals(folder.getNodeType())) {
            throw new BusinessException(ErrorCode.BAD_REQUEST, "仅支持文件夹级联共享");
        }
        List<FileNode> descendants = fileNodeRepository
                .findByOwnerUserIdAndSpaceTypeAndNormalizedPathStartingWithAndDeletedFalse(
                        ownerUserId, folder.getSpaceType(), LikePatterns.escapeSpecials(folder.getNormalizedPath()));
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
        syncEventWriter.recordFileLibraryInvalidation(ownerUserId, descendants.size() + 1);
        log.info("文件夹级联共享: folderId={}, shared={}, 影响{}个节点", folderId, shared, descendants.size());
    }

    /**
     * 设置文件的全局默认权限（仅文件拥有者可操作）。
     *
     * @param ownerUserId 用户 ID
     * @param fileId      文件节点 ID
     * @param request     权限请求
     */
    @Transactional(rollbackFor = Exception.class)
    public void setGlobalPermission(UUID ownerUserId, UUID fileId, PermissionRequest request) {
        fileNodeSupport.requireShareable(fileNodeSupport.findOwnedNode(ownerUserId, fileId));
        filePermissionService.setGlobalPermission(
                fileId,
                request.allowDownload(),
                request.allowShare(),
                request.allowEdit()
        );
        syncEventWriter.recordPermissionEvent(ownerUserId, fileId);
    }

    /**
     * 设置文件对特定用户的权限覆盖（仅文件拥有者可操作）。
     *
     * @param ownerUserId   用户 ID
     * @param fileId        文件节点 ID
     * @param granteeUserId 被授权用户 ID
     * @param request       权限请求
     */
    @Transactional(rollbackFor = Exception.class)
    public void setUserPermission(UUID ownerUserId, UUID fileId, UUID granteeUserId, PermissionRequest request) {
        fileNodeSupport.requireShareable(fileNodeSupport.findOwnedNode(ownerUserId, fileId));
        filePermissionService.setUserPermission(
                fileId,
                granteeUserId,
                request.allowDownload(),
                request.allowShare(),
                request.allowEdit()
        );
        syncEventWriter.recordPermissionEvent(ownerUserId, fileId);
        syncEventWriter.recordPermissionEvent(granteeUserId, fileId);
    }

    /**
     * 删除特定用户的权限覆盖。
     *
     * @param ownerUserId   用户 ID
     * @param fileId        文件节点 ID
     * @param granteeUserId 被授权用户 ID
     */
    @Transactional(rollbackFor = Exception.class)
    public void removeUserPermission(UUID ownerUserId, UUID fileId, UUID granteeUserId) {
        fileNodeSupport.findOwnedNode(ownerUserId, fileId);
        filePermissionService.removeUserPermission(fileId, granteeUserId);
        syncEventWriter.recordPermissionEvent(ownerUserId, fileId);
        syncEventWriter.recordPermissionEvent(granteeUserId, fileId);
    }

    /**
     * 查看文件的所有权限配置（包括全局默认和各用户覆盖）。
     *
     * @param ownerUserId 用户 ID
     * @param fileId      文件节点 ID
     * @return 权限配置列表
     */
    @Transactional(readOnly = true)
    public List<FilePermissionDto> listPermissions(UUID ownerUserId, UUID fileId) {
        fileNodeSupport.findOwnedNode(ownerUserId, fileId);
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

    /**
     * 计算分享 token 的 SHA-256 哈希。
     *
     * @param value 明文 token
     * @return 十六进制哈希
     */
    public static String sha256(String value) {
        try {
            MessageDigest digest = MessageDigest.getInstance("SHA-256");
            return HexFormat.of().formatHex(digest.digest(value.getBytes(StandardCharsets.UTF_8)));
        } catch (NoSuchAlgorithmException exception) {
            throw new IllegalStateException("SHA-256 算法不可用", exception);
        }
    }

    private String resolveGranteeUsername(UUID granteeUserId) {
        if (granteeUserId == null) {
            return null;
        }
        return userAccountQuery.findUsername(granteeUserId)
                .orElse("未知用户");
    }

    /**
     * 把一条接收记录映射为「收到的分享」条目。
     *
     * <p>文件夹分享同样入列：分页总数按接收记录计，若在此丢弃 FOLDER 条目，
     * 列表条数会少于总数且前端统计的文件夹数恒为 0。</p>
     */
    private List<FileSharedItemDto> toSharedItemDto(
            FileShareRecipient recipient,
            Map<UUID, FileNode> nodesById) {
        ShareLink share = recipient.getShareLink();
        if (share == null || share.getDisabledAt() != null) {
            return List.of();
        }
        FileNode file = nodesById.get(share.getResourceId());
        if (file == null || file.isDeleted() || !share.getOwnerUserId().equals(file.getOwnerUserId())) {
            return List.of();
        }
        return List.of(new FileSharedItemDto(
                share.getId(),
                fileNodeSupport.toNodeDto(file),
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
        // 创建响应携带明文令牌；列表查询只能从密文还原，历史行无密文时返回空串，
        // 不得回退到哈希片段——那不是可用地址，复制出去必然 404。
        String shareCode = rawToken != null ? rawToken : revealToken(share);
        return new FileShareLinkDto(
                share.getId(),
                share.getResourceType(),
                share.getResourceId(),
                resourceName,
                shareCode == null ? "" : shareCode,
                resolveShareStatus(share),
                share.getMaxAccessCount(),
                share.getAccessCount(),
                share.getExpiresAt(),
                share.getDisabledAt(),
                share.getCreatedAt(),
                generatedPassword
        );
    }

    /**
     * 还原分享链接的明文令牌。
     *
     * <p>公开访问路径按哈希查库，不经过本方法；这里只服务所有者重新复制链接地址。
     * 密钥轮换或历史数据缺密文时返回 null，由调用方按"无地址"处理。</p>
     */
    private String revealToken(ShareLink share) {
        String cipher = share.getTokenCipher();
        if (cipher == null || cipher.isBlank()) {
            return null;
        }
        try {
            return credentialCipher.decrypt(cipher);
        } catch (RuntimeException error) {
            log.debug("分享令牌解密失败，按无地址处理: shareId={}, errorType={}",
                    share.getId(), error.getClass().getSimpleName());
            return null;
        }
    }

    private SharedFileDto toSharedFileDto(FileNode node, FilePermission permission, String ownerUsername) {
        return new SharedFileDto(
                fileNodeSupport.toNodeDto(node),
                node.getOwnerUserId(),
                ownerUsername,
                permission != null ? permission : FilePermission.denyAll(),
                node.getSharedAt()
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
}
