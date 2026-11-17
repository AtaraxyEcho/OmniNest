package com.omninest.modules.video.service;

import com.omninest.modules.file.service.FileQueryService;
import com.omninest.modules.video.dto.MovieDtos.CastMemberDto;
import com.omninest.modules.video.dto.MovieDtos.CrewMemberDto;
import java.util.List;
import java.util.Map;
import java.util.Objects;
import java.util.UUID;
import java.util.stream.Collectors;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Component;

/**
 * 影视目录条目映射工具：演职员、下载地址与类型名的单点实现。
 *
 * <p>供 {@link MovieLibraryService} 与 {@link VideoItemDtoConverter} 共用，
 * 保证头像解析（MinIO 优先、TMDB 降级）等逻辑只维护一份。</p>
 *
 * @author OmniNest
 */
@Slf4j
@Component
@RequiredArgsConstructor
public class VideoCatalogMappers {
    private final FileQueryService fileQueryService;

    /**
     * 解析文件下载地址，失败时返回 null（调用方降级到外部 URL）。
     */
    public String resolveFileUrl(UUID ownerUserId, UUID fileId) {
        try {
            return fileQueryService.createDownloadUrlAs(ownerUserId, fileId).downloadUrl();
        } catch (RuntimeException ex) {
            log.debug("MinIO 资源 URL 解析失败，降级到外部 URL: fileId={}, message={}", fileId, ex.getMessage());
            return null;
        }
    }

    /**
     * 一次批量解析演职员头像地址。
     *
     * <p>逐条签名会让一部片的 10-20 名演职员变成 10-20 次文件查询与签名，
     * 列表分页下就是几百次；批量接口一次取回，解析不到的条目降级到外部 URL。</p>
     */
    private Map<UUID, String> resolveProfileUrls(UUID ownerUserId, List<Map<String, Object>> members) {
        List<UUID> fileIds = members.stream()
                .map(VideoCatalogMappers::profileFileId)
                .filter(Objects::nonNull)
                .distinct()
                .toList();
        if (fileIds.isEmpty()) {
            return Map.of();
        }
        try {
            return fileQueryService.createDownloadUrlsAs(ownerUserId, fileIds).entrySet().stream()
                    .collect(Collectors.toMap(Map.Entry::getKey, entry -> entry.getValue().downloadUrl()));
        } catch (RuntimeException ex) {
            log.debug("批量解析演职员头像失败，降级到外部 URL: count={}, message={}",
                    fileIds.size(), ex.getMessage());
            return Map.of();
        }
    }

    private static UUID profileFileId(Map<String, Object> member) {
        Object fileIdObj = member.get("profileFileId");
        if (!(fileIdObj instanceof String fileIdStr) || fileIdStr.isBlank()) {
            return null;
        }
        try {
            return UUID.fromString(fileIdStr);
        } catch (IllegalArgumentException ex) {
            // profileFileId 格式异常，退回 profilePath
            return null;
        }
    }

    private static String profileUrlOf(Map<String, Object> member, Map<UUID, String> resolvedUrls) {
        UUID fileId = profileFileId(member);
        String resolved = fileId == null ? null : resolvedUrls.get(fileId);
        return resolved != null ? resolved : (String) member.get("profilePath");
    }

    @SuppressWarnings("unchecked")
    public List<CastMemberDto> toCastDtos(UUID ownerUserId, List<Map<String, Object>> castMembers) {
        if (castMembers == null || castMembers.isEmpty()) {
            return List.of();
        }
        Map<UUID, String> resolvedUrls = resolveProfileUrls(ownerUserId, castMembers);
        return castMembers.stream()
                .map(m -> new CastMemberDto(
                        (String) m.get("name"),
                        (String) m.get("character"),
                        profileUrlOf(m, resolvedUrls),
                        m.get("order") instanceof Number n ? n.intValue() : null
                ))
                .toList();
    }

    @SuppressWarnings("unchecked")
    public List<CrewMemberDto> toCrewDtos(UUID ownerUserId, List<Map<String, Object>> crewMembers) {
        if (crewMembers == null || crewMembers.isEmpty()) {
            return List.of();
        }
        Map<UUID, String> resolvedUrls = resolveProfileUrls(ownerUserId, crewMembers);
        return crewMembers.stream()
                .map(m -> new CrewMemberDto(
                        (String) m.get("name"),
                        (String) m.get("job"),
                        (String) m.get("department"),
                        profileUrlOf(m, resolvedUrls)
                ))
                .toList();
    }

    /**
     * 从元数据中提取类型名列表。
     */
    @SuppressWarnings("unchecked")
    public List<String> extractGenreNames(List<Map<String, Object>> genres) {
        if (genres == null || genres.isEmpty()) {
            return List.of();
        }
        return genres.stream()
                .map(g -> (String) g.get("name"))
                .filter(name -> name != null && !name.isBlank())
                .toList();
    }
}
