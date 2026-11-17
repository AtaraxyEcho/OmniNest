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
        // 篡改签名段的第一个字符；末尾字符可能是 base64 填充位，改动后仍解码成同一字节，
        // 会让断言偶发通过。
        int signatureStart = issued.token().indexOf('.') + 1;
        char replacement = issued.token().charAt(signatureStart) == 'A' ? 'B' : 'A';
        String tampered = issued.token().substring(0, signatureStart)
                + replacement
                + issued.token().substring(signatureStart + 1);

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
