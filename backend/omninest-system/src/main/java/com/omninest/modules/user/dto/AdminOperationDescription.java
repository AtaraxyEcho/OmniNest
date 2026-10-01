package com.omninest.modules.user.dto;

import java.util.Locale;

/**
 * 管理后台操作与任务的精要描述转换器。
 *
 * @author OmniNest
 */
public final class AdminOperationDescription {
    private AdminOperationDescription() {
    }

    /**
     * 返回后台任务的可读描述。
     *
     * @param taskType 任务类型
     * @param routingKey 消息路由键
     * @return 任务描述
     */
    public static String task(String taskType, String routingKey) {
        String normalized = normalize(taskType);
        return switch (normalized) {
            case "FILE_INDEX" -> "更新文件搜索索引";
            case "TEXT_EXTRACTION" -> "提取文件文本内容";
            case "THUMBNAIL" -> "生成文件缩略图";
            case "OFFLINE_DOWNLOAD" -> "执行离线下载";
            case "EXTERNAL_IMPORT" -> "导入外部存储文件";
            case "MUSIC_SCAN" -> "扫描音乐资料库";
            case "PHOTO_SCAN" -> "扫描照片资料库";
            case "MUSIC_SCRAPE" -> "补全音乐元数据";
            case "MEDIA_SCRAPE" -> "补全影片元数据";
            case "VIDEO_TRANSCODE" -> "执行视频转码";
            case "COMIC_PARSE" -> "解析漫画目录与页面";
            case "PHOTO_BATCH" -> "批量处理照片";
            case "PHOTO_INDEX" -> "更新照片搜索索引";
            case "PHOTO_AI" -> "执行照片智能识别";
            default -> routingKey == null || routingKey.isBlank()
                    ? "执行后台任务"
                    : "处理消息任务 " + routingKey;
        };
    }

    /**
     * 返回审计动作的可读描述。
     *
     * @param action 动作编码
     * @param resourceType 资源类型
     * @return 审计描述
     */
    public static String audit(String action, String resourceType) {
        return switch (normalize(action)) {
            case "ADMIN_ROLE_PERMISSIONS_UPDATE" -> "更新角色权限";
            case "ADMIN_CONFIG_UPDATE" -> "修改系统配置";
            case "ADMIN_TASK_RETRY" -> "重新投递失败任务";
            case "ADMIN_TASK_CANCEL" -> "取消排队任务";
            case "ADMIN_TASK_DLQ_DISCARD" -> "丢弃死信任务";
            case "ADMIN_EXTERNAL_STORAGE_CREATE" -> "创建外部存储配置";
            case "ADMIN_EXTERNAL_STORAGE_STATUS_UPDATE" -> "修改外部存储状态";
            case "ADMIN_SESSION_REVOKE" -> "撤销用户会话";
            case "ADMIN_AUDIT_LOG_CLEANUP" -> "清理操作审计记录";
            case "ADMIN_LOGIN_AUDIT_CLEANUP" -> "清理登录审计记录";
            case "ADMIN_SESSION_CLEANUP" -> "清理过期或已撤销会话";
            case "ADMIN_USER_CREATE" -> "创建用户";
            case "ADMIN_USER_STATUS_UPDATE" -> "修改用户状态";
            case "ADMIN_USER_ROLE_UPDATE" -> "修改用户角色";
            default -> resourceType == null || resourceType.isBlank()
                    ? "执行管理操作"
                    : "管理 " + resourceType;
        };
    }

    private static String normalize(String value) {
        return value == null ? "" : value.trim().toUpperCase(Locale.ROOT);
    }
}
