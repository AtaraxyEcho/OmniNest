package com.omninest.modules.file.service;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNotEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;

import com.omninest.common.error.BusinessException;
import java.time.Duration;
import java.time.Instant;
import java.util.UUID;
import org.junit.jupiter.api.Test;

/**
 * 本地内容短期访问令牌测试。
 *
 * @author OmniNest
 */
class LocalContentAccessTokenServiceTest {

    private static final String SECRET = "test-local-content-secret-at-least-32-bytes";
    private final LocalContentAccessTokenService service = new LocalContentAccessTokenService(SECRET);

    @Test
    void shouldIssueFileScopedRandomTokens() {
        UUID ownerUserId = UUID.randomUUID();
        UUID fileId = UUID.randomUUID();

        LocalContentAccessTokenService.IssuedAccess first = service.issue(ownerUserId, fileId);
        LocalContentAccessTokenService.IssuedAccess second = service.issue(ownerUserId, fileId);

        assertNotEquals(first.token(), second.token());
        LocalContentAccessTokenService.AccessGrant grant = service.requireGrant(first.token());
        assertEquals(ownerUserId, grant.ownerUserId());
        assertEquals(fileId, grant.fileId());
        // 注释约定 2 小时；15 分钟会让长视频播放中的后续 Range 请求 403。
        assertTrue(first.expiresAt().isAfter(Instant.now().plus(Duration.ofMinutes(119))));
    }

    @Test
    void shouldRejectUnknownAndTamperedTokens() {
        UUID ownerUserId = UUID.randomUUID();
        UUID fileId = UUID.randomUUID();
        String token = service.issue(ownerUserId, fileId).token();
        String replaced = token.substring(0, token.length() - 2)
                + (token.endsWith("A") ? "B" : "A")
                + token.charAt(token.length() - 1);

        assertThrows(BusinessException.class, () -> service.requireGrant("unknown"));
        assertThrows(BusinessException.class, () -> service.requireGrant(replaced));
    }

    @Test
    void tokenIsVerifiableByAnotherInstanceWithTheSameSecret() {
        UUID ownerUserId = UUID.randomUUID();
        UUID fileId = UUID.randomUUID();
        String token = service.issue(ownerUserId, fileId).token();

        LocalContentAccessTokenService otherNode = new LocalContentAccessTokenService(SECRET);

        LocalContentAccessTokenService.AccessGrant grant = otherNode.requireGrant(token);
        assertEquals(ownerUserId, grant.ownerUserId());
        assertEquals(fileId, grant.fileId());
    }

    @Test
    void tokenFromDifferentSecretIsRejected() {
        String token = service.issue(UUID.randomUUID(), UUID.randomUUID()).token();
        LocalContentAccessTokenService otherNode =
                new LocalContentAccessTokenService("another-secret-at-least-32-bytes-long");

        assertThrows(BusinessException.class, () -> otherNode.requireGrant(token));
    }
}
