package com.omninest.common.security;

import com.omninest.common.config.SecurityProperties;
import java.net.Inet6Address;
import java.net.InetAddress;
import java.net.UnknownHostException;
import java.util.ArrayList;
import java.util.List;
import java.util.Optional;
import java.util.StringJoiner;
import org.springframework.security.web.util.matcher.IpAddressMatcher;
import org.springframework.stereotype.Component;

/**
 * 只在直接连接来自可信代理时解析转发头。
 *
 * @author OmniNest
 */
@Component
public class TrustedProxyClientIpResolver implements ClientIpResolver {
    private static final int MAX_FORWARDED_FOR_LENGTH = 2048;
    private static final int MAX_PROXY_HOPS = 32;
    private static final String UNKNOWN_ADDRESS = "unknown";

    private final List<IpAddressMatcher> trustedProxies;

    /**
     * 根据安全配置构建可信代理匹配器。
     *
     * @param securityProperties 安全配置
     */
    public TrustedProxyClientIpResolver(SecurityProperties securityProperties) {
        List<String> configuredProxies = securityProperties.getTrustedProxies();
        if (configuredProxies == null) {
            this.trustedProxies = List.of();
            return;
        }
        this.trustedProxies = configuredProxies.stream()
                .map(String::trim)
                .filter(value -> !value.isEmpty())
                .map(IpAddressMatcher::new)
                .toList();
    }

    /**
     * {@inheritDoc}
     */
    @Override
    public String resolve(String remoteAddress, String forwardedFor, String realIp) {
        String directPeer = normalizeIp(remoteAddress).orElse(UNKNOWN_ADDRESS);
        if (!isTrustedProxy(directPeer)) {
            return directPeer;
        }
        if (forwardedFor != null && !forwardedFor.isBlank()) {
            Optional<List<String>> chain = parseForwardedFor(forwardedFor);
            if (chain.isEmpty()) {
                return directPeer;
            }
            List<String> addresses = chain.get();
            for (int index = addresses.size() - 1; index >= 0; index--) {
                String candidate = addresses.get(index);
                if (!isTrustedProxy(candidate)) {
                    return candidate;
                }
            }
            return addresses.getFirst();
        }
        return normalizeIp(realIp).orElse(directPeer);
    }

    private Optional<List<String>> parseForwardedFor(String forwardedFor) {
        if (forwardedFor.length() > MAX_FORWARDED_FOR_LENGTH) {
            return Optional.empty();
        }
        String[] rawAddresses = forwardedFor.split(",", -1);
        if (rawAddresses.length == 0 || rawAddresses.length > MAX_PROXY_HOPS) {
            return Optional.empty();
        }
        List<String> addresses = new ArrayList<>(rawAddresses.length);
        for (String rawAddress : rawAddresses) {
            Optional<String> normalized = normalizeIp(rawAddress);
            if (normalized.isEmpty()) {
                return Optional.empty();
            }
            addresses.add(normalized.get());
        }
        return Optional.of(List.copyOf(addresses));
    }

    private Optional<String> normalizeIp(String rawAddress) {
        if (rawAddress == null || rawAddress.isBlank()) {
            return Optional.empty();
        }
        String candidate = rawAddress.trim();
        if (candidate.length() >= 2 && candidate.startsWith("\"") && candidate.endsWith("\"")) {
            candidate = candidate.substring(1, candidate.length() - 1).trim();
        }
        if (candidate.startsWith("[")) {
            int closingBracket = candidate.indexOf(']');
            if (closingBracket < 0) {
                return Optional.empty();
            }
            candidate = candidate.substring(1, closingBracket);
        } else if (candidate.indexOf(':') == candidate.lastIndexOf(':') && candidate.contains(".")) {
            int portSeparator = candidate.lastIndexOf(':');
            if (portSeparator > 0) {
                candidate = candidate.substring(0, portSeparator);
            }
        }
        if (candidate.contains("%")) {
            return Optional.empty();
        }
        return candidate.contains(":") ? normalizeIpv6(candidate) : normalizeIpv4(candidate);
    }

    private Optional<String> normalizeIpv4(String candidate) {
        String[] parts = candidate.split("\\.", -1);
        if (parts.length != 4) {
            return Optional.empty();
        }
        StringJoiner normalized = new StringJoiner(".");
        for (String part : parts) {
            if (part.isEmpty() || !part.chars().allMatch(Character::isDigit)) {
                return Optional.empty();
            }
            try {
                int value = Integer.parseInt(part);
                if (value < 0 || value > 255) {
                    return Optional.empty();
                }
                normalized.add(Integer.toString(value));
            } catch (NumberFormatException exception) {
                return Optional.empty();
            }
        }
        return Optional.of(normalized.toString());
    }

    private Optional<String> normalizeIpv6(String candidate) {
        if (!candidate.matches("[0-9A-Fa-f:.]+")) {
            return Optional.empty();
        }
        try {
            InetAddress address = InetAddress.getByName(candidate);
            if (address instanceof Inet6Address) {
                return Optional.of(address.getHostAddress());
            }
        } catch (UnknownHostException exception) {
            return Optional.empty();
        }
        return Optional.empty();
    }

    private boolean isTrustedProxy(String address) {
        if (UNKNOWN_ADDRESS.equals(address)) {
            return false;
        }
        return trustedProxies.stream().anyMatch(matcher -> matcher.matches(address));
    }
}
