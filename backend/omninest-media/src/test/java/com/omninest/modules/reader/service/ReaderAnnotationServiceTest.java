package com.omninest.modules.reader.service;

import com.omninest.modules.media.service.MediaSyncEventService;
import com.omninest.modules.reader.domain.ReaderAnnotation;
import com.omninest.modules.reader.dto.ReaderDtos.ReaderAnnotationDto;
import com.omninest.modules.reader.dto.ReaderDtos.UpdateAnnotationRequest;
import com.omninest.modules.reader.repository.ReaderAnnotationRepository;
import java.util.Optional;
import java.util.UUID;
import org.assertj.core.api.Assertions;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mockito;
import org.mockito.junit.jupiter.MockitoExtension;

/**
 * Reader 批注更新测试。
 *
 * <p>覆盖备注的三态语义：缺省不改、空串清空、非空覆盖。
 *
 * @author OmniNest
 */
@ExtendWith(MockitoExtension.class)
class ReaderAnnotationServiceTest {

    private ReaderAnnotationService createService(ReaderAnnotationRepository repository) {
        return new ReaderAnnotationService(
                repository,
                Mockito.mock(MediaSyncEventService.class),
                Mockito.mock(ReaderItemService.class));
    }

    private ReaderAnnotation existingAnnotation(UUID ownerUserId, UUID annotationId) {
        ReaderAnnotation annotation = new ReaderAnnotation();
        annotation.setId(annotationId);
        annotation.setOwnerUserId(ownerUserId);
        annotation.setReaderItemId(UUID.randomUUID());
        annotation.setChapterId("chapter_2");
        annotation.setStartOffset(10);
        annotation.setEndOffset(20);
        annotation.setNote("旧备注");
        annotation.setColor("#FFEB3B");
        return annotation;
    }

    @Test
    void updateAnnotationShouldClearNoteWhenSubmittedBlank() {
        ReaderAnnotationRepository repository = Mockito.mock(ReaderAnnotationRepository.class);
        UUID ownerUserId = UUID.randomUUID();
        UUID annotationId = UUID.randomUUID();
        ReaderAnnotation annotation = existingAnnotation(ownerUserId, annotationId);
        Mockito.when(repository.findById(annotationId)).thenReturn(Optional.of(annotation));
        Mockito.when(repository.save(annotation)).thenReturn(annotation);

        ReaderAnnotationDto result = createService(repository).updateAnnotation(
                ownerUserId,
                annotationId,
                new UpdateAnnotationRequest("   ", "#2196F3"));

        Assertions.assertThat(result.note()).isNull();
        Assertions.assertThat(result.color()).isEqualTo("#2196F3");
    }

    @Test
    void updateAnnotationShouldKeepNoteWhenAbsent() {
        ReaderAnnotationRepository repository = Mockito.mock(ReaderAnnotationRepository.class);
        UUID ownerUserId = UUID.randomUUID();
        UUID annotationId = UUID.randomUUID();
        ReaderAnnotation annotation = existingAnnotation(ownerUserId, annotationId);
        Mockito.when(repository.findById(annotationId)).thenReturn(Optional.of(annotation));
        Mockito.when(repository.save(annotation)).thenReturn(annotation);

        ReaderAnnotationDto result = createService(repository).updateAnnotation(
                ownerUserId,
                annotationId,
                new UpdateAnnotationRequest(null, null));

        Assertions.assertThat(result.note()).isEqualTo("旧备注");
        Assertions.assertThat(result.color()).isEqualTo("#FFEB3B");
    }

    @Test
    void updateAnnotationShouldReplaceNoteWhenSubmitted() {
        ReaderAnnotationRepository repository = Mockito.mock(ReaderAnnotationRepository.class);
        UUID ownerUserId = UUID.randomUUID();
        UUID annotationId = UUID.randomUUID();
        ReaderAnnotation annotation = existingAnnotation(ownerUserId, annotationId);
        Mockito.when(repository.findById(annotationId)).thenReturn(Optional.of(annotation));
        Mockito.when(repository.save(annotation)).thenReturn(annotation);

        ReaderAnnotationDto result = createService(repository).updateAnnotation(
                ownerUserId,
                annotationId,
                new UpdateAnnotationRequest("新备注", null));

        Assertions.assertThat(result.note()).isEqualTo("新备注");
        Assertions.assertThat(result.color()).isEqualTo("#FFEB3B");
    }
}
