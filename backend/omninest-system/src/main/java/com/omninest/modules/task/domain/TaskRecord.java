package com.omninest.modules.task.domain;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import jakarta.persistence.PrePersist;
import jakarta.persistence.PreUpdate;
import jakarta.persistence.Table;
import jakarta.persistence.Version;
import java.time.Instant;
import java.util.UUID;
import lombok.AllArgsConstructor;
import lombok.Getter;
import lombok.NoArgsConstructor;
import lombok.Setter;

/**
 * 系统任务记录实体
 */
@Entity
@Table(name = "sys_tasks", schema = "omni")
@Getter
@Setter
@AllArgsConstructor
@NoArgsConstructor
public class TaskRecord {

    @Id
    private UUID id;

    /** 任务类型 */
    @Column(name = "task_type", nullable = false, length = 80)
    private String taskType;

    /** 任务状态 */
    @Column(nullable = false, length = 32)
    private String status;

    /** 消息路由键 */
    @Column(name = "routing_key", length = 200)
    private String routingKey;

    /** 任务内部执行阶段 */
    @Column(length = 64)
    private String phase;

    /** 关联资源类型 */
    @Column(name = "resource_type", length = 64)
    private String resourceType;

    /** 关联资源 ID */
    @Column(name = "resource_id")
    private UUID resourceId;

    /** 任务载荷 */
    @Column(columnDefinition = "TEXT")
    private String payload;

    /** 执行结果 */
    @Column(columnDefinition = "TEXT")
    private String result;

    /** 错误信息 */
    @Column(name = "error_summary", columnDefinition = "TEXT")
    private String errorMessage;

    /** 失败堆栈摘要，脱敏截断 */
    @Column(name = "stack_summary", columnDefinition = "TEXT")
    private String stackSummary;

    /** 已重试次数 */
    @Column(name = "retry_count", nullable = false)
    private int retryCount;

    /** 进度值（0~100） */
    @Column(nullable = false)
    private int progress;

    /** 最大重试次数 */
    @Column(name = "max_retries", nullable = false)
    private int maxRetries;

    /** 开始执行时间 */
    @Column(name = "started_at")
    private Instant startedAt;

    /** 完成时间 */
    @Column(name = "completed_at")
    private Instant completedAt;

    /** 下次允许重试时间 */
    @Column(name = "next_retry_at")
    private Instant nextRetryAt;

    /** 执行心跳时间 */
    @Column(name = "heartbeat_at")
    private Instant heartbeatAt;

    /** 所属用户 ID */
    @Column(name = "owner_user_id")
    private UUID ownerUserId;

    /** 创建时间 */
    @Column(name = "created_at", nullable = false)
    private Instant createdAt;

    /** 更新时间 */
    @Column(name = "updated_at", nullable = false)
    private Instant updatedAt;

    /** 乐观锁版本号 */
    @Version
    @Column(nullable = false)
    private long version;

    @PrePersist
    void fillDefaults() {
        if (id == null) {
            id = UUID.randomUUID();
        }
        final Instant now = Instant.now();
        if (createdAt == null) {
            createdAt = now;
        }
        if (updatedAt == null) {
            updatedAt = now;
        }
    }

    @PreUpdate
    void fillUpdatedAt() {
        updatedAt = Instant.now();
    }

    @Override
    public boolean equals(Object o) {
        if (this == o) return true;
        if (!(o instanceof TaskRecord other)) return false;
        return id != null && id.equals(other.getId());
    }

    @Override
    public int hashCode() {
        return getClass().hashCode();
    }

    /**
     * 仅输出标识与任务状态，避免 TEXT 载荷、结果和错误详情进入日志。
     */
    @Override
    public String toString() {
        return "TaskRecord{id=" + id + ", taskType=" + taskType + ", status=" + status + "}";
    }
}
