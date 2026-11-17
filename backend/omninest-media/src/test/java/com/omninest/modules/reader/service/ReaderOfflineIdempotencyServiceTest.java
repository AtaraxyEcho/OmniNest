package com.omninest.modules.reader.service;

import com.omninest.modules.media.service.MediaSyncEventService;
import com.omninest.modules.reader.domain.ReaderAnnotation;
import com.omninest.modules.reader.domain.ReaderBookmark;
import com.omninest.modules.reader.domain.ReaderNote;
import com.omninest.modules.reader.dto.ReaderDtos.CreateAnnotationRequest;
import com.omninest.modules.reader.dto.ReaderDtos.CreateBookmarkRequest;
import com.omninest.modules.reader.dto.ReaderDtos.CreateNoteRequest;
import com.omninest.modules.reader.dto.ReaderDtos.ReaderAnnotationDto;
import com.omninest.modules.reader.dto.ReaderDtos.ReaderBookmarkDto;
import com.omninest.modules.reader.dto.ReaderDtos.ReaderNoteDto;
import com.omninest.modules.reader.repository.ReaderAnnotationRepository;
import com.omninest.modules.reader.repository.ReaderBookmarkRepository;
import com.omninest.modules.reader.repository.ReaderNoteRepository;
import java.math.BigDecimal;
import java.time.Instant;
import java.util.Optional;
import java.util.UUID;
import org.assertj.core.api.Assertions;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.ArgumentCaptor;
import org.mockito.Mockito;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.TransactionDefinition;
import org.springframework.transaction.support.TransactionTemplate;

/**
 * Reader 离线创建幂等测试。
 *
 * @author OmniNest
 */
@ExtendWith(MockitoExtension.class)
class ReaderOfflineIdempotencyServiceTest {

    @Test
    void createBookmarkShouldReturnExistingWhenClientOperationIdExists() {
        ReaderBookmarkRepository repository = Mockito.mock(ReaderBookmarkRepository.class);
        MediaSyncEventService syncEventService = Mockito.mock(MediaSyncEventService.class);
        ReaderBookmarkService service = new ReaderBookmarkService(
                repository, syncEventService, Mockito.mock(ReaderItemService.class), newTransactionTemplate());
        UUID ownerUserId = UUID.randomUUID();
        UUID readerItemId = UUID.randomUUID();
        ReaderBookmark existing = buildBookmark(ownerUserId, readerItemId);

        Mockito.when(repository.findByOwnerUserIdAndReaderItemIdAndClientOperationId(
                ownerUserId,
                readerItemId,
                "local-1"
        )).thenReturn(Optional.of(existing));

        CreateBookmarkRequest request = new CreateBookmarkRequest(
                "chapter_3",
                120L,
                BigDecimal.valueOf(0.12),
                "note",
                " local-1 "
        );
        ReaderBookmarkDto result = service.createBookmark(ownerUserId, readerItemId, request);

        Assertions.assertThat(result.id()).isEqualTo(existing.getId());
        Mockito.verify(repository, Mockito.never()).saveAndFlush(Mockito.any(ReaderBookmark.class));
    }

    @Test
    void createAnnotationShouldReturnExistingWhenClientOperationIdExists() {
        ReaderAnnotationRepository repository = Mockito.mock(ReaderAnnotationRepository.class);
        MediaSyncEventService syncEventService = Mockito.mock(MediaSyncEventService.class);
        ReaderAnnotationService service = new ReaderAnnotationService(
                repository, syncEventService, Mockito.mock(ReaderItemService.class), newTransactionTemplate());
        UUID ownerUserId = UUID.randomUUID();
        UUID readerItemId = UUID.randomUUID();
        ReaderAnnotation existing = buildAnnotation(ownerUserId, readerItemId);

        Mockito.when(repository.findByOwnerUserIdAndReaderItemIdAndClientOperationId(
                ownerUserId,
                readerItemId,
                "local-2"
        )).thenReturn(Optional.of(existing));

        CreateAnnotationRequest request = new CreateAnnotationRequest(
                "chapter_1",
                10L,
                20L,
                "highlight",
                "note",
                "#FFEB3B",
                "local-2"
        );
        ReaderAnnotationDto result = service.createAnnotation(ownerUserId, readerItemId, request);

        Assertions.assertThat(result.id()).isEqualTo(existing.getId());
        Mockito.verify(repository, Mockito.never()).saveAndFlush(Mockito.any(ReaderAnnotation.class));
    }

    @Test
    void createAnnotationShouldPersistNormalizedChapterId() {
        ReaderAnnotationRepository repository = Mockito.mock(ReaderAnnotationRepository.class);
        MediaSyncEventService syncEventService = Mockito.mock(MediaSyncEventService.class);
        ReaderAnnotationService service = new ReaderAnnotationService(
                repository, syncEventService, Mockito.mock(ReaderItemService.class), newTransactionTemplate());
        UUID ownerUserId = UUID.randomUUID();
        UUID readerItemId = UUID.randomUUID();
        Mockito.when(repository.saveAndFlush(Mockito.any(ReaderAnnotation.class))).thenAnswer(invocation -> {
            ReaderAnnotation annotation = invocation.getArgument(0);
            annotation.setId(UUID.randomUUID());
            annotation.setCreatedAt(Instant.now());
            annotation.setUpdatedAt(Instant.now());
            return annotation;
        });

        CreateAnnotationRequest request = new CreateAnnotationRequest(
                " chapter_3 ",
                10L,
                20L,
                "highlight",
                "note",
                "#FFEB3B",
                null
        );

        ReaderAnnotationDto result = service.createAnnotation(ownerUserId, readerItemId, request);

        Assertions.assertThat(result.chapterId()).isEqualTo("chapter_3");
        Mockito.verify(repository).saveAndFlush(Mockito.argThat(
                annotation -> "chapter_3".equals(annotation.getChapterId())
        ));
    }

    @Test
    void createNoteShouldReturnExistingWhenClientOperationIdExists() {
        ReaderNoteRepository repository = Mockito.mock(ReaderNoteRepository.class);
        MediaSyncEventService syncEventService = Mockito.mock(MediaSyncEventService.class);
        ReaderNoteService service = new ReaderNoteService(
                repository, syncEventService, Mockito.mock(ReaderItemService.class), newTransactionTemplate());
        UUID ownerUserId = UUID.randomUUID();
        UUID readerItemId = UUID.randomUUID();
        ReaderNote existing = buildNote(ownerUserId, readerItemId);

        Mockito.when(repository.findByOwnerUserIdAndReaderItemIdAndClientOperationId(
                ownerUserId,
                readerItemId,
                "local-3"
        )).thenReturn(Optional.of(existing));

        CreateNoteRequest request = new CreateNoteRequest(30L, "title", "content", "local-3");
        ReaderNoteDto result = service.createNote(ownerUserId, readerItemId, request);

        Assertions.assertThat(result.id()).isEqualTo(existing.getId());
        Mockito.verify(repository, Mockito.never()).saveAndFlush(Mockito.any(ReaderNote.class));
    }

    @Test
    void createBookmarkPersistsChapterIdentityAndValidatesItemAccess() {
        ReaderBookmarkRepository repository = Mockito.mock(ReaderBookmarkRepository.class);
        MediaSyncEventService syncEventService = Mockito.mock(MediaSyncEventService.class);
        ReaderItemService itemService = Mockito.mock(ReaderItemService.class);
        ReaderBookmarkService service = new ReaderBookmarkService(
                repository, syncEventService, itemService, newTransactionTemplate());
        UUID ownerUserId = UUID.randomUUID();
        UUID readerItemId = UUID.randomUUID();
        Mockito.when(repository.saveAndFlush(Mockito.any(ReaderBookmark.class))).thenAnswer(invocation -> {
            ReaderBookmark bookmark = invocation.getArgument(0);
            bookmark.setId(UUID.randomUUID());
            bookmark.setCreatedAt(Instant.now());
            return bookmark;
        });

        CreateBookmarkRequest request = new CreateBookmarkRequest(
                "t1280",
                24L,
                BigDecimal.valueOf(0.2),
                null,
                null
        );
        ReaderBookmarkDto result = service.createBookmark(ownerUserId, readerItemId, request);

        // 客户端偏移是章节内的，没有 chapterId 就无法从详情页跳回原位
        Assertions.assertThat(result.chapterId()).isEqualTo("t1280");
        Mockito.verify(repository).saveAndFlush(Mockito.argThat(
                bookmark -> "t1280".equals(bookmark.getChapterId())
        ));
        Mockito.verify(itemService).requireItem(ownerUserId, readerItemId);
    }

    /**
     * 唯一键冲突的写入必须开在自己的事务里：PostgreSQL 命中约束后当前事务即进入 aborted 态，
     * 同一事务内的幂等回查会二次报错，把本该返回已有记录的分支变成 500。
     */
    @Test
    void createBookmarkConflictWriteRunsInSeparateTransactionAndReturnsExistingRecord() {
        ReaderBookmarkRepository repository = Mockito.mock(ReaderBookmarkRepository.class);
        MediaSyncEventService syncEventService = Mockito.mock(MediaSyncEventService.class);
        PlatformTransactionManager transactionManager = Mockito.mock(PlatformTransactionManager.class);
        ReaderBookmarkService service = new ReaderBookmarkService(
                repository,
                syncEventService,
                Mockito.mock(ReaderItemService.class),
                new TransactionTemplate(transactionManager)
        );
        UUID ownerUserId = UUID.randomUUID();
        UUID readerItemId = UUID.randomUUID();
        ReaderBookmark existing = buildBookmark(ownerUserId, readerItemId);
        Mockito.when(repository.saveAndFlush(Mockito.any(ReaderBookmark.class)))
                .thenThrow(new DataIntegrityViolationException("uniq_reader_bookmark_client_operation"));
        // 首次预查为空，写入撞唯一键后再回查才见到并发抢先落库的那一行
        Mockito.when(repository.findByOwnerUserIdAndReaderItemIdAndClientOperationId(
                ownerUserId,
                readerItemId,
                "local-1"
        )).thenReturn(Optional.empty()).thenReturn(Optional.of(existing));

        CreateBookmarkRequest request = new CreateBookmarkRequest(
                "chapter_3",
                120L,
                BigDecimal.valueOf(0.12),
                "note",
                "local-1"
        );
        ReaderBookmarkDto result = service.createBookmark(ownerUserId, readerItemId, request);

        Assertions.assertThat(result.id()).isEqualTo(existing.getId());
        ArgumentCaptor<TransactionDefinition> definition = ArgumentCaptor.forClass(TransactionDefinition.class);
        Mockito.verify(transactionManager).getTransaction(definition.capture());
        Assertions.assertThat(definition.getValue().getPropagationBehavior())
                .isEqualTo(TransactionDefinition.PROPAGATION_REQUIRES_NEW);
        Mockito.verify(transactionManager).rollback(Mockito.isNull());
        Mockito.verifyNoInteractions(syncEventService);
    }

    /**
     * 批注与笔记走同一套冲突隔离，逐条锁住避免只修书签。
     */
    @Test
    void createAnnotationConflictWriteRunsInSeparateTransactionAndReturnsExistingRecord() {
        UUID ownerUserId = UUID.randomUUID();
        UUID readerItemId = UUID.randomUUID();
        PlatformTransactionManager transactionManager = Mockito.mock(PlatformTransactionManager.class);
        ReaderAnnotationRepository annotationRepository = Mockito.mock(ReaderAnnotationRepository.class);
        ReaderAnnotationService annotationService = new ReaderAnnotationService(
                annotationRepository,
                Mockito.mock(MediaSyncEventService.class),
                Mockito.mock(ReaderItemService.class),
                new TransactionTemplate(transactionManager)
        );
        ReaderAnnotation existing = buildAnnotation(ownerUserId, readerItemId);
        Mockito.when(annotationRepository.saveAndFlush(Mockito.any(ReaderAnnotation.class)))
                .thenThrow(new DataIntegrityViolationException("conflict"));
        Mockito.when(annotationRepository.findByOwnerUserIdAndReaderItemIdAndClientOperationId(
                        ownerUserId, readerItemId, "local-2"))
                .thenReturn(Optional.empty()).thenReturn(Optional.of(existing));

        ReaderAnnotationDto result = annotationService.createAnnotation(ownerUserId, readerItemId,
                new CreateAnnotationRequest("chapter_1", 10L, 20L, "highlight", "note", "#FFEB3B", "local-2"));

        Assertions.assertThat(result.id()).isEqualTo(existing.getId());
        ArgumentCaptor<TransactionDefinition> definition = ArgumentCaptor.forClass(TransactionDefinition.class);
        Mockito.verify(transactionManager).getTransaction(definition.capture());
        Assertions.assertThat(definition.getValue().getPropagationBehavior())
                .isEqualTo(TransactionDefinition.PROPAGATION_REQUIRES_NEW);
    }

    @Test
    void createNoteConflictWriteRunsInSeparateTransactionAndReturnsExistingRecord() {
        UUID ownerUserId = UUID.randomUUID();
        UUID readerItemId = UUID.randomUUID();
        PlatformTransactionManager transactionManager = Mockito.mock(PlatformTransactionManager.class);
        ReaderNoteRepository noteRepository = Mockito.mock(ReaderNoteRepository.class);
        ReaderNoteService noteService = new ReaderNoteService(
                noteRepository,
                Mockito.mock(MediaSyncEventService.class),
                Mockito.mock(ReaderItemService.class),
                new TransactionTemplate(transactionManager)
        );
        ReaderNote existing = buildNote(ownerUserId, readerItemId);
        Mockito.when(noteRepository.saveAndFlush(Mockito.any(ReaderNote.class)))
                .thenThrow(new DataIntegrityViolationException("conflict"));
        Mockito.when(noteRepository.findByOwnerUserIdAndReaderItemIdAndClientOperationId(
                        ownerUserId, readerItemId, "local-3"))
                .thenReturn(Optional.empty()).thenReturn(Optional.of(existing));

        ReaderNoteDto result = noteService.createNote(ownerUserId, readerItemId,
                new CreateNoteRequest(30L, "title", "content", "local-3"));

        Assertions.assertThat(result.id()).isEqualTo(existing.getId());
        ArgumentCaptor<TransactionDefinition> definition = ArgumentCaptor.forClass(TransactionDefinition.class);
        Mockito.verify(transactionManager).getTransaction(definition.capture());
        Assertions.assertThat(definition.getValue().getPropagationBehavior())
                .isEqualTo(TransactionDefinition.PROPAGATION_REQUIRES_NEW);
    }

    private TransactionTemplate newTransactionTemplate() {
        return new TransactionTemplate(Mockito.mock(PlatformTransactionManager.class));
    }

    /**
     * 构造书签实体。
     */
    private ReaderBookmark buildBookmark(UUID ownerUserId, UUID readerItemId) {
        ReaderBookmark bookmark = new ReaderBookmark();
        bookmark.setId(UUID.randomUUID());
        bookmark.setOwnerUserId(ownerUserId);
        bookmark.setReaderItemId(readerItemId);
        bookmark.setClientOperationId("local-1");
        bookmark.setCharOffset(120L);
        bookmark.setProgressPercent(BigDecimal.valueOf(0.12));
        bookmark.setNote("note");
        bookmark.setCreatedAt(Instant.now());
        return bookmark;
    }

    /**
     * 构造批注实体。
     */
    private ReaderAnnotation buildAnnotation(UUID ownerUserId, UUID readerItemId) {
        ReaderAnnotation annotation = new ReaderAnnotation();
        annotation.setId(UUID.randomUUID());
        annotation.setOwnerUserId(ownerUserId);
        annotation.setReaderItemId(readerItemId);
        annotation.setClientOperationId("local-2");
        annotation.setStartOffset(10L);
        annotation.setEndOffset(20L);
        annotation.setHighlightText("highlight");
        annotation.setNote("note");
        annotation.setColor("#FFEB3B");
        annotation.setCreatedAt(Instant.now());
        annotation.setUpdatedAt(Instant.now());
        return annotation;
    }

    /**
     * 构造笔记实体。
     */
    private ReaderNote buildNote(UUID ownerUserId, UUID readerItemId) {
        ReaderNote note = new ReaderNote();
        note.setId(UUID.randomUUID());
        note.setOwnerUserId(ownerUserId);
        note.setReaderItemId(readerItemId);
        note.setClientOperationId("local-3");
        note.setCharOffset(30L);
        note.setTitle("title");
        note.setContent("content");
        note.setCreatedAt(Instant.now());
        note.setUpdatedAt(Instant.now());
        return note;
    }
}
