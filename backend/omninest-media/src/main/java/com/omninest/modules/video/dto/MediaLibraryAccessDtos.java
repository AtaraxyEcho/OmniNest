package com.omninest.modules.video.dto;

import com.omninest.modules.video.domain.MediaLibraryVisibility;
import io.swagger.v3.oas.annotations.media.Schema;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.PositiveOrZero;
import java.util.Set;
import java.util.UUID;

/** 媒体库访问控制接口数据。 */
public final class MediaLibraryAccessDtos {

    private MediaLibraryAccessDtos() {
    }

    /** 更新媒体库可见性和显式用户授权。 */
    public record UpdateMediaLibraryAccessRequest(
            @NotNull MediaLibraryVisibility visibilityType,
            @NotNull Set<UUID> userIds,
            @PositiveOrZero long expectedVersion
    ) {
    }

    /** 媒体库访问设置。 */
    @Schema(description = "媒体库访问设置")
    public record MediaLibraryAccessDto(
            UUID librarySourceId,
            MediaLibraryVisibility visibilityType,
            Set<UUID> selectedUserIds,
            long version
    ) {
    }
}
