package com.omninest.modules.file.service;

import com.omninest.common.storage.ObjectStorageClient;
import com.omninest.common.storage.ObjectStorageKey;
import com.omninest.common.user.UserAvatarAssetPort;
import com.omninest.modules.file.domain.FileNode;
import com.omninest.modules.file.domain.FileObject;
import com.omninest.modules.file.repository.FileNodeRepository;
import com.omninest.modules.file.repository.FileObjectRepository;
import java.io.InputStream;
import java.time.Duration;
import java.util.Collection;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Objects;
import java.util.UUID;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;

/**
 * 用户头像的文件模块实现。
 *
 * <p>头像按派生资产落库，因此它和海报、背景图一样进入内容清单，回收走同一条
 * {@link DerivedAssetStorageService} 路径；对象键由 {@code file_objects} 行给出，
 * 不再由读取侧按约定拼装。</p>
 *
 * @author OmniNest
 */
@Slf4j
@Service
@RequiredArgsConstructor
public class FileUserAvatarAssetService implements UserAvatarAssetPort {

    private static final String RESOURCE_TYPE_USER = "USER";
    private static final String ASSET_TYPE_AVATAR = "AVATAR";

    private final DerivedAssetStorageService derivedAssetStorageService;
    private final FileNodeRepository fileNodeRepository;
    private final FileObjectRepository fileObjectRepository;
    private final ObjectStorageClient objectStorageClient;

    @Override
    public UUID store(UUID userId, String fileName, String mimeType, InputStream data) {
        return derivedAssetStorageService.store(
                userId,
                RESOURCE_TYPE_USER,
                userId,
                ASSET_TYPE_AVATAR,
                fileName,
                mimeType,
                data
        );
    }

    @Override
    public void release(UUID userId, UUID fileNodeId) {
        if (userId == null || fileNodeId == null) {
            return;
        }
        try {
            derivedAssetStorageService.deleteOwned(userId, fileNodeId);
        } catch (RuntimeException exception) {
            // 旧头像回收失败不能改写刚完成的上传或删除结果；对象由派生资产孤儿扫描兜底。
            log.warn("头像回收失败: userId={}, assetType={}, errorType={}",
                    userId, ASSET_TYPE_AVATAR, exception.getClass().getSimpleName());
        }
    }

    @Override
    public Map<UUID, String> downloadUrls(
            UUID ownerUserId,
            Collection<UUID> fileNodeIds,
            Duration ttl
    ) {
        if (ownerUserId == null) {
            return Map.of();
        }
        return sign(fileNodeIds, ttl, ownerUserId);
    }

    @Override
    public Map<UUID, String> downloadUrlsForManagedNodes(Collection<UUID> fileNodeIds, Duration ttl) {
        // 授权说明：本方法不限定所有者，调用方是已完成 system:user:read 校验的管理台
        // 用户列表；头像属用户自持的个人空间派生资产，管理台按职责可见其展示地址。
        return sign(fileNodeIds, ttl, null);
    }

    /**
     * 按节点自身的对象行签发地址。
     *
     * @param ownerUserId 限定所有者；{@code null} 表示由调用方自行完成权限校验
     */
    private Map<UUID, String> sign(Collection<UUID> fileNodeIds, Duration ttl, UUID ownerUserId) {
        if (fileNodeIds == null || fileNodeIds.isEmpty()) {
            return Map.of();
        }
        List<UUID> ids = fileNodeIds.stream().filter(Objects::nonNull).distinct().toList();
        if (ids.isEmpty()) {
            return Map.of();
        }
        Map<UUID, UUID> objectIdsByNode = new LinkedHashMap<>();
        for (FileNode node : fileNodeRepository.findAllById(ids)) {
            if (!node.isDeleted()
                    && DerivedAssetStorageService.SOURCE_TYPE_DERIVED.equals(node.getSourceType())
                    && node.getCurrentObjectId() != null
                    && (ownerUserId == null || ownerUserId.equals(node.getOwnerUserId()))) {
                objectIdsByNode.put(node.getId(), node.getCurrentObjectId());
            }
        }
        if (objectIdsByNode.isEmpty()) {
            return Map.of();
        }
        Map<UUID, FileObject> objectsById = new LinkedHashMap<>();
        fileObjectRepository.findAllById(objectIdsByNode.values())
                .forEach(object -> objectsById.put(object.getId(), object));
        Map<UUID, String> urls = new LinkedHashMap<>();
        objectIdsByNode.forEach((fileNodeId, objectId) -> {
            FileObject object = objectsById.get(objectId);
            if (object == null || object.getBucketName() == null || object.getObjectKey() == null) {
                return;
            }
            try {
                urls.put(fileNodeId, objectStorageClient.createDownloadUrl(
                        new ObjectStorageKey(object.getBucketName(), object.getObjectKey()),
                        ttl
                ).toString());
            } catch (RuntimeException exception) {
                // 单个头像签名失败只让这张图缺席，不拖垮整份资料或整页管理列表。
                log.warn("头像地址签发失败: fileId={}, errorType={}",
                        fileNodeId, exception.getClass().getSimpleName());
            }
        });
        return urls;
    }
}
