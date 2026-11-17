package com.omninest.modules.file.service;

import com.omninest.modules.file.repository.FileObjectRepository;
import java.util.Collection;
import java.util.Set;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * 基于文件对象元数据实现对象存储引用查询。
 *
 * @author OmniNest
 */
@Service
@RequiredArgsConstructor
public class FileObjectReferenceQueryService implements FileObjectReferenceQuery {

    private final FileObjectRepository fileObjectRepository;

    /**
     * 查询候选对象键中已有文件元数据引用的键。
     *
     * @param bucketName 存储桶名称
     * @param objectKeys 候选对象键
     * @return 已引用对象键
     */
    @Override
    @Transactional(readOnly = true)
    public Set<String> findReferencedObjectKeys(String bucketName, Collection<String> objectKeys) {
        if (objectKeys == null || objectKeys.isEmpty()) {
            return Set.of();
        }
        return Set.copyOf(fileObjectRepository.findReferencedObjectKeys(bucketName, objectKeys));
    }
}
