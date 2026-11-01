package com.omninest.modules.file.dto;

import java.util.UUID;

/**
 * 单个角色的共享空间权限矩阵行。
 *
 * <p>未配置过的角色也返回一行，能力全部为 false，管理员据此判断"未授权"与
 * "已授权但关闭"的区别。</p>
 *
 * @param roleId 角色标识
 * @param roleCode 角色编码
 * @param canBrowse 可浏览
 * @param canUpload 可上传
 * @param canDownload 可下载
 * @param canDeleteOwn 可删除自己上传的内容
 * @param canDeleteAny 可删除任意成员的内容
 * @param canMoveTo 可迁入共享空间
 * @param canMoveFrom 可迁回个人空间
 * @param canCreateFolder 可建目录
 * @author OmniNest
 */
public record SharedSpaceRolePermissionDto(
        UUID roleId,
        String roleCode,
        boolean canBrowse,
        boolean canUpload,
        boolean canDownload,
        boolean canDeleteOwn,
        boolean canDeleteAny,
        boolean canMoveTo,
        boolean canMoveFrom,
        boolean canCreateFolder
) {
}
