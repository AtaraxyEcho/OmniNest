package com.omninest.modules.quota.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyLong;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import com.omninest.common.enums.ErrorCode;
import com.omninest.common.error.BusinessException;
import com.omninest.common.user.UserAccountQuery;
import com.omninest.common.user.UserAccountSummary;
import com.omninest.common.user.UserStorageCommand;
import com.omninest.modules.quota.domain.StorageQuotaReservation;
import com.omninest.modules.quota.repository.StorageQuotaReservationRepository;
import java.time.Instant;
import java.util.List;
import java.util.Optional;
import java.util.Set;
import java.util.UUID;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.ArgumentCaptor;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

/**
 * 持久化存储配额预留服务测试。
 *
 * @author OmniNest
 */
@ExtendWith(MockitoExtension.class)
class StorageQuotaReservationServiceTest {

    private static final UUID USER_ID = UUID.fromString("10000000-0000-0000-0000-000000000001");
    private static final UUID OTHER_USER_ID = UUID.fromString("10000000-0000-0000-0000-000000000002");
    private static final UUID SOURCE_ID = UUID.fromString("20000000-0000-0000-0000-000000000001");
    private static final UUID RESERVATION_ID = UUID.fromString("30000000-0000-0000-0000-000000000001");

    @Mock
    private StorageQuotaReservationRepository reservationRepository;

    @Mock
    private UserStorageCommand userStorageCommand;

    @Mock
    private UserAccountQuery userAccountQuery;

    private StorageQuotaReservationService service;

    @BeforeEach
    void setUp() {
        service = new StorageQuotaReservationService(
                reservationRepository,
                userStorageCommand,
                userAccountQuery
        );
    }

    @Test
    void reservesQuotaAtomicallyForNewSource() {
        when(reservationRepository.findBySourceTypeAndSourceId("UPLOAD", SOURCE_ID))
                .thenReturn(Optional.empty());
        when(userAccountQuery.findById(USER_ID)).thenReturn(Optional.of(user(false)));
        when(userStorageCommand.tryReserveStorage(USER_ID, 512L)).thenReturn(true);
        when(reservationRepository.save(any())).thenAnswer(invocation -> {
            StorageQuotaReservation reservation = invocation.getArgument(0);
            reservation.setId(RESERVATION_ID);
            return reservation;
        });

        UUID result = service.reserve(
                USER_ID,
                "upload",
                SOURCE_ID,
                512L,
                Instant.now().plusSeconds(600L)
        );

        assertThat(result).isEqualTo(RESERVATION_ID);
        verify(userStorageCommand).tryReserveStorage(USER_ID, 512L);
    }

    @Test
    void unlimitedQuotaReservationSkipsAtomicQuotaUpdate() {
        when(reservationRepository.findBySourceTypeAndSourceId("UPLOAD", SOURCE_ID))
                .thenReturn(Optional.empty());
        when(userAccountQuery.findById(USER_ID)).thenReturn(Optional.of(unlimitedUser()));
        when(reservationRepository.save(any())).thenAnswer(invocation -> {
            StorageQuotaReservation reservation = invocation.getArgument(0);
            reservation.setId(RESERVATION_ID);
            return reservation;
        });

        UUID result = service.reserve(
                USER_ID,
                "UPLOAD",
                SOURCE_ID,
                512L,
                Instant.now().plusSeconds(600L)
        );

        assertThat(result).isEqualTo(RESERVATION_ID);
        verify(userStorageCommand, never()).tryReserveStorage(any(), anyLong());
        ArgumentCaptor<StorageQuotaReservation> captor =
                ArgumentCaptor.forClass(StorageQuotaReservation.class);
        verify(reservationRepository).save(captor.capture());
        assertThat(captor.getValue().isQuotaApplied()).isFalse();
    }

    @Test
    void unlimitedReservationSettlementChargesUsageWithoutQuotaRelease() {
        StorageQuotaReservation reservation = reservation(USER_ID, SOURCE_ID, 512L, false);
        when(reservationRepository.findBySourceTypeAndSourceId("UPLOAD", SOURCE_ID))
                .thenReturn(Optional.of(reservation));
        when(reservationRepository.save(any())).thenAnswer(invocation -> invocation.getArgument(0));

        service.settle("UPLOAD", SOURCE_ID, 512L);

        verify(userStorageCommand).incrementUsage(USER_ID, 512L);
        verify(userStorageCommand, never()).settleStorageReservation(any(), anyLong(), anyLong());
        assertThat(reservation.getStatus()).isEqualTo("COMMITTED");
        assertThat(reservation.getCommittedBytes()).isEqualTo(512L);
    }

    @Test
    void rejectsReservationWhenAtomicQuotaUpdateFails() {
        when(reservationRepository.findBySourceTypeAndSourceId("UPLOAD", SOURCE_ID))
                .thenReturn(Optional.empty());
        when(userAccountQuery.findById(USER_ID)).thenReturn(Optional.of(user(false)));
        when(userStorageCommand.tryReserveStorage(USER_ID, 512L)).thenReturn(false);

        assertThatThrownBy(() -> service.reserve(
                USER_ID,
                "UPLOAD",
                SOURCE_ID,
                512L,
                Instant.now().plusSeconds(600L)
        )).isInstanceOf(BusinessException.class)
                .hasFieldOrPropertyWithValue("errorCode", ErrorCode.FILE_QUOTA_EXCEEDED);
    }

    @Test
    void settlesReservedBytesToCommittedUsage() {
        StorageQuotaReservation reservation = reservation(USER_ID, SOURCE_ID, 512L, true);
        when(reservationRepository.findBySourceTypeAndSourceId("UPLOAD", SOURCE_ID))
                .thenReturn(Optional.of(reservation));
        when(userStorageCommand.settleStorageReservation(USER_ID, 512L, 400L)).thenReturn(true);
        when(reservationRepository.save(any())).thenAnswer(invocation -> invocation.getArgument(0));

        service.settle("UPLOAD", SOURCE_ID, 400L);

        assertThat(reservation.getStatus()).isEqualTo("COMMITTED");
        assertThat(reservation.getCommittedBytes()).isEqualTo(400L);
    }

    @Test
    void releaseSettlesReservationWithZeroUsage() {
        StorageQuotaReservation reservation = reservation(USER_ID, SOURCE_ID, 512L, true);
        when(reservationRepository.findBySourceTypeAndSourceId("UPLOAD", SOURCE_ID))
                .thenReturn(Optional.of(reservation));
        when(userStorageCommand.settleStorageReservation(USER_ID, 512L, 0L)).thenReturn(true);
        when(reservationRepository.save(any())).thenAnswer(invocation -> invocation.getArgument(0));

        service.release("UPLOAD", SOURCE_ID);

        assertThat(reservation.getStatus()).isEqualTo("RELEASED");
        assertThat(reservation.getCommittedBytes()).isZero();
    }

    @Test
    void reclaimReportsOnlySuccessfullyExpiredReservations() {
        StorageQuotaReservation reclaimed = reservation(USER_ID, SOURCE_ID, 512L, true);
        StorageQuotaReservation retained = reservation(
                OTHER_USER_ID,
                UUID.fromString("20000000-0000-0000-0000-000000000002"),
                256L,
                true
        );
        when(reservationRepository.findByStatusAndExpiresAtBeforeOrderByExpiresAtAsc(
                eq("RESERVED"),
                any(Instant.class),
                any()
        )).thenReturn(List.of(reclaimed, retained));
        when(userStorageCommand.settleStorageReservation(USER_ID, 512L, 0L)).thenReturn(true);
        when(userStorageCommand.settleStorageReservation(OTHER_USER_ID, 256L, 0L)).thenReturn(false);
        when(reservationRepository.save(any())).thenAnswer(invocation -> invocation.getArgument(0));

        int count = service.reclaimExpired();

        assertThat(count).isEqualTo(1);
        assertThat(reclaimed.getStatus()).isEqualTo("EXPIRED");
        assertThat(retained.getStatus()).isEqualTo("RESERVED");
    }

    @Test
    void reactivatesFinishedReservationWhenRetryingSameSource() {
        StorageQuotaReservation reservation = reservation(USER_ID, SOURCE_ID, 512L, true);
        reservation.setStatus("RELEASED");
        when(reservationRepository.findBySourceTypeAndSourceId("BACKDROP_UPLOAD", SOURCE_ID))
                .thenReturn(Optional.of(reservation));
        when(userAccountQuery.findById(USER_ID)).thenReturn(Optional.of(user(false)));
        when(userStorageCommand.tryReserveStorage(USER_ID, 512L)).thenReturn(true);
        when(reservationRepository.save(any())).thenAnswer(invocation -> invocation.getArgument(0));

        UUID result = service.reserve(
                USER_ID,
                "BACKDROP_UPLOAD",
                SOURCE_ID,
                512L,
                Instant.now().plusSeconds(600L)
        );

        assertThat(result).isEqualTo(reservation.getId());
        assertThat(reservation.getStatus()).isEqualTo("RESERVED");
        assertThat(reservation.getCommittedBytes()).isZero();
        verify(userStorageCommand).tryReserveStorage(USER_ID, 512L);
    }

    @Test
    void reentrantReservationReservesOnlyOutstandingDifference() {
        StorageQuotaReservation reservation = reservation(USER_ID, SOURCE_ID, 512L, true);
        reservation.setStatus("RELEASED");
        reservation.setCommittedBytes(300L);
        when(reservationRepository.findBySourceTypeAndSourceId("UPLOAD", SOURCE_ID))
                .thenReturn(Optional.of(reservation));
        when(userAccountQuery.findById(USER_ID)).thenReturn(Optional.of(user(false)));
        when(userStorageCommand.tryReserveStorage(USER_ID, 212L)).thenReturn(true);
        when(reservationRepository.save(any())).thenAnswer(invocation -> invocation.getArgument(0));

        UUID result = service.reserve(
                USER_ID,
                "UPLOAD",
                SOURCE_ID,
                512L,
                Instant.now().plusSeconds(600L)
        );

        assertThat(result).isEqualTo(reservation.getId());
        assertThat(reservation.getStatus()).isEqualTo("RESERVED");
        assertThat(reservation.getCommittedBytes()).isEqualTo(300L);
        assertThat(reservation.getReservedBytes()).isEqualTo(212L);
        verify(userStorageCommand).tryReserveStorage(USER_ID, 212L);
    }

    @Test
    void retriedImportReservesRemainderAndSettlesFullSize() {
        StorageQuotaReservation reservation = reservation(USER_ID, SOURCE_ID, 1000L, true);
        reservation.setStatus("COMMITTED");
        reservation.setCommittedBytes(500L);
        when(reservationRepository.findBySourceTypeAndSourceId("EXTERNAL_IMPORT", SOURCE_ID))
                .thenReturn(Optional.of(reservation));
        when(userAccountQuery.findById(USER_ID)).thenReturn(Optional.of(user(false)));
        when(userStorageCommand.tryReserveStorage(USER_ID, 500L)).thenReturn(true);
        when(userStorageCommand.settleStorageReservation(USER_ID, 500L, 500L)).thenReturn(true);
        when(reservationRepository.save(any())).thenAnswer(invocation -> invocation.getArgument(0));

        service.reserve(USER_ID, "EXTERNAL_IMPORT", SOURCE_ID, 1000L, Instant.now().plusSeconds(600L));
        service.settle("EXTERNAL_IMPORT", SOURCE_ID, 1000L);

        // 上一轮已结算的 500 不重复预留，重试只补差额；最终累计记账 1000。
        verify(userStorageCommand).tryReserveStorage(USER_ID, 500L);
        verify(userStorageCommand).settleStorageReservation(USER_ID, 500L, 500L);
        assertThat(reservation.getCommittedBytes()).isEqualTo(1000L);
        assertThat(reservation.getStatus()).isEqualTo("COMMITTED");
    }

    @Test
    void settlesBytesThatLandedAfterReservationExpired() {
        StorageQuotaReservation reservation = reservation(USER_ID, SOURCE_ID, 512L, true);
        reservation.setStatus("EXPIRED");
        reservation.setReservedBytes(0L);
        when(reservationRepository.findBySourceTypeAndSourceId("EXTERNAL_IMPORT", SOURCE_ID))
                .thenReturn(Optional.of(reservation));
        when(reservationRepository.save(any())).thenAnswer(invocation -> invocation.getArgument(0));

        service.settle("EXTERNAL_IMPORT", SOURCE_ID, 300L);

        // 过期回收只退回了预留，落库字节仍必须记入已用配额。
        verify(userStorageCommand).incrementUsage(USER_ID, 300L);
        assertThat(reservation.getCommittedBytes()).isEqualTo(300L);
        assertThat(reservation.getStatus()).isEqualTo("COMMITTED");
    }

    @Test
    void repeatedSettlementOfCommittedSourceDoesNotDoubleCount() {
        StorageQuotaReservation reservation = reservation(USER_ID, SOURCE_ID, 512L, true);
        reservation.setStatus("COMMITTED");
        reservation.setCommittedBytes(512L);
        reservation.setReservedBytes(0L);
        when(reservationRepository.findBySourceTypeAndSourceId("UPLOAD", SOURCE_ID))
                .thenReturn(Optional.of(reservation));

        service.settle("UPLOAD", SOURCE_ID, 512L);

        verify(userStorageCommand, never()).incrementUsage(any(), anyLong());
        verify(userStorageCommand, never()).settleStorageReservation(any(), anyLong(), anyLong());
    }

    private UserAccountSummary user(boolean superAdmin) {
        return new UserAccountSummary(USER_ID, "owner", Set.of(), superAdmin, 1024L, 0L);
    }

    private UserAccountSummary unlimitedUser() {
        return new UserAccountSummary(USER_ID, "owner", Set.of(), false, 0L, 4096L);
    }

    private StorageQuotaReservation reservation(
            UUID ownerUserId,
            UUID sourceId,
            long bytes,
            boolean quotaApplied
    ) {
        StorageQuotaReservation reservation = new StorageQuotaReservation();
        reservation.setId(UUID.randomUUID());
        reservation.setOwnerUserId(ownerUserId);
        reservation.setSourceType("UPLOAD");
        reservation.setSourceId(sourceId);
        reservation.setReservedBytes(bytes);
        reservation.setCommittedBytes(0L);
        reservation.setQuotaApplied(quotaApplied);
        reservation.setStatus("RESERVED");
        reservation.setExpiresAt(Instant.now().minusSeconds(60L));
        return reservation;
    }
}
