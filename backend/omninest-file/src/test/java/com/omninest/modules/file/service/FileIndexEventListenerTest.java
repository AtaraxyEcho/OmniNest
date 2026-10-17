package com.omninest.modules.file.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import com.omninest.modules.file.domain.FileNode;
import com.omninest.modules.file.event.FileNodesRestoredEvent;
import com.omninest.modules.file.repository.FileNodeRepository;
import com.omninest.modules.search.service.FileSearchIndexService;
import java.lang.reflect.Method;
import java.time.Instant;
import java.util.List;
import java.util.UUID;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;
import org.springframework.context.event.EventListener;
import org.springframework.transaction.annotation.Propagation;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.transaction.event.TransactionPhase;
import org.springframework.transaction.event.TransactionalEventListener;

class FileIndexEventListenerTest {

    private final FileSearchIndexService indexService = mock(FileSearchIndexService.class);
    private final FileNodeRepository fileNodeRepository = mock(FileNodeRepository.class);
    private final FileIndexEventListener listener =
            new FileIndexEventListener(indexService, fileNodeRepository);

    @Test
    @DisplayName("索引重建只能在恢复事务提交后触发，并自带只读新事务")
    void rebuildIsBoundToAfterCommitPhase() throws Exception {
        Method method = FileIndexEventListener.class.getMethod(
                "handleFileNodesRestored", FileNodesRestoredEvent.class);

        assertThat(method.getAnnotation(EventListener.class))
                .as("同步 @EventListener 会在提交前写 Lucene，回滚留下幽灵文档")
                .isNull();
        TransactionalEventListener annotation = method.getAnnotation(TransactionalEventListener.class);
        assertThat(annotation).isNotNull();
        assertThat(annotation.phase()).isEqualTo(TransactionPhase.AFTER_COMMIT);

        Transactional transactional = method.getAnnotation(Transactional.class);
        assertThat(transactional).isNotNull();
        assertThat(transactional.propagation()).isEqualTo(Propagation.REQUIRES_NEW);
        assertThat(transactional.readOnly()).isTrue();
    }

    @Test
    @DisplayName("只索引未删除节点，且不带正文以免覆盖已抽取内容")
    void rebuildSkipsDeletedNodesAndCarriesNoContent() {
        UUID ownerUserId = UUID.randomUUID();
        FileNode alive = restoredNode("报告.docx", false);
        FileNode deleted = restoredNode("废纸.txt", true);
        when(fileNodeRepository.findAllById(List.of(alive.getId(), deleted.getId())))
                .thenReturn(List.of(alive, deleted));

        listener.handleFileNodesRestored(
                new FileNodesRestoredEvent(ownerUserId, List.of(alive.getId(), deleted.getId()), Instant.now()));

        @SuppressWarnings("unchecked")
        ArgumentCaptor<List<FileSearchIndexService.IndexDocumentInput>> captor =
                ArgumentCaptor.forClass(List.class);
        verify(indexService).indexFiles(eq(ownerUserId), captor.capture());
        List<FileSearchIndexService.IndexDocumentInput> inputs = captor.getValue();
        assertThat(inputs).hasSize(1);
        assertThat(inputs.get(0).fileNodeId()).isEqualTo(alive.getId());
        assertThat(inputs.get(0).title()).isEqualTo("报告.docx");
        assertThat(inputs.get(0).content()).isNull();
        verify(indexService, never()).indexFile(any(), any(), any(), any(), any());
    }

    @Test
    @DisplayName("空事件不触发索引写入")
    void emptyEventDoesNotTouchIndex() {
        listener.handleFileNodesRestored(new FileNodesRestoredEvent(UUID.randomUUID(), List.of(), Instant.now()));

        verify(indexService, never()).indexFiles(any(), any());
    }

    private FileNode restoredNode(String name, boolean deleted) {
        FileNode node = new FileNode();
        node.setId(UUID.randomUUID());
        node.setName(name);
        node.setDeleted(deleted);
        return node;
    }
}
