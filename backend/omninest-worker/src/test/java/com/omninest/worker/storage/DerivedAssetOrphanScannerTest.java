package com.omninest.worker.storage;

import com.omninest.common.storage.ObjectStorageBuckets;
import com.omninest.common.storage.ObjectStorageClient;
import com.omninest.common.storage.ObjectStorageKey;
import com.omninest.common.storage.ObjectStorageObject;
import com.omninest.common.storage.ObjectStoragePage;
import com.omninest.common.util.RedisUtil;
import com.omninest.modules.file.service.FileObjectReferenceQuery;
import com.omninest.modules.reader.service.ReaderPageAssetReferenceQuery;
import com.omninest.modules.user.service.UserAvatarObjectReferenceQuery;
import java.time.Duration;
import java.time.Instant;
import java.util.List;
import java.util.Set;
import org.assertj.core.api.Assertions;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.ArgumentCaptor;
import org.mockito.Mock;
import org.mockito.Mockito;
import org.mockito.junit.jupiter.MockitoExtension;

/**
 * 派生对象孤儿扫描边界测试。
 *
 * @author OmniNest
 */
@ExtendWith(MockitoExtension.class)
class DerivedAssetOrphanScannerTest {
    private static final String BUCKET = "derived-assets";

    @Mock
    private ObjectStorageBuckets objectStorageBuckets;

    @Mock
    private ObjectStorageClient objectStorageClient;

    @Mock
    private FileObjectReferenceQuery fileObjectReferenceQuery;

    @Mock
    private ReaderPageAssetReferenceQuery readerPageAssetReferenceQuery;

    @Mock
    private UserAvatarObjectReferenceQuery userAvatarObjectReferenceQuery;

    @Mock
    private RedisUtil redisUtil;

    private DerivedAssetOrphanScanProperties properties;
    private DerivedAssetOrphanScanner scanner;

    @BeforeEach
    void setUp() {
        properties = new DerivedAssetOrphanScanProperties();
        scanner = new DerivedAssetOrphanScanner(
                objectStorageBuckets,
                objectStorageClient,
                fileObjectReferenceQuery,
                readerPageAssetReferenceQuery,
                userAvatarObjectReferenceQuery,
                List.of(),
                redisUtil,
                properties
        );
        Mockito.lenient().when(objectStorageBuckets.derivedAssets()).thenReturn(BUCKET);
        Mockito.when(redisUtil.newLockToken()).thenReturn("lock-token");
        Mockito.when(redisUtil.tryLock(
                "omninest:maintenance:derived-orphan-scan:lock",
                "lock-token",
                Duration.ofMinutes(30)
        )).thenReturn(true);
        Mockito.lenient().when(redisUtil.unlock(
                "omninest:maintenance:derived-orphan-scan:lock",
                "lock-token"
        )).thenReturn(true);
        Mockito.lenient().when(userAvatarObjectReferenceQuery.findReferencedObjectKeys(Mockito.anySet()))
                .thenReturn(Set.of());
    }

    @Test
    void dryRunUnionsReferencesAndIgnoresRecentObjects() {
        Instant old = Instant.now().minus(Duration.ofDays(2));
        Instant recent = Instant.now();
        ObjectStoragePage page = new ObjectStoragePage(List.of(
                object("derived/file.jpg", old),
                object("derived/page.jpg", old),
                object("avatars/user/avatar.webp", old),
                object("derived/orphan.jpg", old),
                object("derived/recent.jpg", recent)
        ), null);
        Mockito.when(objectStorageClient.listObjects(BUCKET, "", null, 500)).thenReturn(page);
        Set<String> candidates = Set.of(
                "derived/file.jpg",
                "derived/page.jpg",
                "avatars/user/avatar.webp",
                "derived/orphan.jpg"
        );
        Mockito.when(fileObjectReferenceQuery.findReferencedObjectKeys(BUCKET, candidates))
                .thenReturn(Set.of("derived/file.jpg"));
        Mockito.when(readerPageAssetReferenceQuery.findReferencedObjectKeys(BUCKET, candidates))
                .thenReturn(Set.of("derived/page.jpg"));
        Mockito.when(userAvatarObjectReferenceQuery.findReferencedObjectKeys(candidates))
                .thenReturn(Set.of("avatars/user/avatar.webp"));

        DerivedAssetOrphanScanResult result = scanner.scanOnce();

        Assertions.assertThat(result.executed()).isTrue();
        Assertions.assertThat(result.scannedObjects()).isEqualTo(5);
        Assertions.assertThat(result.eligibleObjects()).isEqualTo(4);
        Assertions.assertThat(result.referencedObjects()).isEqualTo(3);
        Assertions.assertThat(result.orphanObjects()).isEqualTo(1);
        Assertions.assertThat(result.deletedObjects()).isZero();
        Assertions.assertThat(result.completed()).isTrue();
        Mockito.verify(objectStorageClient, Mockito.never()).removeObject(Mockito.any());
        Mockito.verify(redisUtil).delete("omninest:maintenance:derived-orphan-scan:cursor");
    }

    @Test
    void deleteModeHonorsPerRunDeleteLimit() {
        properties.setDeleteEnabled(true);
        properties.setMaximumDeletesPerRun(1);
        Instant old = Instant.now().minus(Duration.ofDays(2));
        ObjectStoragePage page = new ObjectStoragePage(List.of(
                object("derived/orphan-1.jpg", old),
                object("derived/orphan-2.jpg", old)
        ), null);
        Mockito.when(objectStorageClient.listObjects(BUCKET, "", null, 500)).thenReturn(page);
        Set<String> candidates = Set.of("derived/orphan-1.jpg", "derived/orphan-2.jpg");
        Mockito.when(fileObjectReferenceQuery.findReferencedObjectKeys(BUCKET, candidates))
                .thenReturn(Set.of());
        Mockito.when(readerPageAssetReferenceQuery.findReferencedObjectKeys(BUCKET, candidates))
                .thenReturn(Set.of());

        DerivedAssetOrphanScanResult result = scanner.scanOnce();

        Assertions.assertThat(result.orphanObjects()).isEqualTo(2);
        Assertions.assertThat(result.deletedObjects()).isEqualTo(1);
        Assertions.assertThat(result.failedDeletions()).isZero();
        ArgumentCaptor<ObjectStorageKey> keyCaptor = ArgumentCaptor.forClass(ObjectStorageKey.class);
        Mockito.verify(objectStorageClient).removeObject(keyCaptor.capture());
        Assertions.assertThat(keyCaptor.getValue().bucket()).isEqualTo(BUCKET);
        Assertions.assertThat(keyCaptor.getValue().objectKey()).isIn(candidates);
    }

    @Test
    void boundedRunPersistsNextContinuationToken() {
        properties.setMaximumPagesPerRun(1);
        Mockito.when(redisUtil.get("omninest:maintenance:derived-orphan-scan:cursor"))
                .thenReturn("current-page");
        Mockito.when(objectStorageClient.listObjects(BUCKET, "", "current-page", 500))
                .thenReturn(new ObjectStoragePage(List.of(), "next-page"));

        DerivedAssetOrphanScanResult result = scanner.scanOnce();

        Assertions.assertThat(result.scannedPages()).isEqualTo(1);
        Assertions.assertThat(result.completed()).isFalse();
        Mockito.verify(redisUtil).set(
                "omninest:maintenance:derived-orphan-scan:cursor",
                "next-page",
                Duration.ofDays(30)
        );
    }

    @Test
    void missingDistributedLockSkipsStorageScan() {
        Mockito.when(redisUtil.tryLock(
                "omninest:maintenance:derived-orphan-scan:lock",
                "lock-token",
                Duration.ofMinutes(30)
        )).thenReturn(false);

        DerivedAssetOrphanScanResult result = scanner.scanOnce();

        Assertions.assertThat(result).isEqualTo(DerivedAssetOrphanScanResult.skipped());
        Mockito.verifyNoInteractions(objectStorageClient);
        Mockito.verify(redisUtil, Mockito.never()).unlock(Mockito.anyString(), Mockito.anyString());
    }

    private ObjectStorageObject object(String objectKey, Instant lastModified) {
        return new ObjectStorageObject(objectKey, 128L, lastModified);
    }
}
