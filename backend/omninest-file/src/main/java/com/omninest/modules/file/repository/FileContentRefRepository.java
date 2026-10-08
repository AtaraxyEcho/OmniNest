package com.omninest.modules.file.repository;

import com.omninest.modules.file.domain.FileContentRef;
import java.time.Instant;
import java.util.Collection;
import java.util.List;
import java.util.Optional;
import java.util.UUID;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Modifying;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

/**
 * 外部文件内容引用仓储。
 *
 * @author OmniNest
 */
public interface FileContentRefRepository extends JpaRepository<FileContentRef, UUID> {

    /**
     * 按文件节点查询内容引用。
     *
     * @param fileNodeId 文件节点 ID
     * @return 内容引用
     */
    Optional<FileContentRef> findByFileNodeId(UUID fileNodeId);

    /** 批量读取媒体条目对应的内容可用性，避免列表转换产生 N+1 查询。 */
    List<FileContentRef> findByFileNodeIdIn(Collection<UUID> fileNodeIds);

    /**
     * 按所有者、存储位置和相对路径查询内容引用。
     *
     * @param ownerUserId 所有者用户 ID
     * @param storageLocationId 存储位置 ID
     * @param relativePath 相对路径
     * @return 内容引用
     */
    Optional<FileContentRef> findByOwnerUserIdAndStorageLocationIdAndRelativePath(
            UUID ownerUserId,
            UUID storageLocationId,
            String relativePath
    );

    /**
     * 批量查询一组安全相对路径对应的现有引用。
     */
    List<FileContentRef> findByOwnerUserIdAndStorageLocationIdAndRelativePathIn(
            UUID ownerUserId,
            UUID storageLocationId,
            Collection<String> relativePaths
    );

    /**
     * 查询来源目录下的全部内容引用。
     *
     * @param ownerUserId 所有者用户 ID
     * @param storageLocationId 存储位置 ID
     * @param relativePathPrefix 相对路径前缀
     * @return 内容引用列表
     */
    List<FileContentRef> findByOwnerUserIdAndStorageLocationIdAndRelativePathStartingWith(
            UUID ownerUserId,
            UUID storageLocationId,
            String relativePathPrefix
    );

    /**
     * 批量标记扫描中未发现的内容引用。
     *
     * @param ids 内容引用 ID
     * @param availabilityStatus 可用状态
     * @return 更新数量
     */
    @Modifying(clearAutomatically = true, flushAutomatically = true)
    @Query("update FileContentRef ref set ref.availabilityStatus = :availabilityStatus where ref.id in :ids")
    int updateAvailabilityStatus(
            @Param("ids") Collection<UUID> ids,
            @Param("availabilityStatus") String availabilityStatus
    );

    /**
     * 标记本次完整发现中已确认存在的引用，并清除缺失状态。
     */
    @Modifying(clearAutomatically = true, flushAutomatically = true)
    @Query("""
            update FileContentRef ref
               set ref.lastSeenScanRunId = :scanRunId,
                   ref.lastAvailabilityRunId = :scanRunId,
                   ref.availabilityStatus = 'AVAILABLE',
                   ref.lastSeenAt = :observedAt,
                   ref.missingSince = null,
                   ref.missingConfirmations = 0
             where ref.ownerUserId = :ownerUserId
               and ref.storageLocationId = :storageLocationId
               and ref.relativePath in :relativePaths
            """)
    int markObservedInScan(
            @Param("ownerUserId") UUID ownerUserId,
            @Param("storageLocationId") UUID storageLocationId,
            @Param("scanRunId") UUID scanRunId,
            @Param("observedAt") Instant observedAt,
            @Param("relativePaths") Collection<String> relativePaths
    );

    /** 推进既有待确认缺失引用的连续未发现次数。 */
    @Modifying(clearAutomatically = true, flushAutomatically = true)
    @Query("""
            update FileContentRef ref
               set ref.missingConfirmations = ref.missingConfirmations + 1,
                   ref.lastAvailabilityRunId = :scanRunId
             where ref.ownerUserId = :ownerUserId
               and ref.storageLocationId = :storageLocationId
               and ref.relativePath like concat(:relativePathPrefix, '%') escape '\\'
               and ref.availabilityStatus = 'MISSING_PENDING'
               and (ref.lastSeenScanRunId is null or ref.lastSeenScanRunId <> :scanRunId)
               and (ref.lastAvailabilityRunId is null or ref.lastAvailabilityRunId <> :scanRunId)
            """)
    int advanceMissingPending(
            @Param("ownerUserId") UUID ownerUserId,
            @Param("storageLocationId") UUID storageLocationId,
            @Param("relativePathPrefix") String relativePathPrefix,
            @Param("scanRunId") UUID scanRunId
    );

    /** 将达到确认次数和宽限期的引用确认为缺失。 */
    @Modifying(clearAutomatically = true, flushAutomatically = true)
    @Query("""
            update FileContentRef ref
               set ref.availabilityStatus = 'MISSING'
             where ref.ownerUserId = :ownerUserId
               and ref.storageLocationId = :storageLocationId
               and ref.relativePath like concat(:relativePathPrefix, '%') escape '\\'
               and ref.availabilityStatus = 'MISSING_PENDING'
               and ref.missingConfirmations >= :requiredConfirmations
               and ref.missingSince <= :confirmationBefore
            """)
    int confirmMissing(
            @Param("ownerUserId") UUID ownerUserId,
            @Param("storageLocationId") UUID storageLocationId,
            @Param("relativePathPrefix") String relativePathPrefix,
            @Param("requiredConfirmations") int requiredConfirmations,
            @Param("confirmationBefore") Instant confirmationBefore
    );

    /** 在完整成功发现后把首次未发现的引用置为待确认。 */
    @Modifying(clearAutomatically = true, flushAutomatically = true)
    @Query("""
            update FileContentRef ref
               set ref.availabilityStatus = 'MISSING_PENDING',
                   ref.missingSince = :missingSince,
                   ref.missingConfirmations = 1,
                   ref.lastAvailabilityRunId = :scanRunId
             where ref.ownerUserId = :ownerUserId
               and ref.storageLocationId = :storageLocationId
               and ref.relativePath like concat(:relativePathPrefix, '%') escape '\\'
               and ref.availabilityStatus = 'AVAILABLE'
               and (ref.lastSeenScanRunId is null or ref.lastSeenScanRunId <> :scanRunId)
            """)
    int markMissingPending(
            @Param("ownerUserId") UUID ownerUserId,
            @Param("storageLocationId") UUID storageLocationId,
            @Param("relativePathPrefix") String relativePathPrefix,
            @Param("scanRunId") UUID scanRunId,
            @Param("missingSince") Instant missingSince
    );

    /**
     * 统计本子树内仍处于不可用状态的引用数。
     *
     * <p>由 derived 方法改为显式查询：派生属性的 {@code StartingWith} 生成的 LIKE
     * 无法声明转义符，与本仓储其余三个缺失更新不同口径，会让同一次扫描用两种
     * 前缀语义（详见 {@code LocalMediaAvailabilityService.finishSuccessfulScan}）。</p>
     */
    @Query("""
            select count(ref) from FileContentRef ref
             where ref.ownerUserId = :ownerUserId
               and ref.storageLocationId = :storageLocationId
               and ref.relativePath like concat(:relativePathPrefix, '%') escape '\\'
               and ref.availabilityStatus in :availabilityStatuses
            """)
    long countUnavailableInSubtree(
            @Param("ownerUserId") UUID ownerUserId,
            @Param("storageLocationId") UUID storageLocationId,
            @Param("relativePathPrefix") String relativePathPrefix,
            @Param("availabilityStatuses") Collection<String> availabilityStatuses
    );

    /**
     * 按文件节点批量删除内容引用。
     *
     * @param fileNodeIds 文件节点 ID 集合
     * @return 删除数量
     */
    @Modifying(clearAutomatically = true, flushAutomatically = true)
    @Query("delete from FileContentRef ref where ref.fileNodeId in :fileNodeIds")
    int deleteByFileNodeIdIn(@Param("fileNodeIds") Collection<UUID> fileNodeIds);

    /**
     * 统计存储位置的内容引用数量。
     *
     * @param storageLocationId 存储位置 ID
     * @return 引用数量
     */
    long countByStorageLocationId(UUID storageLocationId);
}
