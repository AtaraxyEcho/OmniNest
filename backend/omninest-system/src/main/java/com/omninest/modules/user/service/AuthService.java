package com.omninest.modules.user.service;

import com.omninest.common.enums.ErrorCode;
import com.omninest.common.error.BusinessException;
import com.omninest.common.ratelimit.RateLimitService;
import com.omninest.common.security.ActiveSessionRegistry;
import com.omninest.common.security.AuthenticationTokenPolicy;
import com.omninest.common.security.Roles;
import com.omninest.common.storage.ObjectStorageBuckets;
import com.omninest.common.storage.ObjectStorageClient;
import com.omninest.modules.quota.service.StorageQuotaService;
import com.omninest.modules.user.domain.AuthActiveSession;
import com.omninest.modules.user.domain.AuthRole;
import com.omninest.modules.user.domain.AuthUser;
import com.omninest.modules.user.dto.AuthTokenResponse;
import com.omninest.modules.user.dto.LoginRequest;
import com.omninest.modules.user.dto.RegisterRequest;
import com.omninest.modules.user.dto.TwoFactorDtos.TwoFactorBootstrapEnableResponse;
import com.omninest.modules.user.dto.TwoFactorDtos.TwoFactorSetupResponse;
import com.omninest.modules.user.dto.AuthUserDto;
import com.omninest.modules.user.util.AuthUserMapper;
import com.omninest.modules.user.security.ClientPlatform;
import com.omninest.modules.user.repository.ActiveSessionRepository;
import com.omninest.modules.notification.port.NotificationPublisher;
import com.omninest.modules.user.repository.AuthRoleRepository;
import com.omninest.modules.user.repository.AuthUserRepository;
import java.time.Duration;
import java.time.Instant;
import java.time.temporal.ChronoUnit;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Set;
import java.util.UUID;

import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.security.oauth2.jwt.JwtDecoder;
import org.springframework.security.oauth2.jose.jws.MacAlgorithm;
import org.springframework.security.oauth2.jwt.JwsHeader;
import org.springframework.security.oauth2.jwt.JwtClaimsSet;
import org.springframework.security.oauth2.jwt.JwtEncoder;
import org.springframework.security.oauth2.jwt.JwtEncoderParameters;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Slf4j
@Service
@RequiredArgsConstructor
public class AuthService {
    private static final String TOKEN_TYPE = "Bearer";
    /** 两步验证挑战令牌类型：已启用待验证。 */
    public static final String TOKEN_USE_TWO_FACTOR = "2fa";
    /** 两步验证挑战令牌类型：强制角色待注册。 */
    public static final String TOKEN_USE_TWO_FACTOR_SETUP = "2fa_setup";
    /** 两步验证挑战令牌类型：注册引导已确认，待换取登录令牌。 */
    public static final String TOKEN_USE_TWO_FACTOR_FINALIZE = "2fa_finalize";
    public static final String CHALLENGE_TYPE_VERIFY = "verify";
    public static final String CHALLENGE_TYPE_ENROLL = "enroll";
    private static final Duration TWO_FACTOR_CHALLENGE_TTL = Duration.ofMinutes(5);
    /** 不存在的用户也执行一次同强度 BCrypt，消除用户名枚举的响应时间差。 */
    private static final String DUMMY_PASSWORD_HASH =
            "$2a$12$/cjZ3pCwj52WIu8AMPS.CerPeJL5LZfZz/tNsDY/ZXBpkEKbni0oO";

    private final AuthUserRepository authUserRepository;
    private final AuthRoleRepository authRoleRepository;
    private final PasswordEncoder passwordEncoder;
    private final PasswordPolicy passwordPolicy;
    private final JwtEncoder jwtEncoder;
    private final JwtDecoder jwtDecoder;
    private final AuthenticationTokenPolicy authenticationTokenPolicy;
    private final ObjectStorageClient objectStorageClient;
    private final ObjectStorageBuckets objectStorageBuckets;
    private final SessionRevocationService sessionRevocationService;
    private final ActiveSessionRegistry activeSessionRegistry;
    private final LoginAuditService loginAuditService;
    private final ActiveSessionRepository activeSessionRepository;
    private final NotificationPublisher notificationService;
    private final TwoFactorService twoFactorService;
    private final TwoFactorPolicyService twoFactorPolicyService;
    private final RateLimitService rateLimitService;
    private final StorageQuotaService storageQuotaService;

    @Transactional(rollbackFor = Exception.class)
    public AuthTokenResponse register(
            RegisterRequest request,
            String clientPlatform,
            String deviceId,
            String deviceName,
            String ipAddress,
            String userAgent
    ) {
        AuthUser profile = registerInternal(request);
        UUID sessionId = createActiveSession(
                profile,
                clientPlatform,
                deviceId,
                deviceName,
                ipAddress,
                false
        );
        auditLogin(profile, profile.getUsername(), clientPlatform, deviceId, deviceName,
                ipAddress, userAgent, "SUCCESS", null);
        profile.setLastLoginAt(Instant.now());
        authUserRepository.save(profile);
        log.info("用户注册成功: userId={}, username={}", profile.getId(), profile.getUsername());
        return issueToken(toDto(profile), sessionId);
    }

    @Transactional(rollbackFor = Exception.class)
    public AuthTokenResponse login(LoginRequest request, String clientPlatform,
                                   String deviceId, String deviceName,
                                   String ipAddress, String userAgent) {
        AuthUser profile = authenticatePassword(request, clientPlatform, deviceId, deviceName, ipAddress, userAgent);
        if (twoFactorService.isEnabled(profile.getId())) {
            return buildChallengeResponse(profile.getId(), CHALLENGE_TYPE_VERIFY);
        }
        // 判定只认「已确认启用」：注册引导中途落库的 enabled=false 半成品凭据不得让
        // 命中强制策略的用户在二次登录时跳过两步验证。
        if (twoFactorPolicyService.isRequired(profile)) {
            return buildChallengeResponse(profile.getId(), CHALLENGE_TYPE_ENROLL);
        }
        log.info("用户登录成功: userId={}, platform={}, ip={}", profile.getId(), clientPlatform, ipAddress);
        return completeLogin(profile, clientPlatform, deviceId, deviceName, ipAddress, userAgent);
    }

    /**
     * 两步验证登录第二步：校验挑战令牌与验证码后完成登录。
     *
     * @param challengeToken 第一步返回的挑战令牌
     * @param code 6 位验证码或备份码
     * @param clientPlatform 客户端平台
     * @param deviceId 设备标识
     * @param deviceName 设备名称
     * @param ipAddress 客户端 IP
     * @param userAgent User-Agent
     * @return 访问与刷新令牌
     */
    @Transactional(rollbackFor = Exception.class)
    public AuthTokenResponse completeTwoFactorLogin(
            String challengeToken,
            String code,
            String clientPlatform,
            String deviceId,
            String deviceName,
            String ipAddress,
            String userAgent
    ) {
        UUID userId = verifyChallengeToken(challengeToken, TOKEN_USE_TWO_FACTOR);
        requireUserLoginAttemptBudget(userId, "user:%s:2fa-login", 5, Duration.ofMinutes(1));
        AuthUser profile = loadActiveUserWithRoles(userId);
        try {
            twoFactorService.verifyCode(userId, code);
        } catch (BusinessException exception) {
            if (ErrorCode.TWO_FACTOR_INVALID_CODE.equals(exception.errorCode())) {
                auditLogin(profile, profile.getUsername(), clientPlatform, deviceId, deviceName,
                        ipAddress, userAgent, "FAILED", "两步验证码错误");
            }
            // 验证码错误不核销 jti：单次输错不应作废整个登录挑战，防爆破由上面的按用户预算承担
            throw exception;
        }
        consumeChallengeToken(challengeToken, TOKEN_USE_TWO_FACTOR);
        log.info("用户两步验证登录成功: userId={}, platform={}, ip={}", userId, clientPlatform, ipAddress);
        return completeLogin(profile, clientPlatform, deviceId, deviceName, ipAddress, userAgent);
    }

    /**
     * 强制角色注册引导：使用注册挑战令牌生成 TOTP 秘钥。
     *
     * @param challengeToken 注册挑战令牌
     * @param password 登录密码
     * @return 秘钥与 otpauth URI
     */
    @Transactional(rollbackFor = Exception.class)
    public TwoFactorSetupResponse bootstrapTwoFactorSetup(String challengeToken, String password) {
        UUID userId = verifyChallengeToken(challengeToken, TOKEN_USE_TWO_FACTOR_SETUP);
        requireUserLoginAttemptBudget(userId, "user:%s:2fa-setup", 3, Duration.ofHours(1));
        return twoFactorService.startSetup(userId, password);
    }

    /**
     * 强制角色注册引导：确认验证码启用两步验证，返回备份码与完成令牌。
     *
     * @param challengeToken 注册挑战令牌
     * @param code 认证器验证码
     * @return 备份码与完成令牌
     */
    @Transactional(rollbackFor = Exception.class)
    public TwoFactorBootstrapEnableResponse bootstrapTwoFactorEnable(String challengeToken, String code) {
        UUID userId = verifyChallengeToken(challengeToken, TOKEN_USE_TWO_FACTOR_SETUP);
        requireUserLoginAttemptBudget(userId, "user:%s:2fa-enable", 5, Duration.ofMinutes(1));
        List<String> backupCodes = twoFactorService.enable(userId, code);
        // 注册引导的两个中间步共用同一挑战令牌，jti 只在绑定成功后核销
        consumeChallengeToken(challengeToken, TOKEN_USE_TWO_FACTOR_SETUP);
        Instant now = Instant.now();
        String finalizeToken = encodeChallengeToken(
                userId, TOKEN_USE_TWO_FACTOR_FINALIZE, now, now.plus(TWO_FACTOR_CHALLENGE_TTL));
        return new TwoFactorBootstrapEnableResponse(backupCodes, finalizeToken);
    }

    /**
     * 强制角色注册引导：用户确认保存备份码后换取登录令牌。
     *
     * @param finalizeToken 完成令牌
     * @param clientPlatform 客户端平台
     * @param deviceId 设备标识
     * @param deviceName 设备名称
     * @param ipAddress 客户端 IP
     * @param userAgent User-Agent
     * @return 访问与刷新令牌
     */
    @Transactional(rollbackFor = Exception.class)
    public AuthTokenResponse completeTwoFactorEnrollment(
            String finalizeToken,
            String clientPlatform,
            String deviceId,
            String deviceName,
            String ipAddress,
            String userAgent
    ) {
        UUID userId = consumeChallengeToken(finalizeToken, TOKEN_USE_TWO_FACTOR_FINALIZE);
        AuthUser profile = loadActiveUserWithRoles(userId);
        if (!twoFactorService.isEnabled(userId)) {
            throw new BusinessException(ErrorCode.TWO_FACTOR_NOT_CONFIGURED, "两步验证未配置");
        }
        log.info("管理员两步验证注册完成: userId={}, platform={}", userId, clientPlatform);
        return completeLogin(profile, clientPlatform, deviceId, deviceName, ipAddress, userAgent);
    }

    /**
     * 构造两步验证挑战响应，不签发任何业务令牌。
     *
     * @param userId 用户标识
     * @param challengeType verify 或 enroll
     * @return 挑战响应
     */
    public AuthTokenResponse buildChallengeResponse(UUID userId, String challengeType) {
        Instant now = Instant.now();
        Instant expiresAt = now.plus(TWO_FACTOR_CHALLENGE_TTL);
        String tokenUse = CHALLENGE_TYPE_ENROLL.equals(challengeType)
                ? TOKEN_USE_TWO_FACTOR_SETUP
                : TOKEN_USE_TWO_FACTOR;
        String challengeToken = encodeChallengeToken(userId, tokenUse, now, expiresAt);
        return new AuthTokenResponse(
                null,
                null,
                null,
                null,
                null,
                null,
                true,
                challengeToken,
                challengeType,
                formatInstant(expiresAt),
                null
        );
    }

    /**
     * 只读校验两步验证挑战令牌：签名、类型与有效期，不核销 jti。
     *
     * <p>注册引导是 setup → enable 两步向导，同一段令牌需要跨步复用，因此核销被推迟到
     * 流程终态。中间步另各有按用户计的频率预算，且都必须出示令牌之外的秘密（登录密码或
     * 动态验证码），仅持有挑战令牌无法推进流程。</p>
     *
     * @param rawToken 挑战令牌
     * @param expectedUse 期望的 token_use
     * @return 用户标识
     */
    public UUID verifyChallengeToken(String rawToken, String expectedUse) {
        return parseUserId(decodeChallengeToken(rawToken, expectedUse).getSubject());
    }

    /**
     * 校验并核销两步验证挑战令牌，用于流程终态。
     *
     * @param rawToken 挑战令牌
     * @param expectedUse 期望的 token_use
     * @return 用户标识
     */
    public UUID consumeChallengeToken(String rawToken, String expectedUse) {
        Jwt jwt = decodeChallengeToken(rawToken, expectedUse);
        // 挑战令牌一次性消费：同一 jti 在有效期内第二次出现即拒绝，阻断截获重放
        String jti = jwt.getClaimAsString("jti");
        if (jti != null && !rateLimitService.tryAcquire(
                "omninest:2fa:challenge:" + jti, 1, TWO_FACTOR_CHALLENGE_TTL)) {
            throw new BusinessException(ErrorCode.UNAUTHORIZED, "两步验证凭证已使用，请重新发起");
        }
        return parseUserId(jwt.getSubject());
    }

    private Jwt decodeChallengeToken(String rawToken, String expectedUse) {
        String token = normalizeToken(rawToken);
        Jwt jwt;
        try {
            jwt = jwtDecoder.decode(token);
        } catch (RuntimeException ex) {
            throw new BusinessException(ErrorCode.UNAUTHORIZED, "两步验证凭证无效");
        }
        if (!expectedUse.equals(jwt.getClaimAsString("token_use"))) {
            throw new BusinessException(ErrorCode.UNAUTHORIZED, "两步验证凭证无效");
        }
        return jwt;
    }

    private void requireUserLoginAttemptBudget(UUID userId, String keyPattern, int limit, Duration window) {
        if (!rateLimitService.tryAcquire(String.format(Locale.ROOT, keyPattern, userId), limit, window)) {
            throw new BusinessException(ErrorCode.RATE_LIMITED, "两步验证尝试过于频繁，请稍后再试");
        }
    }

    private AuthUser loadActiveUserWithRoles(UUID userId) {
        AuthUser profile = authUserRepository.findWithRolesAndPermissionsById(userId)
                .orElseThrow(() -> new BusinessException(ErrorCode.UNAUTHORIZED, "当前用户不存在"));
        if (!"ACTIVE".equals(profile.getStatus())) {
            throw new BusinessException(ErrorCode.UNAUTHORIZED, "账号已被禁用");
        }
        return profile;
    }

    private AuthUser registerInternal(RegisterRequest request) {
        String username = normalizeUsername(request.username());
        if (authUserRepository.existsByUsername(username)) {
            throw new BusinessException(ErrorCode.CONFLICT, "用户名已存在");
        }
        passwordPolicy.validate(username, request.password());
        AuthUser profile = new AuthUser();
        profile.setId(UUID.randomUUID());
        profile.setUsername(username);
        profile.setPasswordHash(passwordEncoder.encode(request.password()));
        profile.setDisplayName(normalizeDisplayName(request.displayName(), username));
        profile.setEmail(normalizeEmail(request.email()));
        // 注册默认配额与管理员创建用户同源读取配置中心，避免实体字段默认值绕过
        // storage.quota.default（0 表示无限制）。
        profile.setQuotaBytes(storageQuotaService.getDefaultQuotaBytes());
        profile.getRoles().add(defaultUserRole());
        return authUserRepository.save(profile);
    }

    private AuthUser authenticatePassword(LoginRequest request, String clientPlatform,
                                          String deviceId, String deviceName,
                                          String ipAddress, String userAgent) {
        String username = normalizeUsername(request.username());
        AuthUser profile = authUserRepository.findByUsername(username).orElse(null);
        if (profile == null) {
            // 与真实用户的 BCrypt 成本对齐，避免通过响应时间枚举用户名。
            passwordEncoder.matches(request.password(), DUMMY_PASSWORD_HASH);
            auditLogin(null, username, clientPlatform, deviceId, deviceName,
                    ipAddress, userAgent, "FAILED", "用户不存在");
            throw new BusinessException(ErrorCode.UNAUTHORIZED, "用户名或密码错误");
        }
        if (!"ACTIVE".equals(profile.getStatus())) {
            passwordEncoder.matches(request.password(), profile.getPasswordHash());
            auditLogin(profile, username, clientPlatform, deviceId, deviceName,
                    ipAddress, userAgent, "DISABLED", "账号已被禁用");
            // 对外文案与“用户名或密码错误”一致，避免账号存在性与状态被枚举；
            // 真实原因保留在审计日志（DISABLED）
            throw new BusinessException(ErrorCode.UNAUTHORIZED, "用户名或密码错误");
        }
        if (!passwordEncoder.matches(request.password(), profile.getPasswordHash())) {
            auditLogin(profile, username, clientPlatform, deviceId, deviceName,
                    ipAddress, userAgent, "FAILED", "密码错误");
            throw new BusinessException(ErrorCode.UNAUTHORIZED, "用户名或密码错误");
        }
        return profile;
    }

    private AuthTokenResponse completeLogin(AuthUser profile, String clientPlatform,
                                            String deviceId, String deviceName,
                                            String ipAddress, String userAgent) {
        boolean newDevice = isNewDevice(profile.getId(), clientPlatform, deviceId);
        UUID sessionId = createActiveSession(
                profile,
                clientPlatform,
                deviceId,
                deviceName,
                ipAddress,
                true
        );

        // 审计
        auditLogin(profile, profile.getUsername(), clientPlatform, deviceId, deviceName,
                ipAddress, userAgent, "SUCCESS", null);

        if (newDevice) {
            notifyNewDevice(profile, clientPlatform, deviceName, ipAddress);
        }

        profile.setLastLoginAt(Instant.now());
        authUserRepository.save(profile);
        return issueToken(toDto(profile), sessionId);
    }

    private UUID createActiveSession(
            AuthUser profile,
            String clientPlatform,
            String deviceId,
            String deviceName,
            String ipAddress,
            boolean enforcePlatformMutex
    ) {
        UUID sessionId = UUID.randomUUID();
        // 平台标识参与互斥判定与 Redis 会话键拼接，必须在落库和登记前先归一化到固定档位，
        // 否则改写大小写即可绕开同平台互斥，并把任意长字符串写进键空间。
        String platform = ClientPlatform.normalize(clientPlatform);
        if (enforcePlatformMutex) {
            enforceSamePlatformMutex(profile.getId(), platform, sessionId);
        }
        activeSessionRegistry.register(
                profile.getId(),
                platform,
                sessionId,
                authenticationTokenPolicy.refreshTokenTtl()
        );

        Instant issuedAt = Instant.now();
        AuthActiveSession session = new AuthActiveSession();
        session.setId(sessionId);
        session.setUserId(profile.getId());
        session.setClientPlatform(LoginAuditService.clamped(platform, LoginAuditService.CLIENT_PLATFORM_MAX));
        session.setDeviceId(LoginAuditService.clamped(deviceId, LoginAuditService.DEVICE_ID_MAX));
        session.setDeviceName(LoginAuditService.clamped(deviceName, LoginAuditService.DEVICE_NAME_MAX));
        session.setIpAddress(LoginAuditService.clamped(ipAddress, LoginAuditService.IP_ADDRESS_MAX));
        session.setIssuedAt(issuedAt);
        session.setExpiresAt(issuedAt.plus(authenticationTokenPolicy.refreshTokenTtl()));
        activeSessionRepository.save(session);
        return sessionId;
    }

    @Transactional(rollbackFor = Exception.class)
    public AuthTokenResponse refresh(String refreshToken) {
        String token = normalizeToken(refreshToken);
        Jwt jwt;
        try {
            jwt = jwtDecoder.decode(token);
        } catch (RuntimeException ex) {
            log.warn("JWT 解码失败: {}", ex.getMessage());
            throw new BusinessException(ErrorCode.UNAUTHORIZED, "刷新凭证无效");
        }
        if (!"refresh".equals(jwt.getClaimAsString("token_use"))) {
            throw new BusinessException(ErrorCode.UNAUTHORIZED, "刷新凭证无效");
        }
        UUID userId = parseUserId(jwt.getSubject());
        AuthUser profile = authUserRepository.findWithRolesAndPermissionsById(userId)
                .orElseThrow(() -> new BusinessException(ErrorCode.UNAUTHORIZED, "当前用户不存在"));
        if (!"ACTIVE".equals(profile.getStatus())) {
            throw new BusinessException(ErrorCode.UNAUTHORIZED, "账号已被禁用");
        }

        UUID sessionId = parseSessionId(jwt.getClaimAsString("sid"));
        AuthActiveSession session = activeSessionRepository.findByIdAndUserId(sessionId, userId)
                .orElseThrow(() -> new BusinessException(ErrorCode.UNAUTHORIZED, "活动会话不存在"));
        Instant now = Instant.now();
        if (session.isRevoked()) {
            throw new BusinessException(ErrorCode.UNAUTHORIZED, "活动会话已撤销");
        }
        if (session.getExpiresAt() == null || !session.getExpiresAt().isAfter(now)) {
            throw new BusinessException(ErrorCode.UNAUTHORIZED, "活动会话已过期");
        }
        if (sessionRevocationService.isRevoked(userId, sessionId)) {
            throw new BusinessException(ErrorCode.UNAUTHORIZED, "会话已在其他设备登录");
        }
        // 刷新令牌轮换与重放检测：会话只认最近签发的 jti，旧令牌再次出现即判定令牌泄露，
        // 撤销整个会话迫使全部设备重新登录。存量会话（jti 为空）首次刷新时建立 jti。
        String presentedJti = jwt.getClaimAsString("jti");
        String currentJti = session.getCurrentRefreshJti();
        if (currentJti != null && !currentJti.equals(presentedJti)) {
            sessionRevocationService.revokeSession(userId, sessionId, authenticationTokenPolicy.refreshTokenTtl());
            activeSessionRepository.revokeBySessionId(sessionId, "刷新令牌重放，会话已撤销");
            log.warn("检测到刷新令牌重放，撤销会话: userId={}, sessionId={}", userId, sessionId);
            throw new BusinessException(ErrorCode.UNAUTHORIZED, "刷新凭证已失效，请重新登录");
        }
        String rotatedJti = UUID.randomUUID().toString();
        session.setCurrentRefreshJti(rotatedJti);
        session.setLastActiveAt(now);
        slideSessionExpiry(session, now);
        activeSessionRepository.save(session);
        // 活动会话注册表键与滑动会话同步续期：登录时写入的 TTL 不续写会在
        // 第 30 天先于会话失效，导致同平台互斥查不到旧会话。
        activeSessionRegistry.register(
                userId,
                ClientPlatform.normalize(session.getClientPlatform()),
                sessionId,
                authenticationTokenPolicy.refreshTokenTtl()
        );
        return issueToken(toDto(profile), sessionId, session.getExpiresAt(), rotatedJti);
    }

    /**
     * 刷新时滑动续期会话有效期：不活跃窗口取刷新令牌 TTL，同时不得超过
     * 自会话签发起算的绝对寿命上限。有效期只延长不收缩，策略上限被调小
     * 或旧会话已越过上限时保持既有截止时间自然到期，不把在线用户立即踢下线。
     *
     * @param session 待续期的活动会话
     * @param now 当前时间
     */
    private void slideSessionExpiry(AuthActiveSession session, Instant now) {
        Duration maxLifetime = authenticationTokenPolicy.refreshSessionMaxLifetime();
        Instant candidate = now.plus(authenticationTokenPolicy.refreshTokenTtl());
        if (maxLifetime != null && !maxLifetime.isNegative() && !maxLifetime.isZero()) {
            Instant anchor = session.getIssuedAt() != null ? session.getIssuedAt() : session.getCreatedAt();
            if (anchor != null) {
                Instant cap = anchor.plus(maxLifetime);
                if (cap.isBefore(candidate)) {
                    candidate = cap;
                }
            }
        }
        if (candidate.isAfter(session.getExpiresAt())) {
            session.setExpiresAt(candidate);
        }
    }

    /**
     * 退出登录：吊销刷新令牌对应的活动会话。
     *
     * 幂等成功语义：凭证缺失、无法解码、类型不符或会话已不存在时直接返回，
     * 仅记录调试日志，保证客户端任何状态下都能完成本地登出清理。
     *
     * @param refreshToken 客户端持有的刷新令牌，Web 端为 Cookie 值
     */
    @Transactional(rollbackFor = Exception.class)
    public void logout(String refreshToken) {
        if (refreshToken == null || refreshToken.isBlank()) {
            return;
        }
        UUID userId;
        UUID sessionId;
        try {
            Jwt jwt = jwtDecoder.decode(refreshToken.trim());
            if (!"refresh".equals(jwt.getClaimAsString("token_use"))) {
                log.debug("登出令牌类型非 refresh，按幂等成功处理");
                return;
            }
            userId = parseUserId(jwt.getSubject());
            sessionId = parseSessionId(jwt.getClaimAsString("sid"));
        } catch (RuntimeException ex) {
            log.debug("登出令牌无效，按幂等成功处理: {}", ex.getMessage());
            return;
        }
        if (activeSessionRepository.findByIdAndUserId(sessionId, userId).isEmpty()) {
            return;
        }
        sessionRevocationService.revokeSession(userId, sessionId, authenticationTokenPolicy.refreshTokenTtl());
        activeSessionRepository.revokeBySessionId(sessionId, "用户退出登录");
    }

    private AuthTokenResponse issueToken(AuthUserDto user, UUID sessionId) {
        AuthActiveSession session = activeSessionRepository.findById(sessionId).orElse(null);
        if (session == null) {
            return issueToken(user, sessionId, Instant.now().plus(authenticationTokenPolicy.refreshTokenTtl()), null);
        }
        String refreshJti = UUID.randomUUID().toString();
        session.setCurrentRefreshJti(refreshJti);
        activeSessionRepository.save(session);
        return issueToken(user, sessionId, session.getExpiresAt(), refreshJti);
    }

    /**
     * 签发访问与刷新令牌。刷新路径传入会话行实际截止时间，保证 JWT 过期
     * 声明、Web 端 Cookie Max-Age 与服务端会话有效期三者一致。
     *
     * @param user 用户信息
     * @param sessionId 会话标识
     * @param refreshExpiresAt 刷新令牌截止时间
     * @param refreshJti 刷新令牌 jti；null 时不携带（仅无会话上下文的兜底路径）
     * @return 令牌响应
     */
    private AuthTokenResponse issueToken(
            AuthUserDto user,
            UUID sessionId,
            Instant refreshExpiresAt,
            String refreshJti
    ) {
        Instant now = Instant.now();
        Instant accessExpiresAt = now.plus(authenticationTokenPolicy.accessTokenTtl());
        String accessToken = encodeToken(user, sessionId, now, accessExpiresAt, "access", true, null);
        String refreshToken = encodeToken(user, sessionId, now, refreshExpiresAt, "refresh", false, refreshJti);
        return new AuthTokenResponse(
                TOKEN_TYPE,
                accessToken,
                formatInstant(accessExpiresAt),
                refreshToken,
                formatInstant(refreshExpiresAt),
                user
        );
    }

    private String encodeToken(
            AuthUserDto user,
            UUID sessionId,
            Instant issuedAt,
            Instant expiresAt,
            String tokenUse,
            boolean includeAuthorities,
            String jti
    ) {
        JwtClaimsSet.Builder claims = JwtClaimsSet.builder()
                .subject(user.id().toString())
                .issuedAt(issuedAt)
                .expiresAt(expiresAt)
                .claim("token_use", tokenUse)
                .claim("sid", sessionId.toString());
        if (jti != null) {
            claims.id(jti);
        }
        if (includeAuthorities) {
            claims.claim("username", user.username());
            claims.claim("role", user.role());
            claims.claim("roles", user.roles());
            claims.claim("permissions", user.permissions());
        }
        JwsHeader headers = JwsHeader.with(MacAlgorithm.HS256).build();
        return jwtEncoder.encode(JwtEncoderParameters.from(headers, claims.build())).getTokenValue();
    }

    private String encodeChallengeToken(UUID userId, String tokenUse, Instant issuedAt, Instant expiresAt) {
        JwtClaimsSet claims = JwtClaimsSet.builder()
                .subject(userId.toString())
                .issuedAt(issuedAt)
                .expiresAt(expiresAt)
                .claim("token_use", tokenUse)
                .id(UUID.randomUUID().toString())
                .build();
        JwsHeader headers = JwsHeader.with(MacAlgorithm.HS256).build();
        return jwtEncoder.encode(JwtEncoderParameters.from(headers, claims)).getTokenValue();
    }

    /**
     * 同平台互斥：撤销同平台其他会话，并发布旧会话撤销结果。
     */
    private void enforceSamePlatformMutex(UUID userId, String clientPlatform, UUID newSessionId) {
        // 以数据库未撤销会话为准，而不是只信 Redis 注册表里的单条最新 sid：
        // Redis 淘汰/重启后仍可能有同一平台的多条旧会话，只吊销其中一条会让其余
        // access token 在 TTL 内继续可用。逐条写入吊销缓存，再批量落库。
        List<AuthActiveSession> existingSessions = activeSessionRepository
                .findByUserIdAndClientPlatformAndRevokedAtIsNull(userId, clientPlatform)
                .stream()
                .filter(session -> !newSessionId.equals(session.getId()))
                .toList();
        if (existingSessions.isEmpty()) {
            return;
        }
        for (AuthActiveSession session : existingSessions) {
            sessionRevocationService.revokeSession(
                    userId, session.getId(), authenticationTokenPolicy.refreshTokenTtl());
        }
        activeSessionRepository.revokeByUserAndPlatformExcluding(
                userId, clientPlatform, newSessionId, "同平台新设备登录");
        log.info("同平台互斥: userId={}, platform={}, 已撤销会话数={}",
                userId, clientPlatform, existingSessions.size());
    }

    /**
     * 判断是否为新设备登录。
     * 检查是否存在相同 deviceId 的未撤销会话，如果存在则为同一设备，否则为新设备。
     */
    private boolean isNewDevice(UUID userId, String clientPlatform, String deviceId) {
        if (deviceId == null || deviceId.isBlank()) {
            return false;
        }
        List<AuthActiveSession> existingSessions = activeSessionRepository
                .findByUserIdAndClientPlatformAndRevokedAtIsNull(userId, clientPlatform);
        return existingSessions.stream()
                .noneMatch(session -> deviceId.equals(session.getDeviceId()));
    }

    private void notifyNewDevice(
            AuthUser profile,
            String clientPlatform,
            String deviceName,
            String ipAddress
    ) {
        try {
            String deviceInfo = deviceName != null && !deviceName.isBlank()
                    ? deviceName : clientPlatform;
            notificationService.create(
                    profile.getId(),
                    "NEW_DEVICE_LOGIN",
                    "新设备登录",
                    "检测到新设备登录: " + deviceInfo + " (" + ipAddress + ")",
                    Map.of("platform", clientPlatform, "ip", ipAddress)
            );
        } catch (RuntimeException exception) {
            log.warn("发送新设备登录通知失败: userId={}", profile.getId(), exception);
        }
    }

    /**
     * 记录登录审计日志（独立事务，不随主事务回滚）。
     */
    private void auditLogin(AuthUser user, String username, String clientPlatform,
                            String deviceId, String deviceName,
                            String ipAddress, String userAgent,
                            String result, String failureReason) {
        loginAuditService.record(user, username, clientPlatform, deviceId, deviceName,
                ipAddress, userAgent, result, failureReason);
    }

    private String normalizeUsername(String rawUsername) {
        // 用户名统一按小写存储与查询：数据库唯一索引建在 lower(username) 上，
        // 登录限流键也按小写归一，三者必须同一口径。
        String username = rawUsername == null ? "" : rawUsername.trim().toLowerCase(Locale.ROOT);
        if (username.isEmpty()) {
            throw new BusinessException(ErrorCode.PARAM_ERROR, "用户名不能为空");
        }
        return username;
    }

    private String normalizeDisplayName(String rawDisplayName, String username) {
        String displayName = rawDisplayName == null ? "" : rawDisplayName.trim();
        return displayName.isEmpty() ? username : displayName;
    }

    private String normalizeEmail(String rawEmail) {
        String email = rawEmail == null ? "" : rawEmail.trim();
        return email.isEmpty() ? null : email;
    }

    private String normalizeToken(String rawToken) {
        String token = rawToken == null ? "" : rawToken.trim();
        if (token.isEmpty()) {
            throw new BusinessException(ErrorCode.UNAUTHORIZED, "刷新凭证不能为空");
        }
        return token;
    }

    private UUID parseUserId(String subject) {
        try {
            return UUID.fromString(subject);
        } catch (RuntimeException ex) {
            throw new BusinessException(ErrorCode.UNAUTHORIZED, "刷新凭证无效");
        }
    }

    private UUID parseSessionId(String sid) {
        if (sid == null || sid.isBlank()) {
            throw new BusinessException(ErrorCode.UNAUTHORIZED, "刷新凭证缺少会话标识");
        }
        try {
            return UUID.fromString(sid);
        } catch (RuntimeException exception) {
            throw new BusinessException(ErrorCode.UNAUTHORIZED, "刷新凭证会话标识无效");
        }
    }

    private String formatInstant(Instant instant) {
        return instant.truncatedTo(ChronoUnit.SECONDS).toString();
    }

    private AuthRole defaultUserRole() {
        return authRoleRepository.findByCode(Roles.MEMBER)
                .orElseThrow(() -> new BusinessException(ErrorCode.INTERNAL_ERROR, "默认用户角色未初始化"));
    }

    private AuthUserDto toDto(AuthUser profile) {
        String avatarUrl = AuthUserMapper.resolveAvatarUrl(profile, objectStorageClient, objectStorageBuckets);
        return AuthUserMapper.toDto(profile, avatarUrl);
    }
}
