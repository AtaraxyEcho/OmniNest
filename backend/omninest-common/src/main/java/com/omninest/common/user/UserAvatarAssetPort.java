package com.omninest.common.user;

import java.io.InputStream;
import java.time.Duration;
import java.util.Collection;
import java.util.Map;
import java.util.UUID;

/**
 * 用户头像的资产端口。
 *
 * <p>用户模块不直接操作对象存储：头像必须作为派生资产落 {@code file_nodes} 与
 * {@code file_objects}，才能进入内容清单并被统一的回收路径覆盖；否则
 * {@code auth_users.avatar_file_id} 只是一个凭空生成的 UUID，对象键约定还要在读取、
 * 换头像、删除用户与孤儿扫描四处各自手写一遍。</p>
 *
 * <p>端口声明在 {@code common} 而不是让用户模块直接依赖文件模块，是因为实测依赖方向为
 * {@code omninest-file -> omninest-system}，反向注入会形成 Maven 循环；同一形状已由
 * {@link UserDataPurgePort} 与 {@code TempStagingPort} 确立。</p>
 *
 * @author OmniNest
 */
public interface UserAvatarAssetPort {

    /**
     * 保存头像并返回其文件节点标识。
     *
     * @param userId 头像所属用户 ID
     * @param fileName 文件名，参与派生路径；同一用户换头像时用不同名字以换得新对象键
     * @param mimeType 内容类型
     * @param data 内容流
     * @return {@code file_nodes.id}
     */
    UUID store(UUID userId, String fileName, String mimeType, InputStream data);

    /**
     * 回收头像：对象与内容行一起删除。失败只记录，不向调用方抛出。
     *
     * @param userId 头像所属用户 ID
     * @param fileNodeId 待回收的文件节点标识，{@code null} 时直接返回
     */
    void release(UUID userId, UUID fileNodeId);

    /**
     * 以头像所有者身份签发短期下载地址。
     *
     * @param ownerUserId 头像所有者，同时是签发身份
     * @param fileNodeIds 文件节点标识集合
     * @param ttl 地址有效期：资料接口历来返回 24 小时，而通用下载入口只签 2 小时，
     *            直接复用会让客户端在资料不重拉期间拿到过期地址
     * @return 文件节点标识到 URL 的映射；无对应节点时该键不出现在结果里
     */
    Map<UUID, String> downloadUrls(UUID ownerUserId, Collection<UUID> fileNodeIds, Duration ttl);

    /**
     * 跨所有者批量签发头像地址，供管理台用户列表整页一次取齐。
     *
     * <p>与 {@link #downloadUrls(UUID, Collection, Duration)} 分开是因为授权语义不同：
     * 这里每个节点属于不同用户，调用方必须是已完成管理权限校验的入口。</p>
     *
     * @param fileNodeIds 文件节点标识集合
     * @param ttl 地址有效期
     * @return 文件节点标识到 URL 的映射
     */
    Map<UUID, String> downloadUrlsForManagedNodes(Collection<UUID> fileNodeIds, Duration ttl);
}
