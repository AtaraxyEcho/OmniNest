package com.omninest.modules.video.service;

import com.omninest.modules.video.domain.MediaVideoItem;
import com.omninest.modules.video.dto.MovieDtos.MovieVideoFileDto;
import com.omninest.modules.video.repository.MediaVideoItemRepository;
import com.omninest.modules.file.service.FileQueryService;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.List;
import java.util.UUID;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/** 媒体授权边界内的视频源文件清单。 */
@Service
@RequiredArgsConstructor
public class MovieVideoFileService {
    private final MediaVideoItemRepository videoItemRepository;
    private final MediaContentAccessService mediaContentAccessService;
    private final FileQueryService fileQueryService;

    @Transactional(readOnly = true)
    public List<MovieVideoFileDto> files(UUID requesterUserId, UUID videoItemId) {
        MediaVideoItem requested = mediaContentAccessService.requireReadableVideo(requesterUserId, videoItemId);
        MediaVideoItem source = requested.getSourceVideoItemId() == null
                ? requested
                : videoItemRepository.findById(requested.getSourceVideoItemId()).orElse(requested);
        List<MediaVideoItem> originals;
        if (source.getMovieId() != null) {
            originals = videoItemRepository.findOriginalsByOwnerUserIdAndMovieId(
                    source.getOwnerUserId(), source.getMovieId());
        } else if (source.getEpisodeId() != null) {
            originals = videoItemRepository.findOriginalsByOwnerUserIdAndEpisodeId(
                    source.getOwnerUserId(), source.getEpisodeId());
        } else {
            originals = List.of(source);
        }
        originals = originals.stream()
                .filter(item -> mediaContentAccessService
                        .findReadableVideo(requesterUserId, item.getId()).isPresent())
                .toList();
        if (originals.isEmpty()) {
            originals = List.of(requested);
        }
        List<UUID> sourceIds = originals.stream().map(MediaVideoItem::getId).toList();
        List<MediaVideoItem> files = new ArrayList<>(originals);
        files.addAll(videoItemRepository.findReadableDerivedVersionsBySources(source.getOwnerUserId(), sourceIds));
        files.sort(Comparator.comparing(MediaVideoItem::isDefaultVersion).reversed());
        return files.stream().map(item -> {
            var node = fileQueryService.getFileNode(item.getOwnerUserId(), item.getFileNodeId());
            return new MovieVideoFileDto(
                    item.getId(),
                    item.getFileNodeId(),
                    node.name(),
                    node.sizeBytes(),
                    node.mimeType(),
                    item.getVersionLabel(),
                    item.isDefaultVersion(),
                    item.getVideoCodec(),
                    item.getAudioCodec(),
                    item.getContainerFormat(),
                    item.getResolutionWidth(),
                    item.getResolutionHeight()
            );
        }).toList();
    }
}
