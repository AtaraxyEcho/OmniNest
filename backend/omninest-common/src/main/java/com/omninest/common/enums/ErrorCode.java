package com.omninest.common.enums;

import lombok.AllArgsConstructor;
import lombok.Getter;

/**
 * 定义稳定的 API 错误码与默认消息。
 *
 * @author OmniNest
 */
@Getter
@AllArgsConstructor
public enum ErrorCode {
    // ==================== 系统 1xxx ====================
    SUCCESS(200, "成功"),
    PARAM_ERROR(400, "参数错误"),
    BAD_REQUEST(400, "请求参数错误"),
    VALIDATION_FAILED(400, "参数校验失败"),
    UNAUTHORIZED(401, "未认证"),
    FORBIDDEN(403, "无权限"),
    NOT_FOUND(404, "资源不存在"),
    CONFLICT(409, "数据冲突"),
    RATE_LIMITED(429, "请求过于频繁"),
    DEPENDENCY_UNAVAILABLE(1001, "运行依赖不可用"),
    REGISTRATION_DISABLED(1002, "用户注册未启用"),
    INTERNAL_ERROR(500, "服务器内部错误"),

    // ==================== 任务 2xxx ====================
    TASK_STATUS_ILLEGAL(2001, "任务状态流转非法"),
    TASK_NOT_FOUND(2002, "任务不存在"),
    TASK_ALREADY_COMPLETED(2003, "任务已完成，不可操作"),
    TASK_DEPENDENCY_NOT_READY(2004, "任务依赖未就绪"),

    // ==================== 配置 3xxx ====================
    CONFIG_NOT_FOUND(3001, "配置项不存在"),
    CONFIG_VALUE_INVALID(3002, "配置值不合法"),

    // ==================== 文件 4xxx ====================
    FILE_UPLOAD_FAILED(4001, "文件上传失败"),
    FILE_SIZE_EXCEEDED(4002, "文件大小超过限制"),
    FILE_QUOTA_EXCEEDED(4003, "存储配额不足"),
    FILE_NOT_FOUND(4004, "文件不存在"),
    FILE_PATH_INVALID(4005, "文件路径不合法"),
    RESOURCE_IN_USE(4006, "资源仍被其他业务引用"),
    FILE_LIFECYCLE_CONFLICT(4007, "文件正在执行生命周期操作"),
    FILE_OBJECT_MISSING(4008, "文件对象缺失"),
    FILE_SECURITY_REJECTED(4009, "文件安全扫描未通过"),

    // ==================== 媒体 5xxx ====================
    MEDIA_NOT_FOUND(5001, "媒体资源不存在"),
    MEDIA_TRANSCODE_FAILED(5002, "媒体转码失败"),
    MUSIC_PLATFORM_NOT_CONNECTED(5003, "音乐平台未连接"),
    MUSIC_PLATFORM_AUTH_EXPIRED(5004, "音乐平台登录已失效"),
    MUSIC_RECOMMENDATION_UNAVAILABLE(5005, "每日推荐暂不可用"),

    // ==================== 阅读 6xxx ====================
    BOOK_NOT_FOUND(6001, "书籍不存在"),
    READING_PROGRESS_INVALID(6002, "阅读进度不合法"),

    // ==================== 用户偏好 7xxx ====================
    PREFERENCE_VERSION_CONFLICT(7001, "用户偏好版本冲突"),

    // ==================== 背景 8xxx ====================
    BACKDROP_NOT_FOUND(8001, "背景素材不存在"),
    BACKDROP_UNSUPPORTED_FORMAT(8002, "背景素材格式不支持"),
    BACKDROP_QUOTA_EXCEEDED(8003, "背景库配额不足"),
    BACKDROP_FILE_TOO_LARGE(8004, "背景素材文件过大"),
    BACKDROP_SCAN_UNAVAILABLE(8005, "安全扫描服务不可用"),
    BACKDROP_MALWARE_DETECTED(8006, "背景素材检测到安全威胁"),
    BACKDROP_SCAN_FAILED(8007, "背景素材安全扫描失败"),

    // ==================== 认证扩展 9xxx ====================
    TWO_FACTOR_INVALID_CODE(9001, "两步验证码错误"),
    TWO_FACTOR_NOT_CONFIGURED(9002, "两步验证未配置"),
    TWO_FACTOR_ALREADY_ENABLED(9003, "两步验证已开启"),
    PASSWORD_INVALID(9004, "密码错误"),
    OLD_PASSWORD_INVALID(9005, "原密码错误"),
    SHARE_PASSWORD_REQUIRED(9006, "需要访问密码");

    private final Integer code;
    private final String message;
}
