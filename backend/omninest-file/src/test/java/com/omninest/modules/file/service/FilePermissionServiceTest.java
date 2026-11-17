package com.omninest.modules.file.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;

import com.omninest.modules.file.domain.FileNodePermission;
import com.omninest.modules.file.repository.FileNodePermissionRepository;
import java.util.List;
import java.util.UUID;
import org.junit.jupiter.api.Test;

/**
 * 文件权限服务单元测试。
 *
 * @author OmniNest
 */
class FilePermissionServiceTest {

    private static final UUID USER_ID = UUID.fromString("10000000-0000-0000-0000-000000000001");
    private static final UUID VIEWABLE_FILE_ID = UUID.fromString("20000000-0000-0000-0000-000000000001");
    private static final UUID DENIED_FILE_ID = UUID.fromString("20000000-0000-0000-0000-000000000002");

    private final FileNodePermissionRepository permissionRepository = mock(FileNodePermissionRepository.class);
    private final FilePermissionService service = new FilePermissionService(permissionRepository);

    /**
     * 验证批量权限解析仅返回允许查看的文件标识。
     */
    @Test
    void resolveViewableFileIdsFiltersDeniedPermissions() {
        FileNodePermission viewable = permission(VIEWABLE_FILE_ID, USER_ID, true);
        FileNodePermission denied = permission(DENIED_FILE_ID, null, false);
        List<UUID> fileIds = List.of(VIEWABLE_FILE_ID, DENIED_FILE_ID);
        when(permissionRepository.findByFileIdsAndUserIdOrGlobal(fileIds, USER_ID))
                .thenReturn(List.of(viewable, denied));

        var result = service.resolveViewableFileIds(fileIds, USER_ID);

        assertThat(result).containsExactly(VIEWABLE_FILE_ID);
    }

    private FileNodePermission permission(UUID fileId, UUID granteeUserId, boolean allowView) {
        FileNodePermission permission = new FileNodePermission();
        permission.setFileNodeId(fileId);
        permission.setGranteeUserId(granteeUserId);
        permission.setAllowView(allowView);
        return permission;
    }
}
