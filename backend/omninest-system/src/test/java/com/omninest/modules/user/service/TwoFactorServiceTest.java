package com.omninest.modules.user.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatCode;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyList;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import com.omninest.common.error.BusinessException;
import com.omninest.modules.user.domain.AuthBackupCode;
import com.omninest.modules.user.domain.AuthTotpCredential;
import com.omninest.modules.user.domain.AuthUser;
import com.omninest.modules.user.repository.AuthBackupCodeRepository;
import com.omninest.modules.user.repository.AuthTotpCredentialRepository;
import com.omninest.modules.user.repository.AuthUserRepository;
import com.omninest.modules.user.util.TotpUtil;
import java.time.Instant;
import java.util.List;
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

    private TwoFactorService service;
    private AuthUser user;
    private UUID userId;

    @BeforeEach
    void setUp() {
        service = new TwoFactorService(
                totpCredentialRepository,
                backupCodeRepository,
                authUserRepository,
                passwordEncoder
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
        assertThat(captor.getValue().getSecret()).isEqualTo(response.secret());
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
        assertThat(captor.getValue())
                .allSatisfy(code -> assertThat(code.getCodeHash()).hasSize(64));
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
        stored.setCodeHash(sha256Hex("ABCD2345"));
        when(backupCodeRepository.findByUserIdAndUsedAtIsNull(userId)).thenReturn(List.of(stored));
        when(backupCodeRepository.save(any(AuthBackupCode.class)))
                .thenAnswer(invocation -> invocation.getArgument(0));

        assertThatCode(() -> service.verifyCode(userId, "abcd-2345")).doesNotThrowAnyException();
        assertThat(stored.getUsedAt()).isNotNull();

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
        assertThat(captor.getValue().getSecret()).isEqualTo(secret);
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
    @DisplayName("关闭：密码复核通过后清除全部凭据与备份码")
    void disableRemovesAllCredentials() {
        service.disable(userId, "secret123");

        verify(totpCredentialRepository).deleteByUserId(userId);
        verify(backupCodeRepository).deleteByUserId(userId);
    }

    @Test
    @DisplayName("关闭：密码错误被拒绝")
    void disableRejectsWrongPassword() {
        assertThatThrownBy(() -> service.disable(userId, "wrong-pass"))
                .isInstanceOf(BusinessException.class)
                .hasMessageContaining("密码错误");
        verify(totpCredentialRepository, never()).deleteByUserId(any());
    }

    private AuthTotpCredential pendingCredential(String secret) {
        AuthTotpCredential credential = new AuthTotpCredential();
        credential.setId(UUID.randomUUID());
        credential.setUserId(userId);
        credential.setSecret(secret);
        credential.setEnabled(false);
        return credential;
    }

    private static String sha256Hex(String value) {
        try {
            byte[] bytes = java.security.MessageDigest.getInstance("SHA-256")
                    .digest(value.getBytes(java.nio.charset.StandardCharsets.UTF_8));
            StringBuilder builder = new StringBuilder(bytes.length * 2);
            for (byte b : bytes) {
                builder.append(Character.forDigit((b >> 4) & 0xF, 16));
                builder.append(Character.forDigit(b & 0xF, 16));
            }
            return builder.toString();
        } catch (java.security.NoSuchAlgorithmException exception) {
            throw new IllegalStateException(exception);
        }
    }
}
