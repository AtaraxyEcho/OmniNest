package com.omninest.modules.music.service;

import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.junit.jupiter.api.Assertions.assertDoesNotThrow;

import com.omninest.common.enums.ErrorCode;
import com.omninest.common.error.BusinessException;
import com.omninest.common.security.SafeUrlValidator;
import java.net.InetAddress;
import java.net.URI;
import java.net.UnknownHostException;
import java.util.List;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.mockito.Mockito;

/**
 * 在线音乐播放源信任策略测试。
 *
 * @author OmniNest
 */
class MusicOnlineSourceUrlPolicyTest {
    private final SafeUrlValidator safeUrlValidator = Mockito.mock(SafeUrlValidator.class);
    private final MusicRuntimeConfigService configService = Mockito.mock(MusicRuntimeConfigService.class);
    private final MusicHostAddressResolver hostAddressResolver = Mockito.mock(MusicHostAddressResolver.class);
    private final MusicOnlineSourceUrlPolicy policy = new MusicOnlineSourceUrlPolicy(
            safeUrlValidator,
            configService,
            hostAddressResolver
    );

    @BeforeEach
    void setUp() throws UnknownHostException {
        Mockito.when(configService.trustedPlatformUrls("netease")).thenReturn(List.of(
                "http://192.168.1.206:9090/api",
                "http://localhost:3001"
        ));
        Mockito.when(configService.trustedPlaybackHostSuffixes("netease"))
                .thenReturn(List.of("music.126.net", "music.163.com"));
        Mockito.when(configService.trustedPlatformUrls("legacy")).thenReturn(List.of());
        Mockito.when(configService.trustedPlaybackHostSuffixes("legacy"))
                .thenReturn(List.of("legacy-music-cdn.example.com"));
        Mockito.when(hostAddressResolver.resolve(Mockito.anyString()))
                .thenReturn(addresses("192.168.1.206"));
    }

    @Test
    void allowsPrivateAddressWhenOriginMatchesConfiguredPlatform() {
        URI source = URI.create(
                "http://192.168.1.206:9090/api/v1/music/stream?token=temporary"
        );
        rejectAsPrivate(source);

        assertDoesNotThrow(() -> policy.requireAllowed("netease", source));

        Mockito.verify(safeUrlValidator).requireSafeHttpUrl(source.toString());
    }

    @Test
    void allowsLoopbackWhenOriginMatchesConfiguredPlatform() {
        URI source = URI.create("http://localhost:3001/song/url?id=1");
        rejectAsPrivate(source);

        assertDoesNotThrow(() -> policy.requireAllowed("netease", source));

        Mockito.verify(safeUrlValidator).requireSafeHttpUrl(source.toString());
    }

    @Test
    void delegatesPublicAddressToCommonSsrfValidator() {
        URI source = URI.create("https://cdn.example.com/audio/song.mp3");

        assertDoesNotThrow(() -> policy.requireAllowed("netease", source));

        Mockito.verify(safeUrlValidator).requireSafeHttpUrl(source.toString());
    }

    @Test
    void rejectsPrivateAddressWhenConfiguredPortDoesNotMatch() {
        URI source = URI.create("http://192.168.1.206:9091/audio/song.mp3");
        rejectAsPrivate(source);

        assertThatThrownBy(() -> policy.requireAllowed("netease", source))
                .isInstanceOf(BusinessException.class)
                .hasMessageContaining("内网地址");
    }

    @Test
    void allowsOfficialNeteaseCdnWhenProxyReturnsFakeIpv4AndUla() throws UnknownHostException {
        URI source = URI.create("http://m701.music.126.net/audio/song.mp3");
        rejectAsPrivate(source);
        Mockito.when(hostAddressResolver.resolve("m701.music.126.net"))
                .thenReturn(addresses("198.18.0.122", "fdfe:dcba:9876::69"));

        assertDoesNotThrow(() -> policy.requireAllowed("netease", source));
    }

    @Test
    void rejectsOfficialCdnWhenSourcePlatformDoesNotMatch() throws UnknownHostException {
        URI source = URI.create("http://m701.music.126.net/audio/song.mp3");
        rejectAsPrivate(source);
        Mockito.when(hostAddressResolver.resolve("m701.music.126.net"))
                .thenReturn(addresses("198.18.0.122", "fdfe:dcba:9876::69"));

        assertThatThrownBy(() -> policy.requireAllowed("legacy", source))
                .isInstanceOf(BusinessException.class)
                .hasMessageContaining("内网地址");
    }

    @Test
    void rejectsFakeIpResolutionWhenItAlsoContainsPrivateIpv4() throws UnknownHostException {
        URI source = URI.create("http://m701.music.126.net/audio/song.mp3");
        rejectAsPrivate(source);
        Mockito.when(hostAddressResolver.resolve("m701.music.126.net"))
                .thenReturn(addresses("198.18.0.122", "192.168.1.8"));

        assertThatThrownBy(() -> policy.requireAllowed("netease", source))
                .isInstanceOf(BusinessException.class)
                .hasMessageContaining("内网地址");
    }

    @Test
    void rejectsOfficialCdnWhenResolutionOnlyContainsUla() throws UnknownHostException {
        URI source = URI.create("http://m701.music.126.net/audio/song.mp3");
        rejectAsPrivate(source);
        Mockito.when(hostAddressResolver.resolve("m701.music.126.net"))
                .thenReturn(addresses("fdfe:dcba:9876::69"));

        assertThatThrownBy(() -> policy.requireAllowed("netease", source))
                .isInstanceOf(BusinessException.class)
                .hasMessageContaining("内网地址");
    }

    @Test
    void rejectsMetadataEndpointEvenWhenConfiguredAsPlatformOrigin() {
        Mockito.when(configService.trustedPlatformUrls("netease"))
                .thenReturn(List.of("http://169.254.169.254"));

        assertThatThrownBy(() -> policy.requireAllowed("netease",
                URI.create("http://169.254.169.254/latest/meta-data/")
        ))
                .isInstanceOf(BusinessException.class)
                .hasMessageContaining("元数据服务");
    }

    @Test
    void rejectsCredentialsBeforeTrustedOriginMatching() {
        assertThatThrownBy(() -> policy.requireAllowed("netease",
                URI.create("http://user:password@192.168.1.206:9090/audio")
        ))
                .isInstanceOf(BusinessException.class)
                .hasMessageContaining("用户信息");
    }

    private void rejectAsPrivate(URI source) {
        Mockito.doThrow(new BusinessException(ErrorCode.BAD_REQUEST, "URL 不能指向本地或内网地址"))
                .when(safeUrlValidator)
                .requireSafeHttpUrl(source.toString());
    }

    private InetAddress[] addresses(String... values) throws UnknownHostException {
        InetAddress[] addresses = new InetAddress[values.length];
        for (int index = 0; index < values.length; index++) {
            addresses[index] = InetAddress.getByName(values[index]);
        }
        return addresses;
    }
}
