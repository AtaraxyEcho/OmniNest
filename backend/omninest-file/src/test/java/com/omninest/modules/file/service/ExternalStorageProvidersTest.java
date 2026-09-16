package com.omninest.modules.file.service;

import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.assertj.core.api.Assertions.assertThatCode;

import com.omninest.common.enums.ErrorCode;
import com.omninest.common.error.BusinessException;
import org.junit.jupiter.api.Test;

/**
 * 外部存储 Provider 白名单测试。
 */
class ExternalStorageProvidersTest {

    @Test
    void allowsRemoteProviders() {
        assertThatCode(() -> ExternalStorageProviders.requireAllowed("webdav"))
                .doesNotThrowAnyException();
        assertThatCode(() -> ExternalStorageProviders.requireAllowed("S3"))
                .doesNotThrowAnyException();
        assertThatCode(() -> ExternalStorageProviders.requireAllowed("QUARK"))
                .doesNotThrowAnyException();
        assertThatCode(() -> ExternalStorageProviders.requireAllowed("BAIDU"))
                .doesNotThrowAnyException();
    }

    @Test
    void rejectsLocalAndSmb() {
        assertThatThrownBy(() -> ExternalStorageProviders.requireAllowed("LOCAL"))
                .isInstanceOf(BusinessException.class)
                .extracting(exception -> ((BusinessException) exception).errorCode())
                .isEqualTo(ErrorCode.PARAM_ERROR);
        assertThatThrownBy(() -> ExternalStorageProviders.requireAllowed("SMB"))
                .isInstanceOf(BusinessException.class);
    }

    @Test
    void rejectsUnknownProvider() {
        assertThatThrownBy(() -> ExternalStorageProviders.requireAllowed("FTP"))
                .isInstanceOf(BusinessException.class);
    }
}
