package com.omninest.modules.file.service;

import com.omninest.common.cache.ReadThroughCache;
import com.omninest.common.enums.ErrorCode;
import com.omninest.common.error.BusinessException;
import com.omninest.common.ratelimit.RateLimitService;
import com.omninest.common.sync.SyncAction;
import com.omninest.common.sync.SyncEventCommand;
import com.omninest.common.sync.SyncScope;
import com.omninest.common.sync.UserSyncEventRecorder;
import com.omninest.common.util.LikePatterns;
import com.omninest.modules.quota.service.StorageQuotaService;
import com.omninest.modules.file.domain.FileNode;
import com.omninest.modules.file.domain.NodeType;
import com.omninest.modules.file.domain.ShareLink;
import com.omninest.modules.file.domain.SourceType;
import com.omninest.modules.file.domain.SpaceType;
import com.omninest.modules.file.dto.AcceptShareRequest;
import com.omninest.modules.file.dto.FileDownloadUrlDto;
import com.omninest.modules.file.dto.FileNodeDto;
import com.omninest.modules.file.dto.FileShareAccessDto;
import com.omninest.modules.file.dto.FileShareChildDto;
import com.omninest.modules.file.dto.FileSharePreviewDto;
import com.omninest.modules.file.dto.ShareAccessSessionDto;
import com.omninest.modules.file.repository.FileNodeRepository;
import com.omninest.modules.file.repository.FileShareRecipientRepository;
import com.omninest.modules.file.repository.ShareLinkRepository;
import com.omninest.modules.notification.port.NotificationPublisher;
import java.time.Duration;
import java.time.Instant;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.data.domain.Page;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.transaction.support.TransactionSynchronization;
import org.springframework.transaction.support.TransactionSynchronizationManager;

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
    private final FileShareRecipientRepository shareRecipientRepository;
    private final PasswordEncoder passwordEncoder;
    private final RateLimitService rateLimitService;
    private final NotificationPublisher notificationService;
    private final FileQueryService fileQueryService;
    private final ResourceShareLinkService resourceShareLinkService;
    private final ReadThroughCache readThroughCache;
    private final FileNodeSupport fileNodeSupport;
    private final StorageQuotaService storageQuotaService;
    private final UserSyncEventRecorder syncEventRecorder;
    private final FileIndexSyncService fileIndexSyncService;

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
        requireShareRateLimit(tokenHash, null);
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
        requireShareRateLimit(tokenHash, null);
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
     * <p>访问次数在建立会话时一次性消费：会话有效期内的预览、浏览子目录与下载
     * 不再重复扣减。文件夹分享没有单文件下载动作，若把消费放在下载上，
     * {@code maxAccessCount} 永远不会生效。</p>
     *
     * @param rawToken       分享明文 token
     * @param password       分享密码
     * @param clientAddress  客户端地址
     * @return 短期会话信息
     */
    @Transactional(rollbackFor = Exception.class)
    public ShareAccessSessionDto issueShareSession(String rawToken, String password, String clientAddress) {
        ShareAccessSessionDto session = resourceShareLinkService.issueConsumedSession(
                rawToken, password, null, clientAddress);
        notifyShareAccessedAfterCommit(FileShareService.sha256(rawToken));
        return session;
    }

    private void notifyShareAccessedAfterCommit(String tokenHash) {
        if (TransactionSynchronizationManager.isSynchronizationActive()) {
            TransactionSynchronizationManager.registerSynchronization(new TransactionSynchronization() {
                @Override
                public void afterCommit() {
                    notifyShareAccessed(tokenHash);
                }
            });
            return;
        }
        notifyShareAccessed(tokenHash);
    }

    private void notifyShareAccessed(String tokenHash) {
        try {
            ShareLink link = findShareLinkCached(tokenHash);
            FileNode node = fileNodeRepository.findByIdAndOwnerUserIdAndDeletedFalse(
                            link.getResourceId(), link.getOwnerUserId())
                    .orElse(null);
            if (node == null) {
                return;
            }
            notificationService.notifyOrLog(
                    link.getOwnerUserId(),
                    "SHARE_ACCESSED",
                    "分享被访问",
                    "有人访问了您分享的文件: " + node.getName(),
                    Map.of("shareId", link.getId().toString(), "fileName", node.getName())
            );
        } catch (RuntimeException exception) {
            log.warn("发送分享访问通知失败: errorType={}", exception.getClass().getSimpleName());
        }
    }

    /**
     * 使用短期会话访问分享文件；访问次数已在签发会话时消费。
     *
     * @param rawToken     分享明文 token
     * @param sessionToken 短期会话 token
     * @param clientAddress 客户端地址，用于按访问者计限流键
     * @return 分享文件访问结果
     */
    @Transactional(rollbackFor = Exception.class)
    public FileShareAccessDto shareAccessSession(String rawToken, String sessionToken, String clientAddress) {
        String tokenHash = FileShareService.sha256(rawToken);
        requireShareRateLimit(tokenHash, clientAddress);
        resourceShareLinkService.requireAnySession(rawToken, sessionToken);
        ShareLink link = findShareLinkCached(tokenHash);
        FileNode node = fileNodeRepository.findByIdAndOwnerUserIdAndDeletedFalse(
                        link.getResourceId(), link.getOwnerUserId())
                .orElseThrow(() -> new BusinessException(ErrorCode.FILE_NOT_FOUND, "文件不存在或已被删除"));
        // 文件夹没有单文件下载语义：createDownloadUrl 会直接拒绝非 FILE 节点，
        // 让整条分享以 400 结束。此处回文件夹元数据并把下载入口留空。
        if (NodeType.FOLDER.getValue().equals(link.getResourceType())) {
            return new FileShareAccessDto(
                    node.getName(), node.getMimeType(), node.getSizeBytes(), null, link.getResourceType());
        }
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
     * @param clientAddress 客户端地址，用于按访问者计限流键
     * @return 分享预览信息
     */
    @Transactional(readOnly = true)
    public FileSharePreviewDto previewShareSession(String rawToken, String sessionToken, String clientAddress) {
        String tokenHash = FileShareService.sha256(rawToken);
        requireShareRateLimit(tokenHash, clientAddress);
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
     * 使用短期会话浏览被分享的文件夹子树。
     *
     * <p>访客只能从分享根目录逐级进入：请求的节点必须属于链接所有者且未删除，并且路径落在根目录子树内，
     * 越界一律按"不存在"处理，不能让一条分享链接变成遍历其他目录的凭据。派生资产与只读影视库来源
     * 沿用文件列表的可见性口径，不出现在子项里；文件按页批量签发短期下载地址，与单文件分享一致。</p>
     *
     * @param rawToken      分享明文 token
     * @param sessionToken  短期会话 token
     * @param clientAddress 客户端地址，用于按访问者计限流键
     * @param parentId      要浏览的目录 ID，空表示分享根目录
     * @param page          页码
     * @param size          每页数量
     * @return 子项分页结果
     */
    @Transactional(readOnly = true)
    public Page<FileShareChildDto> shareChildrenSession(
            String rawToken,
            String sessionToken,
            String clientAddress,
            UUID parentId,
            int page,
            int size
    ) {
        String tokenHash = FileShareService.sha256(rawToken);
        requireShareRateLimit(tokenHash, clientAddress);
        resourceShareLinkService.requireAnySession(rawToken, sessionToken);
        return childrenOfShareLink(findShareLinkCached(tokenHash), parentId, page, size);
    }

    /**
     * 定向分享的接收人浏览被分享的文件夹子树。
     *
     * <p>授权依据是"接收人 ↔ 分享链接"这层关系：{@code createShare} 只写接收人记录，
     * 既不写 FilePermission、也不给后代打 shared 标记，所以这里不能借用文件权限解析，
     * 也不能要求节点 shared。链接被撤销或过期后不得继续可逛。</p>
     *
     * @param userId   当前用户（接收人）ID
     * @param shareId  分享链接 ID
     * @param parentId 要浏览的目录 ID，空表示分享根目录
     * @param page     页码
     * @param size     每页数量
     * @return 子项分页结果
     */
    @Transactional(readOnly = true)
    public Page<FileShareChildDto> shareChildrenForRecipient(
            UUID userId,
            UUID shareId,
            UUID parentId,
            int page,
            int size
    ) {
        if (!shareRecipientRepository.existsByShareLink_IdAndRecipientUserId(shareId, userId)) {
            throw new BusinessException(ErrorCode.FORBIDDEN, "该分享不是分享给你的");
        }
        ShareLink link = shareLinkRepository.findById(shareId)
                .orElseThrow(() -> new BusinessException(ErrorCode.FILE_NOT_FOUND, "分享链接不存在"));
        if (link.getDisabledAt() != null) {
            throw new BusinessException(ErrorCode.CONFLICT, "分享链接已撤销");
        }
        if (link.getExpiresAt() != null && Instant.now().isAfter(link.getExpiresAt())) {
            throw new BusinessException(ErrorCode.CONFLICT, "分享链接已过期");
        }
        return childrenOfShareLink(link, parentId, page, size);
    }

    private Page<FileShareChildDto> childrenOfShareLink(
            ShareLink link,
            UUID parentId,
            int page,
            int size
    ) {
        if (!NodeType.FOLDER.getValue().equals(link.getResourceType())) {
            throw new BusinessException(ErrorCode.FILE_PATH_INVALID, "该分享链接不是文件夹");
        }
        FileNode root = requireShareOwnerNode(link, link.getResourceId(), "分享的文件夹不存在或已被删除");
        FileNode parent = parentId == null || parentId.equals(root.getId())
                ? root
                : requireInsideSharedSubtree(link, root, parentId);
        Page<FileNodeDto> nodes = fileQueryService.listFilesPage(
                link.getOwnerUserId(), parent.getId(), null, page, size);
        Map<UUID, String> downloadUrls = signShareChildUrls(link.getOwnerUserId(), nodes.getContent());
        return nodes.map(node -> new FileShareChildDto(
                node.id(),
                node.parentId(),
                node.nodeType(),
                node.name(),
                node.mimeType(),
                node.sizeBytes(),
                node.updatedAt(),
                downloadUrls.get(node.id())
        ));
    }

    private FileNode requireShareOwnerNode(ShareLink link, UUID nodeId, String message) {
        return fileNodeRepository.findByIdAndOwnerUserIdAndDeletedFalse(nodeId, link.getOwnerUserId())
                .orElseThrow(() -> new BusinessException(ErrorCode.FILE_NOT_FOUND, message));
    }

    private FileNode requireInsideSharedSubtree(ShareLink link, FileNode root, UUID nodeId) {
        FileNode node = requireShareOwnerNode(link, nodeId, "文件夹不存在或已被删除");
        // 前缀带尾斜杠：/docs 不能把 /documentation 也算进子树。
        if (!node.getNormalizedPath().startsWith(root.getNormalizedPath() + "/")) {
            throw new BusinessException(ErrorCode.FILE_NOT_FOUND, "文件夹不存在或已被删除");
        }
        if (NodeType.FILE.getValue().equals(node.getNodeType())) {
            throw new BusinessException(ErrorCode.FILE_PATH_INVALID, "文件没有子目录");
        }
        return node;
    }

    private Map<UUID, String> signShareChildUrls(UUID ownerUserId, List<FileNodeDto> nodes) {
        List<UUID> fileIds = nodes.stream()
                .filter(node -> NodeType.FILE.getValue().equals(node.nodeType()))
                .map(FileNodeDto::id)
                .toList();
        if (fileIds.isEmpty()) {
            return Map.of();
        }
        Map<UUID, String> urls = new LinkedHashMap<>();
        fileQueryService.createDownloadUrls(ownerUserId, fileIds)
                .forEach((nodeId, downloadUrl) -> urls.put(nodeId, downloadUrl.downloadUrl()));
        return urls;
    }

    /**
     * 使用短期会话接受文件分享。
     *
     * @param userId       接受用户 ID
     * @param rawToken     分享明文 token
     * @param sessionToken 短期会话 token
     * @param clientAddress 客户端地址，用于按访问者计限流键
     * @param request      接受请求
     */
    @Transactional(rollbackFor = Exception.class)
    public void acceptShareSession(
            UUID userId,
            String rawToken,
            String sessionToken,
            String clientAddress,
            AcceptShareRequest request
    ) {
        String tokenHash = FileShareService.sha256(rawToken);
        requireShareRateLimit(tokenHash, clientAddress);
        resourceShareLinkService.requireAnySession(rawToken, sessionToken);
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

    private void requireShareRateLimit(String tokenHash, String clientAddress) {
        // 单链接全局兜底阈值必须高于单 IP 阈值，否则任一访客刷几次就能把该链接对所有
        // 正常访问者锁死，限流键退化成拒绝服务开关。
        if (clientAddress != null && !rateLimitService.tryAcquire(
                "share:ip:" + FileShareService.sha256(clientAddress) + ":" + tokenHash,
                30,
                Duration.ofMinutes(1))) {
            throw new BusinessException(ErrorCode.RATE_LIMITED, "访问过于频繁，请稍后再试");
        }
        if (!rateLimitService.tryAcquire("share:" + tokenHash, 300, Duration.ofMinutes(1))) {
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
        FileNode targetParent = resolveAcceptTargetParent(userId, targetParentId);
        if (fileNodeSupport.sameNameExists(
                userId, SpaceType.PERSONAL, targetParentId, source.getName())) {
            throw new BusinessException(ErrorCode.CONFLICT, "目标位置已存在同名文件");
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
        FileNode saved = fileNodeRepository.save(newNode);
        chargePersonalQuota(userId, newNode.getSizeBytes());
        fileIndexSyncService.scheduleAfterCommit(userId, List.of(saved.getId()));
        recordFileEvent(userId, saved.getId(), SyncAction.CREATED);
    }

    /**
     * 转存目标必须是个人空间里的文件夹，不能把共享空间节点或普通文件当作父目录。
     */
    private FileNode resolveAcceptTargetParent(UUID userId, UUID targetParentId) {
        if (targetParentId == null) {
            return null;
        }
        FileNode targetParent = fileNodeRepository
                .findByIdAndOwnerUserIdAndDeletedFalse(targetParentId, userId)
                .orElseThrow(() -> new BusinessException(ErrorCode.FILE_NOT_FOUND, "目标文件夹不存在"));
        if (!NodeType.FOLDER.getValue().equals(targetParent.getNodeType())
                || targetParent.getSpaceType() != SpaceType.PERSONAL) {
            throw new BusinessException(ErrorCode.FILE_PATH_INVALID, "目标必须是个人空间文件夹");
        }
        return targetParent;
    }

    /**
     * 转存进个人空间的节点按实际字节计入用户配额。
     *
     * <p>彻底删除时一律按节点字节扣减，转存与复制若不加计，用户可以用「转存—清空回收站」
     * 把已用空间反复刷成负数并绕过配额。</p>
     */
    private void chargePersonalQuota(UUID userId, long bytes) {
        storageQuotaService.checkQuota(userId, bytes);
        storageQuotaService.incrementUsage(userId, bytes);
    }

    private void recordFileEvent(UUID ownerUserId, UUID fileId, SyncAction action) {
        syncEventRecorder.record(new SyncEventCommand(
                ownerUserId,
                SyncScope.FILES,
                "FILE_NODE",
                fileId.toString(),
                action,
                null,
                Map.of()
        ));
    }

    private void acceptFolderShare(UUID userId, FileNode sourceFolder, UUID targetParentId) {
        FileNode targetParent = resolveAcceptTargetParent(userId, targetParentId);
        UUID targetParentNodeId = targetParent != null ? targetParent.getId() : null;
        if (fileNodeSupport.sameNameExists(
                userId, SpaceType.PERSONAL, targetParentNodeId, sourceFolder.getName())) {
            throw new BusinessException(ErrorCode.CONFLICT, "目标目录已存在同名文件夹，请先改名或清理后再保存");
        }
        FileNode newFolder = new FileNode();
        // 预生成主键：子节点要靠父节点 ID 建立映射，而 ID 原本在 flush 才赋值，
        // 逐条 save 就是把它逼出来的 N+1 写。预分配后整棵子树可以一次 saveAll。
        newFolder.setId(UUID.randomUUID());
        newFolder.setOwnerUserId(userId);
        newFolder.setParentId(targetParent != null ? targetParent.getId() : null);
        newFolder.setNodeType(NodeType.FOLDER.getValue());
        newFolder.setName(sourceFolder.getName());
        newFolder.setNormalizedPath(fileNodeSupport.resolveChildPath(targetParent, sourceFolder.getName()));
        newFolder.setSizeBytes(0L);
        newFolder.setSourceType(SourceType.SHARE.getValue());
        newFolder.setShared(false);
        newFolder.setSpaceType(SpaceType.PERSONAL);

        List<FileNode> descendants = fileNodeRepository
                .findDescendantsByPrefixOrdered(
                        sourceFolder.getOwnerUserId(),
                        LikePatterns.escapeSpecials(sourceFolder.getNormalizedPath() + "/"));

        List<FileNode> pending = new ArrayList<>();
        pending.add(newFolder);
        Map<String, FileNode> pathToNewNode = new LinkedHashMap<>();
        pathToNewNode.put(sourceFolder.getNormalizedPath(), newFolder);

        long totalBytes = 0L;
        for (FileNode child : descendants) {
            String relativePath = child.getNormalizedPath().substring(sourceFolder.getNormalizedPath().length());
            String trimmedRelative = relativePath.startsWith("/") ? relativePath.substring(1) : relativePath;
            String[] segments = trimmedRelative.isEmpty() ? new String[0] : trimmedRelative.split("/");
            FileNode parentNode = newFolder;
            StringBuilder currentPath = new StringBuilder(sourceFolder.getNormalizedPath());

            for (int i = 0; i < segments.length - 1; i++) {
                currentPath.append("/").append(segments[i]);
                parentNode = pathToNewNode.get(currentPath.toString());
                if (parentNode == null) {
                    throw new IllegalStateException("文件夹分享子树父节点缺失: " + currentPath);
                }
            }

            FileNode newChild = new FileNode();
            newChild.setId(UUID.randomUUID());
            newChild.setOwnerUserId(userId);
            newChild.setParentId(parentNode.getId());
            newChild.setNodeType(child.getNodeType());
            newChild.setName(child.getName());
            newChild.setNormalizedPath(fileNodeSupport.resolveChildPath(parentNode, child.getName()));
            newChild.setMimeType(child.getMimeType());
            newChild.setSizeBytes(child.getSizeBytes());
            newChild.setCurrentObjectId(child.getCurrentObjectId());
            newChild.setSourceType(SourceType.SHARE.getValue());
            newChild.setShared(false);
            newChild.setSpaceType(SpaceType.PERSONAL);
            pathToNewNode.put(child.getNormalizedPath(), newChild);
            pending.add(newChild);
            if (NodeType.FILE.getValue().equals(child.getNodeType())) {
                totalBytes += child.getSizeBytes();
            }
        }
        List<FileNode> savedNodes = fileNodeRepository.saveAll(pending);
        chargePersonalQuota(userId, totalBytes);
        fileIndexSyncService.scheduleAfterCommit(
                userId, savedNodes.stream().map(FileNode::getId).toList());
        recordFileEvent(userId, newFolder.getId(), SyncAction.CREATED);
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
