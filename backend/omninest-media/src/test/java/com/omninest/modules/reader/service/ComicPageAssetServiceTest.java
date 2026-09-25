package com.omninest.modules.reader.service;
import com.omninest.modules.media.config.MediaProcessingLimitsProperties;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyLong;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verifyNoInteractions;
import static org.mockito.Mockito.when;

import com.omninest.modules.file.domain.SpaceType;
import com.omninest.modules.file.dto.FileContentStream;
import com.omninest.modules.file.dto.FileDescriptor;
import com.omninest.modules.file.service.DerivedAssetStorageService;
import com.omninest.modules.file.service.FileMetadataQueryService;
import com.omninest.modules.file.service.FileQueryService;

import com.omninest.modules.reader.domain.ReaderItem;
import com.omninest.modules.reader.domain.ReaderItemSource;
import com.omninest.modules.reader.domain.ReaderPage;
import com.omninest.modules.reader.domain.ReaderPageAsset;
import com.omninest.modules.reader.repository.ReaderItemRepository;
import com.omninest.modules.reader.repository.ReaderItemSourceRepository;
import com.omninest.modules.reader.repository.ReaderPageAssetRepository;
import com.omninest.modules.reader.repository.ReaderPageRepository;
import com.omninest.modules.reader.service.ComicPageAssetService.PageDownloadDescriptor;
import com.omninest.modules.reader.service.ReaderArchiveSafetyPolicy.ArchiveReadSession;
import com.omninest.modules.reader.service.ReaderArchiveSafetyPolicy.EntryReadGuard;
import java.io.ByteArrayInputStream;
import java.io.ByteArrayOutputStream;
import java.nio.charset.StandardCharsets;
import java.time.Instant;
import java.util.Optional;
import java.util.UUID;
import java.util.zip.ZipEntry;
import java.util.zip.ZipOutputStream;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

/**
 * 漫画页面资产服务单元测试。
 *
 * @author OmniNest
 */
@ExtendWith(MockitoExtension.class)
class ComicPageAssetServiceTest {

    @Mock
    private ReaderItemRepository itemRepository;

    @Mock
    private ReaderItemSourceRepository sourceRepository;

    @Mock
    private ReaderPageRepository pageRepository;

    @Mock
    private ReaderPageAssetRepository pageAssetRepository;

    @Mock
    private FileMetadataQueryService fileMetadataQueryService;

    @Mock
    private FileQueryService fileQueryService;

    @Mock
    private DerivedAssetStorageService derivedAssetStorageService;

    @Mock
    private ReaderArchiveSafetyPolicy archiveSafetyPolicy;

    @org.mockito.Spy
    private MediaProcessingLimitsProperties processingLimits = new MediaProcessingLimitsProperties();

    @InjectMocks
    private ComicPageAssetService service;

    @Test
    void preparePageImageDownloadDoesNotReadMaterializedObject() throws Exception {
        UUID ownerUserId = UUID.randomUUID();
        UUID itemId = UUID.randomUUID();
        UUID sourceId = UUID.randomUUID();
        UUID pageId = UUID.randomUUID();
        ReaderPage page = new ReaderPage();
        page.setId(pageId);
        page.setSourceId(sourceId);
        ReaderItemSource source = new ReaderItemSource();
        source.setId(sourceId);
        source.setReaderItemId(itemId);
        ReaderItem item = new ReaderItem();
        item.setId(itemId);
        item.setOwnerUserId(ownerUserId);
        item.setManifestVersion(3);
        ReaderPageAsset asset = new ReaderPageAsset();
        asset.setFileNodeId(UUID.randomUUID());
        asset.setMimeType("image/jpeg");
        asset.setByteSize(5L);
        asset.setId(UUID.randomUUID());

        when(pageRepository.findById(pageId)).thenReturn(Optional.of(page));
        when(sourceRepository.findById(sourceId)).thenReturn(Optional.of(source));
        when(itemRepository.findById(itemId)).thenReturn(Optional.of(item));
        when(pageAssetRepository.findByPageIdAndManifestVersion(pageId, 3))
                .thenReturn(Optional.of(asset));

        PageDownloadDescriptor descriptor = service.preparePageImageDownload(ownerUserId, pageId);

        assertThat(descriptor.derivedAssetId()).isEqualTo(asset.getId());
        assertThat(descriptor.mimeType()).isEqualTo("image/jpeg");
        assertThat(descriptor.sizeBytes()).isEqualTo(5L);
        assertThat(descriptor.sourceArchive()).isFalse();
        verifyNoInteractions(derivedAssetStorageService);

        byte[] imageBytes = "image".getBytes(StandardCharsets.UTF_8);
        when(pageAssetRepository.findById(asset.getId())).thenReturn(Optional.of(asset));
        when(fileQueryService.openOwnedFileContent(ownerUserId, asset.getFileNodeId()))
                .thenReturn(new FileContentStream(
                        new ByteArrayInputStream(imageBytes), "page.jpg", imageBytes.length, "image/jpeg"));
        ByteArrayOutputStream output = new ByteArrayOutputStream();

        service.streamPageImage(descriptor, output);

        assertThat(output.toByteArray()).isEqualTo(imageBytes);
    }

    @Test
    void streamPageImageReadsLegacyArchiveOnlyDuringStreaming() throws Exception {
        UUID ownerUserId = UUID.randomUUID();
        UUID itemId = UUID.randomUUID();
        UUID sourceId = UUID.randomUUID();
        UUID pageId = UUID.randomUUID();
        UUID fileNodeId = UUID.randomUUID();
        ReaderPage page = new ReaderPage();
        page.setId(pageId);
        page.setSourceId(sourceId);
        page.setSourcePath("pages/1.jpg");
        page.setEntryIndex(0);
        page.setMimeType("image/jpeg");
        page.setByteSize(5L);
        ReaderItemSource source = new ReaderItemSource();
        source.setId(sourceId);
        source.setReaderItemId(itemId);
        source.setFileNodeId(fileNodeId);
        ReaderItem item = new ReaderItem();
        item.setId(itemId);
        item.setOwnerUserId(ownerUserId);
        item.setManifestVersion(3);
        FileDescriptor fileNode = new FileDescriptor(
                fileNodeId,
                ownerUserId,
                null,
                "FILE",
                "comic.cbz",
                "/comic.cbz",
                "application/vnd.comicbook+zip",
                256L,
                null,
                "UPLOAD",
                false,
                false,
                SpaceType.PERSONAL,
                ownerUserId,
                Instant.EPOCH,
                Instant.EPOCH
        );
        when(pageRepository.findById(pageId)).thenReturn(Optional.of(page));
        when(sourceRepository.findById(sourceId)).thenReturn(Optional.of(source));
        when(itemRepository.findById(itemId)).thenReturn(Optional.of(item));
        when(pageAssetRepository.findByPageIdAndManifestVersion(pageId, 3))
                .thenReturn(Optional.empty());
        when(pageAssetRepository.findFirstByPageIdOrderByManifestVersionDesc(pageId))
                .thenReturn(Optional.empty());
        when(fileMetadataQueryService.findById(fileNodeId)).thenReturn(Optional.of(fileNode));

        PageDownloadDescriptor descriptor = service.preparePageImageDownload(ownerUserId, pageId);

        assertThat(descriptor.ownerUserId()).isEqualTo(ownerUserId);
        assertThat(descriptor.sourceFileNodeId()).isEqualTo(fileNodeId);
        assertThat(descriptor.sourceArchive()).isTrue();
        verifyNoInteractions(fileQueryService);

        byte[] imageBytes = "image".getBytes(StandardCharsets.UTF_8);
        byte[] archiveBytes = createZip("pages/1.jpg", imageBytes);
        when(fileQueryService.openOwnedFileContent(ownerUserId, fileNodeId))
                .thenReturn(new FileContentStream(
                        new ByteArrayInputStream(archiveBytes),
                        "comic.cbz",
                        archiveBytes.length,
                        "application/vnd.comicbook+zip"
                ));
        ArchiveReadSession session = mock(ArchiveReadSession.class);
        EntryReadGuard guard = mock(EntryReadGuard.class);
        when(archiveSafetyPolicy.newReadSession()).thenReturn(session);
        when(session.beginEntry(any(ZipEntry.class), anyLong())).thenReturn(guard);
        ByteArrayOutputStream output = new ByteArrayOutputStream();

        service.streamPageImage(descriptor, output);

        assertThat(output.toByteArray()).isEqualTo(imageBytes);
    }

    private byte[] createZip(String entryName, byte[] bytes) throws Exception {
        ByteArrayOutputStream output = new ByteArrayOutputStream();
        try (ZipOutputStream zip = new ZipOutputStream(output)) {
            zip.putNextEntry(new ZipEntry(entryName));
            zip.write(bytes);
            zip.closeEntry();
        }
        return output.toByteArray();
    }

    @Test
    void readImageDimensionsParsesPngHeader() {
        byte[] header = new byte[24];
        header[0] = (byte) 0x89;
        header[1] = 0x50;
        header[2] = 0x4E;
        header[3] = 0x47;
        header[4] = 0x0D;
        header[5] = 0x0A;
        header[6] = 0x1A;
        header[7] = 0x0A;
        header[18] = 0x03;
        header[19] = 0x20;
        header[22] = 0x02;
        header[23] = 0x58;

        int[] dimensions = ComicPageAssetService.readImageDimensions(header);

        assertThat(dimensions).containsExactly(800, 600);
    }

    @Test
    void readImageDimensionsParsesGifHeader() {
        byte[] header = new byte[24];
        header[0] = 'G';
        header[1] = 'I';
        header[2] = 'F';
        header[3] = '8';
        header[4] = '9';
        header[5] = 'a';
        header[6] = 0x40;
        header[7] = 0x01;
        header[8] = (byte) 0xF0;

        int[] dimensions = ComicPageAssetService.readImageDimensions(header);

        assertThat(dimensions).containsExactly(320, 240);
    }

    @Test
    void readImageDimensionsReturnsZeroForShortHeader() {
        int[] dimensions = ComicPageAssetService.readImageDimensions(new byte[10]);

        assertThat(dimensions).containsExactly(0, 0);
    }

    @Test
    void readImageDimensionsReturnsZeroForNullHeader() {
        int[] dimensions = ComicPageAssetService.readImageDimensions(null);

        assertThat(dimensions).containsExactly(0, 0);
    }
}
