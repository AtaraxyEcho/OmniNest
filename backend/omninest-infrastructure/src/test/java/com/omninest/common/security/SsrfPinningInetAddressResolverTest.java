package com.omninest.common.security;

import static org.assertj.core.api.Assertions.assertThat;

import java.net.InetAddress;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.Test;

/**
 * SSRF 公网地址钉死解析器测试。
 *
 * <p>JEP 418 的解析器由 JVM 在启动时通过 ServiceLoader 装载，测试直接走
 * {@link InetAddress#getAllByName}，同时验证服务注册文件确实生效。</p>
 *
 * @author OmniNest
 */
class SsrfPinningInetAddressResolverTest {

    private static final String PINNED_HOST = "omninest-pin-test.invalid";

    @AfterEach
    void clearPins() {
        SsrfSafeUrlValidator.clearPinnedHostsForTest();
    }

    @Test
    void pinnedHostResolvesToVerifiedAddressThroughJvmResolver() throws Exception {
        InetAddress pinned = InetAddress.getByAddress(
                PINNED_HOST, new byte[] {93, (byte) 184, (byte) 216, 34});
        SsrfSafeUrlValidator.pinVerifiedHost(PINNED_HOST, new InetAddress[] {pinned});

        assertThat(InetAddress.getAllByName(PINNED_HOST)).containsExactly(pinned);
    }

    @Test
    void unpinnedHostStillUsesBuiltinResolver() throws Exception {
        // localhost 不在钉死表里：必须由内置解析器返回环回地址，证明委托链路没有被拦截。
        assertThat(InetAddress.getAllByName("localhost")).allMatch(InetAddress::isLoopbackAddress);
    }
}
