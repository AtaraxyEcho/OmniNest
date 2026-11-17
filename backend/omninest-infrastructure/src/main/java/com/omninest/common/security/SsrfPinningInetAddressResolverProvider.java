package com.omninest.common.security;

import java.net.InetAddress;
import java.net.UnknownHostException;
import java.net.spi.InetAddressResolver;
import java.net.spi.InetAddressResolverProvider;
import java.util.Arrays;
import java.util.stream.Stream;

/**
 * JDK 25（JEP 418）全局 DNS 解析守卫。
 *
 * <p>对刚通过 {@link SsrfSafeUrlValidator} 公网校验的域名直接返回已验证 IP，
 * 消除校验与连接之间的二次解析窗口；未登记的主机原样交给 JVM 内置解析器，
 * 容器内 service name 解析不受影响。</p>
 *
 * @author OmniNest
 */
public final class SsrfPinningInetAddressResolverProvider extends InetAddressResolverProvider {

    @Override
    public InetAddressResolver get(Configuration configuration) {
        InetAddressResolver builtin = configuration.builtinResolver();
        return new InetAddressResolver() {
            @Override
            public Stream<InetAddress> lookupByName(String host, LookupPolicy lookupPolicy)
                    throws UnknownHostException {
                var pinned = SsrfSafeUrlValidator.findPinnedPublicAddresses(host);
                if (pinned.isPresent()) {
                    return Arrays.stream(pinned.get());
                }
                return builtin.lookupByName(host, lookupPolicy);
            }

            @Override
            public String lookupByAddress(byte[] addr) throws UnknownHostException {
                return builtin.lookupByAddress(addr);
            }
        };
    }

    @Override
    public String name() {
        return "omninest-ssrf-pinning-dns-resolver";
    }
}
