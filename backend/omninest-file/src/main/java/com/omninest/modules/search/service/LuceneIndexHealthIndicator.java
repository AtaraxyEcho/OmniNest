package com.omninest.modules.search.service;

import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.health.contributor.Health;
import org.springframework.boot.health.contributor.HealthIndicator;
import org.springframework.stereotype.Component;

/**
 * Lucene 索引目录可写性探针。
 *
 * <p>管理台曾把 "Lucene Index" 写死为 UP；索引卷只读或磁盘满时，搜索/索引任务
 * 会持续失败而监控面板不变色。探针在索引目录创建并删除一个临时文件验证可写。</p>
 *
 * @author OmniNest
 */
@Component
public class LuceneIndexHealthIndicator implements HealthIndicator {

    private final String indexPath;

    public LuceneIndexHealthIndicator(@Value("${omninest.search.index-path}") String indexPath) {
        this.indexPath = indexPath;
    }

    @Override
    public Health health() {
        try {
            Path directory = Path.of(indexPath);
            Files.createDirectories(directory);
            Path probe = Files.createTempFile(directory, ".health-", ".tmp");
            Files.deleteIfExists(probe);
            return Health.up().build();
        } catch (IOException | RuntimeException exception) {
            return Health.down(exception).build();
        }
    }
}
