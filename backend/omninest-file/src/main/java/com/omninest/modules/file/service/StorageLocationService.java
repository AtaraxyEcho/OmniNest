package com.omninest.modules.file.service;

import com.omninest.common.enums.ErrorCode;
import com.omninest.common.error.BusinessException;
import com.omninest.modules.file.config.LocalMediaStorageProperties;
import com.omninest.modules.file.domain.StorageLocation;
import com.omninest.modules.file.dto.StorageLocationDtos.CreateStorageLocationRequest;
import com.omninest.modules.file.dto.StorageLocationDtos.StorageLocationDescriptor;
import com.omninest.modules.file.dto.StorageLocationDtos.StorageLocationDto;
import com.omninest.modules.file.dto.StorageLocationDtos.UpdateStorageLocationRequest;
import com.omninest.modules.file.dto.StorageLocationDtos.TrustedMountDto;
import com.omninest.modules.file.repository.FileContentRefRepository;
import com.omninest.modules.file.repository.StorageLocationRepository;
import java.nio.file.Files;
import java.nio.file.InvalidPathException;
import java.nio.file.Path;
import java.util.Comparator;
import java.util.List;
import java.util.Locale;
import java.util.UUID;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * 本地只读存储位置管理与授权服务。
 *
 * @author OmniNest
 */
@Slf4j
@Service
@RequiredArgsConstructor
public class StorageLocationService {
    private static final String LOCAL_FILESYSTEM = "LOCAL_FILESYSTEM";
    private static final String READ_ONLY = "READ_ONLY";
    private static final String SYSTEM = "SYSTEM";
    private static final String USER = "USER";

    private final StorageLocationRepository storageLocationRepository;
    private final FileContentRefRepository contentRefRepository;
    private final LocalMediaPathResolver pathResolver;
    private final LocalMediaStorageProperties properties;
    private final LocalMediaRuntimeConfigService runtimeConfigService;
    private final StorageLocationInserter locationInserter;
    private final List<StorageLocationUsageInspector> usageInspectors;

    /**
     * 管理员列出全部存储位置。
     *
     * @return 存储位置列表
     */
    @Transactional(readOnly = true)
    public List<StorageLocationDto> listAll() {
        return storageLocationRepository.findAllByOrderByNameAsc().stream().map(this::toDto).toList();
    }

    /**
     * 列出部署配置允许的挂载键，不返回宿主机路径或媒体进程路径。
     *
     * @return 可信挂载列表
     */
    public List<TrustedMountDto> listTrustedMounts() {
        if (!runtimeConfigService.isEnabled()) {
            return List.of();
        }
        return properties.getMounts().entrySet().stream()
                .map(entry -> new TrustedMountDto(
                        entry.getKey(),
                        entry.getKey(),
                        isMountAvailable(entry.getValue())
                ))
                .sorted(Comparator.comparing(TrustedMountDto::mountKey))
                .toList();
    }

    /**
     * 创建本地只读存储位置。
     *
     * @param operatorId 操作用户 ID
     * @param request 创建请求
     * @return 已创建存储位置
     */
    @Transactional(rollbackFor = Exception.class)
    public StorageLocationDto create(UUID operatorId, CreateStorageLocationRequest request) {
        StorageLocation location = new StorageLocation();
        location.setName(normalizeName(request.name()));
        location.setProviderType(LOCAL_FILESYSTEM);
        location.setManagementMode(READ_ONLY);
        location.setMountKey(normalizeMountKey(request.mountKey()));
        location.setRelativeRoot(normalizeRelativeRoot(request.relativeRoot()));
        applyScope(location, request.scopeType(), request.scopeId());
        location.setEnabled(request.enabled());
        location.setCreatedBy(operatorId);
        if (isDuplicateLocation(location)) {
            throw new BusinessException(ErrorCode.CONFLICT, "相同作用域的存储位置已存在");
        }
        validateLocation(location);
        StorageLocation saved = storageLocationRepository.save(location);
        log.info("本地媒体存储位置已创建: locationId={}, mountKey={}, scopeType={}",
                saved.getId(), saved.getMountKey(), saved.getScopeType());
        return toDto(saved);
    }

    /**
     * 更新本地只读存储位置的名称与启用状态。
     *
     * @param locationId 存储位置 ID
     * @param request 更新请求
     * @return 已更新存储位置
     */
    @Transactional(rollbackFor = Exception.class)
    public StorageLocationDto update(UUID locationId, UpdateStorageLocationRequest request) {
        StorageLocation location = requireLocation(locationId);
        location.setName(normalizeName(request.name()));
        location.setEnabled(request.enabled());
        if (request.enabled()) {
            validateLocation(location);
        }
        StorageLocation saved = storageLocationRepository.save(location);
        log.info("本地媒体存储位置状态已更新: locationId={}, enabled={}", saved.getId(), saved.isEnabled());
        return toDto(saved);
    }

    /**
     * 删除没有内容引用的存储位置。
     *
     * @param locationId 存储位置 ID
     */
    @Transactional(rollbackFor = Exception.class)
    public void delete(UUID locationId) {
        StorageLocation location = requireLocation(locationId);
        if (contentRefRepository.countByStorageLocationId(locationId) > 0) {
            throw new BusinessException(ErrorCode.RESOURCE_IN_USE, "存储位置仍被文件内容引用");
        }
        if (usageInspectors.stream().anyMatch(inspector -> inspector.isInUse(locationId))) {
            throw new BusinessException(ErrorCode.RESOURCE_IN_USE, "存储位置仍被业务来源引用");
        }
        storageLocationRepository.delete(location);
        log.info("本地媒体存储位置已删除: locationId={}", locationId);
    }

    /**
     * 查询当前用户可用于影视库的存储位置。
     *
     * @param userId 当前用户 ID
     * @return 可访问存储位置列表
     */
    @Transactional(readOnly = true)
    public List<StorageLocationDescriptor> listAccessible(UUID userId) {
        if (!runtimeConfigService.isEnabled()) {
            return List.of();
        }
        return storageLocationRepository.findAllByOrderByNameAsc().stream()
                .filter(StorageLocation::isEnabled)
                .filter(location -> SYSTEM.equals(location.getScopeType()))
                .map(this::toDescriptor)
                .toList();
    }

    /**
     * 校验并返回当前用户可访问的存储位置。
     *
     * @param userId 当前用户 ID
     * @param locationId 存储位置 ID
     * @return 存储位置实体
     */
    @Transactional(readOnly = true)
    public StorageLocation requireAccessibleLocation(UUID userId, UUID locationId) {
        ensureRuntimeEnabled();
        StorageLocation location = requireLocation(locationId);
        if (!location.isEnabled() || !isInScope(location, userId)) {
            throw new BusinessException(ErrorCode.FORBIDDEN, "无权使用该存储位置");
        }
        if (!pathResolver.isAvailable(location)) {
            throw new BusinessException(ErrorCode.DEPENDENCY_UNAVAILABLE, "存储位置在当前节点不可用");
        }
        return location;
    }

    /**
     * 供已完成业务授权的模块读取存储位置元数据，不放宽文件内容访问权限。
     *
     * @param locationId 存储位置 ID
     * @return 存储位置
     */
    @Transactional(readOnly = true)
    public StorageLocation requireLocationForBusiness(UUID locationId) {
        return requireLocation(locationId);
    }

    /**
     * 按挂载键列出全部存储位置，供业务模块做同挂载跨位置的物理路径冲突检查。
     *
     * @param mountKey 挂载键
     * @return 同挂载键的存储位置列表
     */
    @Transactional(readOnly = true)
    public List<StorageLocation> listByMountKeyForBusiness(String mountKey) {
        return storageLocationRepository.findByMountKey(normalizeMountKey(mountKey));
    }

    /**
     * 查找或创建系统级存储位置，供持有系统配置管理权限的业务流程挂载直达使用。
     *
     * <p>命中同挂载与相对根的系统级位置时直接复用；未命中时在独立事务中创建，
     * 并发撞唯一键时回查返回既有记录。创建的记录独立提交，调用方后续业务失败
     * 时应通过 rollbackAutoCreatedLocation 清理本次新建且无引用的位置。</p>
     *
     * @param operatorId 操作用户 ID
     * @param mountKey 部署可信挂载键
     * @param relativeRoot 位置相对根目录
     * @return 位置与本次是否新建的判定结果
     */
    public SystemLocationResolution findOrCreateSystemLocation(UUID operatorId, String mountKey, String relativeRoot) {
        ensureRuntimeEnabled();
        String normalizedMountKey = normalizeMountKey(mountKey);
        String normalizedRoot = normalizeRelativeRoot(relativeRoot);
        StorageLocation existing = storageLocationRepository
                .findFirstByMountKeyAndRelativeRootAndScopeTypeAndScopeIdIsNull(
                        normalizedMountKey, normalizedRoot, SYSTEM)
                .orElse(null);
        if (existing != null) {
            if (!existing.isEnabled()) {
                throw new BusinessException(ErrorCode.DEPENDENCY_UNAVAILABLE, "存储位置已停用");
            }
            return new SystemLocationResolution(existing, false);
        }
        StorageLocation location = new StorageLocation();
        location.setName(autoLocationName(normalizedMountKey, normalizedRoot));
        location.setProviderType(LOCAL_FILESYSTEM);
        location.setManagementMode(READ_ONLY);
        location.setMountKey(normalizedMountKey);
        location.setRelativeRoot(normalizedRoot);
        location.setScopeType(SYSTEM);
        location.setScopeId(null);
        location.setEnabled(true);
        location.setCreatedBy(operatorId);
        validateLocation(location);
        try {
            return new SystemLocationResolution(locationInserter.insert(location), true);
        } catch (DataIntegrityViolationException exception) {
            return storageLocationRepository
                    .findFirstByMountKeyAndRelativeRootAndScopeTypeAndScopeIdIsNull(
                            normalizedMountKey, normalizedRoot, SYSTEM)
                    .map(found -> new SystemLocationResolution(found, false))
                    .orElseThrow(() -> exception);
        }
    }

    /**
     * 回滚挂载直达本次自动创建的存储位置：仍被内容引用或业务来源引用时跳过。
     *
     * <p>必须在独立事务中执行判定与删除，避免外层失败事务中止后无法继续查询；
     * 判定与删除之间存在极小的并发窗口（他方恰在此时引用该位置），由引用方
     * 后续健康检查暴露，不做悲观锁。</p>
     *
     * @param locationId 自动创建的存储位置 ID
     */
    public void rollbackAutoCreatedLocation(UUID locationId) {
        locationInserter.deleteIfUnreferenced(locationId);
    }

    /**
     * find-or-create 结果：位置与本次调用是否新建，供调用方决定失败清理。
     */
    public record SystemLocationResolution(StorageLocation location, boolean created) {
    }

    /**
     * 自动生成位置显示名：挂载根直接用挂载键，子目录用挂载键加末段；
     * 按 Unicode 码点截断至 160，避免切断代理项对。
     */
    private String autoLocationName(String mountKey, String relativeRoot) {
        String name = ".".equals(relativeRoot)
                ? mountKey
                : mountKey + "/" + Path.of(relativeRoot).getFileName();
        if (name.codePointCount(0, name.length()) <= 160) {
            return name;
        }
        return new String(name.codePoints().limit(160).toArray(), 0, 160);
    }

    private StorageLocation requireLocation(UUID locationId) {
        return storageLocationRepository.findById(locationId)
                .orElseThrow(() -> new BusinessException(ErrorCode.NOT_FOUND, "存储位置不存在"));
    }

    /**
     * 系统作用域 scope_id 为 NULL，等值查询无法匹配，必须走 IsNull 变体。
     */
    private boolean isDuplicateLocation(StorageLocation location) {
        if (SYSTEM.equals(location.getScopeType())) {
            return storageLocationRepository.existsByMountKeyAndRelativeRootAndScopeTypeAndScopeIdIsNull(
                    location.getMountKey(),
                    location.getRelativeRoot(),
                    location.getScopeType()
            );
        }
        return storageLocationRepository.existsByMountKeyAndRelativeRootAndScopeTypeAndScopeId(
                location.getMountKey(),
                location.getRelativeRoot(),
                location.getScopeType(),
                location.getScopeId()
        );
    }

    private void validateLocation(StorageLocation location) {
        ensureRuntimeEnabled();
        pathResolver.resolveLocationRoot(location);
    }

    private void ensureRuntimeEnabled() {
        if (!runtimeConfigService.isEnabled()) {
            throw new BusinessException(ErrorCode.DEPENDENCY_UNAVAILABLE, "本地媒体功能未在部署配置或配置中心启用");
        }
    }

    private void applyScope(StorageLocation location, String rawScopeType, UUID scopeId) {
        String scopeType = rawScopeType == null ? "" : rawScopeType.trim().toUpperCase(Locale.ROOT);
        if (SYSTEM.equals(scopeType)) {
            if (scopeId != null) {
                throw new BusinessException(ErrorCode.PARAM_ERROR, "系统级存储位置不能指定作用域 ID");
            }
            location.setScopeType(SYSTEM);
            location.setScopeId(null);
            return;
        }
        if (USER.equals(scopeType) && scopeId != null) {
            location.setScopeType(USER);
            location.setScopeId(scopeId);
            return;
        }
        throw new BusinessException(ErrorCode.PARAM_ERROR, "当前版本仅支持 SYSTEM 或带用户 ID 的 USER 作用域");
    }

    private boolean isInScope(StorageLocation location, UUID userId) {
        return SYSTEM.equals(location.getScopeType())
                || USER.equals(location.getScopeType()) && userId.equals(location.getScopeId());
    }

    private boolean isMountAvailable(LocalMediaStorageProperties.MountProperties mount) {
        if (mount == null || mount.getHostPath() == null || mount.getHostPath().isBlank()) {
            return false;
        }
        try {
            return Files.isDirectory(Path.of(mount.getHostPath()));
        } catch (InvalidPathException exception) {
            return false;
        }
    }

    private String normalizeName(String value) {
        String name = value == null ? "" : value.trim();
        if (name.isBlank()) {
            throw new BusinessException(ErrorCode.PARAM_ERROR, "存储位置名称不能为空");
        }
        return name;
    }

    private String normalizeMountKey(String value) {
        String mountKey = value == null ? "" : value.trim();
        if (mountKey.isBlank() || mountKey.contains("/") || mountKey.contains("\\")) {
            throw new BusinessException(ErrorCode.PARAM_ERROR, "挂载键不合法");
        }
        return mountKey;
    }

    private String normalizeRelativeRoot(String value) {
        String raw = value == null || value.isBlank() ? "." : value.trim();
        if (raw.indexOf('\0') >= 0) {
            throw new BusinessException(ErrorCode.FILE_PATH_INVALID, "存储位置根目录必须是安全的相对路径");
        }
        try {
            Path path = Path.of(raw).normalize();
            if (path.isAbsolute() || path.startsWith("..")) {
                throw new BusinessException(ErrorCode.FILE_PATH_INVALID, "存储位置根目录必须是安全的相对路径");
            }
            String normalized = path.toString().replace('\\', '/');
            return normalized.isBlank() ? "." : normalized;
        } catch (InvalidPathException e) {
            throw new BusinessException(ErrorCode.FILE_PATH_INVALID, "存储位置根目录格式无效");
        }
    }

    private StorageLocationDto toDto(StorageLocation location) {
        return new StorageLocationDto(
                location.getId(),
                location.getName(),
                location.getProviderType(),
                location.getManagementMode(),
                location.getMountKey(),
                location.getRelativeRoot(),
                location.getScopeType(),
                location.getScopeId(),
                location.isEnabled(),
                healthStatus(location),
                properties.getNodeId(),
                location.getCreatedAt(),
                location.getUpdatedAt()
        );
    }

    private StorageLocationDescriptor toDescriptor(StorageLocation location) {
        return new StorageLocationDescriptor(
                location.getId(),
                location.getName(),
                location.getProviderType(),
                location.getMountKey(),
                location.getRelativeRoot(),
                location.getScopeType(),
                location.getScopeId(),
                location.isEnabled(),
                healthStatus(location),
                rootDisplayName(location)
        );
    }

    private String rootDisplayName(StorageLocation location) {
        LocalMediaStorageProperties.MountProperties mount = properties.getMounts().get(location.getMountKey());
        if (mount == null || mount.getHostPath() == null || mount.getHostPath().isBlank()) {
            return location.getName();
        }
        try {
            Path root = Path.of(mount.getHostPath());
            Path relative = Path.of(location.getRelativeRoot() == null ? "." : location.getRelativeRoot());
            Path resolved = ".".equals(relative.toString()) ? root : root.resolve(relative);
            Path fileName = resolved.normalize().getFileName();
            return fileName == null || fileName.toString().isBlank() ? location.getName() : fileName.toString();
        } catch (InvalidPathException exception) {
            return location.getName();
        }
    }

    private String healthStatus(StorageLocation location) {
        if (!runtimeConfigService.isEnabled() || !location.isEnabled()) {
            return "DISABLED";
        }
        return pathResolver.isAvailable(location) ? "AVAILABLE" : "UNAVAILABLE";
    }
}
