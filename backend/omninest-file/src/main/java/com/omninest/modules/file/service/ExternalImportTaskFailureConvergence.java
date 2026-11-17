package com.omninest.modules.file.service;

import com.omninest.common.task.DomainTaskFailureConvergence;
import java.util.UUID;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;

/**
 * 外部存储导入进入死信时把 {@code storage_import_tasks} 收敛为 FAILED 并结算配额。
 *
 * @author OmniNest
 */
@Service
@RequiredArgsConstructor
public class ExternalImportTaskFailureConvergence implements DomainTaskFailureConvergence {

    private static final String EXTERNAL_IMPORT = "EXTERNAL_IMPORT";

    private final ExternalImportTaskStatusService taskStatusService;

    @Override
    public boolean supports(String taskType) {
        return EXTERNAL_IMPORT.equals(taskType);
    }

    @Override
    public void converge(UUID taskId, String reason) {
        taskStatusService.markFailed(taskId, reason);
    }
}
