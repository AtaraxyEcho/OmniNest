package com.omninest.modules.user.service;

import java.time.Clock;
import java.time.Duration;
import java.time.Instant;
import java.util.Map;
import java.util.function.Supplier;

/**
 * 管理台健康探测的短时缓存。
 *
 * <p>监控页每次刷新都会串行探测 PostgreSQL、Redis、MinIO、ClamAV 与 Lucene，其中
 * MinIO/ClamAV 是真实网络往返、超时以秒计。多个管理员同时打开页面或前端按秒轮询时，
 * 这些探测会成倍打到被探测组件上，而健康状态在几秒内不会变。</p>
 *
 * <p>缓存只覆盖很短的一段时间（默认 5 秒），既挡住同一波刷新，又不会把真实故障藏住
 * 太久。加载失败不写缓存：探测本身抛异常时下一次调用会重新探测。</p>
 *
 * @author OmniNest
 */
final class AdminHealthProbeCache {

    /** 与前端监控页的轮询节奏同阶，略短一档即可挡住并发刷新。 */
    static final Duration DEFAULT_TTL = Duration.ofSeconds(5);

    private final Duration ttl;
    private final Clock clock;
    private volatile Entry entry;

    AdminHealthProbeCache() {
        this(DEFAULT_TTL, Clock.systemUTC());
    }

    AdminHealthProbeCache(Duration ttl, Clock clock) {
        this.ttl = ttl;
        this.clock = clock;
    }

    /**
     * 取一次健康快照，未过期时直接返回缓存。
     *
     * @param loader 真正执行探测的加载器
     * @return 组件名到快照的映射
     */
    Map<String, HealthSnapshot> get(Supplier<Map<String, HealthSnapshot>> loader) {
        Instant now = clock.instant();
        Entry current = entry;
        if (current != null && now.isBefore(current.readAt().plus(ttl))) {
            return current.snapshots();
        }
        // 加载抛异常时保持旧缓存不动、异常继续上抛：宁可这次请求失败，
        // 也不能把"探测炸了"记成"组件正常"。
        Map<String, HealthSnapshot> fresh = loader.get();
        entry = new Entry(now, fresh);
        return fresh;
    }

    /**
     * 单个组件的健康快照。
     *
     * @param status 界面展示状态
     * @param detail 健康详情
     */
    record HealthSnapshot(String status, String detail) {
    }

    private record Entry(Instant readAt, Map<String, HealthSnapshot> snapshots) {
    }
}
