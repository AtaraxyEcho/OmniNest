package com.omninest.modules.video.service;

import com.omninest.modules.video.dto.MovieDtos.ScrapeCandidateDto;
import java.util.List;

public interface MetadataProvider {
    String providerName();

    List<ScrapeCandidateDto> search(FileNameGuess guess);
}
