package com.omninest.common.storage;

import lombok.RequiredArgsConstructor;
import org.springframework.boot.health.contributor.Health;
import org.springframework.boot.health.contributor.HealthIndicator;
import org.springframework.stereotype.Component;

/**
 * 对象存储连通性探针。
 *
 * <p>管理台此前把「对象存储」固定写成 UP；MinIO 故障时页面仍是绿灯。
 * 用一次对象头查询判断可达性：对象不存在返回 false 也说明服务与凭据可用，
 * 连接失败或桶缺失才判定为 DOWN。</p>
 *
 * @author OmniNest
 */
@Component
@RequiredArgsConstructor
public class MinioHealthIndicator implements HealthIndicator {

    private final ObjectStorageClient objectStorageClient;
    private final ObjectStorageBuckets objectStorageBuckets;

    @Override
    public Health health() {
        try {
            ObjectStorageKey probe = new ObjectStorageKey(
                    objectStorageBuckets.userFiles(), "_health/probe");
            objectStorageClient.objectExists(probe);
            return Health.up()
                    .withDetail("bucket", objectStorageBuckets.userFiles())
                    .build();
        } catch (RuntimeException exception) {
            return Health.down(exception).build();
        }
    }
}
