package com.omninest.modules.user.service;

import com.omninest.common.enums.ErrorCode;
import com.omninest.common.error.BusinessException;
import com.omninest.common.security.CredentialCipher;
import com.omninest.common.security.PayloadAuthenticator;
import com.omninest.modules.user.domain.AuthBackupCode;
import com.omninest.modules.user.domain.AuthTotpCredential;
import com.omninest.modules.user.domain.AuthUser;
import com.omninest.modules.user.dto.TwoFactorDtos.TwoFactorSetupResponse;
import com.omninest.modules.user.repository.AuthBackupCodeRepository;
import com.omninest.modules.user.repository.AuthTotpCredentialRepository;
import com.omninest.modules.user.repository.AuthUserRepository;
import com.omninest.modules.user.util.TotpUtil;
import java.security.SecureRandom;
import java.time.Instant;
import java.util.ArrayList;
import java.util.List;
import java.util.Locale;
import java.util.UUID;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * 两步验证（TOTP）凭据服务：注册引导、确认启用、关闭与登录验证码校验。
 *
 * <p>登录挑战令牌的签发与消费由 {@link AuthService} 负责，本服务只管理凭据与验证码。</p>
 *
 * <p>落库形态：TOTP 秘钥经 {@link CredentialCipher} 加密存储，备份码只存
 * {@link PayloadAuthenticator} 的加钥摘要。因此轮换凭据加密密钥会使已注册的
 * 两步验证失效，轮换 JWT 密钥会使已签发的备份码失效，两者都只能重新开启恢复。</p>
 *
 * @author OmniNest
 */
@Slf4j
@Service
@RequiredArgsConstructor
public class TwoFactorService {

    static final int BACKUP_CODE_COUNT = 10;
    private static final String BACKUP_CODE_ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";
    private static final int BACKUP_CODE_LENGTH = 8;
    private static final String OTPAUTH_ISSUER = "OmniNest";
    private static final SecureRandom SECURE_RANDOM = new SecureRandom();

    private final AuthTotpCredentialRepository totpCredentialRepository;
    private final AuthBackupCodeRepository backupCodeRepository;
    private final AuthUserRepository authUserRepository;
    private final PasswordEncoder passwordEncoder;
    private final CredentialCipher credentialCipher;
    private final PayloadAuthenticator payloadAuthenticator;

    /**
     * 生成待确认的 TOTP 秘钥，重复调用会覆盖旧的未确认秘钥。
     *
     * @param userId 用户标识
     * @param password 登录密码（复核防会话劫持后偷偷开启）
     * @return 秘钥与 otpauth URI
     */
    @Transactional(rollbackFor = Exception.class)
    public TwoFactorSetupResponse startSetup(UUID userId, String password) {
        AuthUser user = requireUser(userId);
        requirePassword(user, password);
        if (isEnabled(userId)) {
            throw new BusinessException(ErrorCode.TWO_FACTOR_ALREADY_ENABLED, "两步验证已开启");
        }
        String secret = TotpUtil.generateSecret();
        AuthTotpCredential credential = totpCredentialRepository.findByUserId(userId)
                .orElseGet(AuthTotpCredential::new);
        credential.setUserId(userId);
        credential.setSecret(credentialCipher.encrypt(secret));
        credential.setEnabled(false);
        credential.setConfirmedAt(null);
        credential.setLastUsedStep(null);
        totpCredentialRepository.save(credential);
        return new TwoFactorSetupResponse(secret, TotpUtil.otpauthUri(OTPAUTH_ISSUER, user.getUsername(), secret));
    }

    /**
     * 确认启用两步验证，验证成功后全量重置备份码。
     *
     * @param userId 用户标识
     * @param code 认证器当前验证码
     * @return 一次性明文备份码列表（仅此一次返回）
     */
    @Transactional(rollbackFor = Exception.class)
    public List<String> enable(UUID userId, String code) {
        if (isEnabled(userId)) {
            throw new BusinessException(ErrorCode.TWO_FACTOR_ALREADY_ENABLED, "两步验证已开启");
        }
        AuthTotpCredential credential = totpCredentialRepository.findByUserId(userId)
                .orElseThrow(() -> new BusinessException(ErrorCode.TWO_FACTOR_NOT_CONFIGURED, "请先生成两步验证秘钥"));
        long minStep = credential.getLastUsedStep() == null ? Long.MIN_VALUE : credential.getLastUsedStep();
        String secret = plainSecret(credential);
        long step = TotpUtil.matchingStep(secret, code, Instant.now(), TotpUtil.DEFAULT_SKEW, minStep);
        if (step == TotpUtil.NO_MATCH) {
            throw new BusinessException(ErrorCode.TWO_FACTOR_INVALID_CODE, "两步验证码错误");
        }
        credential.setEnabled(true);
        credential.setConfirmedAt(Instant.now());
        credential.setLastUsedStep(step);
        totpCredentialRepository.save(credential);
        return resetBackupCodes(userId);
    }

    /**
     * 关闭两步验证并清除全部凭据与备份码。
     *
     * @param userId 用户标识
     * @param password 登录密码（复核防会话劫持后偷偷关闭）
     * @param code 当前动态验证码或一次性备份码（证明仍持有认证器）
     */
    @Transactional(rollbackFor = Exception.class)
    public void disable(UUID userId, String password, String code) {
        AuthUser user = requireUser(userId);
        requirePassword(user, password);
        verifyCode(userId, code);
        clearCredentials(userId);
        log.info("两步验证已关闭: userId={}", userId);
    }

    /**
     * 管理员重置：清除该用户的两步验证凭据与备份码，不需要密码复核。
     *
     * <p>用于认证器丢失，或凭据加密密钥轮换后密文无法解开的恢复场景——这两种情况下
     * 用户都无法完成两步验证登录，只能由持有 {@code system:user:manage} 的管理员清零后重新开启。
     * 被重置用户若角色强制两步验证，下次登录会进入注册引导流程。</p>
     *
     * @param userId 用户标识
     */
    @Transactional(rollbackFor = Exception.class)
    public void resetByAdmin(UUID userId) {
        requireUser(userId);
        clearCredentials(userId);
        log.info("两步验证已被管理员重置: userId={}", userId);
    }

    private void clearCredentials(UUID userId) {
        totpCredentialRepository.deleteByUserId(userId);
        backupCodeRepository.deleteByUserId(userId);
    }

    /**
     * 为安装向导生成全新秘钥（无用户上下文，仅返回秘钥与扫码 URI）。
     *
     * @param username 向导中输入的超管用户名，用于认证器展示
     * @return 秘钥与 otpauth URI
     */
    @Transactional(readOnly = true)
    public TwoFactorSetupResponse newSetupSecret(String username) {
        String account = username == null || username.isBlank() ? "admin" : username.trim();
        String secret = TotpUtil.generateSecret();
        return new TwoFactorSetupResponse(secret, TotpUtil.otpauthUri(OTPAUTH_ISSUER, account, secret));
    }

    /**
     * 为刚创建的用户直接落成已确认的两步验证凭据（安装向导专用，跳过待确认状态）。
     *
     * @param userId 用户标识
     * @param secret 安装向导生成的 Base32 秘钥
     * @param code 认证器验证码
     * @return 一次性明文备份码列表
     */
    @Transactional(rollbackFor = Exception.class)
    public List<String> provisionForNewUser(UUID userId, String secret, String code) {
        if (secret == null || secret.isBlank()) {
            throw new BusinessException(ErrorCode.TWO_FACTOR_NOT_CONFIGURED, "请先生成两步验证秘钥");
        }
        long step = TotpUtil.matchingStep(secret, code, Instant.now(), TotpUtil.DEFAULT_SKEW, Long.MIN_VALUE);
        if (step == TotpUtil.NO_MATCH) {
            throw new BusinessException(ErrorCode.TWO_FACTOR_INVALID_CODE, "两步验证码错误");
        }
        AuthTotpCredential credential = totpCredentialRepository.findByUserId(userId)
                .orElseGet(AuthTotpCredential::new);
        credential.setUserId(userId);
        credential.setSecret(credentialCipher.encrypt(secret));
        credential.setEnabled(true);
        credential.setConfirmedAt(Instant.now());
        credential.setLastUsedStep(step);
        totpCredentialRepository.save(credential);
        return resetBackupCodes(userId);
    }

    /**
     * 判断用户是否已确认启用两步验证。
     *
     * @param userId 用户标识
     * @return 是否启用
     */
    @Transactional(readOnly = true)
    public boolean isEnabled(UUID userId) {
        return totpCredentialRepository.existsByUserIdAndEnabledTrue(userId);
    }

    /**
     * 校验登录验证码：优先 TOTP（防重放），未命中再消费一次性备份码。
     *
     * @param userId 用户标识
     * @param code 6 位验证码或备份码
     */
    @Transactional(rollbackFor = Exception.class)
    public void verifyCode(UUID userId, String code) {
        AuthTotpCredential credential = totpCredentialRepository.findByUserIdAndEnabledTrue(userId)
                .orElseThrow(() -> new BusinessException(ErrorCode.TWO_FACTOR_NOT_CONFIGURED, "两步验证未配置"));
        long minStep = credential.getLastUsedStep() == null ? Long.MIN_VALUE : credential.getLastUsedStep();
        String secret = plainSecret(credential);
        long step = TotpUtil.matchingStep(secret, code, Instant.now(), TotpUtil.DEFAULT_SKEW, minStep);
        if (step != TotpUtil.NO_MATCH) {
            credential.setLastUsedStep(step);
            totpCredentialRepository.save(credential);
            return;
        }
        if (consumeBackupCode(userId, code)) {
            return;
        }
        throw new BusinessException(ErrorCode.TWO_FACTOR_INVALID_CODE, "两步验证码错误");
    }

    private boolean consumeBackupCode(UUID userId, String code) {
        if (code == null || code.isBlank()) {
            return false;
        }
        String compact = code.replace("-", "").replace(" ", "").trim().toUpperCase(Locale.ROOT);
        List<AuthBackupCode> candidates = backupCodeRepository.findByUserIdAndUsedAtIsNull(userId);
        for (AuthBackupCode candidate : candidates) {
            if (payloadAuthenticator.verify(compact, candidate.getCodeHash())) {
                // 原子条件更新：并发提交同一枚备份码时只有一个请求能成功。
                if (backupCodeRepository.consume(candidate.getId(), Instant.now()) == 0) {
                    continue;
                }
                log.info("两步验证备份码已使用: userId={}, remaining={}", userId, candidates.size() - 1);
                return true;
            }
        }
        return false;
    }

    private List<String> resetBackupCodes(UUID userId) {
        backupCodeRepository.deleteByUserId(userId);
        List<String> plainCodes = new ArrayList<>(BACKUP_CODE_COUNT);
        List<AuthBackupCode> entities = new ArrayList<>(BACKUP_CODE_COUNT);
        for (int i = 0; i < BACKUP_CODE_COUNT; i++) {
            StringBuilder builder = new StringBuilder(BACKUP_CODE_LENGTH);
            for (int j = 0; j < BACKUP_CODE_LENGTH; j++) {
                builder.append(BACKUP_CODE_ALPHABET.charAt(SECURE_RANDOM.nextInt(BACKUP_CODE_ALPHABET.length())));
            }
            String plain = builder.toString();
            plainCodes.add(plain.substring(0, 4) + "-" + plain.substring(4));
            AuthBackupCode entity = new AuthBackupCode();
            entity.setUserId(userId);
            entity.setCodeHash(payloadAuthenticator.sign(plain));
            entities.add(entity);
        }
        backupCodeRepository.saveAll(entities);
        return plainCodes;
    }

    private AuthUser requireUser(UUID userId) {
        return authUserRepository.findById(userId)
                .orElseThrow(() -> new BusinessException(ErrorCode.UNAUTHORIZED, "当前用户不存在"));
    }

    private void requirePassword(AuthUser user, String password) {
        if (password == null || !passwordEncoder.matches(password, user.getPasswordHash())) {
            throw new BusinessException(ErrorCode.PASSWORD_INVALID, "密码错误");
        }
    }

    private String plainSecret(AuthTotpCredential credential) {
        try {
            return credentialCipher.decrypt(credential.getSecret());
        } catch (BusinessException exception) {
            log.warn("两步验证秘钥解密失败: userId={}, reason={}", credential.getUserId(), exception.getMessage());
            throw new BusinessException(ErrorCode.TWO_FACTOR_NOT_CONFIGURED, "两步验证凭据不可用，需重新开启");
        }
    }
}
