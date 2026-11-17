package com.omninest.modules.file.service;

import com.omninest.modules.file.domain.FileNodePermission;
import com.omninest.modules.file.domain.FilePermission;
import com.omninest.modules.file.repository.FileNodePermissionRepository;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.UUID;
import java.util.stream.Collectors;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * 文件节点权限解析与维护服务。
 *
 * @author OmniNest
 */
@Service
@RequiredArgsConstructor
public class FilePermissionService {

    private final FileNodePermissionRepository permissionRepository;

    /**
     * 解析用户对文件的有效权限。
     * 优先级：特定用户权限 > 全局默认权限 > 系统默认（拒绝所有）
     */
    public FilePermission resolvePermission(UUID fileNodeId, UUID userId) {
        var userPerm = permissionRepository.findByFileNodeIdAndGranteeUserId(fileNodeId, userId);
        if (userPerm.isPresent()) {
            return fromEntity(userPerm.get());
        }
        var globalPerm = permissionRepository.findByFileNodeIdAndGranteeUserIdIsNull(fileNodeId);
        if (globalPerm.isPresent()) {
            return fromEntity(globalPerm.get());
        }
        return FilePermission.denyAll();
    }

    /**
     * 批量解析权限（用于文件列表页）。
     * 无权限记录的文件默认拒绝所有访问。
     */
    public Map<UUID, FilePermission> resolvePermissions(List<UUID> fileIds, UUID userId) {
        if (fileIds.isEmpty()) {
            return Map.of();
        }
        var perms = permissionRepository.findByFileIdsAndUserIdOrGlobal(fileIds, userId);
        Map<UUID, FilePermission> result = new HashMap<>();
        Map<UUID, FilePermission> globalFallback = new HashMap<>();
        for (var p : perms) {
            if (p.getGranteeUserId() != null) {
                result.put(p.getFileNodeId(), fromEntity(p));
            } else {
                globalFallback.putIfAbsent(p.getFileNodeId(), fromEntity(p));
            }
        }
        for (var entry : globalFallback.entrySet()) {
            result.putIfAbsent(entry.getKey(), entry.getValue());
        }
        for (var fileId : fileIds) {
            result.putIfAbsent(fileId, FilePermission.denyAll());
        }
        return result;
    }

    /**
     * 批量解析当前用户可查看的文件标识。
     *
     * @param fileIds 文件节点 ID 列表
     * @param userId 当前用户 ID
     * @return 允许查看的文件节点 ID 集合
     */
    public Set<UUID> resolveViewableFileIds(List<UUID> fileIds, UUID userId) {
        return resolvePermissions(fileIds, userId).entrySet().stream()
                .filter(entry -> entry.getValue().allowView())
                .map(Map.Entry::getKey)
                .collect(Collectors.toUnmodifiableSet());
    }

    /**
     * 设置文件的全局默认权限。
     */
    @Transactional(rollbackFor = Exception.class)
    public void setGlobalPermission(UUID fileNodeId, boolean allowDownload, boolean allowShare, boolean allowEdit) {
        var existing = permissionRepository.findByFileNodeIdAndGranteeUserIdIsNull(fileNodeId);
        FileNodePermission perm = existing.orElse(new FileNodePermission());
        perm.setFileNodeId(fileNodeId);
        perm.setGranteeUserId(null);
        perm.setAllowView(true);
        perm.setAllowDownload(allowDownload);
        perm.setAllowShare(allowShare);
        perm.setAllowEdit(allowEdit);
        permissionRepository.save(perm);
    }

    /**
     * 设置文件对特定用户的权限覆盖。
     */
    @Transactional(rollbackFor = Exception.class)
    public void setUserPermission(UUID fileNodeId, UUID granteeUserId, boolean allowDownload, boolean allowShare, boolean allowEdit) {
        var existing = permissionRepository.findByFileNodeIdAndGranteeUserId(fileNodeId, granteeUserId);
        FileNodePermission perm = existing.orElse(new FileNodePermission());
        perm.setFileNodeId(fileNodeId);
        perm.setGranteeUserId(granteeUserId);
        perm.setAllowView(true);
        perm.setAllowDownload(allowDownload);
        perm.setAllowShare(allowShare);
        perm.setAllowEdit(allowEdit);
        permissionRepository.save(perm);
    }

    /**
     * 删除特定用户的权限覆盖。
     */
    @Transactional(rollbackFor = Exception.class)
    public void removeUserPermission(UUID fileNodeId, UUID granteeUserId) {
        permissionRepository.findByFileNodeIdAndGranteeUserId(fileNodeId, granteeUserId)
                .ifPresent(permissionRepository::delete);
    }

    /**
     * 清理文件的所有权限记录（文件取消共享或删除时调用）。
     */
    @Transactional(rollbackFor = Exception.class)
    public void clearPermissions(UUID fileNodeId) {
        permissionRepository.deleteByFileNodeId(fileNodeId);
    }

    /**
     * 批量清理多个文件的权限记录（文件夹取消共享时调用）。
     */
    @Transactional(rollbackFor = Exception.class)
    public void clearPermissionsBatch(List<UUID> fileNodeIds) {
        if (!fileNodeIds.isEmpty()) {
            permissionRepository.deleteByFileNodeIdIn(fileNodeIds);
        }
    }

    /**
     * 查询文件的所有权限配置（包括全局默认和各用户覆盖）。
     */
    @Transactional(readOnly = true)
    public List<FileNodePermission> listAllPermissions(UUID fileNodeId) {
        return permissionRepository.findByFileNodeId(fileNodeId);
    }

    private FilePermission fromEntity(FileNodePermission entity) {
        return new FilePermission(
                entity.isAllowView(),
                entity.isAllowDownload(),
                entity.isAllowShare(),
                entity.isAllowEdit()
        );
    }
}
