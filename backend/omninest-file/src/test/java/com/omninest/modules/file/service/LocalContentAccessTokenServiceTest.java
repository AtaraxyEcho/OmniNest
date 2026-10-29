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
        // 旧写法按末尾字符挑替换值，若该位本就是 'A'/'B' 就改成原值：
        // 令牌没变自然验签通过，这条用例约 1/64 概率假失败。
        char[] tampered = token.toCharArray();
        int signatureStart = token.indexOf('.');
        int index = signatureStart > 0 ? signatureStart - 1 : tampered.length - 1;
        tampered[index] = tampered[index] == 'A' ? 'B' : 'A';
        String replaced = new String(tampered);
        assertNotEquals(token, replaced);

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
