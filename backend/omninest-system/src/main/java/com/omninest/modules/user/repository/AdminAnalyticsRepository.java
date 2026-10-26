package com.omninest.modules.user.repository;

import jakarta.persistence.EntityManager;
import jakarta.persistence.Query;
import java.util.List;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Repository;

/**
 * 管理后台分析数据仓库 — 时序指标查询（PostgreSQL generate_series 等特有函数，使用原生 SQL）。
 */
@Repository
@RequiredArgsConstructor
public class AdminAnalyticsRepository {
    private final EntityManager entityManager;

    /**
     * 近 N 天每日新增用户数（空日期补零）。
     */
    @SuppressWarnings("unchecked")
    public List<Object[]> dailyUserGrowth(int days) {
        Query query = entityManager.createNativeQuery("""
                select to_char(series_day, 'YYYY-MM-DD') as date, coalesce(cnt, 0) as value
                from generate_series(
                    date_trunc('day', now()) - make_interval(days => :days - 1),
                    date_trunc('day', now()),
                    interval '1 day'
                ) series_day
                left join (
                    select date_trunc('day', created_at) as d, count(*) as cnt
                    from omni.auth_users
                    where created_at >= now() - make_interval(days => :days)
                    group by d
                ) t on t.d = series_day
                order by series_day
                """);
        query.setParameter("days", days);
        return query.getResultList();
    }

    /**
     * 近 N 天每日任务状态分布（空日期补零）。
     */
    @SuppressWarnings("unchecked")
    public List<Object[]> dailyTaskThroughput(int days, String zoneId) {
        // 分桶按实例配置时区：会话时区通常是 UTC，直接 date_trunc 会让每日边界错位。
        Query query = entityManager.createNativeQuery("""
                select to_char(series_day, 'YYYY-MM-DD') as date,
                       coalesce(completed, 0) as completed,
                       coalesce(failed, 0) as failed,
                       coalesce(running, 0) as running
                from generate_series(
                    date_trunc('day', now() AT TIME ZONE :zoneId) - make_interval(days => :days - 1),
                    date_trunc('day', now() AT TIME ZONE :zoneId),
                    interval '1 day'
                ) series_day
                left join (
                    select date_trunc('day', updated_at AT TIME ZONE :zoneId) as d,
                           count(*) filter (where status = 'COMPLETED') as completed,
                           count(*) filter (where status = 'FAILED' or status = 'DLQ') as failed,
                           count(*) filter (where status = 'RUNNING') as running
                    from omni.sys_tasks
                    where updated_at >= now() - make_interval(days => :days)
                    group by d
                ) t on t.d = series_day
                order by series_day
                """);
        query.setParameter("days", days);
        query.setParameter("zoneId", zoneId);
        return query.getResultList();
    }

    /**
     * 近 N 天每日累计存储量（字节），空日期沿用前一日值。
     */
    @SuppressWarnings("unchecked")
    public List<Object[]> dailyStorageGrowth(int days) {
        Query query = entityManager.createNativeQuery("""
                with baseline as (
                    select coalesce(sum(size_bytes), 0) as bytes
                    from omni.file_objects
                    where created_at < date_trunc('day', now()) - make_interval(days => :days - 1)
                ),
                daily as (
                    select date_trunc('day', created_at) as d,
                           coalesce(sum(size_bytes), 0) as bytes
                    from omni.file_objects
                    where created_at >= date_trunc('day', now()) - make_interval(days => :days - 1)
                    group by d
                ),
                cumulative as (
                    select d, (select bytes from baseline) + sum(bytes) over (order by d) as total
                    from daily
                )
                select to_char(series_day, 'YYYY-MM-DD') as date,
                       coalesce(c.total, (select bytes from baseline)) as value
                from generate_series(
                    date_trunc('day', now()) - make_interval(days => :days - 1),
                    date_trunc('day', now()),
                    interval '1 day'
                ) series_day
                left join cumulative c on c.d = series_day
                order by series_day
                """);
        query.setParameter("days", days);
        return query.getResultList();
    }
}
