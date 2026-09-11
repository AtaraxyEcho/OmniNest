package com.omninest.modules.file.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import com.omninest.common.enums.ErrorCode;
import com.omninest.common.error.BusinessException;
import com.omninest.modules.file.config.LocalMediaStorageProperties;
import com.omninest.modules.file.domain.StorageLocation;
import com.omninest.modules.file.dto.StorageLocationDtos.CreateStorageLocationRequest;
import com.omninest.modules.file.repository.FileContentRefRepository;
import com.omninest.modules.file.repository.StorageLocationRepository;
import java.util.List;
import java.util.UUID;
import org.junit.jupiter.api.Test;
import org.mockito.Mockito;

/**
 * 存储位置运行时门禁测试。
 *
 * @author OmniNest
 */
class StorageLocationServiceTest {
    private final StorageLocationRepository locationRepository = Mockito.mock(StorageLocationRepository.class);
    private final FileContentRefRepository contentRefRepository = Mockito.mock(FileContentRefRepository.class);
    private final LocalMediaPathResolver pathResolver = Mockito.mock(LocalMediaPathResolver.class);
    private final LocalMediaRuntimeConfigService runtimeConfigService =
            Mockito.mock(LocalMediaRuntimeConfigService.class);
    private final StorageLocationInserter locationInserter = Mockito.mock(StorageLocationInserter.class);
    private final StorageLocationService service = new StorageLocationService(
            locationRepository,
            contentRefRepository,
            pathResolver,
            new LocalMediaStorageProperties(),
            runtimeConfigService,
            locationInserter,
            List.of()
    );

    @Test
    void disabledRuntimeReturnsNoAccessibleLocations() {
        Mockito.when(runtimeConfigService.isEnabled()).thenReturn(false);

        assertThat(service.listAccessible(UUID.randomUUID())).isEmpty();
        Mockito.verifyNoInteractions(locationRepository);
    }

    @Test
    void disabledRuntimeRejectsLocationAccessBeforeRepositoryLookup() {
        Mockito.when(runtimeConfigService.isEnabled()).thenReturn(false);

        assertThatThrownBy(() -> service.requireAccessibleLocation(UUID.randomUUID(), UUID.randomUUID()))
                .isInstanceOf(BusinessException.class)
                .extracting(exception -> ((BusinessException) exception).errorCode())
                .isEqualTo(ErrorCode.DEPENDENCY_UNAVAILABLE);
        Mockito.verifyNoInteractions(locationRepository, pathResolver);
    }

    @Test
    void createRejectsDuplicateSystemScopeLocationViaIsNullLookup() {
        Mockito.when(runtimeConfigService.isEnabled()).thenReturn(true);
        Mockito.when(locationRepository.existsByMountKeyAndRelativeRootAndScopeTypeAndScopeIdIsNull(
                        "media", ".", "SYSTEM"))
                .thenReturn(true);

        assertThatThrownBy(() -> service.create(UUID.randomUUID(), new CreateStorageLocationRequest(
                "重复位置", "media", ".", "SYSTEM", null, true)))
                .isInstanceOf(BusinessException.class)
                .extracting(exception -> ((BusinessException) exception).errorCode())
                .isEqualTo(ErrorCode.CONFLICT);
        Mockito.verify(locationRepository).existsByMountKeyAndRelativeRootAndScopeTypeAndScopeIdIsNull(
                "media", ".", "SYSTEM");
        Mockito.verify(locationRepository, Mockito.never())
                .existsByMountKeyAndRelativeRootAndScopeTypeAndScopeId(Mockito.any(), Mockito.any(),
                        Mockito.any(), Mockito.any());
    }

    @Test
    void createRejectsDuplicateUserScopeLocationViaEqualityLookup() {
        Mockito.when(runtimeConfigService.isEnabled()).thenReturn(true);
        UUID scopeId = UUID.randomUUID();
        Mockito.when(locationRepository.existsByMountKeyAndRelativeRootAndScopeTypeAndScopeId(
                        "media", "Movies", "USER", scopeId))
                .thenReturn(true);

        assertThatThrownBy(() -> service.create(UUID.randomUUID(), new CreateStorageLocationRequest(
                "重复位置", "media", "Movies", "USER", scopeId, true)))
                .isInstanceOf(BusinessException.class)
                .extracting(exception -> ((BusinessException) exception).errorCode())
                .isEqualTo(ErrorCode.CONFLICT);
        Mockito.verify(locationRepository).existsByMountKeyAndRelativeRootAndScopeTypeAndScopeId(
                "media", "Movies", "USER", scopeId);
        Mockito.verify(locationRepository, Mockito.never())
                .existsByMountKeyAndRelativeRootAndScopeTypeAndScopeIdIsNull(Mockito.any(), Mockito.any(),
                        Mockito.any());
    }

    @Test
    void findOrCreateSystemLocationReusesExistingEnabledLocation() {
        Mockito.when(runtimeConfigService.isEnabled()).thenReturn(true);
        StorageLocation existing = systemLocation("media", ".");
        Mockito.when(locationRepository.findFirstByMountKeyAndRelativeRootAndScopeTypeAndScopeIdIsNull(
                "media", ".", "SYSTEM")).thenReturn(java.util.Optional.of(existing));

        assertThat(service.findOrCreateSystemLocation(UUID.randomUUID(), "media", "."))
                .isSameAs(existing);
        Mockito.verifyNoInteractions(locationInserter);
    }

    @Test
    void findOrCreateSystemLocationRejectsDisabledExistingLocation() {
        Mockito.when(runtimeConfigService.isEnabled()).thenReturn(true);
        StorageLocation disabled = systemLocation("media", ".");
        disabled.setEnabled(false);
        Mockito.when(locationRepository.findFirstByMountKeyAndRelativeRootAndScopeTypeAndScopeIdIsNull(
                "media", ".", "SYSTEM")).thenReturn(java.util.Optional.of(disabled));

        assertThatThrownBy(() -> service.findOrCreateSystemLocation(UUID.randomUUID(), "media", "."))
                .isInstanceOf(BusinessException.class)
                .extracting(exception -> ((BusinessException) exception).errorCode())
                .isEqualTo(ErrorCode.DEPENDENCY_UNAVAILABLE);
        Mockito.verifyNoInteractions(locationInserter);
    }

    @Test
    void findOrCreateSystemLocationCreatesValidatedLocationWithAutoName() {
        Mockito.when(runtimeConfigService.isEnabled()).thenReturn(true);
        Mockito.when(locationRepository.findFirstByMountKeyAndRelativeRootAndScopeTypeAndScopeIdIsNull(
                "media", ".", "SYSTEM")).thenReturn(java.util.Optional.empty());
        Mockito.when(locationInserter.insert(Mockito.any(StorageLocation.class)))
                .thenAnswer(invocation -> invocation.getArgument(0));

        StorageLocation created = service.findOrCreateSystemLocation(UUID.randomUUID(), "media", ".");

        assertThat(created.getMountKey()).isEqualTo("media");
        assertThat(created.getRelativeRoot()).isEqualTo(".");
        assertThat(created.getName()).isEqualTo("media");
        assertThat(created.getScopeType()).isEqualTo("SYSTEM");
        assertThat(created.isEnabled()).isTrue();
        Mockito.verify(pathResolver).resolveLocationRoot(created);
        Mockito.verify(locationInserter).insert(created);
    }

    @Test
    void findOrCreateSystemLocationRefetchesAfterConcurrentUniqueConflict() {
        Mockito.when(runtimeConfigService.isEnabled()).thenReturn(true);
        StorageLocation winner = systemLocation("media", ".");
        Mockito.when(locationRepository.findFirstByMountKeyAndRelativeRootAndScopeTypeAndScopeIdIsNull(
                "media", ".", "SYSTEM"))
                .thenReturn(java.util.Optional.empty())
                .thenReturn(java.util.Optional.of(winner));
        Mockito.when(locationInserter.insert(Mockito.any(StorageLocation.class)))
                .thenThrow(new org.springframework.dao.DataIntegrityViolationException("唯一键冲突"));

        assertThat(service.findOrCreateSystemLocation(UUID.randomUUID(), "media", "."))
                .isSameAs(winner);
    }

    private StorageLocation systemLocation(String mountKey, String relativeRoot) {
        StorageLocation location = new StorageLocation();
        location.setId(UUID.randomUUID());
        location.setName(mountKey);
        location.setProviderType("LOCAL_FILESYSTEM");
        location.setManagementMode("READ_ONLY");
        location.setMountKey(mountKey);
        location.setRelativeRoot(relativeRoot);
        location.setScopeType("SYSTEM");
        location.setEnabled(true);
        return location;
    }
}
