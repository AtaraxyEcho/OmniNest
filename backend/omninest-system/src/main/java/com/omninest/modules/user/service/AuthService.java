package com.omninest.modules.user.service;

import com.omninest.common.enums.ErrorCode;
import com.omninest.common.error.BusinessException;
import com.omninest.common.ratelimit.RateLimitService;
import com.omninest.common.security.ActiveSessionRegistry;
import com.omninest.common.security.AuthenticationTokenPolicy;
import com.omninest.common.security.Roles;
import com.omninest.common.storage.ObjectStorageBuckets;
import com.omninest.common.storage.ObjectStorageClient;
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
import com.omninest.modules.user.repository.ActiveSessionRepository;
import com.omninest.modules.notification.port.NotificationPublisher;
import com.omninest.modules.user.repository.AuthRoleRepository;
import com.omninest.modules.user.repository.AuthUserRepository;
import java.time.Duration;
import java.time.Instant;
import java.time.temporal.ChronoUnit;
import java.util.List;
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
        if (twoFactorPolicyService.isRequired(profile) && !twoFactorService.hasCredential(profile.getId())) {
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
        UUID userId = consumeChallengeToken(challengeToken, TOKEN_USE_TWO_FACTOR);
        requireUserLoginAttemptBudget(userId, "user:%s:2fa-login", 5, Duration.ofMinutes(1));
        AuthUser profile = loadActiveUserWithRoles(userId);
        try {
            twoFactorService.verifyCode(userId, code);
        } catch (BusinessException exception) {
            if (ErrorCode.TWO_FACTOR_INVALID_CODE.equals(exception.errorCode())) {
                auditLogin(profile, profile.getUsername(), clientPlatform, deviceId, deviceName,
                        ipAddress, userAgent, "FAILED", "两步验证码错误");
            }
            throw exception;
        }
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
        UUID userId = consumeChallengeToken(challengeToken, TOKEN_USE_TWO_FACTOR_SETUP);
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
        UUID userId = consumeChallengeToken(challengeToken, TOKEN_USE_TWO_FACTOR_SETUP);
        requireUserLoginAttemptBudget(userId, "user:%s:2fa-enable", 5, Duration.ofMinutes(1));
        List<String> backupCodes = twoFactorService.enable(userId, code);
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
     * 消费两步验证挑战令牌，校验签名、类型与有效期。
     *
     * @param rawToken 挑战令牌
     * @param expectedUse 期望的 token_use
     * @return 用户标识
     */
    public UUID consumeChallengeToken(String rawToken, String expectedUse) {
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
        return parseUserId(jwt.getSubject());
    }

    private void requireUserLoginAttemptBudget(UUID userId, String keyPattern, int limit, Duration window) {
        if (!rateLimitService.tryAcquire(String.format(java.util.Locale.ROOT, keyPattern, userId), limit, window)) {
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
        profile.getRoles().add(defaultUserRole());
        return authUserRepository.save(profile);
    }

    private AuthUser authenticatePassword(LoginRequest request, String clientPlatform,
                                          String deviceId, String deviceName,
                                          String ipAddress, String userAgent) {
        String username = normalizeUsername(request.username());
        AuthUser profile = authUserRepository.findByUsername(username)
                .orElseThrow(() -> {
                    auditLogin(null, username, clientPlatform, deviceId, deviceName,
                            ipAddress, userAgent, "FAILED", "用户不存在");
                    return new BusinessException(ErrorCode.UNAUTHORIZED, "用户名或密码错误");
                });
        if (!"ACTIVE".equals(profile.getStatus())) {
            auditLogin(profile, username, clientPlatform, deviceId, deviceName,
                    ipAddress, userAgent, "DISABLED", "账号已被禁用");
            throw new BusinessException(ErrorCode.UNAUTHORIZED, "账号已被禁用");
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
        if (enforcePlatformMutex) {
            enforceSamePlatformMutex(profile.getId(), clientPlatform, sessionId);
        }
        activeSessionRegistry.register(
                profile.getId(),
                clientPlatform,
                sessionId,
                authenticationTokenPolicy.refreshTokenTtl()
        );

        Instant issuedAt = Instant.now();
        AuthActiveSession session = new AuthActiveSession();
        session.setId(sessionId);
        session.setUserId(profile.getId());
        session.setClientPlatform(clientPlatform);
        session.setDeviceId(deviceId);
        session.setDeviceName(deviceName);
        session.setIpAddress(ipAddress);
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
        session.setLastActiveAt(now);
        slideSessionExpiry(session, now);
        activeSessionRepository.save(session);
        // 活动会话注册表键与滑动会话同步续期：登录时写入的 TTL 不续写会在
        // 第 30 天先于会话失效，导致同平台互斥查不到旧会话。
        activeSessionRegistry.register(
                userId,
                session.getClientPlatform(),
                sessionId,
                authenticationTokenPolicy.refreshTokenTtl()
        );
        return issueToken(toDto(profile), sessionId, session.getExpiresAt());
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
        return issueToken(user, sessionId, Instant.now().plus(authenticationTokenPolicy.refreshTokenTtl()));
    }

    /**
     * 签发访问与刷新令牌。刷新路径传入会话行实际截止时间，保证 JWT 过期
     * 声明、Web 端 Cookie Max-Age 与服务端会话有效期三者一致。
     *
     * @param user 用户信息
     * @param sessionId 会话标识
     * @param refreshExpiresAt 刷新令牌截止时间
     * @return 令牌响应
     */
    private AuthTokenResponse issueToken(AuthUserDto user, UUID sessionId, Instant refreshExpiresAt) {
        Instant now = Instant.now();
        Instant accessExpiresAt = now.plus(authenticationTokenPolicy.accessTokenTtl());
        String accessToken = encodeToken(user, sessionId, now, accessExpiresAt, "access", true);
        String refreshToken = encodeToken(user, sessionId, now, refreshExpiresAt, "refresh", false);
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
            boolean includeAuthorities
    ) {
        JwtClaimsSet.Builder claims = JwtClaimsSet.builder()
                .subject(user.id().toString())
                .issuedAt(issuedAt)
                .expiresAt(expiresAt)
                .claim("token_use", tokenUse)
                .claim("sid", sessionId.toString());
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
                .build();
        JwsHeader headers = JwsHeader.with(MacAlgorithm.HS256).build();
        return jwtEncoder.encode(JwtEncoderParameters.from(headers, claims)).getTokenValue();
    }

    /**
     * 同平台互斥：撤销同平台其他会话，并发布旧会话撤销结果。
     */
    private void enforceSamePlatformMutex(UUID userId, String clientPlatform, UUID newSessionId) {
        UUID oldSid = activeSessionRegistry.find(userId, clientPlatform).orElse(null);
        if (oldSid != null) {
            sessionRevocationService.revokeSession(userId, oldSid, authenticationTokenPolicy.refreshTokenTtl());
            activeSessionRepository.revokeByUserAndPlatformExcluding(
                    userId, clientPlatform, newSessionId, "同平台新设备登录");
            log.info("同平台互斥: userId={}, platform={}, 旧会话已撤销: {}", userId, clientPlatform, oldSid);
        }
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
        String username = rawUsername == null ? "" : rawUsername.trim();
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
