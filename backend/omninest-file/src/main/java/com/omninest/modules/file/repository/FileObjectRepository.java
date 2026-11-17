package com.omninest.modules.file.repository;

import com.omninest.modules.file.domain.FileObject;
import java.util.Collection;
import java.util.List;
import java.util.Optional;
import java.util.UUID;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

/**
 * 文件对象元数据仓储。
 *
 * @author OmniNest
 */
public interface FileObjectRepository extends JpaRepository<FileObject, UUID> {

    /**
     * 按存储桶和对象键查询文件对象。
     *
     * @param bucketName 存储桶名称
     * @param objectKey 对象键
     * @return 文件对象
     */
    Optional<FileObject> findByBucketNameAndObjectKey(String bucketName, String objectKey);

    /**
     * 查询候选对象键中已有文件元数据引用的键。
     *
     * @param bucketName 存储桶名称
     * @param objectKeys 候选对象键
     * @return 已引用对象键
     */
    @Query("""
            select fileObject.objectKey
            from FileObject fileObject
            where fileObject.bucketName = :bucketName
              and fileObject.objectKey in :objectKeys
            """)
    List<String> findReferencedObjectKeys(
            @Param("bucketName") String bucketName,
            @Param("objectKeys") Collection<String> objectKeys
    );
}
