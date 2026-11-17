package com.omninest.modules.file.dto;

import com.omninest.modules.file.service.FileBusinessReference;
import io.swagger.v3.oas.annotations.media.Schema;
import java.util.List;
import java.util.Map;
import java.util.UUID;

/**
 * 文件永久删除影响摘要。
 *
 * @param rootFileNodeId 根文件节点 ID
 * @param fileNodeCount 文件节点数量
 * @param estimatedBytes 预计释放的用户配额字节数
 * @param referenceCount 未被请求来源覆盖的业务引用数量
 * @param referencesByModule 按模块汇总的业务引用数量
 * @param references 业务引用明细
 * @author OmniNest
 */
@Schema(description = "文件永久删除影响摘要")
public record FilePurgeImpactDto(
        UUID rootFileNodeId,
        int fileNodeCount,
        long estimatedBytes,
        int referenceCount,
        Map<String, Integer> referencesByModule,
        List<FileBusinessReference> references
) {
    /**
     * 判断是否仍存在额外业务引用。
     *
     * @return 存在引用时返回 true
     */
    public boolean inUse() {
        return referenceCount > 0;
    }
}
