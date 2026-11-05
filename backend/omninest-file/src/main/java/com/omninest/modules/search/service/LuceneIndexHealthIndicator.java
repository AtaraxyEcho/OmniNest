package com.omninest.modules.search.service;

import java.io.IOException;
import java.nio.file.FileStore;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.List;
import java.util.concurrent.TimeUnit;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.health.contributor.Health;
import org.springframework.boot.health.contributor.HealthIndicator;
import org.springframework.stereotype.Component;

/**
 * Lucene 索引目录可写性探针。
 *
 * <p>管理台曾把 "Lucene Index" 写死为 UP；索引卷只读或磁盘满时，搜索/索引任务
 * 会持续失败而监控面板不变色。探针因此要真实写一个字节：{@code Files.isWritable}
 * 只检查权限位，Linux 容器里卷被重挂载为只读（EROFS）或 inode 耗尽（ENOSPC）时
 * 权限位依然可写，只有实际写入才会失败。</p>
 *
 * <p>探针文件名固定为 {@value #PROBE_FILE_NAME} 而不是随机临时文件：监控每 15 秒
 * 轮询一次时随机文件会持续制造元数据写 IO，进程被强杀还会留下 {@code .health-*.tmp}
 * 孤儿文件；固定名互相覆盖且崩溃后仍复用同一路径。探测结果缓存
 * {@value #PROBE_CACHE_SECONDS} 秒，避免多路并发健康检查把磁盘写打满。</p>
 *
 * @author OmniNest
 */
@Component
public class LuceneIndexHealthIndicator implements HealthIndicator {

    private static final long PROBE_CACHE_SECONDS = 30L;
    private static final long PROBE_CACHE_TTL_NANOS = TimeUnit.SECONDS.toNanos(PROBE_CACHE_SECONDS);
    /** 低于该剩余空间时索引写入会先写坏段文件，按不可用上报。 */
    private static final long MIN_USABLE_SPACE_BYTES = 64L * 1024 * 1024;
    private static final String PROBE_FILE_NAME = ".health-probe";
    private static final byte[] PROBE_PAYLOAD = {1};

    private final List<Path> indexPaths;
    private volatile CachedHealth cachedHealth;

    /**
     * 索引根目录由配置决定，与 {@link FileSearchIndexService} 同一取值。
     *
     * <p>@Value 只影响 Spring 注入；直接 {@code new} 传入路径的调用方行为不变。</p>
     *
     * @param indexPath 文件索引根目录
     */
    @Autowired
    public LuceneIndexHealthIndicator(
            @Value("${omninest.search.index-path:${user.home}/.omninest/lucene-index}") String indexPath
    ) {
        this(List.of(Path.of(indexPath)));
    }

    private LuceneIndexHealthIndicator(List<Path> indexPaths) {
        this.indexPaths = List.copyOf(indexPaths);
    }

    /**
     * 按多个目录构造探针，供同时挂载多个索引卷的部署使用。
     *
     * @param indexPaths 索引目录
     * @return 探针实例
     */
    public static LuceneIndexHealthIndicator forDirectories(List<Path> indexPaths) {
        return new LuceneIndexHealthIndicator(indexPaths);
    }

    @Override
    public Health health() {
        long now = System.nanoTime();
        CachedHealth snapshot = this.cachedHealth;
        if (isFresh(snapshot, now)) {
            return snapshot.health();
        }
        synchronized (this) {
            snapshot = this.cachedHealth;
            if (isFresh(snapshot, now)) {
                return snapshot.health();
            }
            Health computed = probeAllDirectories();
            this.cachedHealth = new CachedHealth(computed, System.nanoTime());
            return computed;
        }
    }

    private boolean isFresh(CachedHealth snapshot, long now) {
        return snapshot != null && now - snapshot.checkedAtNanos() < PROBE_CACHE_TTL_NANOS;
    }

    private Health probeAllDirectories() {
        try {
            for (Path directory : indexPaths) {
                Files.createDirectories(directory);
                FileStore store = Files.getFileStore(directory);
                long usableSpace = store.getUsableSpace();
                if (usableSpace < MIN_USABLE_SPACE_BYTES) {
                    return Health.down()
                            .withDetail("directory", directory.toString())
                            .withDetail("usableSpaceBytes", usableSpace)
                            .build();
                }
                Path probe = directory.resolve(PROBE_FILE_NAME);
                Files.write(probe, PROBE_PAYLOAD);
                Files.deleteIfExists(probe);
            }
            return Health.up().build();
        } catch (IOException | RuntimeException exception) {
            return Health.down(exception).build();
        }
    }

    private record CachedHealth(Health health, long checkedAtNanos) {
    }
}
