package com.omninest.modules.file.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import com.omninest.modules.file.domain.ShareLink;
import com.omninest.modules.file.repository.ShareLinkRepository;
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
    private final ShareAccessSessionService sessionService = new ShareAccessSessionService();
    private final RateLimitService rateLimitService = mock(RateLimitService.class);
    private final CredentialCipher credentialCipher = mock(CredentialCipher.class);
    private final ResourceShareLinkService service = new ResourceShareLinkService(
            shareLinkRepository,
            passwordEncoder,
            sessionService,
            rateLimitService,
            credentialCipher
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
    void sessionAccessRejectsRateLimitExhaustion() {
        when(rateLimitService.tryAcquire(anyString(),
                org.mockito.ArgumentMatchers.anyInt(), any(Duration.class))).thenReturn(false);

        assertThatThrownBy(() -> service.requireSession("raw-token", "session", "PHOTO_ALBUM"))
                .isInstanceOf(BusinessException.class)
                .hasFieldOrPropertyWithValue("errorCode", ErrorCode.RATE_LIMITED);
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