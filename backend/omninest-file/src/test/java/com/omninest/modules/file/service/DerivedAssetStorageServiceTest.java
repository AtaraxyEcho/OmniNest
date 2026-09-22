package com.omninest.modules.file.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.times;
import static org.mockito.Mockito.doThrow;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import com.omninest.modules.file.config.FileTransferLimitsProperties;
import com.omninest.modules.file.domain.SpaceType;
import com.omninest.common.error.BusinessException;
import com.omninest.common.security.SafeUrlValidator;
import com.omninest.common.storage.ObjectStorageBuckets;
import com.omninest.common.storage.ObjectStorageClient;
import com.omninest.common.storage.ObjectStorageKey;
import com.omninest.modules.file.domain.FileNode;
import com.omninest.modules.file.domain.FileObject;
import com.omninest.modules.file.repository.FileNodeRepository;
import com.omninest.modules.file.repository.FileObjectRepository;
import com.sun.net.httpserver.HttpServer;
import java.io.ByteArrayInputStream;
import java.io.InputStream;
import java.io.RandomAccessFile;
import java.net.InetSocketAddress;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.List;
import java.util.Optional;
import java.util.UUID;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.io.TempDir;
import org.mockito.ArgumentCaptor;
import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.support.SimpleTransactionStatus;
import org.springframework.transaction.support.TransactionCallback;
import org.springframework.transaction.support.TransactionTemplate;

/**
 * 派生资源存储服务单元测试。
 *
 * @author OmniNest
 */
class DerivedAssetStorageServiceTest {
    private static final UUID OWNER_ID = UUID.fromString("10000000-0000-0000-0000-000000000001");
    private static final UUID RESOURCE_ID = UUID.fromString("60000000-0000-0000-0000-000000000001");
    private static final UUID FILE_NODE_ID = UUID.fromString("70000000-0000-0000-0000-000000000001");
    private static final UUID FILE_OBJECT_ID = UUID.fromString("80000000-0000-0000-0000-000000000001");

    private final ObjectStorageClient objectStorageClient = mock(ObjectStorageClient.class);
    private final FileObjectRepository fileObjectRepository = mock(FileObjectRepository.class);
    private final FileNodeRepository fileNodeRepository = mock(FileNodeRepository.class);
    private final SafeUrlValidator safeUrlValidator = mock(SafeUrlValidator.class);
    private final TransactionTemplate transactionTemplate = mock(TransactionTemplate.class);
    private final PlatformTransactionManager platformTransactionManager = mock(PlatformTransactionManager.class);

    private void allowTransactionCallback() {
        when(transactionTemplate.execute(any())).thenAnswer(invocation ->
                ((TransactionCallback<?>) invocation.getArgument(0)).doInTransaction(null));
    }

    private void allowStoreTransaction() {
        when(transactionTemplate.getTransactionManager()).thenReturn(platformTransactionManager);
        when(platformTransactionManager.getTransaction(any())).thenAnswer(invocation ->
                new SimpleTransactionStatus());
    }

    @Test
    void openLegacyObjectDelegatesToStorageClient() {
        DerivedAssetStorageService service = new DerivedAssetStorageService(
                objectStorageBuckets(),
                objectStorageClient,
                fileObjectRepository,
                fileNodeRepository,
                safeUrlValidator,
                transactionTemplate,
                new FileTransferLimitsProperties()
        );
        LegacyObjectReference reference = new LegacyObjectReference(
                "derived-assets",
                "derived/owner/photo.jpg"
        );
        InputStream expected = new ByteArrayInputStream(new byte[]{1, 2, 3});
        when(objectStorageClient.getObject(
                new ObjectStorageKey("derived-assets", "derived/owner/photo.jpg")
        )).thenReturn(expected);

        InputStream actual = service.openLegacyObject(reference);

        assertThat(actual).isSameAs(expected);
    }

    @Test
    void deleteOwnedRemovesDerivedObjectAndNode() {
        FileNode node = new FileNode();
        node.setId(FILE_NODE_ID);
        node.setOwnerUserId(OWNER_ID);
        node.setSourceType("DERIVED");
        node.setCurrentObjectId(FILE_OBJECT_ID);
        FileObject object = new FileObject();
        object.setId(FILE_OBJECT_ID);
        object.setBucketName("derived-assets");
        object.setObjectKey("derived/owner/photo.jpg");
        when(fileNodeRepository.findByIdAndOwnerUserIdAndDeletedFalse(FILE_NODE_ID, OWNER_ID))
                .thenReturn(Optional.of(node));
        when(fileObjectRepository.findById(FILE_OBJECT_ID)).thenReturn(Optional.of(object));
        DerivedAssetStorageService service = new DerivedAssetStorageService(
                objectStorageBuckets(),
                objectStorageClient,
                fileObjectRepository,
                fileNodeRepository,
                safeUrlValidator,
                transactionTemplate,
                new FileTransferLimitsProperties()
        );

        boolean deleted = service.deleteOwned(OWNER_ID, FILE_NODE_ID);

        assertThat(deleted).isTrue();
        verify(objectStorageClient).removeObject(new ObjectStorageKey("derived-assets", "derived/owner/photo.jpg"));
        verify(fileObjectRepository).delete(object);
        verify(fileNodeRepository).delete(node);
    }

    @Test
    void deleteOwnedBatchCountsOnlyOwnedDerivedNodes() {
        UUID missingFileNodeId = UUID.fromString("70000000-0000-0000-0000-000000000002");
        FileNode node = new FileNode();
        node.setId(FILE_NODE_ID);
        node.setOwnerUserId(OWNER_ID);
        node.setSourceType("DERIVED");
        when(fileNodeRepository.findByIdAndOwnerUserIdAndDeletedFalse(FILE_NODE_ID, OWNER_ID))
                .thenReturn(Optional.of(node));
        when(fileNodeRepository.findByIdAndOwnerUserIdAndDeletedFalse(missingFileNodeId, OWNER_ID))
                .thenReturn(Optional.empty());
        DerivedAssetStorageService service = new DerivedAssetStorageService(
                objectStorageBuckets(),
                objectStorageClient,
                fileObjectRepository,
                fileNodeRepository,
                safeUrlValidator,
                transactionTemplate,
                new FileTransferLimitsProperties()
        );

        int deletedCount = service.deleteOwnedBatch(
                OWNER_ID,
                List.of(FILE_NODE_ID, missingFileNodeId)
        );

        assertThat(deletedCount).isEqualTo(1);
        verify(fileNodeRepository).delete(node);
    }

    @Test
    void deleteOwnedKeepsMetadataWhenPhysicalObjectDeletionFails() {
        FileNode node = new FileNode();
        node.setId(FILE_NODE_ID);
        node.setOwnerUserId(OWNER_ID);
        node.setSourceType("DERIVED");
        node.setCurrentObjectId(FILE_OBJECT_ID);
        FileObject object = new FileObject();
        object.setId(FILE_OBJECT_ID);
        object.setBucketName("derived-assets");
        object.setObjectKey("derived/owner/photo.jpg");
        when(fileNodeRepository.findByIdAndOwnerUserIdAndDeletedFalse(FILE_NODE_ID, OWNER_ID))
                .thenReturn(Optional.of(node));
        when(fileObjectRepository.findById(FILE_OBJECT_ID)).thenReturn(Optional.of(object));
        doThrow(new IllegalStateException("storage unavailable"))
                .when(objectStorageClient)
                .removeObject(new ObjectStorageKey("derived-assets", "derived/owner/photo.jpg"));
        DerivedAssetStorageService service = new DerivedAssetStorageService(
                objectStorageBuckets(),
                objectStorageClient,
                fileObjectRepository,
                fileNodeRepository,
                safeUrlValidator,
                transactionTemplate,
                new FileTransferLimitsProperties()
        );

        assertThatThrownBy(() -> service.deleteOwned(OWNER_ID, FILE_NODE_ID))
                .isInstanceOf(IllegalStateException.class)
                .hasMessage("storage unavailable");

        verify(fileObjectRepository, never()).delete(object);
        verify(fileNodeRepository, never()).delete(node);
    }

    @Test
    void isAvailableRequiresActiveMetadataAndPhysicalObject() {
        FileNode node = new FileNode();
        node.setId(FILE_NODE_ID);
        node.setOwnerUserId(OWNER_ID);
        node.setSourceType("DERIVED");
        node.setCurrentObjectId(FILE_OBJECT_ID);
        FileObject object = new FileObject();
        object.setId(FILE_OBJECT_ID);
        object.setBucketName("derived-assets");
        object.setObjectKey("derived/owner/photo.jpg");
        String expectedPath = "/.metadata/PHOTO_ITEM/" + RESOURCE_ID + "/POSTER/cover.jpg";
        when(fileNodeRepository.findActivePath(OWNER_ID, expectedPath)).thenReturn(Optional.of(node));
        when(fileObjectRepository.findById(FILE_OBJECT_ID)).thenReturn(Optional.of(object));
        when(objectStorageClient.objectExists(
                new ObjectStorageKey("derived-assets", "derived/owner/photo.jpg")
        )).thenReturn(true);
        DerivedAssetStorageService service = new DerivedAssetStorageService(
                objectStorageBuckets(),
                objectStorageClient,
                fileObjectRepository,
                fileNodeRepository,
                safeUrlValidator,
                transactionTemplate,
                new FileTransferLimitsProperties()
        );

        boolean available = service.isAvailable(
                OWNER_ID,
                "PHOTO_ITEM",
                RESOURCE_ID,
                "POSTER",
                "cover.jpg"
        );

        assertThat(available).isTrue();
    }

    @Test
    void storePathUploadsCallerOwnedFileWithoutDeletingIt(@TempDir Path tempDirectory) throws Exception {
        Path sourceFile = tempDirectory.resolve("photos.zip");
        Files.writeString(sourceFile, "zip-content", StandardCharsets.UTF_8);
        when(fileNodeRepository.findActivePath(any(), any())).thenReturn(Optional.empty());
        when(fileObjectRepository.save(any())).thenAnswer(invocation -> {
            FileObject object = invocation.getArgument(0);
            object.setId(FILE_OBJECT_ID);
            return object;
        });
        when(fileNodeRepository.save(any())).thenAnswer(invocation -> {
            FileNode node = invocation.getArgument(0);
            node.setId(FILE_NODE_ID);
            return node;
        });
        allowStoreTransaction();
        DerivedAssetStorageService service = new DerivedAssetStorageService(
                objectStorageBuckets(),
                objectStorageClient,
                fileObjectRepository,
                fileNodeRepository,
                safeUrlValidator,
                transactionTemplate,
                new FileTransferLimitsProperties()
        );

        UUID fileNodeId = service.store(
                OWNER_ID,
                "PHOTO_BATCH",
                RESOURCE_ID,
                "DOWNLOAD",
                "photos.zip",
                "application/zip",
                sourceFile
        );

        assertThat(fileNodeId).isEqualTo(FILE_NODE_ID);
        assertThat(Files.exists(sourceFile)).isTrue();
        ArgumentCaptor<Path> pathCaptor = ArgumentCaptor.forClass(Path.class);
        verify(objectStorageClient).putObject(
                any(ObjectStorageKey.class),
                pathCaptor.capture(),
                eq("application/zip")
        );
        assertThat(pathCaptor.getValue()).isEqualTo(sourceFile.toAbsolutePath().normalize());
        verify(objectStorageClient).copyObject(
                any(ObjectStorageKey.class),
                any(ObjectStorageKey.class)
        );
    }

    @Test
    void storePathKeepsLogicalAndStorageFileNamesIndependent(@TempDir Path tempDirectory) throws Exception {
        Path sourceFile = tempDirectory.resolve("transcoded.mp4");
        Files.writeString(sourceFile, "video-content", StandardCharsets.UTF_8);
        when(fileNodeRepository.findActivePath(any(), any())).thenReturn(Optional.empty());
        when(fileObjectRepository.save(any())).thenAnswer(invocation -> {
            FileObject object = invocation.getArgument(0);
            object.setId(FILE_OBJECT_ID);
            return object;
        });
        when(fileNodeRepository.save(any())).thenAnswer(invocation -> {
            FileNode node = invocation.getArgument(0);
            node.setId(FILE_NODE_ID);
            return node;
        });
        allowStoreTransaction();
        DerivedAssetStorageService service = new DerivedAssetStorageService(
                objectStorageBuckets(),
                objectStorageClient,
                fileObjectRepository,
                fileNodeRepository,
                safeUrlValidator,
                transactionTemplate,
                new FileTransferLimitsProperties()
        );
        String logicalName = FILE_NODE_ID + "_h265.mp4";

        UUID fileNodeId = service.store(
                OWNER_ID,
                "VIDEO",
                RESOURCE_ID,
                "TRANSCODE",
                logicalName,
                "h265.mp4",
                "video/mp4",
                sourceFile
        );

        assertThat(fileNodeId).isEqualTo(FILE_NODE_ID);
        ArgumentCaptor<ObjectStorageKey> targetKeyCaptor = ArgumentCaptor.forClass(ObjectStorageKey.class);
        verify(objectStorageClient).copyObject(any(), targetKeyCaptor.capture());
        assertThat(targetKeyCaptor.getValue().objectKey())
                .endsWith("/VIDEO/60000000-0000-0000-0000-000000000001/TRANSCODE/h265.mp4");
        ArgumentCaptor<FileNode> nodeCaptor = ArgumentCaptor.forClass(FileNode.class);
        verify(fileNodeRepository).save(nodeCaptor.capture());
        assertThat(nodeCaptor.getValue().getName()).isEqualTo(logicalName);
        assertThat(nodeCaptor.getValue().getNormalizedPath())
                .endsWith("/VIDEO/60000000-0000-0000-0000-000000000001/TRANSCODE/" + logicalName);
    }

    @Test
    void storeRemoteDownloadsAssetIntoDerivedBucketAndFileNode() throws Exception {
        HttpServer server = HttpServer.create(new InetSocketAddress(0), 0);
        server.createContext("/poster.jpg", exchange -> {
            byte[] body = "fake-image".getBytes(StandardCharsets.UTF_8);
            exchange.getResponseHeaders().add("Content-Type", "image/jpeg");
            exchange.sendResponseHeaders(200, body.length);
            exchange.getResponseBody().write(body);
            exchange.close();
        });
        server.createContext("/redirect", exchange -> {
            exchange.getResponseHeaders().add("Location", "/poster.jpg");
            exchange.sendResponseHeaders(302, -1);
            exchange.close();
        });
        server.start();
        try {
            String url = "http://127.0.0.1:" + server.getAddress().getPort() + "/redirect";
            when(fileNodeRepository.findActivePath(any(), any())).thenReturn(Optional.empty());
            when(fileObjectRepository.save(any())).thenAnswer(invocation -> {
                FileObject object = invocation.getArgument(0);
                object.setId(FILE_OBJECT_ID);
                return object;
            });
            when(fileNodeRepository.save(any())).thenAnswer(invocation -> {
                FileNode node = invocation.getArgument(0);
                node.setId(FILE_NODE_ID);
                return node;
            });
            allowTransactionCallback();
            DerivedAssetStorageService service = new DerivedAssetStorageService(
                    objectStorageBuckets(),
                    objectStorageClient,
                    fileObjectRepository,
                    fileNodeRepository,
                    safeUrlValidator,
                    transactionTemplate,
                    new FileTransferLimitsProperties()
            );

            UUID fileNodeId = service.storeRemote(new DerivedAssetRequest(
                    OWNER_ID,
                    url,
                    "VIDEO_ITEM",
                    RESOURCE_ID,
                    "POSTER",
                    "poster.jpg",
                    "image/jpeg",
                    SpaceType.PERSONAL
            ));
            verify(safeUrlValidator).requireSafeHttpUrl(url);
            verify(safeUrlValidator).requireSafeHttpUrl(
                    "http://127.0.0.1:" + server.getAddress().getPort() + "/poster.jpg"
            );

            assertThat(fileNodeId).isEqualTo(FILE_NODE_ID);
            ArgumentCaptor<ObjectStorageKey> targetKeyCaptor = ArgumentCaptor.forClass(ObjectStorageKey.class);
            verify(objectStorageClient).copyObject(any(), targetKeyCaptor.capture());
            assertThat(targetKeyCaptor.getValue().bucket()).isEqualTo("derived-assets");
            assertThat(targetKeyCaptor.getValue().objectKey())
                    .isEqualTo("derived/10000000-0000-0000-0000-000000000001/VIDEO_ITEM/60000000-0000-0000-0000-000000000001/POSTER/poster.jpg");
            ArgumentCaptor<FileNode> nodeCaptor = ArgumentCaptor.forClass(FileNode.class);
            verify(fileNodeRepository).save(nodeCaptor.capture());
            assertThat(nodeCaptor.getValue().getSourceType()).isEqualTo("DERIVED");
            assertThat(nodeCaptor.getValue().getNormalizedPath())
                    .isEqualTo("/.metadata/VIDEO_ITEM/60000000-0000-0000-0000-000000000001/POSTER/poster.jpg");
        } finally {
            server.stop(0);
        }
    }

    @Test
    void storePathAllowsLargeMediaProductsButRejectsLargeSmallAssets(@TempDir Path tempDirectory) throws Exception {
        Path bigFile = tempDirectory.resolve("audio_only.aac");
        try (RandomAccessFile file = new RandomAccessFile(bigFile.toFile(), "rw")) {
            file.setLength(129L * 1024 * 1024);
        }
        FileTransferLimitsProperties limits = new FileTransferLimitsProperties();
        limits.setMaxDerivedAssetBytes(128L * 1024 * 1024);
        DerivedAssetStorageService service = new DerivedAssetStorageService(
                objectStorageBuckets(),
                objectStorageClient,
                fileObjectRepository,
                fileNodeRepository,
                safeUrlValidator,
                transactionTemplate,
                limits
        );
        allowStoreTransaction();

        assertThatThrownBy(() -> service.store(
                OWNER_ID,
                "VIDEO",
                RESOURCE_ID,
                "POSTER",
                "big.jpg",
                "image/jpeg",
                bigFile
        ))
                .isInstanceOf(BusinessException.class)
                .hasMessage("派生资源大小超出限制");

        when(fileNodeRepository.findActivePath(any(), any())).thenReturn(Optional.empty());
        when(fileObjectRepository.save(any())).thenAnswer(invocation -> {
            FileObject object = invocation.getArgument(0);
            object.setId(FILE_OBJECT_ID);
            return object;
        });
        when(fileNodeRepository.save(any())).thenAnswer(invocation -> {
            FileNode node = invocation.getArgument(0);
            node.setId(FILE_NODE_ID);
            return node;
        });

        allowStoreTransaction();

        UUID fileNodeId = service.store(
                OWNER_ID,
                "VIDEO",
                RESOURCE_ID,
                "TRANSCODE",
                "audio_only.aac",
                "audio/aac",
                bigFile
        );

        assertThat(fileNodeId).isEqualTo(FILE_NODE_ID);
        verify(objectStorageClient).putObject(
                any(ObjectStorageKey.class),
                eq(bigFile.toAbsolutePath().normalize()),
                eq("audio/aac")
        );
    }

    @Test
    void storeRetriesOnceWhenConcurrentWriteConflictsOnUniqueKey(@TempDir Path tempDirectory) throws Exception {
        Path sourceFile = tempDirectory.resolve("thumb.jpg");
        Files.writeString(sourceFile, "image", StandardCharsets.UTF_8);
        FileObject existingObject = new FileObject();
        existingObject.setId(FILE_OBJECT_ID);
        existingObject.setBucketName("derived-assets");
        when(fileObjectRepository.findByBucketNameAndObjectKey(any(), any()))
                .thenReturn(Optional.empty())
                .thenReturn(Optional.of(existingObject));
        when(fileObjectRepository.save(any()))
                .thenThrow(new DataIntegrityViolationException("duplicate key"))
                .thenAnswer(invocation -> invocation.getArgument(0));
        when(fileNodeRepository.findActivePath(any(), any())).thenReturn(Optional.empty());
        when(fileNodeRepository.save(any())).thenAnswer(invocation -> {
            FileNode node = invocation.getArgument(0);
            node.setId(FILE_NODE_ID);
            return node;
        });
        allowStoreTransaction();
        DerivedAssetStorageService service = new DerivedAssetStorageService(
                objectStorageBuckets(),
                objectStorageClient,
                fileObjectRepository,
                fileNodeRepository,
                safeUrlValidator,
                transactionTemplate,
                new FileTransferLimitsProperties()
        );

        UUID fileNodeId = service.store(
                OWNER_ID,
                "PHOTO_ITEM",
                RESOURCE_ID,
                "POSTER",
                "thumb.jpg",
                "image/jpeg",
                sourceFile
        );

        assertThat(fileNodeId).isEqualTo(FILE_NODE_ID);
        verify(fileObjectRepository, times(2)).save(any());
        verify(fileObjectRepository, times(2)).findByBucketNameAndObjectKey(any(), any());
    }

    private ObjectStorageBuckets objectStorageBuckets() {
        ObjectStorageBuckets buckets = mock(ObjectStorageBuckets.class);
        when(buckets.derivedAssets()).thenReturn("derived-assets");
        return buckets;
    }
}
