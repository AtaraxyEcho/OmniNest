package com.omninest.modules.video.repository;

import com.omninest.modules.task.domain.TaskRecord;
import com.omninest.modules.task.service.TaskRecordService;
import com.omninest.modules.video.dto.MovieDtos.MovieTaskDto;
import java.util.Collection;
import java.util.List;
import java.util.UUID;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Repository;

/**
 * 媒体任务查询适配器。
 *
 * @author OmniNest
 */
@Repository
@RequiredArgsConstructor
public class MediaTaskRepository {
    private static final int DEFAULT_TASK_LIMIT = 100;

    private final TaskRecordService taskRecordService;

    /**
     * 查询媒体任务列表。
     *
     * @param ownerUserId 所属用户 ID
     * @param taskType 任务类型
     * @return 任务 DTO 列表
     */
    public List<MovieTaskDto> listTasks(UUID ownerUserId, String taskType) {
        List<TaskRecord> records = taskRecordService.listTasks(ownerUserId, taskType, DEFAULT_TASK_LIMIT);
        return records.stream().map(this::toDto).toList();
    }

    /**
     * 按任务类型白名单查询影视相关任务。
     *
     * @param ownerUserId 所属用户 ID
     * @param taskTypes 影视任务类型白名单
     * @return 任务 DTO 列表
     */
    public List<MovieTaskDto> listTasksByTypes(UUID ownerUserId, Collection<String> taskTypes) {
        List<TaskRecord> records = taskRecordService.listTasksByTypes(ownerUserId, taskTypes, DEFAULT_TASK_LIMIT);
        return records.stream().map(this::toDto).toList();
    }

    private MovieTaskDto toDto(TaskRecord record) {
        return new MovieTaskDto(
                record.getId(),
                record.getTaskType(),
                record.getStatus(),
                record.getProgress(),
                record.getRoutingKey(),
                record.getErrorMessage(),
                record.getUpdatedAt()
        );
    }
}
