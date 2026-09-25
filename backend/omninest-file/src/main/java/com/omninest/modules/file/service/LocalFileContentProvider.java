package com.omninest.modules.file.service;

import com.omninest.common.enums.ErrorCode;
import com.omninest.common.error.BusinessException;
import com.omninest.modules.file.domain.FileContentRef;
import com.omninest.modules.file.domain.FileNode;
import com.omninest.modules.file.domain.StorageLocation;
import com.omninest.modules.file.dto.FileContentResource;
import com.omninest.modules.file.dto.FileContentStream;
import com.omninest.modules.file.dto.FileDownloadUrlDto;
import com.omninest.modules.file.dto.FileProcessInput;
import com.omninest.modules.file.repository.FileContentRefRepository;
import com.omninest.modules.file.repository.StorageLocationRepository;
import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.Optional;
import lombok.RequiredArgsConstructor;
import org.springframework.core.io.FileSystemResource;
import org.springframework.stereotype.Service;

/**
 * 本地文件系统只读内容提供者。
 *
 * @author OmniNest
 */
@Service
@RequiredArgsConstructor
public class LocalFileContentProvider implements FileContentProvider {
    private static final String PROVIDER_TYPE = "LOCAL_FILESYSTEM";
    private static final String AVAILABLE = "AVAILABLE";

    private final FileContentRefRepository contentRefRepository;
    private final StorageLocationRepository storageLocationRepository;
    private final LocalMediaPathResolver pathResolver;
    private final LocalContentAccessTokenService tokenService;
    private final LocalMediaRuntimeConfigService runtimeConfigService;

    @Override
    public String providerType() {
        return PROVIDER_TYPE;
    }

    @Override
    public boolean supports(FileNode node) {
        return node.getCurrentObjectId() == null && contentRefRepository.findByFileNodeId(node.getId()).isPresent();
    }

    @Override
    public FileContentStream open(FileNode node) {
        ResolvedContent content = resolve(node);
        try {
            return new FileContentStream(
                    Files.newInputStream(content.path()),
                    node.getName(),
                    Files.size(content.path()),
                    node.getMimeType()
            );
        } catch (IOException e) {
            throw unavailable();
        }
    }

    @Override
    public FileDownloadUrlDto createDownloadUrl(FileNode node) {
        resolve(node);
        LocalContentAccessTokenService.IssuedAccess issued = tokenService.issue(node.getOwnerUserId(), node.getId());
        String relativeUrl = "/api/v1/public/file-content/" + issued.token();
        return new FileDownloadUrlDto(node.getId(), node.getName(), relativeUrl, issued.expiresAt());
    }

    @Override
    public FileProcessInput createProcessInput(FileNode node) {
        ResolvedContent content = resolve(node);
        String processPath = pathResolver.resolveProcessPath(content.location(), content.reference().getRelativePath());
        return new FileProcessInput(node.getId(), PROVIDER_TYPE, processPath);
    }

    @Override
    public Optional<FileContentResource> findRangeResource(FileNode node) {
        ResolvedContent content = resolve(node);
        try {
            return Optional.of(new FileContentResource(
                    new FileSystemResource(content.path()),
                    node.getName(),
                    Files.size(content.path()),
                    node.getMimeType()
            ));
        } catch (IOException e) {
            throw unavailable();
        }
    }

    private ResolvedContent resolve(FileNode node) {
        if (!runtimeConfigService.isEnabled()) {
            throw unavailable("本地媒体功能未启用");
        }
        FileContentRef reference = contentRefRepository.findByFileNodeId(node.getId())
                .orElseThrow(() -> new BusinessException(ErrorCode.FILE_NOT_FOUND, "文件内容引用不存在"));
        StorageLocation location = storageLocationRepository.findById(reference.getStorageLocationId())
                .orElseThrow(() -> unavailable("存储位置不存在"));
        if (!location.isEnabled() || !PROVIDER_TYPE.equals(location.getProviderType())) {
            throw unavailable("存储位置已停用或类型不匹配");
        }
        Path path = pathResolver.resolveFile(location, reference.getRelativePath());
        // 读路径不写 availabilityStatus，可用性由扫描/维护流程更新。
        return new ResolvedContent(reference, location, path);
    }

    private BusinessException unavailable() {
        return unavailable("本地媒体文件当前不可用");
    }

    private BusinessException unavailable(String message) {
        return new BusinessException(ErrorCode.DEPENDENCY_UNAVAILABLE, message);
    }

    private record ResolvedContent(FileContentRef reference, StorageLocation location, Path path) {
    }
}
