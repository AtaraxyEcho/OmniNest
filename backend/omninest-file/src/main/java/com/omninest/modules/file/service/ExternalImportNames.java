package com.omninest.modules.file.service;

import com.omninest.modules.file.domain.SpaceType;
import com.omninest.modules.file.domain.StorageImportTask;
import com.omninest.modules.file.repository.FileNodeRepository;
import java.util.UUID;

/**
 * 外部导入的同名冲突消解。
 *
 * <p>共享空间根目录与个人空间根目录使用不同的唯一索引查询，必须显式分支；
 * 判定条件与 {@code FileManagerService}、{@code FileUploadSessionService} 保持一致。</p>
 *
 * @author OmniNest
 */
final class ExternalImportNames {

    private static final int MAX_COLLISION_ITERATIONS = 1000;
    private static final int MAX_FILE_NAME_LENGTH = 255;

    private ExternalImportNames() {
    }

    /**
     * 在目标目录下解析一个不冲突的文件名，必要时追加序号后缀。
     *
     * @param repository 文件节点仓储
     * @param task 导入任务，仅用于取所有者
     * @param spaceType 目标空间
     * @param parentId 目标父目录，null 表示空间根目录
     * @param requestedName 原始文件名
     * @return 可落库的文件名
     */
    static String resolveAvailable(
            FileNodeRepository repository,
            StorageImportTask task,
            SpaceType spaceType,
            UUID parentId,
            String requestedName
    ) {
        String name = withSuffix(requestedName, "");
        int index = 1;
        while (exists(repository, task, spaceType, parentId, name)) {
            String suffix = index > MAX_COLLISION_ITERATIONS
                    ? " (" + UUID.randomUUID().toString().substring(0, 8) + ")"
                    : " (" + index + ")";
            name = withSuffix(requestedName, suffix);
            if (index > MAX_COLLISION_ITERATIONS) {
                break;
            }
            index++;
        }
        return name;
    }

    /**
     * 在扩展名前插入冲突后缀，并把总分片名截到 file_nodes.name 的 255 字符列宽。
     */
    private static String withSuffix(String requestedName, String suffix) {
        int dotIndex = requestedName.lastIndexOf('.');
        String stem = dotIndex <= 0 ? requestedName : requestedName.substring(0, dotIndex);
        String extension = dotIndex <= 0 ? "" : requestedName.substring(dotIndex);
        int stemLimit = Math.max(1, MAX_FILE_NAME_LENGTH - suffix.length() - extension.length());
        if (stem.length() > stemLimit) {
            stem = stem.substring(0, stemLimit);
        }
        return stem + suffix + extension;
    }

    private static boolean exists(
            FileNodeRepository repository,
            StorageImportTask task,
            SpaceType spaceType,
            UUID parentId,
            String name
    ) {
        if (spaceType == SpaceType.SHARED) {
            if (parentId == null) {
                return repository.existsBySpaceTypeAndParentIdIsNullAndNameAndDeletedFalse(
                        SpaceType.SHARED,
                        name
                );
            }
            return repository.existsBySpaceTypeAndParentIdAndNameAndDeletedFalse(
                    SpaceType.SHARED,
                    parentId,
                    name
            );
        }
        if (parentId == null) {
            return repository.existsByOwnerUserIdAndSpaceTypeAndParentIdIsNullAndNameAndDeletedFalse(
                    task.getOwnerUserId(),
                    SpaceType.PERSONAL,
                    name
            );
        }
        return repository.existsByOwnerUserIdAndSpaceTypeAndParentIdAndNameAndDeletedFalse(
                task.getOwnerUserId(),
                SpaceType.PERSONAL,
                parentId,
                name
        );
    }
}
