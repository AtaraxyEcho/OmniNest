package com.omninest.modules.quota.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyLong;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.times;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import com.omninest.common.audit.AdminAuditRecorder;
import com.omninest.common.enums.ErrorCode;
import com.omninest.common.error.BusinessException;
import com.omninest.common.user.UserAccountDetails;
import com.omninest.common.user.UserAccountQuery;
import com.omninest.common.user.UserAccountSummary;
import com.omninest.common.user.UserStorageCommand;
import com.omninest.modules.notification.service.NotificationService;
import com.omninest.modules.quota.QuotaStatus;
import com.omninest.modules.quota.port.StorageMetricsQuery;
import com.omninest.modules.quota.port.StorageQuotaPolicy;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.Set;
import java.util.UUID;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.ArgumentCaptor;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

/**
 * 存储配额服务测试。
 *
 * @author OmniNest
 */
@ExtendWith(MockitoExtension.class)
class StorageQuotaServiceTest {

    @Mock
    private UserAccountQuery userAccountQuery;
    @Mock
    private UserStorageCommand userStorageCommand;
    @Mock
    private StorageMetricsQuery storageMetricsQuery;
    @Mock
    private StorageQuotaPolicy storageQuotaPolicy;
    @Mock
    private AdminAuditRecorder auditRecorder;
    @Mock
    private NotificationService notificationService;
    @Mock
    private StorageQuotaReservationService reservationService;

    private StorageQuotaService service;

    private static final UUID USER_ID = UUID.fromString("aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa");
    private static final UUID SUPER_ADMIN_ID = UUID.fromString("bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb");

    @BeforeEach
    void setUp() {
        service = new StorageQuotaService(
                userAccountQuery,
                userStorageCommand,
                storageMetricsQuery,
                storageQuotaPolicy,
                auditRecorder,
                notificationService,
                reservationService
        );
    }

    // ─── checkQuota ───

    @Test
    @DisplayName("checkQuota: 配额充足时不抛异常")
    void checkQuotaSufficientDoesNotThrow() {
        UserAccountSummary user = userWith(1000, 500);
        when(userAccountQuery.findById(USER_ID)).thenReturn(Optional.of(user));

        service.checkQuota(USER_ID, 400);
        // 不抛异常即通过
    }

    @Test
    @DisplayName("checkQuota: 配额不足时抛出 FILE_QUOTA_EXCEEDED")
    void checkQuotaInsufficientThrows() {
        UserAccountSummary user = userWith(1000, 800);
        when(userAccountQuery.findById(USER_ID)).thenReturn(Optional.of(user));

        assertThatThrownBy(() -> service.checkQuota(USER_ID, 300))
                .isInstanceOf(BusinessException.class)
                .hasFieldOrPropertyWithValue("errorCode", ErrorCode.FILE_QUOTA_EXCEEDED);
    }

    @Test
    @DisplayName("checkQuota: 超级管理员跳过配额检查")
    void checkQuotaSkipsForSuperAdmin() {
        UserAccountSummary user = superAdminUser(100, 90);
        when(userAccountQuery.findById(SUPER_ADMIN_ID)).thenReturn(Optional.of(user));

        // 超级管理员即使超出配额也不抛异常
        service.checkQuota(SUPER_ADMIN_ID, 1000);
    }

    @Test
    @DisplayName("checkQuota: 用户不存在时抛出 UNAUTHORIZED")
    void checkQuotaUserNotFoundThrows() {
        when(userAccountQuery.findById(USER_ID)).thenReturn(Optional.empty());

        assertThatThrownBy(() -> service.checkQuota(USER_ID, 100))
                .isInstanceOf(BusinessException.class)
                .hasFieldOrPropertyWithValue("errorCode", ErrorCode.UNAUTHORIZED);
    }

    // ─── incrementUsage ───

    @Test
    @DisplayName("incrementUsage: 正常增加用量")
    void incrementUsageAddsBytes() {
        when(userStorageCommand.incrementUsage(USER_ID, 200))
                .thenReturn(userWith(1000, 700));

        service.incrementUsage(USER_ID, 200);

        verify(userStorageCommand).incrementUsage(USER_ID, 200);
    }

    @Test
    @DisplayName("incrementUsage: bytes 为 0 时不操作")
    void incrementUsageZeroBytesNoop() {
        service.incrementUsage(USER_ID, 0);
        verify(userStorageCommand, never()).incrementUsage(any(), anyLong());
    }

    @Test
    @DisplayName("incrementUsage: bytes 为负数时不操作")
    void incrementUsageNegativeBytesNoop() {
        service.incrementUsage(USER_ID, -100);
        verify(userStorageCommand, never()).incrementUsage(any(), anyLong());
    }

    // ─── decrementUsage ───

    @Test
    @DisplayName("decrementUsage: 正常减少用量")
    void decrementUsageSubtractsBytes() {
        service.decrementUsage(USER_ID, 200);

        verify(userStorageCommand).decrementUsage(USER_ID, 200);
    }

    @Test
    @DisplayName("decrementUsage: 减少量超过已用量时归零")
    void decrementUsageClampsToZero() {
        service.decrementUsage(USER_ID, 500);

        verify(userStorageCommand).decrementUsage(USER_ID, 500);
    }

    @Test
    @DisplayName("decrementUsage: 用户不存在时不抛异常")
    void decrementUsageUserNotFoundNoop() {
        service.decrementUsage(USER_ID, 100);
        // 不抛异常
    }

    // ─── updateQuota ───

    @Test
    @DisplayName("updateQuota: 正常修改配额")
    void updateQuotaSuccess() {
        UserAccountSummary user = userWith(1000, 500);
        when(userAccountQuery.findById(USER_ID)).thenReturn(Optional.of(user));
        UUID operatorId = UUID.randomUUID();

        service.updateQuota(USER_ID, 2000, operatorId);

        verify(userStorageCommand).updateQuota(USER_ID, 2000);
        ArgumentCaptor<Map<String, Object>> payloadCaptor = ArgumentCaptor.forClass(Map.class);
        verify(auditRecorder).recordWithPayload(
                any(), eq("ADMIN_QUOTA_UPDATE"), eq("auth_users"), eq(USER_ID), payloadCaptor.capture());
        assertThat(payloadCaptor.getValue())
                .containsEntry("oldQuotaBytes", 1000L)
                .containsEntry("newQuotaBytes", 2000L)
                .containsEntry("changeBy", operatorId.toString());
    }

    @Test
    @DisplayName("updateQuotaAndGetDetails: 返回更新后的公共账户详情")
    void updateQuotaAndGetDetailsReturnsUpdatedContract() {
        UUID operatorId = UUID.randomUUID();
        UserAccountSummary user = userWith(1000, 500);
        UserAccountDetails details = new UserAccountDetails(
                USER_ID,
                "testuser",
                "Test User",
                null,
                "test@example.com",
                "ACTIVE",
                "MEMBER",
                Set.of("MEMBER"),
                Set.of("file:read"),
                2000,
                500
        );
        when(userAccountQuery.findById(USER_ID)).thenReturn(Optional.of(user));
        when(userAccountQuery.findDetailsById(USER_ID)).thenReturn(Optional.of(details));

        UserAccountDetails result = service.updateQuotaAndGetDetails(USER_ID, 2000, operatorId);

        assertThat(result).isEqualTo(details);
        verify(userStorageCommand).updateQuota(USER_ID, 2000);
        verify(userAccountQuery).findDetailsById(USER_ID);
    }

    @Test
    @DisplayName("updateQuota: 新配额小于已用量时拒绝")
    void updateQuotaRejectsWhenBelowUsed() {
        UserAccountSummary user = userWith(1000, 800);
        when(userAccountQuery.findById(USER_ID)).thenReturn(Optional.of(user));

        assertThatThrownBy(() -> service.updateQuota(USER_ID, 500, UUID.randomUUID()))
                .isInstanceOf(BusinessException.class)
                .hasFieldOrPropertyWithValue("errorCode", ErrorCode.PARAM_ERROR);
    }

    @Test
    @DisplayName("updateQuota: 超级管理员不可修改")
    void updateQuotaRejectsSuperAdmin() {
        UserAccountSummary user = superAdminUser(0, 0);
        when(userAccountQuery.findById(SUPER_ADMIN_ID)).thenReturn(Optional.of(user));

        assertThatThrownBy(() -> service.updateQuota(SUPER_ADMIN_ID, 5000, UUID.randomUUID()))
                .isInstanceOf(BusinessException.class)
                .hasFieldOrPropertyWithValue("errorCode", ErrorCode.FORBIDDEN);
    }

    // ─── getDefaultQuotaBytes ───

    @Test
    @DisplayName("getDefaultQuotaBytes: 委托配额策略读取默认值")
    void getDefaultQuotaBytesDelegatesToPolicy() {
        when(storageQuotaPolicy.defaultQuotaBytes()).thenReturn(50L * 1024 * 1024 * 1024);

        long result = service.getDefaultQuotaBytes();

        assertThat(result).isEqualTo(50L * 1024 * 1024 * 1024);
    }

    // ─── getQuotaStatus ───

    @Test
    @DisplayName("getQuotaStatus: 正常用户返回对应状态")
    void getQuotaStatusReturnsCorrectStatus() {
        UserAccountSummary user = userWith(1000, 500);
        when(userAccountQuery.findById(USER_ID)).thenReturn(Optional.of(user));
        when(storageQuotaPolicy.resolveStatus(500, 1000, false)).thenReturn(QuotaStatus.NORMAL);

        QuotaStatus status = service.getQuotaStatus(USER_ID);
        assertThat(status).isEqualTo(QuotaStatus.NORMAL);
    }

    @Test
    @DisplayName("getQuotaStatus: 超级管理员始终返回 NORMAL")
    void getQuotaStatusSuperAdminAlwaysNormal() {
        UserAccountSummary user = superAdminUser(100, 99);
        when(userAccountQuery.findById(SUPER_ADMIN_ID)).thenReturn(Optional.of(user));

        QuotaStatus status = service.getQuotaStatus(SUPER_ADMIN_ID);
        assertThat(status).isEqualTo(QuotaStatus.NORMAL);
    }

    @Test
    @DisplayName("getQuotaStatus: 用户不存在返回 NORMAL")
    void getQuotaStatusUserNotFoundReturnsNormal() {
        when(userAccountQuery.findById(USER_ID)).thenReturn(Optional.empty());

        QuotaStatus status = service.getQuotaStatus(USER_ID);
        assertThat(status).isEqualTo(QuotaStatus.NORMAL);
    }

    // ─── resolveQuotaStatus ───

    @Test
    @DisplayName("resolveQuotaStatus: 超级管理员始终返回 NORMAL")
    void resolveQuotaStatusSuperAdminAlwaysNormal() {
        when(storageQuotaPolicy.resolveStatus(999, 1000, true)).thenReturn(QuotaStatus.NORMAL);

        QuotaStatus status = service.resolveQuotaStatus(999, 1000, true);
        assertThat(status).isEqualTo(QuotaStatus.NORMAL);
    }

    @Test
    @DisplayName("resolveQuotaStatus: 普通用户按比例返回")
    void resolveQuotaStatusNormalUser() {
        when(storageQuotaPolicy.resolveStatus(500, 1000, false)).thenReturn(QuotaStatus.NORMAL);

        QuotaStatus status = service.resolveQuotaStatus(500, 1000, false);
        assertThat(status).isEqualTo(QuotaStatus.NORMAL);
    }

    // ─── batchUpdateQuota ───

    @Test
    @DisplayName("batchUpdateQuota: 跳过超级管理员")
    void batchUpdateQuotaSkipsSuperAdmin() {
        UserAccountSummary normalUser = userWith(1000, 200);
        UserAccountSummary superAdmin = superAdminUser(0, 0);
        when(userAccountQuery.findById(USER_ID)).thenReturn(Optional.of(normalUser));
        when(userAccountQuery.findById(SUPER_ADMIN_ID)).thenReturn(Optional.of(superAdmin));

        int updated = service.batchUpdateQuota(
                List.of(USER_ID, SUPER_ADMIN_ID), 5000, UUID.randomUUID());

        assertThat(updated).isEqualTo(1);
        verify(userStorageCommand).updateQuota(USER_ID, 5000);
    }

    @Test
    void recalculateAllUsagesProcessesBoundedBatchesAndIncludesZeroUsage() {
        List<UUID> firstBatch = new ArrayList<>();
        for (int index = 0; index < 200; index++) {
            firstBatch.add(new UUID(0L, index + 1L));
        }
        UUID finalUserId = new UUID(0L, 201L);
        when(userAccountQuery.findIdsAfter(null, 200)).thenReturn(firstBatch);
        when(userAccountQuery.findIdsAfter(firstBatch.getLast(), 200))
                .thenReturn(List.of(finalUserId));
        when(storageMetricsQuery.actualUsageByUsers(firstBatch))
                .thenReturn(Map.of(firstBatch.getFirst(), 1024L));
        when(storageMetricsQuery.actualUsageByUsers(List.of(finalUserId)))
                .thenReturn(Map.of());
        when(userStorageCommand.reconcileUsage(any())).thenReturn(2, 1);

        int updated = service.recalculateAllUsages();

        assertThat(updated).isEqualTo(3);
        verify(storageMetricsQuery).actualUsageByUsers(firstBatch);
        verify(storageMetricsQuery).actualUsageByUsers(List.of(finalUserId));
        verify(userStorageCommand, times(2)).reconcileUsage(any());
    }

    // ─── 辅助方法 ───

    private UserAccountSummary userWith(long quotaBytes, long usedBytes) {
        return new UserAccountSummary(USER_ID, "testuser", Set.of(), false, quotaBytes, usedBytes);
    }

    private UserAccountSummary superAdminUser(long quotaBytes, long usedBytes) {
        return new UserAccountSummary(
                SUPER_ADMIN_ID, "superadmin", Set.of(), true, quotaBytes, usedBytes);
    }
}
