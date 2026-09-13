package com.omninest.modules.music.config;

import org.springframework.boot.context.properties.ConfigurationProperties;
import org.springframework.stereotype.Component;

/**
 * 音乐模块运行期配置。
 */
@Component
@ConfigurationProperties(prefix = "omninest.music")
public class MusicLibraryProperties {
    /** 播放历史保留天数，默认 90 天。 */
    private int historyRetentionDays = 90;

    public int getHistoryRetentionDays() {
        return historyRetentionDays;
    }

    public void setHistoryRetentionDays(int historyRetentionDays) {
        this.historyRetentionDays = historyRetentionDays;
    }
}
