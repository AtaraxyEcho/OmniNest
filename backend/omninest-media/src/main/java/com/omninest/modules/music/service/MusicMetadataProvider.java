package com.omninest.modules.music.service;

import com.omninest.modules.music.domain.MusicTrack;
import com.omninest.modules.music.dto.MusicDtos.MusicScrapeCandidateDto;
import java.util.List;

public interface MusicMetadataProvider {
    String providerName();

    List<MusicScrapeCandidateDto> search(MusicTrack track);
}
