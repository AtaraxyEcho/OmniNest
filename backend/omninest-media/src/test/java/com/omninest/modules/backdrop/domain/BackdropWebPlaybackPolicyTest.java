package com.omninest.modules.backdrop.domain;

import static org.assertj.core.api.Assertions.assertThat;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

class BackdropWebPlaybackPolicyTest {

    @Test
    @DisplayName("浏览器稳定支持的编码判为可播")
    void acceptsBrowserSupportedCodecs() {
        assertThat(BackdropWebPlaybackPolicy.isWebPlayable("h264")).isTrue();
        assertThat(BackdropWebPlaybackPolicy.isWebPlayable("av1")).isTrue();
        assertThat(BackdropWebPlaybackPolicy.isWebPlayable("vp9")).isTrue();
        assertThat(BackdropWebPlaybackPolicy.isWebPlayable("H264")).isTrue();
        assertThat(BackdropWebPlaybackPolicy.isWebPlayable(" vp8 ")).isTrue();
    }

    @Test
    @DisplayName("HEVC 等浏览器不保证支持的编码判为不可播")
    void rejectsCodecsWithoutBrowserSupport() {
        assertThat(BackdropWebPlaybackPolicy.isWebPlayable("hevc")).isFalse();
        assertThat(BackdropWebPlaybackPolicy.isWebPlayable("h265")).isFalse();
        assertThat(BackdropWebPlaybackPolicy.isWebPlayable("mpeg4")).isFalse();
        assertThat(BackdropWebPlaybackPolicy.isWebPlayable("vc1")).isFalse();
    }

    @Test
    @DisplayName("探测失败时按可播处理，避免误报")
    void treatsUnknownCodecAsPlayable() {
        assertThat(BackdropWebPlaybackPolicy.isWebPlayable(null)).isTrue();
        assertThat(BackdropWebPlaybackPolicy.isWebPlayable("")).isTrue();
        assertThat(BackdropWebPlaybackPolicy.isWebPlayable("   ")).isTrue();
    }
}
