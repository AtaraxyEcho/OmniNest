package com.omninest.modules.video.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import com.omninest.common.enums.ErrorCode;
import com.omninest.common.error.BusinessException;
import com.omninest.modules.file.service.DerivedAssetStorageService;
import com.omninest.modules.video.domain.MediaMovie;
import com.omninest.modules.video.domain.MediaNfoExport;
import com.omninest.modules.video.domain.MediaType;
import com.omninest.modules.video.domain.MediaVideoItem;
import com.omninest.modules.video.domain.NfoStatus;
import com.omninest.modules.video.dto.MovieDtos.NfoExportDto;
import com.omninest.modules.video.repository.MediaMovieRepository;
import com.omninest.modules.video.repository.MediaNfoExportRepository;
import com.omninest.modules.video.repository.MediaTvEpisodeRepository;
import com.omninest.modules.video.repository.MediaTvSeriesRepository;
import com.omninest.modules.video.repository.MediaVideoItemRepository;
import java.io.ByteArrayInputStream;
import java.io.IOException;
import java.io.InputStream;
import java.nio.charset.StandardCharsets;
import java.util.Optional;
import java.util.UUID;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.ArgumentCaptor;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

/**
 * NFO 导出单测：锁定"导出必须真的产生可取得的文件"。
 *
 * <p>修复前导出只把一条从未写过的路径记进 {@code export_path}，接口声称导出为文件，
 * 库里却没有对象。这里捕获传给派生资产存储的字节，保证记录与存储指向同一份内容。</p>
 *
 * @author OmniNest
 */
@ExtendWith(MockitoExtension.class)
class MovieNfoServiceTest {

    private static final UUID OWNER_ID = UUID.fromString("10000000-0000-0000-0000-000000000001");
    private static final UUID VIDEO_ID = UUID.fromString("20000000-0000-0000-0000-000000000001");
    private static final UUID MOVIE_ID = UUID.fromString("30000000-0000-0000-0000-000000000001");
    private static final UUID STORED_NODE_ID = UUID.fromString("40000000-0000-0000-0000-000000000001");

    @Mock
    private MediaVideoItemRepository videoItemRepository;
    @Mock
    private MediaNfoExportRepository nfoExportRepository;
    @Mock
    private MediaMovieRepository movieRepository;
    @Mock
    private MediaTvEpisodeRepository episodeRepository;
    @Mock
    private MediaTvSeriesRepository tvSeriesRepository;
    @Mock
    private DerivedAssetStorageService derivedAssetStorageService;

    @InjectMocks
    private MovieNfoService service;

    @Test
    @DisplayName("导出把 NFO 字节写入派生资产，并把存储节点 ID 记进 export_path")
    void exportStoresTheNfoBytesAndRecordsTheStoredNodeId() throws IOException {
        MediaVideoItem item = videoItem();
        MediaMovie movie = new MediaMovie();
        movie.setTitle("A & B <特别版>");
        movie.setOverview("剧情 & 概要");
        movie.setRuntimeSeconds(5_400);
        when(videoItemRepository.findByIdAndOwnerUserId(VIDEO_ID, OWNER_ID)).thenReturn(Optional.of(item));
        when(movieRepository.findById(MOVIE_ID)).thenReturn(Optional.of(movie));
        when(nfoExportRepository.findTopByOwnerUserIdAndVideoItemIdOrderByUpdatedAtDesc(OWNER_ID, VIDEO_ID))
                .thenReturn(Optional.empty());
        when(nfoExportRepository.save(any(MediaNfoExport.class)))
                .thenAnswer(invocation -> invocation.getArgument(0));
        when(videoItemRepository.save(item)).thenReturn(item);
        ArgumentCaptor<InputStream> contentCaptor = ArgumentCaptor.forClass(InputStream.class);
        when(derivedAssetStorageService.store(
                eq(OWNER_ID),
                eq("VIDEO_ITEM"),
                eq(VIDEO_ID),
                eq("NFO"),
                eq("nfo-" + VIDEO_ID + ".nfo"),
                eq("application/xml"),
                contentCaptor.capture()))
                .thenReturn(STORED_NODE_ID);

        NfoExportDto dto = service.export(OWNER_ID, VIDEO_ID);

        String storedBytes = new String(contentCaptor.getValue().readAllBytes(), StandardCharsets.UTF_8);
        assertThat(dto.exportPath()).isEqualTo(STORED_NODE_ID.toString());
        assertThat(storedBytes)
                .as("落盘内容必须与接口返回的正文一致，否则导出的文件是另一份东西")
                .isEqualTo(dto.content());
        assertThat(storedBytes).contains("<title>A &amp; B &lt;特别版&gt;</title>");
        assertThat(storedBytes).contains("<runtime>90</runtime>");
        assertThat(item.getNfoPath()).isEqualTo(STORED_NODE_ID.toString());
        assertThat(item.getNfoStatus()).isEqualTo(NfoStatus.GENERATED.getValue());
        verify(nfoExportRepository).save(any(MediaNfoExport.class));
    }

    @Test
    @DisplayName("预览只回显已存储路径与正文，不重新写文件")
    void previewReturnsStoredPathWithoutStoringAgain() {
        MediaVideoItem item = videoItem();
        item.setNfoPath(STORED_NODE_ID.toString());
        item.setNfoStatus(NfoStatus.GENERATED.getValue());
        when(videoItemRepository.findByIdAndOwnerUserId(VIDEO_ID, OWNER_ID)).thenReturn(Optional.of(item));
        when(movieRepository.findById(MOVIE_ID)).thenReturn(Optional.of(new MediaMovie()));

        NfoExportDto dto = service.preview(OWNER_ID, VIDEO_ID);

        assertThat(dto.exportPath()).isEqualTo(STORED_NODE_ID.toString());
        assertThat(dto.status()).isEqualTo(NfoStatus.GENERATED.getValue());
        assertThat(dto.content()).contains("<movie>");
        verify(derivedAssetStorageService, never()).store(any(), any(), any(), any(), any(), any(), any(InputStream.class));
        verify(nfoExportRepository, never()).save(any());
    }

    @Test
    @DisplayName("条目不存在时按媒体资源不存在拒绝")
    void exportRejectsMissingItem() {
        when(videoItemRepository.findByIdAndOwnerUserId(VIDEO_ID, OWNER_ID)).thenReturn(Optional.empty());

        assertThatThrownBy(() -> service.export(OWNER_ID, VIDEO_ID))
                .isInstanceOf(BusinessException.class)
                .extracting(exception -> ((BusinessException) exception).errorCode())
                .isEqualTo(ErrorCode.MEDIA_NOT_FOUND);
        verify(derivedAssetStorageService, never())
                .store(any(), any(), any(), any(), any(), any(), any(InputStream.class));
    }

    private MediaVideoItem videoItem() {
        MediaVideoItem item = new MediaVideoItem();
        item.setId(VIDEO_ID);
        item.setOwnerUserId(OWNER_ID);
        item.setMediaType(MediaType.MOVIE.getValue());
        item.setMovieId(MOVIE_ID);
        return item;
    }
}
