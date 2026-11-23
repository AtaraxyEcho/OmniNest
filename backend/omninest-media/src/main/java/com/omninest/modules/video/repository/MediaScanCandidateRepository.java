package com.omninest.modules.video.repository;

import com.omninest.modules.video.domain.MediaScanCandidate;
import java.util.Collection;
import java.util.List;
import java.util.Optional;
import java.util.UUID;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Modifying;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

/** 媒体发现候选仓储。 */
public interface MediaScanCandidateRepository extends JpaRepository<MediaScanCandidate, UUID> {

    Optional<MediaScanCandidate> findByIdAndOwnerUserIdAndScanRunId(UUID id, UUID ownerUserId, UUID scanRunId);

    Page<MediaScanCandidate> findByOwnerUserIdAndScanRunIdOrderByGroupTitleAscSeasonNumberAscEpisodeNumberAsc(
            UUID ownerUserId,
            UUID scanRunId,
            Pageable pageable
    );

    @Query("""
            select c from MediaScanCandidate c
             where c.ownerUserId = :ownerUserId
               and c.scanRunId = :scanRunId
               and (
                   :scope = 'ALL'
                   or (:scope = 'PENDING' and c.applyStatus <> 'APPLIED' and c.matchStatus in ('NEW', 'CHANGED'))
                   or (:scope = 'IMPORTED' and (c.applyStatus = 'APPLIED' or c.matchStatus = 'EXISTING'))
                   or (:scope = 'ISSUES' and (c.applyStatus = 'FAILED' or c.matchStatus in ('AMBIGUOUS', 'UNMATCHED')))
               )
             order by c.groupTitle asc, c.seasonNumber asc, c.episodeNumber asc
            """)
    Page<MediaScanCandidate> findScopedCandidates(
            @Param("ownerUserId") UUID ownerUserId,
            @Param("scanRunId") UUID scanRunId,
            @Param("scope") String scope,
            Pageable pageable
    );

    Page<MediaScanCandidate> findByOwnerUserIdAndScanRunIdAndGroupIdAndSeasonNumberOrderByEpisodeNumberAsc(
            UUID ownerUserId,
            UUID scanRunId,
            UUID groupId,
            Integer seasonNumber,
            Pageable pageable
    );

    @Query("""
            select c from MediaScanCandidate c
             where c.ownerUserId = :ownerUserId
               and c.scanRunId = :scanRunId
               and c.groupId = :groupId
               and c.seasonNumber = :seasonNumber
               and (
                   :scope = 'ALL'
                   or (:scope = 'PENDING' and c.applyStatus <> 'APPLIED' and c.matchStatus in ('NEW', 'CHANGED'))
                   or (:scope = 'IMPORTED' and (c.applyStatus = 'APPLIED' or c.matchStatus = 'EXISTING'))
                   or (:scope = 'ISSUES' and (c.applyStatus = 'FAILED' or c.matchStatus in ('AMBIGUOUS', 'UNMATCHED')))
               )
             order by c.episodeNumber asc
            """)
    Page<MediaScanCandidate> findScopedSeasonCandidates(
            @Param("ownerUserId") UUID ownerUserId,
            @Param("scanRunId") UUID scanRunId,
            @Param("groupId") UUID groupId,
            @Param("seasonNumber") Integer seasonNumber,
            @Param("scope") String scope,
            Pageable pageable
    );

    @Query("""
            select c from MediaScanCandidate c
             where c.ownerUserId = :ownerUserId
               and c.scanRunId = :scanRunId
               and c.groupId in :groupIds
               and (
                   :scope = 'ALL'
                   or (:scope = 'PENDING' and c.applyStatus <> 'APPLIED' and c.matchStatus in ('NEW', 'CHANGED'))
                   or (:scope = 'IMPORTED' and (c.applyStatus = 'APPLIED' or c.matchStatus = 'EXISTING'))
                   or (:scope = 'ISSUES' and (c.applyStatus = 'FAILED' or c.matchStatus in ('AMBIGUOUS', 'UNMATCHED')))
               )
             order by c.groupTitle asc, c.relativePath asc
            """)
    List<MediaScanCandidate> findScopedCandidatesByGroupIds(
            @Param("ownerUserId") UUID ownerUserId,
            @Param("scanRunId") UUID scanRunId,
            @Param("groupIds") Collection<UUID> groupIds,
            @Param("scope") String scope
    );

    Page<MediaScanCandidate> findByOwnerUserIdAndScanRunIdAndSelectedTrueAndApplyStatusOrderByRelativePathAsc(
            UUID ownerUserId,
            UUID scanRunId,
            String applyStatus,
            Pageable pageable
    );

    long countByOwnerUserIdAndScanRunId(UUID ownerUserId, UUID scanRunId);

    long countByOwnerUserIdAndScanRunIdAndSelectedTrue(UUID ownerUserId, UUID scanRunId);

    long countByOwnerUserIdAndScanRunIdAndMatchStatus(UUID ownerUserId, UUID scanRunId, String matchStatus);

    long countByOwnerUserIdAndScanRunIdAndApplyStatus(UUID ownerUserId, UUID scanRunId, String applyStatus);

    @Query("""
            select c.relativePath
              from MediaScanCandidate c
             where c.ownerUserId = :ownerUserId
               and c.scanRunId = :scanRunId
               and c.relativePath in :relativePaths
            """)
    List<String> findPersistedRelativePaths(
            @Param("ownerUserId") UUID ownerUserId,
            @Param("scanRunId") UUID scanRunId,
            @Param("relativePaths") Collection<String> relativePaths
    );

    void deleteByOwnerUserIdAndScanRunId(UUID ownerUserId, UUID scanRunId);

    /**
     * 按来源批量删除候选行。
     *
     * <p>派生删除会先把每一行读进持久化上下文再逐条 DELETE；删除整个来源时
     * 候选行数可达数万，必须走 bulk DELETE。</p>
     *
     * @param librarySourceId 影视库来源 ID
     * @return 删除行数
     */
    @Modifying(clearAutomatically = true, flushAutomatically = true)
    @Query("delete from MediaScanCandidate candidate where candidate.librarySourceId = :librarySourceId")
    int deleteByLibrarySourceId(@Param("librarySourceId") UUID librarySourceId);

    @Query(
            value = """
                    select c.groupId as groupId,
                           min(c.groupTitle) as groupTitle,
                           count(c.id) as candidateCount,
                           sum(case when c.selected = true then 1 else 0 end) as selectedCount,
                           sum(case when c.matchStatus in ('AMBIGUOUS', 'UNMATCHED') then 1 else 0 end) as issueCount,
                           sum(case when c.candidateType = 'EPISODE' then 1 else 0 end) as episodeCount
                      from MediaScanCandidate c
                     where c.ownerUserId = :ownerUserId and c.scanRunId = :scanRunId
                     group by c.groupId
                     order by min(c.groupTitle)
                    """,
            countQuery = """
                    select count(distinct c.groupId)
                      from MediaScanCandidate c
                     where c.ownerUserId = :ownerUserId and c.scanRunId = :scanRunId
                    """
    )
    Page<GroupSummary> summarizeGroups(
            @Param("ownerUserId") UUID ownerUserId,
            @Param("scanRunId") UUID scanRunId,
            Pageable pageable
    );

    @Query(
            value = """
                    select c.groupId as groupId,
                           min(c.groupTitle) as groupTitle,
                           count(c.id) as candidateCount,
                           sum(case when c.selected = true then 1 else 0 end) as selectedCount,
                           sum(case when c.matchStatus in ('AMBIGUOUS', 'UNMATCHED') then 1 else 0 end) as issueCount,
                           sum(case when c.candidateType = 'EPISODE' then 1 else 0 end) as episodeCount
                      from MediaScanCandidate c
                     where c.ownerUserId = :ownerUserId
                       and c.scanRunId = :scanRunId
                       and (
                           :scope = 'ALL'
                           or (:scope = 'PENDING' and c.applyStatus <> 'APPLIED' and c.matchStatus in ('NEW', 'CHANGED'))
                           or (:scope = 'IMPORTED' and (c.applyStatus = 'APPLIED' or c.matchStatus = 'EXISTING'))
                           or (:scope = 'ISSUES' and (c.applyStatus = 'FAILED' or c.matchStatus in ('AMBIGUOUS', 'UNMATCHED')))
                       )
                     group by c.groupId
                     order by min(c.groupTitle)
                    """,
            countQuery = """
                    select count(distinct c.groupId)
                      from MediaScanCandidate c
                     where c.ownerUserId = :ownerUserId
                       and c.scanRunId = :scanRunId
                       and (
                           :scope = 'ALL'
                           or (:scope = 'PENDING' and c.applyStatus <> 'APPLIED' and c.matchStatus in ('NEW', 'CHANGED'))
                           or (:scope = 'IMPORTED' and (c.applyStatus = 'APPLIED' or c.matchStatus = 'EXISTING'))
                           or (:scope = 'ISSUES' and (c.applyStatus = 'FAILED' or c.matchStatus in ('AMBIGUOUS', 'UNMATCHED')))
                       )
                    """
    )
    Page<GroupSummary> summarizeGroupsByScope(
            @Param("ownerUserId") UUID ownerUserId,
            @Param("scanRunId") UUID scanRunId,
            @Param("scope") String scope,
            Pageable pageable
    );

    @Query("""
            select c.seasonNumber as seasonNumber,
                   count(c.id) as candidateCount,
                   sum(case when c.selected = true then 1 else 0 end) as selectedCount,
                   sum(case when c.matchStatus in ('AMBIGUOUS', 'UNMATCHED') then 1 else 0 end) as issueCount
              from MediaScanCandidate c
             where c.ownerUserId = :ownerUserId
               and c.scanRunId = :scanRunId
               and c.groupId = :groupId
             group by c.seasonNumber
             order by c.seasonNumber
            """)
    List<SeasonSummary> summarizeSeasons(
            @Param("ownerUserId") UUID ownerUserId,
            @Param("scanRunId") UUID scanRunId,
            @Param("groupId") UUID groupId
    );

    @Query("""
            select c.seasonNumber as seasonNumber,
                   count(c.id) as candidateCount,
                   sum(case when c.selected = true then 1 else 0 end) as selectedCount,
                   sum(case when c.matchStatus in ('AMBIGUOUS', 'UNMATCHED') then 1 else 0 end) as issueCount
              from MediaScanCandidate c
             where c.ownerUserId = :ownerUserId
               and c.scanRunId = :scanRunId
               and c.groupId = :groupId
               and c.seasonNumber is not null
               and (
                   :scope = 'ALL'
                   or (:scope = 'PENDING' and c.applyStatus <> 'APPLIED' and c.matchStatus in ('NEW', 'CHANGED'))
                   or (:scope = 'IMPORTED' and (c.applyStatus = 'APPLIED' or c.matchStatus = 'EXISTING'))
                   or (:scope = 'ISSUES' and (c.applyStatus = 'FAILED' or c.matchStatus in ('AMBIGUOUS', 'UNMATCHED')))
               )
             group by c.seasonNumber
             order by c.seasonNumber
            """)
    List<SeasonSummary> summarizeSeasonsByScope(
            @Param("ownerUserId") UUID ownerUserId,
            @Param("scanRunId") UUID scanRunId,
            @Param("groupId") UUID groupId,
            @Param("scope") String scope
    );

    @Modifying(clearAutomatically = true, flushAutomatically = true)
    @Query("""
            update MediaScanCandidate c
               set c.selected = :selected
             where c.ownerUserId = :ownerUserId
               and c.scanRunId = :scanRunId
               and (:selected = false or (c.applyStatus <> 'APPLIED' and c.matchStatus in ('NEW', 'CHANGED')))
            """)
    int updateSelectionForRun(
            @Param("ownerUserId") UUID ownerUserId,
            @Param("scanRunId") UUID scanRunId,
            @Param("selected") boolean selected
    );

    @Modifying(clearAutomatically = true, flushAutomatically = true)
    @Query("""
            update MediaScanCandidate c
               set c.selected = :selected
             where c.ownerUserId = :ownerUserId
               and c.scanRunId = :scanRunId
               and c.groupId = :groupId
               and (:selected = false or (c.applyStatus <> 'APPLIED' and c.matchStatus in ('NEW', 'CHANGED')))
            """)
    int updateSelectionForGroup(
            @Param("ownerUserId") UUID ownerUserId,
            @Param("scanRunId") UUID scanRunId,
            @Param("groupId") UUID groupId,
            @Param("selected") boolean selected
    );

    @Modifying(clearAutomatically = true, flushAutomatically = true)
    @Query("""
            update MediaScanCandidate c
               set c.selected = :selected
             where c.ownerUserId = :ownerUserId
               and c.scanRunId = :scanRunId
               and c.groupId = :groupId
               and c.seasonNumber = :seasonNumber
               and (:selected = false or (c.applyStatus <> 'APPLIED' and c.matchStatus in ('NEW', 'CHANGED')))
            """)
    int updateSelectionForSeason(
            @Param("ownerUserId") UUID ownerUserId,
            @Param("scanRunId") UUID scanRunId,
            @Param("groupId") UUID groupId,
            @Param("seasonNumber") Integer seasonNumber,
            @Param("selected") boolean selected
    );

    @Modifying(clearAutomatically = true, flushAutomatically = true)
    @Query("""
            update MediaScanCandidate c
               set c.selected = :selected
             where c.ownerUserId = :ownerUserId
               and c.scanRunId = :scanRunId
               and c.id = :candidateId
            """)
    int updateSelectionForCandidate(
            @Param("ownerUserId") UUID ownerUserId,
            @Param("scanRunId") UUID scanRunId,
            @Param("candidateId") UUID candidateId,
            @Param("selected") boolean selected
    );

    /** 将进程异常中断时遗留的处理中候选恢复为可重试状态。 */
    @Modifying(clearAutomatically = true, flushAutomatically = true)
    @Query("""
            update MediaScanCandidate c
               set c.applyStatus = 'PENDING'
             where c.ownerUserId = :ownerUserId
               and c.scanRunId = :scanRunId
               and c.applyStatus = 'APPLYING'
            """)
    int resetInterruptedCandidates(
            @Param("ownerUserId") UUID ownerUserId,
            @Param("scanRunId") UUID scanRunId
    );

    /** 用户从部分失败状态重试时，仅恢复仍被选中的失败候选。 */
    @Modifying(clearAutomatically = true, flushAutomatically = true)
    @Query("""
            update MediaScanCandidate c
               set c.applyStatus = 'PENDING',
                   c.errorSummary = null
             where c.ownerUserId = :ownerUserId
               and c.scanRunId = :scanRunId
               and c.selected = true
               and c.applyStatus = 'FAILED'
            """)
    int resetSelectedFailures(
            @Param("ownerUserId") UUID ownerUserId,
            @Param("scanRunId") UUID scanRunId
    );

    /** 按系列聚合的树节点投影。 */
    interface GroupSummary {
        UUID getGroupId();

        String getGroupTitle();

        long getCandidateCount();

        long getSelectedCount();

        long getIssueCount();

        default long getEpisodeCount() {
            return getCandidateCount();
        }
    }

    /** 按季度聚合的树节点投影。 */
    interface SeasonSummary {
        Integer getSeasonNumber();

        long getCandidateCount();

        long getSelectedCount();

        long getIssueCount();
    }
}
