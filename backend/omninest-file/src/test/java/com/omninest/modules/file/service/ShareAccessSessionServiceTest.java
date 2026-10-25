package com.omninest.modules.file.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import com.omninest.common.enums.ErrorCode;
import com.omninest.common.error.BusinessException;
import java.time.Instant;
import org.junit.jupiter.api.Test;

/**
 * 分享访问会话无状态令牌测试。
 *
 * @author OmniNest
 */
class ShareAccessSessionServiceTest {

    private static final String SECRET = "test-share-session-secret-at-least-32-bytes";
    private final ShareAccessSessionService service = new ShareAccessSessionService(SECRET);

    @Test
    void sessionIsVerifiableByAnotherInstanceWithTheSameSecret() {
        var issued = service.issue("hash-1", "FILE", null);
        var otherNode = new ShareAccessSessionService(SECRET);

        otherNode.require(issued.token(), "hash-1", "FILE");

        assertThat(issued.expiresAt()).isAfter(Instant.now());
    }

    @Test
    void mismatchDoesNotInvalidateTheOriginalSession() {
        var issued = service.issue("hash-1", "FILE", null);

        assertThatThrownBy(() -> service.require(issued.token(), "hash-2", "FILE"))
                .isInstanceOf(BusinessException.class)
                .satisfies(exception -> assertThat(((BusinessException) exception).errorCode())
                        .isEqualTo(ErrorCode.UNAUTHORIZED));
        // 错误请求只返回失败，不得让原持有者的合法会话失效。
        service.require(issued.token(), "hash-1", "FILE");
    }

    @Test
    void rejectsTamperedSignatureAndWrongResourceType() {
        var issued = service.issue("hash-1", "FILE", null);
        int last = issued.token().length() - 1;
        String tampered = issued.token().substring(0, last)
                + (issued.token().charAt(last) == 'A' ? 'B' : 'A');

        assertThatThrownBy(() -> service.require(tampered, "hash-1", "FILE"))
                .isInstanceOf(BusinessException.class);
        assertThatThrownBy(() -> service.require(issued.token(), "hash-1", "FOLDER"))
                .isInstanceOf(BusinessException.class);
    }

    @Test
    void rejectsSessionForExpiredLink() {
        assertThatThrownBy(() -> service.issue("hash-1", "FILE", Instant.now().minusSeconds(1)))
                .isInstanceOf(BusinessException.class)
                .satisfies(exception -> assertThat(((BusinessException) exception).errorCode())
                        .isEqualTo(ErrorCode.BAD_REQUEST));
    }
}
