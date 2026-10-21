package com.omninest.worker.storage;

import com.omninest.common.storage.ObjectStorageBuckets;
import com.omninest.common.storage.ObjectStorageClient;
import com.omninest.common.storage.ObjectStorageKey;
import com.omninest.common.storage.ObjectStorageObject;
import com.omninest.common.storage.ObjectStoragePage;
import com.omninest.common.util.RedisUtil;
import com.omninest.modules.file.service.FileIngressObjectReferenceQuery;
import com.omninest.modules.file.service.FileObjectReferenceQuery;
import java.time.Duration;
import java.time.Instant;
import java.util.List;
import java.util.Set;
import org.assertj.core.api.Assertions;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.ArgumentCaptor;
import org.mockito.Mock;
import org.mockito.Mockito;
import org.mockito.junit.jupiter.MockitoExtension;

/**
 * 原件对象孤儿扫描边界测试。
 *
 * @author OmniNest
 */
@ExtendWith(MockitoExtension.class)
class UserFileOrphanScannerTest {
    private static final String BUCKET = "user-files";
    private static final String LOCK = "omninest:maintenance:user-file-orphan-scan:lock";
    private static final String CURSOR = "omninest:maintenance:user-file-orphan-scan:cursor";
    private static final String METADATA_KEY = "users/u1/files/n1/a.pdf";
    private static final String IN_FLIGHT_KEY = "users/u1/files/n2/b.jpg";
    private static final String ORPHAN_KEY = "users/u1/files/n3/c.jpg";
    private static final String RECENT_KEY = "users/u1/files/n4/d.pdf";

    @Mock
    private ObjectStorageBuckets objectStorageBuckets;

    @Mock
    private ObjectStorageClient objectStorageClient;

    @Mock
    private FileObjectReferenceQuery fileObjectReferenceQuery;

    @Mock
    private FileIngressObjectReferenceQuery fileIngressObjectReferenceQuery;

    @Mock
    private RedisUtil redisUtil;

    private UserFileOrphanScanProperties properties;
    private UserFileOrphanScanner scanner;

    @BeforeEach
    void setUp() {
        properties = new UserFileOrphanScanProperties();
        scanner = new UserFileOrphanScanner(
                objectStorageBuckets,
                objectStorageClient,
                fileObjectReferenceQuery,
                fileIngressObjectReferenceQuery,
                redisUtil,
                properties
        );
        Mockito.lenient().when(objectStorageBuckets.userFiles()).thenReturn(BUCKET);
        Mockito.when(redisUtil.newLockToken()).thenReturn("lock-token");
        Mockito.when(redisUtil.tryLock(LOCK, "lock-token", Duration.ofMinutes(30))).thenReturn(true);
        Mockito.lenient().when(redisUtil.unlock(LOCK, "lock-token")).thenReturn(true);
    }

    @Test
    @DisplayName("默认只报告孤儿：元数据行与在途入库记录持有的对象都不算孤儿")
    void dryRunExcludesMetadataRowsAndInFlightSessionsAndCountsBytes() {
        Instant old = Instant.now().minus(Duration.ofDays(31));
        Instant recent = Instant.now();
        Mockito.when(objectStorageClient.listObjects(BUCKET, "", null, 500)).thenReturn(
                new ObjectStoragePage(List.of(
                        object(METADATA_KEY, old, 303L),
                        object(IN_FLIGHT_KEY, old, 404L),
                        object(ORPHAN_KEY, old, 500L),
                        object(RECENT_KEY, recent, 600L)
                ), null));
        Set<String> eligible = Set.of(METADATA_KEY, IN_FLIGHT_KEY, ORPHAN_KEY);
        Mockito.when(fileObjectReferenceQuery.findReferencedObjectKeys(BUCKET, eligible))
                .thenReturn(Set.of(METADATA_KEY));
        Mockito.when(fileIngressObjectReferenceQuery.findInFlightObjectKeys(
                        BUCKET, Set.of(IN_FLIGHT_KEY, ORPHAN_KEY)))
                .thenReturn(Set.of(IN_FLIGHT_KEY));

        UserFileOrphanScanResult result = scanner.scanOnce();

        Assertions.assertThat(result.executed()).isTrue();
        Assertions.assertThat(result.scannedObjects()).isEqualTo(4);
        Assertions.assertThat(result.eligibleObjects()).isEqualTo(3);
        Assertions.assertThat(result.referencedObjects()).isEqualTo(1);
        Assertions.assertThat(result.ingressHeldObjects()).isEqualTo(1);
        Assertions.assertThat(result.orphanObjects()).isEqualTo(1);
        Assertions.assertThat(result.orphanBytes()).isEqualTo(500L);
        Assertions.assertThat(result.deletedObjects()).isZero();
        Assertions.assertThat(result.deletedBytes()).isZero();
        Assertions.assertThat(result.completed()).isTrue();
        Mockito.verify(objectStorageClient, Mockito.never()).removeObject(Mockito.any());
        Mockito.verify(redisUtil).delete(CURSOR);
    }

    @Test
    @DisplayName("显式开启删除后仍受每轮删除上限约束")
    void deleteModeHonorsPerRunLimitAndAccountsBytes() {
        properties.setDeleteEnabled(true);
        properties.setMaximumDeletesPerRun(1);
        Instant old = Instant.now().minus(Duration.ofDays(31));
        String secondOrphan = "users/u1/files/n5/e.jpg";
        Mockito.when(objectStorageClient.listObjects(BUCKET, "", null, 500)).thenReturn(
                new ObjectStoragePage(List.of(
                        object(ORPHAN_KEY, old, 700L),
                        object(secondOrphan, old, 800L)
                ), null));
        Set<String> candidates = Set.of(ORPHAN_KEY, secondOrphan);
        Mockito.when(fileObjectReferenceQuery.findReferencedObjectKeys(BUCKET, candidates))
                .thenReturn(Set.of());
        Mockito.when(fileIngressObjectReferenceQuery.findInFlightObjectKeys(BUCKET, candidates))
                .thenReturn(Set.of());

        UserFileOrphanScanResult result = scanner.scanOnce();

        Assertions.assertThat(result.orphanObjects()).isEqualTo(2);
        Assertions.assertThat(result.orphanBytes()).isEqualTo(1500L);
        Assertions.assertThat(result.deletedObjects()).isEqualTo(1);
        Assertions.assertThat(result.deletedBytes()).isIn(700L, 800L);
        Assertions.assertThat(result.failedDeletions()).isZero();
        ArgumentCaptor<ObjectStorageKey> keyCaptor = ArgumentCaptor.captor();
        Mockito.verify(objectStorageClient).removeObject(keyCaptor.capture());
        Assertions.assertThat(keyCaptor.getValue().bucket()).isEqualTo(BUCKET);
        Assertions.assertThat(keyCaptor.getValue().objectKey()).isIn(candidates);
    }

    @Test
    @DisplayName("删除失败只计入失败数，不虚报已释放字节")
    void failedDeletionIsCountedSeparately() {
        properties.setDeleteEnabled(true);
        Instant old = Instant.now().minus(Duration.ofDays(31));
        Mockito.when(objectStorageClient.listObjects(BUCKET, "", null, 500)).thenReturn(
                new ObjectStoragePage(List.of(object(ORPHAN_KEY, old, 500L)), null));
        Mockito.when(fileObjectReferenceQuery.findReferencedObjectKeys(BUCKET, Set.of(ORPHAN_KEY)))
                .thenReturn(Set.of());
        Mockito.when(fileIngressObjectReferenceQuery.findInFlightObjectKeys(BUCKET, Set.of(ORPHAN_KEY)))
                .thenReturn(Set.of());
        Mockito.doThrow(new IllegalStateException("存储不可达"))
                .when(objectStorageClient).removeObject(new ObjectStorageKey(BUCKET, ORPHAN_KEY));

        UserFileOrphanScanResult result = scanner.scanOnce();

        Assertions.assertThat(result.orphanObjects()).isEqualTo(1);
        Assertions.assertThat(result.deletedObjects()).isZero();
        Assertions.assertThat(result.deletedBytes()).isZero();
        Assertions.assertThat(result.failedDeletions()).isEqualTo(1);
    }

    @Test
    @DisplayName("空页不查询引用源，有界轮次保存续查标识")
    void boundedRunPersistsCursorWithoutQueryingReferences() {
        properties.setMaximumPagesPerRun(1);
        Mockito.when(redisUtil.get(CURSOR)).thenReturn("current-page");
        Mockito.when(objectStorageClient.listObjects(BUCKET, "", "current-page", 500))
                .thenReturn(new ObjectStoragePage(List.of(), "next-page"));

        UserFileOrphanScanResult result = scanner.scanOnce();

        Assertions.assertThat(result.scannedPages()).isEqualTo(1);
        Assertions.assertThat(result.eligibleObjects()).isZero();
        Assertions.assertThat(result.completed()).isFalse();
        Mockito.verifyNoInteractions(fileObjectReferenceQuery, fileIngressObjectReferenceQuery);
        Mockito.verify(redisUtil).set(CURSOR, "next-page", Duration.ofDays(30));
    }

    @Test
    @DisplayName("未获得执行锁时不访问对象存储")
    void missingDistributedLockSkipsStorageScan() {
        Mockito.when(redisUtil.tryLock(LOCK, "lock-token", Duration.ofMinutes(30))).thenReturn(false);

        UserFileOrphanScanResult result = scanner.scanOnce();

        Assertions.assertThat(result).isEqualTo(UserFileOrphanScanResult.skipped());
        Mockito.verifyNoInteractions(objectStorageClient);
        Mockito.verify(redisUtil, Mockito.never()).unlock(Mockito.anyString(), Mockito.anyString());
    }

    private ObjectStorageObject object(String objectKey, Instant lastModified, long sizeBytes) {
        return new ObjectStorageObject(objectKey, sizeBytes, lastModified);
    }
}
