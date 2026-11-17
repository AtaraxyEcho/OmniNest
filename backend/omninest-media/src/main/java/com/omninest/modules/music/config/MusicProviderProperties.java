package com.omninest.modules.music.config;

import org.springframework.boot.context.properties.ConfigurationProperties;
import org.springframework.stereotype.Component;

/**
 * 音乐外部服务的部署级地址与身份配置。
 */
@Component
@ConfigurationProperties(prefix = "music.providers")
public class MusicProviderProperties {
    private String musicBrainzUserAgent = "OmniNest/0.1.0 (music@omninest.local)";
    private String neteaseBaseUrl = "http://localhost:3001";

    public String getMusicBrainzUserAgent() {
        return musicBrainzUserAgent;
    }

    public void setMusicBrainzUserAgent(String musicBrainzUserAgent) {
        this.musicBrainzUserAgent = musicBrainzUserAgent;
    }

    public String getNeteaseBaseUrl() {
        return neteaseBaseUrl;
    }

    public void setNeteaseBaseUrl(String neteaseBaseUrl) {
        this.neteaseBaseUrl = neteaseBaseUrl;
    }
}
