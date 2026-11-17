package com.omninest.modules.reader.service;

import com.omninest.modules.media.service.MediaCoverContributor;
import com.omninest.modules.reader.domain.ReaderItem;
import com.omninest.modules.reader.repository.ReaderItemRepository;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Component;

/**
 * 阅读域封面贡献者：直接返回阅读条目自带的封面文件。
 *
 * @author OmniNest
 */
@Component
@RequiredArgsConstructor
public class ReaderCoverContributor implements MediaCoverContributor {

    private final ReaderItemRepository readerItemRepository;

    @Override
    public void contribute(UUID ownerUserId, List<UUID> fileNodeIds, Map<UUID, UUID> covers) {
        for (ReaderItem item : readerItemRepository.findByFileNodeIdIn(fileNodeIds)) {
            if (item.getCoverFileId() != null) {
                covers.put(item.getFileNodeId(), item.getCoverFileId());
            }
        }
    }
}
