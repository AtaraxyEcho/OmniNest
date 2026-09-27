package com.omninest.modules.video.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.verifyNoInteractions;
import static org.mockito.Mockito.when;

import com.omninest.common.enums.ErrorCode;
import com.omninest.common.error.BusinessException;
import com.omninest.common.security.Permissions;
import com.omninest.modules.file.domain.StorageLocation;
import com.omninest.modules.file.service.StorageLocationService;
import com.omninest.modules.user.dto.UserDirectoryDtos.UserAuthorizationProfile;
import com.omninest.modules.user.service.UserDirectoryQueryService;
import com.omninest.modules.video.domain.MediaLibraryVisibility;
import com.omninest.modules.video.domain.VideoLibrarySource;
import com.omninest.modules.video.dto.MediaLibraryAccessDtos.UpdateMediaLibraryAccessRequest;
import com.omninest.modules.video.repository.MediaLibraryAccessRepository;
import com.omninest.modules.video.repository.VideoLibrarySourceRepository;
import java.util.Optional;
import java.util.Set;
import java.util.UUID;
import org.junit.jupiter.api.Test;

class MediaLibraryAccessServiceTest {
    private static final UUID OWNER_ID = UUID.fromString("10000000-0000-0000-0000-000000000001");
    private static final UUID MEMBER_ID = UUID.fromString("20000000-0000-0000-0000-000000000001");
    private static final UUID SOURCE_ID = UUID.fromString("30000000-0000-0000-0000-000000000001");
    private static final UUID LOCATION_ID = UUID.fromString("40000000-0000-0000-0000-000000000001");

    private final VideoLibrarySourceRepository sourceRepository = mock(VideoLibrarySourceRepository.class);
    private final MediaLibraryAccessRepository accessRepository = mock(MediaLibraryAccessRepository.class);
    private final UserDirectoryQueryService userDirectoryQueryService = mock(UserDirectoryQueryService.class);
    private final StorageLocationService storageLocationService = mock(StorageLocationService.class);
    private final MediaLibraryAccessService service = new MediaLibraryAccessService(
            sourceRepository,
            accessRepository,
            userDirectoryQueryService,
            storageLocationService
    );

    @Test
    void privateLibraryRejectsNonOwner() {
        VideoLibrarySource source = source(MediaLibraryVisibility.PRIVATE);
        when(sourceRepository.findById(SOURCE_ID)).thenReturn(Optional.of(source));
        when(userDirectoryQueryService.requireAuthorizationProfile(MEMBER_ID)).thenReturn(profile("MEMBER"));

        assertThatThrownBy(() -> service.requireRead(MEMBER_ID, SOURCE_ID))
                .isInstanceOfSatisfying(BusinessException.class, exception ->
                        assertThat(exception.errorCode()).isEqualTo(ErrorCode.FORBIDDEN));
    }

    @Test
    void privateLibraryAllowsOwnerWithReadPermission() {
        VideoLibrarySource source = source(MediaLibraryVisibility.PRIVATE);
        when(sourceRepository.findById(SOURCE_ID)).thenReturn(Optional.of(source));
        when(userDirectoryQueryService.requireAuthorizationProfile(OWNER_ID)).thenReturn(ownerProfile());

        assertThat(service.requireRead(OWNER_ID, SOURCE_ID)).isSameAs(source);
    }

    @Test
    void disabledLibraryRejectsOwner() {
        VideoLibrarySource source = source(MediaLibraryVisibility.PRIVATE);
        source.setEnabled(false);
        when(sourceRepository.findById(SOURCE_ID)).thenReturn(Optional.of(source));
        when(userDirectoryQueryService.requireAuthorizationProfile(OWNER_ID)).thenReturn(ownerProfile());

        assertThatThrownBy(() -> service.requireRead(OWNER_ID, SOURCE_ID))
                .isInstanceOfSatisfying(BusinessException.class, exception ->
                        assertThat(exception.errorCode()).isEqualTo(ErrorCode.FORBIDDEN));
    }

    @Test
    void selectedUserCanReadWithoutBecomingOwner() {
        VideoLibrarySource source = source(MediaLibraryVisibility.SELECTED_USERS);
        when(sourceRepository.findById(SOURCE_ID)).thenReturn(Optional.of(source));
        when(userDirectoryQueryService.requireAuthorizationProfile(MEMBER_ID)).thenReturn(profile("MEMBER"));
        when(accessRepository.existsByLibrarySourceIdAndUserId(SOURCE_ID, MEMBER_ID)).thenReturn(true);

        assertThat(service.requireRead(MEMBER_ID, SOURCE_ID)).isSameAs(source);
    }

    @Test
    void selectedUserWithoutGrantCannotRead() {
        VideoLibrarySource source = source(MediaLibraryVisibility.SELECTED_USERS);
        when(sourceRepository.findById(SOURCE_ID)).thenReturn(Optional.of(source));
        when(userDirectoryQueryService.requireAuthorizationProfile(MEMBER_ID)).thenReturn(profile("MEMBER"));
        when(accessRepository.existsByLibrarySourceIdAndUserId(SOURCE_ID, MEMBER_ID)).thenReturn(false);

        assertThatThrownBy(() -> service.requireRead(MEMBER_ID, SOURCE_ID))
                .isInstanceOfSatisfying(BusinessException.class, exception ->
                        assertThat(exception.errorCode()).isEqualTo(ErrorCode.FORBIDDEN));
    }

    @Test
    void allMembersIncludesGuestWithMediaRead() {
        VideoLibrarySource source = source(MediaLibraryVisibility.ALL_MEMBERS);
        when(sourceRepository.findById(SOURCE_ID)).thenReturn(Optional.of(source));
        when(userDirectoryQueryService.requireAuthorizationProfile(MEMBER_ID)).thenReturn(profile("GUEST"));

        assertThat(service.requireRead(MEMBER_ID, SOURCE_ID)).isSameAs(source);
    }

    @Test
    void allMembersAllowsAnActiveMemberWithMediaReadPermission() {
        VideoLibrarySource source = source(MediaLibraryVisibility.ALL_MEMBERS);
        when(sourceRepository.findById(SOURCE_ID)).thenReturn(Optional.of(source));
        when(userDirectoryQueryService.requireAuthorizationProfile(MEMBER_ID)).thenReturn(profile("MEMBER"));

        assertThat(service.requireRead(MEMBER_ID, SOURCE_ID)).isSameAs(source);
    }

    @Test
    void disabledSelectedUserCannotRead() {
        VideoLibrarySource source = source(MediaLibraryVisibility.SELECTED_USERS);
        when(sourceRepository.findById(SOURCE_ID)).thenReturn(Optional.of(source));
        when(userDirectoryQueryService.requireAuthorizationProfile(MEMBER_ID)).thenReturn(new UserAuthorizationProfile(
                MEMBER_ID,
                "DISABLED",
                Set.of("MEMBER"),
                Set.of(Permissions.MEDIA_READ)
        ));
        when(accessRepository.existsByLibrarySourceIdAndUserId(SOURCE_ID, MEMBER_ID)).thenReturn(true);

        assertThatThrownBy(() -> service.requireRead(MEMBER_ID, SOURCE_ID))
                .isInstanceOfSatisfying(BusinessException.class, exception ->
                        assertThat(exception.errorCode()).isEqualTo(ErrorCode.FORBIDDEN));
    }

    @Test
    void userScopedStorageCannotBecomeShared() {
        VideoLibrarySource source = source(MediaLibraryVisibility.PRIVATE);
        source.setVersion(2);
        StorageLocation location = new StorageLocation();
        location.setScopeType("USER");
        when(sourceRepository.findById(SOURCE_ID)).thenReturn(Optional.of(source));
        when(userDirectoryQueryService.requireAuthorizationProfile(OWNER_ID)).thenReturn(new UserAuthorizationProfile(
                OWNER_ID,
                "ACTIVE",
                Set.of("ADMIN"),
                Set.of(Permissions.MEDIA_LIBRARY_MANAGE)
        ));
        when(storageLocationService.requireLocationForBusiness(LOCATION_ID)).thenReturn(location);

        var request = new UpdateMediaLibraryAccessRequest(
                MediaLibraryVisibility.ALL_MEMBERS,
                Set.of(),
                2
        );
        assertThatThrownBy(() -> service.replaceSelectedUsers(OWNER_ID, SOURCE_ID, request))
                .isInstanceOfSatisfying(BusinessException.class, exception ->
                        assertThat(exception.errorCode()).isEqualTo(ErrorCode.FORBIDDEN));
    }

    @Test
    void staleVersionDoesNotMutateAccessSettings() {
        VideoLibrarySource source = source(MediaLibraryVisibility.PRIVATE);
        source.setVersion(3);
        when(sourceRepository.findById(SOURCE_ID)).thenReturn(Optional.of(source));
        when(userDirectoryQueryService.requireAuthorizationProfile(OWNER_ID)).thenReturn(manageProfile());

        var request = new UpdateMediaLibraryAccessRequest(
                MediaLibraryVisibility.ALL_MEMBERS,
                Set.of(),
                2
        );

        assertThatThrownBy(() -> service.replaceSelectedUsers(OWNER_ID, SOURCE_ID, request))
                .isInstanceOfSatisfying(BusinessException.class, exception ->
                        assertThat(exception.errorCode()).isEqualTo(ErrorCode.CONFLICT));
        verify(accessRepository, never()).deleteByLibrarySourceId(any());
        verify(sourceRepository, never()).saveAndFlush(any());
        verifyNoInteractions(storageLocationService);
    }

    @Test
    void switchingToPrivateClearsExplicitGrantsWithoutStorageLookup() {
        VideoLibrarySource source = source(MediaLibraryVisibility.SELECTED_USERS);
        source.setVersion(4);
        when(sourceRepository.findById(SOURCE_ID)).thenReturn(Optional.of(source));
        when(sourceRepository.saveAndFlush(source)).thenReturn(source);
        when(userDirectoryQueryService.requireAuthorizationProfile(OWNER_ID)).thenReturn(manageProfile());

        var result = service.replaceSelectedUsers(
                OWNER_ID,
                SOURCE_ID,
                new UpdateMediaLibraryAccessRequest(MediaLibraryVisibility.PRIVATE, Set.of(MEMBER_ID), 4)
        );

        assertThat(result.visibilityType()).isEqualTo(MediaLibraryVisibility.PRIVATE);
        assertThat(result.selectedUserIds()).isEmpty();
        verify(accessRepository).deleteByLibrarySourceId(SOURCE_ID);
        verify(accessRepository, never()).saveAll(any());
        verifyNoInteractions(storageLocationService);
    }

    @Test
    void switchingToSelectedUsersPersistsValidatedGrant() {
        VideoLibrarySource source = source(MediaLibraryVisibility.PRIVATE);
        source.setVersion(5);
        StorageLocation location = new StorageLocation();
        location.setScopeType("SYSTEM");
        when(sourceRepository.findById(SOURCE_ID)).thenReturn(Optional.of(source));
        when(sourceRepository.saveAndFlush(source)).thenReturn(source);
        when(userDirectoryQueryService.requireAuthorizationProfile(OWNER_ID)).thenReturn(manageProfile());
        when(userDirectoryQueryService.requireAuthorizationProfile(MEMBER_ID)).thenReturn(profile("MEMBER"));
        when(storageLocationService.requireLocationForBusiness(LOCATION_ID)).thenReturn(location);

        var result = service.replaceSelectedUsers(
                OWNER_ID,
                SOURCE_ID,
                new UpdateMediaLibraryAccessRequest(
                        MediaLibraryVisibility.SELECTED_USERS,
                        Set.of(MEMBER_ID),
                        5
                )
        );

        assertThat(result.visibilityType()).isEqualTo(MediaLibraryVisibility.SELECTED_USERS);
        verify(accessRepository).deleteByLibrarySourceId(SOURCE_ID);
        verify(accessRepository).saveAll(any());
        verify(sourceRepository).saveAndFlush(source);
    }

    private UserAuthorizationProfile profile(String role) {
        return new UserAuthorizationProfile(
                MEMBER_ID,
                "ACTIVE",
                Set.of(role),
                Set.of(Permissions.MEDIA_READ)
        );
    }

    private UserAuthorizationProfile ownerProfile() {
        return new UserAuthorizationProfile(
                OWNER_ID,
                "ACTIVE",
                Set.of("ADMIN"),
                Set.of(Permissions.MEDIA_READ)
        );
    }

    private UserAuthorizationProfile manageProfile() {
        return new UserAuthorizationProfile(
                OWNER_ID,
                "ACTIVE",
                Set.of("ADMIN"),
                Set.of(Permissions.MEDIA_LIBRARY_MANAGE)
        );
    }

    private VideoLibrarySource source(MediaLibraryVisibility visibility) {
        VideoLibrarySource source = new VideoLibrarySource();
        source.setId(SOURCE_ID);
        source.setOwnerUserId(OWNER_ID);
        source.setStorageLocationId(LOCATION_ID);
        source.setVisibilityType(visibility.name());
        source.setEnabled(true);
        return source;
    }
}
