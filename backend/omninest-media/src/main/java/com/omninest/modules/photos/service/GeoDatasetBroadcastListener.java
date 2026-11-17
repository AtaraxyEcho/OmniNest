package com.omninest.modules.photos.service;

import com.omninest.common.config.ConfigRefreshEvent;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.context.event.EventListener;
import org.springframework.stereotype.Component;

/**
 * GeoNames 数据集发布广播监听器。
 *
 * <p>复用配置刷新 fanout 通道作为传输层：各实例收到 key 前缀为
 * photo.geo.dataset.reload: 的广播后，将内存索引重载到指定数据集版本。
 * 仅复用消息传输，不把数据集事件定义成配置语义。</p>
 *
 * @author OmniNest
 */
@Slf4j
@Component
@RequiredArgsConstructor
public class GeoDatasetBroadcastListener {

    private final GeoCityIndex geoCityIndex;

    /**
     * 处理数据集发布广播。
     *
     * @param event 配置刷新通道事件
     */
    @EventListener
    public void onConfigRefresh(ConfigRefreshEvent event) {
        String key = event.key();
        if (key == null || !key.startsWith(GeoDatasetService.BROADCAST_KEY_PREFIX)) {
            return;
        }
        String datasetVersion = key.substring(GeoDatasetService.BROADCAST_KEY_PREFIX.length());
        try {
            if (datasetVersion.isBlank()) {
                geoCityIndex.reloadCurrentPublished();
            } else {
                geoCityIndex.reloadToVersion(datasetVersion);
            }
            log.info("已响应 GeoNames 数据集发布广播并重载索引: datasetVersion={}", datasetVersion);
        } catch (RuntimeException ex) {
            // 单实例重载失败不影响其他实例，可通过手动 reload 或重启对齐。
            log.error("响应 GeoNames 数据集广播重载索引失败: datasetVersion={}", datasetVersion, ex);
        }
    }
}
