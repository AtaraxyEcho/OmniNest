package com.omninest.modules.photos.search;

import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.assertj.core.api.Assertions.assertThat;

import java.nio.file.Path;
import java.util.List;
import java.util.UUID;
import org.apache.lucene.analysis.standard.StandardAnalyzer;
import org.apache.lucene.index.IndexWriter;
import org.apache.lucene.index.IndexWriterConfig;
import org.apache.lucene.store.FSDirectory;
import org.apache.lucene.store.LockObtainFailedException;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.io.TempDir;

/**
 * 照片搜索索引服务测试：锁冲突必须作为失败冒泡，不能只留日志。
 *
 * @author OmniNest
 */
class PhotoSearchIndexServiceTest {

    @TempDir
    Path indexDir;

    @Test
    @DisplayName("索引卷被其他写者持有时抛出锁冲突，交由消费侧重试进 DLQ")
    void propagatesWriteLockConflictInsteadOfSwallowingIt() throws Exception {
        IndexWriterConfig config = new IndexWriterConfig(new StandardAnalyzer());
        try (IndexWriter holder = new IndexWriter(FSDirectory.open(indexDir), config);
             PhotoSearchIndexService service = new PhotoSearchIndexService(indexDir.toString())) {
            holder.commit();

            assertThatThrownBy(() -> service.indexPhoto(
                    UUID.randomUUID(), UUID.randomUUID(), "标题", null, List.of("标签")))
                    .isInstanceOf(IllegalStateException.class)
                    .hasCauseInstanceOf(LockObtainFailedException.class);
        }
    }

    @Test
    @DisplayName("独占索引卷时写入与删除正常完成")
    void writesAndDeletesWhenHoldingTheIndexExclusively() throws Exception {
        PhotoSearchIndexService service = new PhotoSearchIndexService(indexDir.toString());
        try {
            UUID photoId = UUID.randomUUID();
            UUID ownerUserId = UUID.randomUUID();
            service.indexPhoto(photoId, ownerUserId, "sunset ridge", "黄昏的海边", List.of("travel"));
            service.indexPhoto(photoId, ownerUserId, "sunset ridge", "黄昏的海边", List.of("travel", "sea"));
            service.deletePhoto(photoId);
            service.deletePhotos(List.of(photoId, UUID.randomUUID()));
        } finally {
            service.close();
        }

        // 写入侧失败已经改为冒泡，正常路径不应留下任何异常。
        assertThat(java.nio.file.Files.exists(indexDir)).isTrue();
    }

}
