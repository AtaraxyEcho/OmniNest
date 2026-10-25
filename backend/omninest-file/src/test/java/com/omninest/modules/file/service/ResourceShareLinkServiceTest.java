package com.omninest.modules.file.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.argThat;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import com.omninest.modules.file.domain.ShareLink;
import com.omninest.modules.file.repository.ShareLinkRepository;
import com.omninest.common.cache.ReadThroughCache;
import com.omninest.common.enums.ErrorCode;
import com.omninest.common.error.BusinessException;
import com.omninest.common.ratelimit.RateLimitService;
import com.omninest.common.security.CredentialCipher;
import java.time.Instant;
import java.time.Duration;
import java.util.List;
import java.util.Optional;
import java.util.UUID;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;
import org.springframework.security.crypto.password.PasswordEncoder;

/**
 * 通用资源分享链接服务单元测试。
 *
 * @author OmniNest
 */
class ResourceShareLinkServiceTest {

    private static final UUID OWNER_ID = UUID.fromString("10000000-0000-0000-0000-000000000001");
    private static final UUID RESOURCE_ID = UUID.fromString("20000000-0000-0000-0000-000000000001");
    private static final UUID SHARE_ID = UUID.fromString("30000000-0000-0000-0000-000000000001");

    private final ShareLinkRepository shareLinkRepository = mock(ShareLinkRepository.class);
    private final PasswordEncoder passwordEncoder = mock(PasswordEncoder.class);
    private final ShareAccessSessionService sessionService = new ShareAccessSessionService("test-share-session-secret-at-least-32-bytes");
    private final RateLimitService rateLimitService = mock(RateLimitService.class);
    private final CredentialCipher credentialCipher = mock(CredentialCipher.class);
    private final ReadThroughCache readThroughCache = mock(ReadThroughCache.class);
    private final ResourceShareLinkService service = new ResourceShareLinkService(
            shareLinkRepository,
            passwordEncoder,
            sessionService,
            rateLimitService,
            credentialCipher,
            readThroughCache
    );

    /**
     * 验证创建链接仅返回一次原始令牌并持久化哈希。
     */
    @Test
    void createReturnsRawTokenAndPersistsHash() {
        when(rateLimitService.tryAcquire(anyString(), org.mockito.ArgumentMatchers.anyInt(), any(Duration.class)))
                .thenReturn(true);
        when(passwordEncoder.encode("secret")).thenReturn("encoded");
        when(credentialCipher.encrypt(anyString())).thenReturn("v1:cipher");
        when(shareLinkRepository.save(any(ShareLink.class))).thenAnswer(invocation -> {
            ShareLink share = invocation.getArgument(0);
            share.setId(SHARE_ID);
            share.setCreatedAt(Instant.parse("2026-07-19T00:00:00Z"));
            return share;
        });

        var result = service.create(OWNER_ID, "PHOTO_ALBUM", RESOURCE_ID, "secret", null, 10);

        assertThat(result.token()).isNotBlank();
        ArgumentCaptor<ShareLink> captor = ArgumentCaptor.forClass(ShareLink.class);
        verify(shareLinkRepository).save(captor.capture());
        assertThat(captor.getValue().getTokenHash()).hasSize(64).isNotEqualTo(result.token());
        assertThat(captor.getValue().getTokenCipher()).isEqualTo("v1:cipher");
        assertThat(captor.getValue().getPasswordHash()).isEqualTo("encoded");
    }

    @Test
    void blankPasswordProbeDoesNotConsumePasswordAttemptQuota() {
        when(rateLimitService.tryAcquire(anyString(),
                org.mockito.ArgumentMatchers.anyInt(), any(Duration.class))).thenReturn(true);
        when(shareLinkRepository.findByTokenHash(anyString()))
                .thenReturn(Optional.of(passwordShare()));

        assertThatThrownBy(() -> service.issueConsumedSession("raw-token", null, null, "1.2.3.4"))
                .isInstanceOfSatisfying(BusinessException.class,
                        exception -> assertThat(exception.errorCode())
                                .isEqualTo(ErrorCode.SHARE_PASSWORD_REQUIRED));
        verify(rateLimitService, never()).tryAcquire(
                argThat(key -> key != null && key.startsWith("share-pwd-attempt:")),
                org.mockito.ArgumentMatchers.anyInt(),
                any(Duration.class));
        verify(shareLinkRepository, never()).consumeAccess(any(), any());
    }

    @Test
    void wrongPasswordAttemptKeyIsScopedToClientAddress() {
        when(rateLimitService.tryAcquire(anyString(),
                org.mockito.ArgumentMatchers.anyInt(), any(Duration.class))).thenReturn(true);
        when(shareLinkRepository.findByTokenHash(anyString()))
                .thenReturn(Optional.of(passwordShare()));
        when(passwordEncoder.matches("wrong", "encoded")).thenReturn(false);

        assertThatThrownBy(() -> service.issueConsumedSession("raw-token", "wrong", null, "1.2.3.4"))
                .isInstanceOfSatisfying(BusinessException.class,
                        exception -> assertThat(exception.errorCode())
                                .isEqualTo(ErrorCode.PASSWORD_INVALID));

        ArgumentCaptor<String> keyCaptor = ArgumentCaptor.forClass(String.class);
        verify(rateLimitService, org.mockito.Mockito.times(3)).tryAcquire(
                keyCaptor.capture(),
                org.mockito.ArgumentMatchers.anyInt(),
                any(Duration.class));
        String clientHash = FileShareService.sha256("1.2.3.4");
        assertThat(keyCaptor.getAllValues())
                .anyMatch(key -> key.startsWith("share-pwd-attempt:")
                        && key.contains(clientHash));
        verify(shareLinkRepository, never()).consumeAccess(any(), any());
    }

    private ShareLink passwordShare() {
        ShareLink share = new ShareLink();
        share.setId(SHARE_ID);
        share.setOwnerUserId(OWNER_ID);
        share.setResourceType("PHOTO_ALBUM");
        share.setResourceId(RESOURCE_ID);
        share.setPasswordHash("encoded");
        return share;
    }

    /**
     * 验证公开访问通过密码校验后增加访问次数。
     */
    @Test
    void authorizeIncrementsAccessCount() {
        when(rateLimitService.tryAcquire(anyString(),
                org.mockito.ArgumentMatchers.anyInt(), any(Duration.class))).thenReturn(true);
        ShareLink share = new ShareLink();
        share.setId(SHARE_ID);
        share.setOwnerUserId(OWNER_ID);
        share.setResourceType("PHOTO_ALBUM");
        share.setResourceId(RESOURCE_ID);
        share.setPasswordHash("encoded");
        share.setMaxAccessCount(3);
        share.setAccessCount(1);
        when(shareLinkRepository.findByTokenHash(anyString())).thenReturn(Optional.of(share));
        when(passwordEncoder.matches("secret", "encoded")).thenReturn(true);
        when(shareLinkRepository.consumeAccess(any(UUID.class), any(Instant.class)))
                .thenAnswer(invocation -> {
                    share.setAccessCount(share.getAccessCount() + 1);
                    return 1;
                });
        when(shareLinkRepository.findById(SHARE_ID)).thenReturn(Optional.of(share));

        var result = service.authorize("raw-token", "secret", "PHOTO_ALBUM");

        assertThat(result.resourceId()).isEqualTo(RESOURCE_ID);
        assertThat(result.accessCount()).isEqualTo(2);
        verify(shareLinkRepository).consumeAccess(any(UUID.class), any(Instant.class));
    }

    @Test
    void consumedSessionCountsOnceAndCanBeReusedForPagination() {
        ShareLink share = new ShareLink();
        share.setId(SHARE_ID);
        share.setOwnerUserId(OWNER_ID);
        share.setResourceType("PHOTO_ALBUM");
        share.setResourceId(RESOURCE_ID);
        share.setPasswordHash("encoded");
        when(rateLimitService.tryAcquire(anyString(),
                org.mockito.ArgumentMatchers.anyInt(), any(Duration.class))).thenReturn(true);
        when(shareLinkRepository.findByTokenHash(anyString())).thenReturn(Optional.of(share));
        when(passwordEncoder.matches("secret", "encoded")).thenReturn(true);
        when(shareLinkRepository.consumeAccess(eq(SHARE_ID), any(Instant.class))).thenReturn(1);

        var session = service.issueConsumedSession(
                "raw-token", "secret", "PHOTO_ALBUM", "127.0.0.1");
        var firstPage = service.requireSession("raw-token", session.sessionToken(), "PHOTO_ALBUM");
        var secondPage = service.requireSession("raw-token", session.sessionToken(), "PHOTO_ALBUM");

        assertThat(firstPage.resourceId()).isEqualTo(RESOURCE_ID);
        assertThat(secondPage.resourceId()).isEqualTo(RESOURCE_ID);
        verify(shareLinkRepository).consumeAccess(eq(SHARE_ID), any(Instant.class));
    }

    @Test
    void fileSessionWithoutExpectedTypeBindsTheLinkResourceType() {
        ShareLink share = new ShareLink();
        share.setId(SHARE_ID);
        share.setOwnerUserId(OWNER_ID);
        share.setResourceType("FILE");
        share.setResourceId(RESOURCE_ID);
        when(rateLimitService.tryAcquire(anyString(),
                org.mockito.ArgumentMatchers.anyInt(), any(Duration.class))).thenReturn(true);
        when(shareLinkRepository.findByTokenHash(anyString())).thenReturn(Optional.of(share));
        when(shareLinkRepository.consumeAccess(eq(SHARE_ID), any(Instant.class))).thenReturn(1);

        var session = service.issueConsumedSession("raw-token", null, null, "127.0.0.1");
        var descriptor = service.requireAnySession("raw-token", session.sessionToken());

        assertThat(descriptor.resourceId()).isEqualTo(RESOURCE_ID);
        assertThat(descriptor.resourceType()).isEqualTo("FILE");
    }

    @Test
    void sessionAccessRejectsRateLimitExhaustion() {
        when(rateLimitService.tryAcquire(anyString(),
                org.mockito.ArgumentMatchers.anyInt(), any(Duration.class))).thenReturn(false);

        assertThatThrownBy(() -> service.requireSession("raw-token", "session", "PHOTO_ALBUM"))
                .isInstanceOf(BusinessException.class)
                .hasFieldOrPropertyWithValue("errorCode", ErrorCode.RATE_LIMITED);
    }

    @Test
    void revokeInvalidatesShareLinkCache() {
        ShareLink share = shareLink(SHARE_ID, null);
        share.setTokenHash("0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef");
        when(shareLinkRepository.findByIdAndOwnerUserId(SHARE_ID, OWNER_ID))
                .thenReturn(Optional.of(share));
        when(shareLinkRepository.save(any(ShareLink.class)))
                .thenAnswer(invocation -> invocation.getArgument(0));

        service.revoke(OWNER_ID, SHARE_ID);

        verify(readThroughCache).invalidate(
                "omninest:share:link:0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef");
        assertThat(share.getDisabledAt()).isNotNull();
    }

    /**
     * 撤销是软删除：列表必须过滤已撤销链接，否则管理界面删除后重开仍显示。
     */
    @Test
    void listExcludesRevokedLinks() {
        ShareLink active = shareLink(SHARE_ID, null);
        ShareLink revoked = shareLink(
                UUID.fromString("30000000-0000-0000-0000-000000000002"),
                Instant.parse("2026-07-20T00:00:00Z"));
        when(shareLinkRepository.findByOwnerUserIdAndResourceIdIn(eq(OWNER_ID), any()))
                .thenReturn(List.of(active, revoked));

        var result = service.list(OWNER_ID, RESOURCE_ID);

        assertThat(result).extracting(dto -> dto.id()).containsExactly(SHARE_ID);
    }

    /**
     * 一键清空：撤销资源全部有效链接并返回条数。
     */
    @Test
    void revokeAllDisablesEveryActiveLink() {
        when(shareLinkRepository.findByResourceIdAndDisabledAtIsNull(RESOURCE_ID))
                .thenReturn(List.of(shareLink(SHARE_ID, null),
                        shareLink(UUID.fromString("30000000-0000-0000-0000-000000000003"), null)));

        int revoked = service.revokeAll(RESOURCE_ID);

        assertThat(revoked).isEqualTo(2);
        verify(shareLinkRepository).disableByResourceId(eq(RESOURCE_ID), any(Instant.class));
    }

    /**
     * 没有有效链接时不应触发批量更新（避免无谓写库）。
     */
    @Test
    void revokeAllSkipsUpdateWhenNothingActive() {
        when(shareLinkRepository.findByResourceIdAndDisabledAtIsNull(RESOURCE_ID))
                .thenReturn(List.of());

        int revoked = service.revokeAll(RESOURCE_ID);

        assertThat(revoked).isZero();
        verify(shareLinkRepository, never()).disableByResourceId(any(UUID.class), any(Instant.class));
    }

    /**
     * 列表回传解密后的明文令牌，供所有者重新复制既有链接地址。
     */
    @Test
    void listRevealsDecryptedToken() {
        ShareLink share = shareLink(SHARE_ID, null);
        share.setTokenCipher("v1:cipher");
        when(shareLinkRepository.findByOwnerUserIdAndResourceIdIn(eq(OWNER_ID), any()))
                .thenReturn(List.of(share));
        when(credentialCipher.decrypt("v1:cipher")).thenReturn("raw-token");

        var result = service.list(OWNER_ID, RESOURCE_ID);

        assertThat(result).extracting(dto -> dto.token()).containsExactly("raw-token");
    }

    /**
     * 历史链接没有密文时回传空令牌，不得因解密失败阻断列表。
     */
    @Test
    void listToleratesLinkWithoutCipher() {
        when(shareLinkRepository.findByOwnerUserIdAndResourceIdIn(eq(OWNER_ID), any()))
                .thenReturn(List.of(shareLink(SHARE_ID, null)));

        var result = service.list(OWNER_ID, RESOURCE_ID);

        assertThat(result).extracting(dto -> dto.token()).containsExactly((String) null);
    }

    /**
     * 验证原地更新只替换可变属性：令牌哈希与密文不变，因此已发出的地址继续可用。
     */
    @Test
    void updateKeepsTokenAndReplacesMutableAttributes() {
        ShareLink existing = updatableShareLink();
        String originalHash = existing.getTokenHash();
        when(shareLinkRepository.findByIdAndOwnerUserId(SHARE_ID, OWNER_ID))
                .thenReturn(Optional.of(existing));
        when(credentialCipher.decrypt("v1:cipher")).thenReturn("raw-token");
        when(passwordEncoder.encode("new-secret")).thenReturn("re-encoded");
        when(shareLinkRepository.save(any(ShareLink.class)))
                .thenAnswer(invocation -> invocation.getArgument(0));

        var result = service.update(
                OWNER_ID,
                SHARE_ID,
                "new-secret",
                Instant.parse("2026-12-31T00:00:00Z"),
                5,
                false,
                true
        );

        ArgumentCaptor<ShareLink> captor = ArgumentCaptor.forClass(ShareLink.class);
        verify(shareLinkRepository).save(captor.capture());
        ShareLink saved = captor.getValue();
        assertThat(saved.getTokenHash()).isEqualTo(originalHash);
        assertThat(saved.getTokenCipher()).isEqualTo("v1:cipher");
        assertThat(saved.getPasswordHash()).isEqualTo("re-encoded");
        assertThat(saved.getExpiresAt()).isEqualTo(Instant.parse("2026-12-31T00:00:00Z"));
        assertThat(saved.getMaxAccessCount()).isEqualTo(5);
        assertThat(saved.isIncludeLocation()).isFalse();
        assertThat(result.token()).isEqualTo("raw-token");
        verify(readThroughCache).invalidate("omninest:share:link:" + originalHash);
    }

    /**
     * 验证空白密码表示清除访问密码，而不是保留原值。
     */
    @Test
    void updateClearsPasswordWhenBlank() {
        ShareLink existing = updatableShareLink();
        existing.setPasswordHash("encoded");
        when(shareLinkRepository.findByIdAndOwnerUserId(SHARE_ID, OWNER_ID))
                .thenReturn(Optional.of(existing));
        when(credentialCipher.decrypt("v1:cipher")).thenReturn("raw-token");
        when(shareLinkRepository.save(any(ShareLink.class)))
                .thenAnswer(invocation -> invocation.getArgument(0));

        service.update(OWNER_ID, SHARE_ID, "   ", null, null, true, true);

        ArgumentCaptor<ShareLink> captor = ArgumentCaptor.forClass(ShareLink.class);
        verify(shareLinkRepository).save(captor.capture());
        assertThat(captor.getValue().getPasswordHash()).isNull();
        assertThat(captor.getValue().getExpiresAt()).isNull();
        verify(passwordEncoder, never()).encode(any(CharSequence.class));
    }

    /**
     * 验证密码缺省（null）保持原口令不变：调用方无法回读明文，
     * 若把缺省当清除，则改有效期会顺带抹掉已经发出去的提取码。
     */
    @Test
    void updateKeepsPasswordWhenOmitted() {
        ShareLink existing = updatableShareLink();
        existing.setPasswordHash("encoded");
        when(shareLinkRepository.findByIdAndOwnerUserId(SHARE_ID, OWNER_ID))
                .thenReturn(Optional.of(existing));
        when(credentialCipher.decrypt("v1:cipher")).thenReturn("raw-token");
        when(shareLinkRepository.save(any(ShareLink.class)))
                .thenAnswer(invocation -> invocation.getArgument(0));

        var result = service.update(
                OWNER_ID,
                SHARE_ID,
                null,
                Instant.parse("2026-12-31T00:00:00Z"),
                null,
                false,
                false
        );

        ArgumentCaptor<ShareLink> captor = ArgumentCaptor.forClass(ShareLink.class);
        verify(shareLinkRepository).save(captor.capture());
        assertThat(captor.getValue().getPasswordHash()).isEqualTo("encoded");
        assertThat(captor.getValue().getExpiresAt()).isEqualTo(Instant.parse("2026-12-31T00:00:00Z"));
        assertThat(captor.getValue().isIncludeLocation()).isFalse();
        assertThat(result.passwordProtected()).isTrue();
        verify(passwordEncoder, never()).encode(any(CharSequence.class));
    }

    /**
     * 验证过期时间早于当前时间被拒绝，避免更新出即刻失效的链接。
     */
    @Test
    void updateRejectsPastExpiry() {
        when(shareLinkRepository.findByIdAndOwnerUserId(SHARE_ID, OWNER_ID))
                .thenReturn(Optional.of(updatableShareLink()));

        assertThatThrownBy(() -> service.update(
                OWNER_ID,
                SHARE_ID,
                null,
                Instant.parse("2020-01-01T00:00:00Z"),
                null,
                true,
                true
        )).isInstanceOf(BusinessException.class)
                .extracting("errorCode")
                .isEqualTo(ErrorCode.PARAM_ERROR);
        verify(shareLinkRepository, never()).save(any(ShareLink.class));
    }

    /**
     * 验证访问次数上限不得低于已访问次数，否则链接会立即被判耗尽。
     */
    @Test
    void updateRejectsAccessCountBelowUsage() {
        ShareLink existing = updatableShareLink();
        existing.setAccessCount(7);
        when(shareLinkRepository.findByIdAndOwnerUserId(SHARE_ID, OWNER_ID))
                .thenReturn(Optional.of(existing));

        assertThatThrownBy(() -> service.update(
                OWNER_ID, SHARE_ID, null, null, 3, true, true
        )).isInstanceOf(BusinessException.class)
                .extracting("errorCode")
                .isEqualTo(ErrorCode.PARAM_ERROR);
    }

    /**
     * 验证非所有者按不存在处理，已撤销链接按业务错误拒绝。
     */
    @Test
    void updateRejectsUnknownOwnerAndRevokedLink() {
        when(shareLinkRepository.findByIdAndOwnerUserId(SHARE_ID, OWNER_ID))
                .thenReturn(Optional.empty());
        assertThatThrownBy(() -> service.update(
                OWNER_ID, SHARE_ID, null, null, null, true, true
        )).isInstanceOf(BusinessException.class)
                .extracting("errorCode")
                .isEqualTo(ErrorCode.NOT_FOUND);

        ShareLink revoked = updatableShareLink();
        revoked.setDisabledAt(Instant.parse("2026-07-20T00:00:00Z"));
        when(shareLinkRepository.findByIdAndOwnerUserId(SHARE_ID, OWNER_ID))
                .thenReturn(Optional.of(revoked));
        assertThatThrownBy(() -> service.update(
                OWNER_ID, SHARE_ID, null, null, null, true, true
        )).isInstanceOf(BusinessException.class)
                .extracting("errorCode")
                .isEqualTo(ErrorCode.BAD_REQUEST);
    }

    /** 构造一条可更新的分享链接夹具：带令牌哈希、密文与既有密码。 */
    private ShareLink updatableShareLink() {
        ShareLink share = shareLink(SHARE_ID, null);
        share.setTokenHash("token-hash");
        share.setTokenCipher("v1:cipher");
        share.setPasswordHash("encoded");
        share.setExpiresAt(Instant.parse("2026-08-19T00:00:00Z"));
        share.setAccessCount(2);
        share.setIncludeLocation(true);
        share.setOriginalQuality(true);
        return share;
    }

    private ShareLink shareLink(UUID id, Instant disabledAt) {
        ShareLink share = new ShareLink();
        share.setId(id);
        share.setOwnerUserId(OWNER_ID);
        share.setResourceType("PHOTO_ALBUM");
        share.setResourceId(RESOURCE_ID);
        share.setDisabledAt(disabledAt);
        share.setCreatedAt(Instant.parse("2026-07-19T00:00:00Z"));
        return share;
    }
}