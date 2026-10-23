package com.omninest.modules.user.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatCode;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyList;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import com.omninest.common.enums.ErrorCode;
import com.omninest.common.error.BusinessException;
import com.omninest.common.security.CredentialCipher;
import com.omninest.common.security.PayloadAuthenticator;
import com.omninest.modules.user.domain.AuthBackupCode;
import com.omninest.modules.user.domain.AuthTotpCredential;
import com.omninest.modules.user.domain.AuthUser;
import com.omninest.modules.user.repository.AuthBackupCodeRepository;
import com.omninest.modules.user.repository.AuthTotpCredentialRepository;
import com.omninest.modules.user.repository.AuthUserRepository;
import com.omninest.modules.user.util.TotpUtil;
import java.time.Instant;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.UUID;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;
import org.springframework.security.crypto.bcrypt.BCryptPasswordEncoder;

/**
 * 两步验证凭据服务测试。
 *
 * @author OmniNest
 */
class TwoFactorServiceTest {

    private final AuthTotpCredentialRepository totpCredentialRepository = mock(AuthTotpCredentialRepository.class);
    private final AuthBackupCodeRepository backupCodeRepository = mock(AuthBackupCodeRepository.class);
    private final AuthUserRepository authUserRepository = mock(AuthUserRepository.class);
    private final BCryptPasswordEncoder passwordEncoder = new BCryptPasswordEncoder();
    private final RecordingCredentialCipher credentialCipher = new RecordingCredentialCipher();
    private final PrefixPayloadAuthenticator payloadAuthenticator = new PrefixPayloadAuthenticator();

    private TwoFactorService service;
    private AuthUser user;
    private UUID userId;

    @BeforeEach
    void setUp() {
        service = new TwoFactorService(
                totpCredentialRepository,
                backupCodeRepository,
                authUserRepository,
                passwordEncoder,
                credentialCipher,
                payloadAuthenticator
        );
        userId = UUID.randomUUID();
        user = new AuthUser();
        user.setId(userId);
        user.setUsername("admin");
        user.setPasswordHash(passwordEncoder.encode("secret123"));
        user.setStatus("ACTIVE");
        when(authUserRepository.findById(userId)).thenReturn(Optional.of(user));
        when(totpCredentialRepository.existsByUserIdAndEnabledTrue(userId)).thenReturn(false);
        when(totpCredentialRepository.findByUserId(userId)).thenReturn(Optional.empty());
    }

    @Test
    @DisplayName("生成秘钥：密码复核通过后写入未确认凭据并返回 otpauth URI")
    void startSetupCreatesPendingCredential() {
        when(totpCredentialRepository.save(any(AuthTotpCredential.class)))
                .thenAnswer(invocation -> invocation.getArgument(0));

        var response = service.startSetup(userId, "secret123");

        assertThat(response.secret()).hasSize(32).matches("[A-Z2-7]+");
        assertThat(response.otpauthUri())
                .startsWith("otpauth://totp/")
                .contains("secret=" + response.secret())
                .contains("admin");
        ArgumentCaptor<AuthTotpCredential> captor = ArgumentCaptor.forClass(AuthTotpCredential.class);
        verify(totpCredentialRepository).save(captor.capture());
        assertThat(captor.getValue().isEnabled()).isFalse();
        assertThat(captor.getValue().getUserId()).isEqualTo(userId);
        assertThat(captor.getValue().getSecret()).isNotEqualTo(response.secret());
        assertThat(credentialCipher.decrypt(captor.getValue().getSecret())).isEqualTo(response.secret());
    }

    @Test
    @DisplayName("生成秘钥：密码错误被拒绝")
    void startSetupRejectsWrongPassword() {
        assertThatThrownBy(() -> service.startSetup(userId, "wrong-pass"))
                .isInstanceOf(BusinessException.class)
                .hasMessageContaining("密码错误");
        verify(totpCredentialRepository, never()).save(any());
    }

    @Test
    @DisplayName("生成秘钥：已开启时拒绝重复开启")
    void startSetupRejectsWhenAlreadyEnabled() {
        when(totpCredentialRepository.existsByUserIdAndEnabledTrue(userId)).thenReturn(true);

        assertThatThrownBy(() -> service.startSetup(userId, "secret123"))
                .isInstanceOf(BusinessException.class)
                .hasMessageContaining("两步验证已开启");
    }

    @Test
    @DisplayName("确认启用：验证码正确时启用凭据并重置 10 组备份码")
    void enableConfirmsCredentialAndResetsBackupCodes() {
        String secret = TotpUtil.generateSecret();
        AuthTotpCredential credential = pendingCredential(secret);
        when(totpCredentialRepository.findByUserId(userId)).thenReturn(Optional.of(credential));
        when(totpCredentialRepository.save(any(AuthTotpCredential.class)))
                .thenAnswer(invocation -> invocation.getArgument(0));
        when(backupCodeRepository.saveAll(anyList()))
                .thenAnswer(invocation -> invocation.getArgument(0));

        List<String> backupCodes = service.enable(userId, TotpUtil.currentCode(secret, Instant.now()));

        assertThat(backupCodes).hasSize(TwoFactorService.BACKUP_CODE_COUNT);
        assertThat(backupCodes).allMatch(code -> code.matches("[A-Z0-9]{4}-[A-Z0-9]{4}"));
        assertThat(credential.isEnabled()).isTrue();
        assertThat(credential.getConfirmedAt()).isNotNull();
        verify(backupCodeRepository).deleteByUserId(userId);
        @SuppressWarnings("unchecked")
        ArgumentCaptor<List<AuthBackupCode>> captor = ArgumentCaptor.forClass((Class) List.class);
        verify(backupCodeRepository).saveAll(captor.capture());
        assertThat(captor.getValue()).hasSize(TwoFactorService.BACKUP_CODE_COUNT);
        for (int index = 0; index < backupCodes.size(); index++) {
            String compact = backupCodes.get(index).replace("-", "");
            assertThat(captor.getValue().get(index).getCodeHash())
                    .startsWith("mac-")
                    .isNotEqualTo(compact)
                    .isNotEqualTo(backupCodes.get(index));
        }
    }

    @Test
    @DisplayName("确认启用：验证码错误时保持未确认")
    void enableRejectsWrongCode() {
        String secret = TotpUtil.generateSecret();
        AuthTotpCredential credential = pendingCredential(secret);
        when(totpCredentialRepository.findByUserId(userId)).thenReturn(Optional.of(credential));
        String futureCode = TotpUtil.currentCode(secret, Instant.now().plusSeconds(600));

        assertThatThrownBy(() -> service.enable(userId, futureCode))
                .isInstanceOf(BusinessException.class)
                .hasMessageContaining("两步验证码错误");
        assertThat(credential.isEnabled()).isFalse();
        verify(backupCodeRepository, never()).saveAll(anyList());
    }

    @Test
    @DisplayName("确认启用：没有待确认凭据时提示先生成秘钥")
    void enableRejectsWithoutPendingCredential() {
        assertThatThrownBy(() -> service.enable(userId, "123456"))
                .isInstanceOf(BusinessException.class)
                .hasMessageContaining("请先生成两步验证秘钥");
    }

    @Test
    @DisplayName("登录验证：TOTP 命中后同一验证码不可重放")
    void verifyCodeRejectsTotpReplay() {
        String secret = TotpUtil.generateSecret();
        AuthTotpCredential credential = pendingCredential(secret);
        credential.setEnabled(true);
        credential.setLastUsedStep(null);
        when(totpCredentialRepository.findByUserIdAndEnabledTrue(userId)).thenReturn(Optional.of(credential));
        when(totpCredentialRepository.save(any(AuthTotpCredential.class)))
                .thenAnswer(invocation -> invocation.getArgument(0));

        String code = TotpUtil.currentCode(secret, Instant.now());
        assertThatCode(() -> service.verifyCode(userId, code)).doesNotThrowAnyException();

        assertThatThrownBy(() -> service.verifyCode(userId, code))
                .isInstanceOf(BusinessException.class)
                .hasMessageContaining("两步验证码错误");
        assertThat(credential.getLastUsedStep()).isNotNull();
    }

    @Test
    @DisplayName("登录验证：备份码可用且一次性")
    void verifyCodeConsumesBackupCodeExactlyOnce() {
        String secret = TotpUtil.generateSecret();
        AuthTotpCredential credential = pendingCredential(secret);
        credential.setEnabled(true);
        credential.setLastUsedStep(Long.MAX_VALUE / 2);
        when(totpCredentialRepository.findByUserIdAndEnabledTrue(userId)).thenReturn(Optional.of(credential));
        AuthBackupCode stored = new AuthBackupCode();
        stored.setId(UUID.randomUUID());
        stored.setUserId(userId);
        stored.setCodeHash(payloadAuthenticator.sign("ABCD2345"));
        when(backupCodeRepository.findByUserIdAndUsedAtIsNull(userId)).thenReturn(List.of(stored));
        when(backupCodeRepository.consume(eq(stored.getId()), any(Instant.class))).thenReturn(1);

        assertThatCode(() -> service.verifyCode(userId, "abcd-2345")).doesNotThrowAnyException();
        verify(backupCodeRepository).consume(eq(stored.getId()), any(Instant.class));

        when(backupCodeRepository.findByUserIdAndUsedAtIsNull(userId)).thenReturn(List.of());
        assertThatThrownBy(() -> service.verifyCode(userId, "abcd-2345"))
                .isInstanceOf(BusinessException.class)
                .hasMessageContaining("两步验证码错误");
    }

    @Test
    @DisplayName("登录验证：未启用时提示未配置")
    void verifyCodeRejectsWhenNotEnabled() {
        when(totpCredentialRepository.findByUserIdAndEnabledTrue(userId)).thenReturn(Optional.empty());

        assertThatThrownBy(() -> service.verifyCode(userId, "123456"))
                .isInstanceOf(BusinessException.class)
                .hasMessageContaining("两步验证未配置");
    }

    @Test
    @DisplayName("登录验证：秘钥密文不可解密时拒绝，不把库内字符串当明文秘钥用")
    void verifyCodeRejectsUndecryptableSecret() {
        String legacyPlainSecret = TotpUtil.generateSecret();
        AuthTotpCredential credential = new AuthTotpCredential();
        credential.setId(UUID.randomUUID());
        credential.setUserId(userId);
        credential.setSecret(legacyPlainSecret);
        credential.setEnabled(true);
        when(totpCredentialRepository.findByUserIdAndEnabledTrue(userId)).thenReturn(Optional.of(credential));

        assertThatThrownBy(() -> service.verifyCode(
                userId, TotpUtil.currentCode(legacyPlainSecret, Instant.now())))
                .isInstanceOf(BusinessException.class)
                .hasMessageContaining("两步验证凭据不可用");
    }

    @Test
    @DisplayName("新用户直落凭据：验证码正确时直接启用并返回备份码")
    void provisionForNewUserConfirmsCredentialDirectly() {
        String secret = TotpUtil.generateSecret();
        when(totpCredentialRepository.findByUserId(userId)).thenReturn(Optional.empty());
        when(totpCredentialRepository.save(any(AuthTotpCredential.class)))
                .thenAnswer(invocation -> invocation.getArgument(0));
        when(backupCodeRepository.saveAll(anyList()))
                .thenAnswer(invocation -> invocation.getArgument(0));

        List<String> backupCodes = service.provisionForNewUser(
                userId, secret, TotpUtil.currentCode(secret, Instant.now()));

        assertThat(backupCodes).hasSize(TwoFactorService.BACKUP_CODE_COUNT);
        ArgumentCaptor<AuthTotpCredential> captor = ArgumentCaptor.forClass(AuthTotpCredential.class);
        verify(totpCredentialRepository).save(captor.capture());
        assertThat(captor.getValue().isEnabled()).isTrue();
        assertThat(captor.getValue().getConfirmedAt()).isNotNull();
        assertThat(captor.getValue().getLastUsedStep()).isNotNull();
        assertThat(captor.getValue().getSecret()).isNotEqualTo(secret);
        assertThat(credentialCipher.decrypt(captor.getValue().getSecret())).isEqualTo(secret);
    }

    @Test
    @DisplayName("新用户直落凭据：低熵或非规范秘钥被拒绝")
    void provisionForNewUserRejectsWeakSecret() {
        assertThatThrownBy(() -> service.provisionForNewUser(userId, "AAAAAAAAAAAAAAAA", "123456"))
                .isInstanceOf(BusinessException.class)
                .hasMessageContaining("长度不足");
        assertThatThrownBy(() -> service.provisionForNewUser(userId, "AAAABBBB!CCCCDDDD", "123456"))
                .isInstanceOf(BusinessException.class)
                .hasMessageContaining("Base32");
        verify(totpCredentialRepository, never()).save(any());
    }

    @Test
    @DisplayName("新用户直落凭据：验证码错误被拒绝")
    void provisionForNewUserRejectsWrongCode() {
        String secret = TotpUtil.generateSecret();
        String futureCode = TotpUtil.currentCode(secret, Instant.now().plusSeconds(600));

        assertThatThrownBy(() -> service.provisionForNewUser(userId, secret, futureCode))
                .isInstanceOf(BusinessException.class)
                .hasMessageContaining("两步验证码错误");
        verify(totpCredentialRepository, never()).save(any());
    }

    @Test
    @DisplayName("新用户直落凭据：缺少秘钥提示先生成")
    void provisionForNewUserRejectsBlankSecret() {
        assertThatThrownBy(() -> service.provisionForNewUser(userId, " ", "123456"))
                .isInstanceOf(BusinessException.class)
                .hasMessageContaining("请先生成两步验证秘钥");
    }

    @Test
    @DisplayName("关闭：密码与验证码复核通过后清除全部凭据与备份码")
    void disableRemovesAllCredentials() {
        String secret = TotpUtil.generateSecret();
        AuthTotpCredential credential = pendingCredential(secret);
        credential.setEnabled(true);
        credential.setLastUsedStep(null);
        when(totpCredentialRepository.findByUserIdAndEnabledTrue(userId)).thenReturn(Optional.of(credential));

        service.disable(userId, "secret123", TotpUtil.currentCode(secret, Instant.now()));

        verify(totpCredentialRepository).deleteByUserId(userId);
        verify(backupCodeRepository).deleteByUserId(userId);
    }

    @Test
    @DisplayName("关闭：密码错误被拒绝")
    void disableRejectsWrongPassword() {
        assertThatThrownBy(() -> service.disable(userId, "wrong-pass", "123456"))
                .isInstanceOf(BusinessException.class)
                .hasMessageContaining("密码错误");
        verify(totpCredentialRepository, never()).deleteByUserId(any());
    }

    @Test
    @DisplayName("关闭：验证码错误被拒绝，不清除凭据")
    void disableRejectsWrongCode() {
        String secret = TotpUtil.generateSecret();
        AuthTotpCredential credential = pendingCredential(secret);
        credential.setEnabled(true);
        when(totpCredentialRepository.findByUserIdAndEnabledTrue(userId)).thenReturn(Optional.of(credential));

        assertThatThrownBy(() -> service.disable(userId, "secret123", "000000"))
                .isInstanceOf(BusinessException.class)
                .hasMessageContaining("两步验证码错误");
        verify(totpCredentialRepository, never()).deleteByUserId(any());
        verify(backupCodeRepository, never()).deleteByUserId(any());
    }

    @Test
    @DisplayName("管理员重置：清除凭据与备份码，不需要密码复核")
    void resetByAdminClearsCredentialsWithoutPassword() {
        service.resetByAdmin(userId);

        verify(totpCredentialRepository).deleteByUserId(userId);
        verify(backupCodeRepository).deleteByUserId(userId);
    }

    @Test
    @DisplayName("管理员重置：用户不存在时不清除任何凭据")
    void resetByAdminRejectsMissingUser() {
        when(authUserRepository.findById(userId)).thenReturn(Optional.empty());

        assertThatThrownBy(() -> service.resetByAdmin(userId))
                .isInstanceOf(BusinessException.class)
                .hasMessageContaining("当前用户不存在");
        verify(totpCredentialRepository, never()).deleteByUserId(any());
        verify(backupCodeRepository, never()).deleteByUserId(any());
    }

    private AuthTotpCredential pendingCredential(String plainSecret) {
        AuthTotpCredential credential = new AuthTotpCredential();
        credential.setId(UUID.randomUUID());
        credential.setUserId(userId);
        credential.setSecret(credentialCipher.encrypt(plainSecret));
        credential.setEnabled(false);
        return credential;
    }

    /**
     * 可逆的凭据加密替身：只认识自己发出过的密文，其余按真实实现的失败口径抛异常。
     */
    private static final class RecordingCredentialCipher implements CredentialCipher {
        private final Map<String, String> plaintextByPayload = new HashMap<>();

        @Override
        public String encrypt(String plaintext) {
            String payload = "v1:" + java.util.UUID.randomUUID();
            plaintextByPayload.put(payload, plaintext);
            return payload;
        }

        @Override
        public String decrypt(String payload) {
            String plaintext = plaintextByPayload.get(payload);
            if (plaintext == null) {
                throw new BusinessException(ErrorCode.CONFIG_VALUE_INVALID, "外部凭据密文格式无效");
            }
            return plaintext;
        }

        @Override
        public int currentKeyVersion() {
            return 1;
        }
    }

    /**
     * 前缀式摘要替身：同一负载稳定，便于断言库内不存明文。
     */
    private static final class PrefixPayloadAuthenticator implements PayloadAuthenticator {

        @Override
        public String sign(String payload) {
            return "mac-" + payload;
        }

        @Override
        public boolean verify(String payload, String signature) {
            return signature != null && signature.equals(sign(payload));
        }
    }
}
