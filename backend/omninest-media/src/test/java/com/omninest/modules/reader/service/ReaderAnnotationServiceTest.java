package com.omninest.modules.reader.service;

import com.omninest.common.error.BusinessException;
import com.omninest.modules.media.service.MediaSyncEventService;
import com.omninest.modules.reader.domain.ReaderAnnotation;
import com.omninest.modules.reader.dto.ReaderDtos.CreateAnnotationRequest;
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
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.support.TransactionTemplate;

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
                Mockito.mock(ReaderItemService.class),
                new TransactionTemplate(Mockito.mock(PlatformTransactionManager.class)));
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

    /// 倒挂区间会被原样落库：高亮绘制与跳转都按 start<=end 计算长度与定位。
    @Test
    void createAnnotationRejectsReversedOffsets() {
        ReaderAnnotationRepository repository = Mockito.mock(ReaderAnnotationRepository.class);
        UUID ownerUserId = UUID.randomUUID();
        ReaderAnnotationService service = createService(repository);

        Assertions.assertThatThrownBy(() -> service.createAnnotation(
                        ownerUserId,
                        UUID.randomUUID(),
                        new CreateAnnotationRequest(
                                "chapter_1", 40L, 20L, "高亮", null, "#FFEB3B", null)))
                .isInstanceOf(BusinessException.class)
                .hasMessageContaining("批注结束偏移不能小于起始偏移");

        Mockito.verifyNoInteractions(repository);
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
