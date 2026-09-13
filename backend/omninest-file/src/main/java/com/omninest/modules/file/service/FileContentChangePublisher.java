package com.omninest.modules.file.service;

import com.omninest.modules.file.domain.FileNode;
import com.omninest.modules.file.domain.FileObject;
import com.omninest.modules.file.event.FileUploadedEvent;
import java.time.Instant;
import java.util.UUID;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;

/**
 * 文件当前内容变更后的派生任务发布入口。
 *
 * <p>版本保存与恢复完成后复用与新建上传相同的后处理管线
 * （媒体自动导入、索引、缩略图等），避免缩略图与元数据陈旧。</p>
 *
 * @author OmniNest
 */
@Service
@RequiredArgsConstructor
public class FileContentChangePublisher {

    private final FilePostProcessingTaskService postProcessingTaskService;

    /**
     * 在当前事务内为变更后的文件内容创建后处理任务。
     *
     * @param node 已保存的文件节点
     * @param object 当前内容对象
     * @param ownerUserId 所有者
     * @return 媒体自动导入任务 ID
     */
    public UUID publish(FileNode node, FileObject object, UUID ownerUserId) {
        FileUploadedEvent event = new FileUploadedEvent(
                node.getId(),
                object.getId(),
                ownerUserId,
                object.getBucketName(),
                object.getObjectKey(),
                node.getName(),
                node.getMimeType(),
                node.getSizeBytes(),
                Instant.now()
        );
        UUID mediaAutoImportTaskId = postProcessingTaskService.enqueueMediaAutoImport(event);
        postProcessingTaskService.enqueuePostProcess(event, node.getMimeType());
        return mediaAutoImportTaskId;
    }
}
