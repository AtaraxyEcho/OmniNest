package com.omninest.modules.user.repository;

import com.omninest.modules.user.dto.AdminOperationsDto;
import com.omninest.modules.user.dto.AdminOperationDescription;
import jakarta.persistence.EntityManager;
import java.sql.Timestamp;
import java.time.Instant;
import java.util.UUID;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Repository;

/**
 * 管理后台任务写入仓库。
 *
 * 任务记录使用原生 SQL：
 * - sys_tasks → RETURNING 子句
 */
@Repository
@RequiredArgsConstructor
public class AdminConsoleMetricsRepository {
    private final EntityManager entityManager;

    // ── 任务记录（跨模块 — 原生 SQL） ──────────────────────────────────

    /**
     * 更新任务状态并返回完整记录（PostgreSQL RETURNING 子句）。
     *
     * <p>RETURNING 只给出被更新行本身，归属显示名需再联用户表，
     * 因此写成 CTE 后在外层补齐 owner 两列。</p>
     */
    public AdminOperationsDto.TaskRecordItem updateTaskStatusReturning(UUID taskId, String status, int progress) {
        var query = entityManager.createNativeQuery("""
                with updated as (
                    update omni.sys_tasks
                    set status = :status,
                        progress = :progress,
                        error_summary = null,
                        retry_count = retry_count + 1,
                        updated_at = now(),
                        version = version + 1
                    where id = :taskId
                    returning *
                )
                select t.id, t.task_type, t.status, t.progress, t.routing_key,
                       t.error_summary, t.retry_count, t.created_at, t.updated_at,
                       t.owner_user_id,
                       coalesce(nullif(a.display_name, ''), a.username) as owner_label
                from updated t
                left join omni.auth_users a on a.id = t.owner_user_id
                """);
        query.setParameter("taskId", taskId);
        query.setParameter("status", status);
        query.setParameter("progress", progress);
        return taskRecord((Object[]) query.getSingleResult());
    }

    /**
     * 以预期状态为守卫把任务更新为终态并返回完整记录（PostgreSQL RETURNING 子句）。
     *
     * <p>用于管理员取消排队任务与丢弃死信任务：并发状态变化导致守卫不命中时
     * 不更新任何行并抛出 NoResultException，由调用方转换为稳定业务错误。
     * reason 非空时覆盖错误摘要（取消原因），为空时保留原死信错误摘要。</p>
     *
     * @param taskId 任务 ID
     * @param status 目标终态
     * @param expectedStatus 调用方刚读取到的状态守卫
     * @param reason 覆盖写入的取消原因，可为 null
     * @return 更新后的任务记录
     */
    public AdminOperationsDto.TaskRecordItem updateTaskTerminalReturning(
            UUID taskId,
            String status,
            String expectedStatus,
            String reason
    ) {
        var query = entityManager.createNativeQuery("""
                with updated as (
                    update omni.sys_tasks
                    set status = :status,
                        error_summary = coalesce(:reason, error_summary),
                        next_retry_at = null,
                        completed_at = now(),
                        updated_at = now(),
                        version = version + 1
                    where id = :taskId and status = :expectedStatus
                    returning *
                )
                select t.id, t.task_type, t.status, t.progress, t.routing_key,
                       t.error_summary, t.retry_count, t.created_at, t.updated_at,
                       t.owner_user_id,
                       coalesce(nullif(a.display_name, ''), a.username) as owner_label
                from updated t
                left join omni.auth_users a on a.id = t.owner_user_id
                """);
        query.setParameter("taskId", taskId);
        query.setParameter("status", status);
        query.setParameter("expectedStatus", expectedStatus);
        query.setParameter("reason", reason);
        return taskRecord((Object[]) query.getSingleResult());
    }

    // ── DTO 映射 ──────────────────────────────────────────────────────

    private AdminOperationsDto.TaskRecordItem taskRecord(Object[] row) {
        return new AdminOperationsDto.TaskRecordItem(
                uuid(row[0]), text(row[1]), AdminOperationDescription.task(text(row[1]), text(row[4])),
                text(row[2]), intValue(row[3]),
                text(row[4]), text(row[5]), intValue(row[6]),
                instant(row[7]), instant(row[8]),
                uuidOrNull(row[9]), text(row[10])
        );
    }

    private UUID uuidOrNull(Object value) {
        if (value == null) {
            return null;
        }
        return uuid(value);
    }

    private UUID uuid(Object value) {
        if (value instanceof UUID uuid) return uuid;
        return UUID.fromString(value.toString());
    }

    private String text(Object value) {
        return value == null ? null : value.toString();
    }

    private int intValue(Object value) {
        if (value instanceof Number number) return number.intValue();
        return Integer.parseInt(value.toString());
    }

    private Instant instant(Object value) {
        if (value instanceof Instant instant) return instant;
        if (value instanceof Timestamp timestamp) return timestamp.toInstant();
        return Instant.parse(value.toString());
    }
}
