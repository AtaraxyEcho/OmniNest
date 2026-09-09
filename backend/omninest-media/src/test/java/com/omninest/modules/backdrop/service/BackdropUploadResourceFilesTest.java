package com.omninest.modules.backdrop.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyInt;
import static org.mockito.ArgumentMatchers.anyLong;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import com.omninest.common.enums.ErrorCode;
import com.omninest.common.error.BusinessException;
import com.omninest.common.ratelimit.RateLimitService;
import com.omninest.common.security.MalwareScanGateway;
import com.omninest.common.user.UserStorageCommand;
import com.omninest.modules.backdrop.config.BackdropRuntimeConfigService;
import com.omninest.modules.backdrop.domain.BackdropAsset;
import com.omninest.modules.backdrop.domain.BackdropAssetStatus;
import com.omninest.modules.backdrop.domain.BackdropMediaType;
import com.omninest.modules.backdrop.dto.BackdropDtos.BackdropAssetDto;
import com.omninest.modules.backdrop.repository.BackdropAssetRepository;
import com.omninest.modules.file.dto.FileDownloadUrlDto;
import com.omninest.modules.file.service.DerivedAssetStorageService;
import com.omninest.modules.file.service.FileQueryService;
import com.omninest.modules.quota.service.StorageQuotaService;
import java.io.IOException;
import java.io.InputStream;
import java.nio.file.Files;
import java.nio.file.Path;
import java.time.Duration;
import java.time.Instant;
import java.util.HexFormat;
import java.util.List;
import java.security.MessageDigest;
import java.util.HexFormat;
import java.util.UUID;
import java.util.concurrent.atomic.AtomicInteger;
import java.util.concurrent.atomic.AtomicReference;
import java.util.stream.Stream;
import org.junit.jupiter.api.BeforeAll;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.TestInstance;
import org.junit.jupiter.api.TestInstance.Lifecycle;
import org.junit.jupiter.api.condition.EnabledIf;
import org.springframework.mock.web.MockMultipartFile;

/**
 * 使用本机真实背景资源(D:/Development/Resource/Background)做全链路校验:
 * 魔数识别、流式 SHA-256、真实缩略图解码、去重、限额与安全拒绝。
 * 目录不存在时整类跳过,不依赖外部环境。
 *
 * @author OmniNest
 */
@DisplayName("真实背景资源全链路校验")
@TestInstance(Lifecycle.PER_CLASS)
class BackdropUploadResourceFilesTest {

    static final Path RESOURCE_DIR = Path.of("D:/Development/Resource/Background");
    static final UUID OWNER_ID = UUID.fromString("11111111-1111-1111-1111-111111111111");

    BackdropAssetRepository backdropAssetRepository;
    BackdropRuntimeConfigService runtimeConfigService;
    DerivedAssetStorageService derivedAssetStorageService;
    FileQueryService fileQueryService;
    StorageQuotaService storageQuotaService;
    UserStorageCommand userStorageCommand;
    MalwareScanGateway malwareScanGateway;
    RateLimitService rateLimitService;
    BackdropAssetService service;
    final AtomicReference<BackdropAsset> storedAsset = new AtomicReference<>();
    final List<BackdropAsset> storedAssets = new java.util.ArrayList<>();
    final AtomicInteger storeCalls = new AtomicInteger();

    @BeforeAll
    void assumeResourcesPresent() {
        assumeTrueDirectory();
    }

    static void assumeTrueDirectory() {
        org.junit.jupiter.api.Assumptions.assumeTrue(
                Files.isDirectory(RESOURCE_DIR), "测试资源目录不存在:" + RESOURCE_DIR);
    }

    @BeforeEach
    void setUp() {
        storedAsset.set(null);
        storedAssets.clear();
        storeCalls.set(0);
        backdropAssetRepository = mock(BackdropAssetRepository.class);
        runtimeConfigService = mock(BackdropRuntimeConfigService.class);
        derivedAssetStorageService = mock(DerivedAssetStorageService.class);
        fileQueryService = mock(FileQueryService.class);
        storageQuotaService = mock(StorageQuotaService.class);
        userStorageCommand = mock(UserStorageCommand.class);
        malwareScanGateway = mock(MalwareScanGateway.class);
        rateLimitService = mock(RateLimitService.class);

        when(runtimeConfigService.uploadRatePerHour()).thenReturn(20);
        when(runtimeConfigService.maxAssetsPerUser()).thenReturn(30);
        when(runtimeConfigService.maxImageBytes()).thenReturn(20 * 1024 * 1024);
        when(runtimeConfigService.maxVideoBytes()).thenReturn(64 * 1024 * 1024);
        when(rateLimitService.tryAcquire(anyString(), anyInt(), any(Duration.class))).thenReturn(true);
        when(malwareScanGateway.scan(any(Path.class))).thenReturn(MalwareScanGateway.ScanResult.clean());
        when(backdropAssetRepository.save(any())).thenAnswer(invocation -> {
            BackdropAsset asset = invocation.getArgument(0);
            storedAssets.removeIf(existing -> existing.getId().equals(asset.getId()));
            storedAssets.add(asset);
            storedAsset.set(asset);
            return asset;
        });
        when(backdropAssetRepository.countByOwnerUserIdAndStatusNot(any(), any())).thenReturn(0L);
        when(backdropAssetRepository.findById(any(UUID.class)))
                .thenAnswer(invocation -> storedAssets.stream()
                        .filter(asset -> asset.getId().equals(invocation.getArgument(0)))
                        .findFirst());
        when(backdropAssetRepository.findByOwnerUserIdAndSha256(any(), any()))
                .thenAnswer(invocation -> storedAssets.stream()
                        .filter(asset -> asset.getSha256().equals(invocation.getArgument(1)))
                        .findFirst());
        when(fileQueryService.createDownloadUrl(any(), any())).thenAnswer(invocation ->
                new FileDownloadUrlDto(
                        invocation.getArgument(1), "file",
                        "https://signed/" + invocation.getArgument(1),
                        Instant.now().plusSeconds(900)));
        service = new BackdropAssetService(
                backdropAssetRepository,
                runtimeConfigService,
                derivedAssetStorageService,
                fileQueryService,
                storageQuotaService,
                userStorageCommand,
                malwareScanGateway,
                rateLimitService,
                afterCommitFiringTransactionManager()
        );
    }

    private org.springframework.transaction.PlatformTransactionManager
            afterCommitFiringTransactionManager() {
        return new org.springframework.transaction.PlatformTransactionManager() {
            @Override
            public org.springframework.transaction.TransactionStatus getTransaction(
                    org.springframework.transaction.TransactionDefinition definition) {
                return new org.springframework.transaction.support.SimpleTransactionStatus();
            }

            @Override
            public void commit(org.springframework.transaction.TransactionStatus status) {
            }

            @Override
            public void rollback(org.springframework.transaction.TransactionStatus status) {
            }
        };
    }

    private MockMultipartFile real(String fileName) throws IOException {
        Path path = RESOURCE_DIR.resolve(fileName);
        byte[] bytes = Files.readAllBytes(path);
        return new MockMultipartFile("file", fileName, "application/octet-stream", bytes);
    }

    private String sha256OfFile(String fileName) throws Exception {
        MessageDigest digest = MessageDigest.getInstance("SHA-256");
        try (InputStream input = Files.newInputStream(RESOURCE_DIR.resolve(fileName))) {
            digest.update(input.readAllBytes());
        }
        return HexFormat.of().formatHex(digest.digest());
    }

    private UUID stubStore() {
        AtomicInteger sequence = new AtomicInteger();
        when(derivedAssetStorageService.store(
                eq(OWNER_ID), anyString(), any(UUID.class), anyString(), anyString(),
                anyString(), any(java.nio.file.Path.class)))
                .thenAnswer(invocation -> {
                    storeCalls.incrementAndGet();
                    return UUID.randomUUID();
                });
        return UUID.fromString("00000000-0000-0000-0000-00000000000" + sequence.incrementAndGet());
    }

    @Test
    @DisplayName("真实 JPG 全链路:魔数/SHA256/真实缩略图/READY")
    void realJpgFullPipeline() throws Exception {
        stubStore();
        String expectedSha = sha256OfFile("01_5wtlkjl0.jpg");

        BackdropAssetDto dto = service.uploadAsset(OWNER_ID, real("01_5wtlkjl0.jpg"));

        assertThat(dto.status()).isEqualTo("READY");
        assertThat(dto.mediaType()).isEqualTo("image");
        assertThat(storedAsset.get().getSha256()).isEqualTo(expectedSha);
        assertThat(storedAsset.get().getFileSize()).isEqualTo(1039651L);
        assertThat(storedAsset.get().getThumbFileId()).isNotNull();
        // 原始 + 缩略图两次派生发布
        assertThat(storeCalls.get()).isEqualTo(2);
    }

    @Test
    @DisplayName("真实视频全链路:容器识别/无缩略图/READY")
    void realVideoFullPipeline() throws Exception {
        stubStore();
        String expectedSha = sha256OfFile("horizon-sky.mp4");

        BackdropAssetDto dto = service.uploadAsset(OWNER_ID, real("horizon-sky.mp4"));

        assertThat(dto.status()).isEqualTo("READY");
        assertThat(dto.mediaType()).isEqualTo("video");
        assertThat(storedAsset.get().getSha256()).isEqualTo(expectedSha);
        assertThat(storedAsset.get().getFileSize()).isEqualTo(25302036L);
        assertThat(storedAsset.get().getThumbFileId()).isNull();
        assertThat(storeCalls.get()).isEqualTo(1);
    }

    @Test
    @DisplayName("同名内容的视频上传去重:第二次直接返回已有素材")
    void duplicateUploadReturnsExisting() throws Exception {
        stubStore();
        service.uploadAsset(OWNER_ID, real("test.mp4"));
        int callsAfterFirst = storeCalls.get();

        BackdropAssetDto dto = service.uploadAsset(OWNER_ID, real("test.mp4"));

        assertThat(dto.id()).isEqualTo(storedAsset.get().getId());
        assertThat(storeCalls.get()).isEqualTo(callsAfterFirst);
    }

    @Test
    @DisplayName("内容不同的两张 JPG 各自入库,互不去重")
    void distinctJpgsAreStoredSeparately() throws Exception {
        stubStore();
        BackdropAssetDto first = service.uploadAsset(OWNER_ID, real("01_5wtlkjl0.jpg"));

        BackdropAssetDto second = service.uploadAsset(OWNER_ID, real("01_xmgmpd4s.jpg"));

        assertThat(second.id()).isNotEqualTo(first.id());
        assertThat(storedAssets).hasSize(2);
        assertThat(storedAssets.stream().map(BackdropAsset::getSha256)).doesNotHaveDuplicates();
    }

    @Test
    @DisplayName("魔数翻转的 JPG 被拒绝(8002)")
    void corruptedMagicRejected() throws Exception {
        byte[] bytes = Files.readAllBytes(RESOURCE_DIR.resolve("01_5wtlkjl0.jpg"));
        bytes[0] = 0x00;
        bytes[1] = 0x11;

        assertThatThrownBy(() -> service.uploadAsset(OWNER_ID,
                        new MockMultipartFile("file", "corrupt.jpg", "application/octet-stream", bytes)))
                .isInstanceOfSatisfying(BusinessException.class, exception ->
                        assertThat(exception.errorCode().getCode()).isEqualTo(8002));
    }

    @Test
    @DisplayName("截断到 8 字节且无有效魔数的视频被拒绝(8002)")
    void truncatedVideoRejected() throws Exception {
        byte[] bytes = Files.readAllBytes(RESOURCE_DIR.resolve("horizon-sky.mp4"));
        byte[] head = java.util.Arrays.copyOf(bytes, 8);

        assertThatThrownBy(() -> service.uploadAsset(OWNER_ID,
                        new MockMultipartFile("file", "broken.mp4", "application/octet-stream", head)))
                .isInstanceOfSatisfying(BusinessException.class, exception ->
                        assertThat(exception.errorCode().getCode()).isEqualTo(8002));
    }

    @Test
    @DisplayName("视频内容配图片扩展名被拒绝(8002)")
    void extensionMagicMismatchRejected() throws Exception {
        assertThatThrownBy(() -> service.uploadAsset(OWNER_ID,
                        new MockMultipartFile("file", "fake.jpg", "application/octet-stream",
                                Files.readAllBytes(RESOURCE_DIR.resolve("horizon-sky.mp4")))))
                .isInstanceOfSatisfying(BusinessException.class, exception ->
                        assertThat(exception.errorCode().getCode()).isEqualTo(8002));
    }

    @Test
    @DisplayName("视频超过运行时大小限额被拒绝(8004)")
    void videoOverLimitRejected() throws Exception {
        when(runtimeConfigService.maxVideoBytes()).thenReturn(1024 * 1024);

        assertThatThrownBy(() -> service.uploadAsset(OWNER_ID, real("horizon-sky.mp4")))
                .isInstanceOfSatisfying(BusinessException.class, exception ->
                        assertThat(exception.errorCode().getCode()).isEqualTo(8004));
    }

    @Test
    @DisplayName("数量限额触发(8003)且预留不残留")
    void countLimitRejected() throws Exception {
        when(backdropAssetRepository.countByOwnerUserIdAndStatusNot(any(), any())).thenReturn(30L);

        assertThatThrownBy(() -> service.uploadAsset(OWNER_ID, real("01_5wtlkjl0.jpg")))
                .isInstanceOfSatisfying(BusinessException.class, exception ->
                        assertThat(exception.errorCode().getCode()).isEqualTo(8003));
        verify(storageQuotaService, never()).reserve(any(), anyString(), any(), anyLong(), any(Instant.class));
    }

    @Test
    @DisplayName("限流触发(429)")
    void rateLimitedRejected() {
        when(rateLimitService.tryAcquire(anyString(), anyInt(), any(Duration.class))).thenReturn(false);

        assertThatThrownBy(() -> service.uploadAsset(OWNER_ID, real("01_5wtlkjl0.jpg")))
                .isInstanceOfSatisfying(BusinessException.class, exception ->
                        assertThat(exception.errorCode().getCode()).isEqualTo(429));
    }

    @Test
    @DisplayName("扫描不可用 fail-closed(8005)与检出威胁(8006)")
    void scanFailClosedAndThreat() throws Exception {
        when(malwareScanGateway.scan(any(Path.class)))
                .thenReturn(MalwareScanGateway.ScanResult.error("clamav down"));
        assertThatThrownBy(() -> service.uploadAsset(OWNER_ID, real("01_5wtlkjl0.jpg")))
                .isInstanceOfSatisfying(BusinessException.class, exception ->
                        assertThat(exception.errorCode().getCode()).isEqualTo(8005));

        when(malwareScanGateway.scan(any(Path.class)))
                .thenReturn(MalwareScanGateway.ScanResult.infected("EICAR"));
        assertThatThrownBy(() -> service.uploadAsset(OWNER_ID, real("01_5wtlkjl0.jpg")))
                .isInstanceOfSatisfying(BusinessException.class, exception ->
                        assertThat(exception.errorCode().getCode()).isEqualTo(8006));
    }
}
