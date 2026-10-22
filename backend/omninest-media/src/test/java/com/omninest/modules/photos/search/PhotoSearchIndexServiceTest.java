package com.omninest.modules.photos.search;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import com.omninest.modules.photos.search.PhotoSearchIndexService.PhotoIndexDocument;
import java.nio.file.Path;
import java.util.List;
import java.util.UUID;
import org.apache.lucene.analysis.cn.smart.SmartChineseAnalyzer;
import org.apache.lucene.index.IndexWriter;
import org.apache.lucene.index.IndexWriterConfig;
import org.apache.lucene.store.FSDirectory;
import org.apache.lucene.store.LockObtainFailedException;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.io.TempDir;

/**
 * 照片搜索索引服务测试：锁冲突、多租户隔离与中文词元检索。
 *
 * @author OmniNest
 */
class PhotoSearchIndexServiceTest {

    @TempDir
    Path indexDir;

    @Test
    @DisplayName("索引卷被其他写者持有时抛出锁冲突，交由消费侧重试进 DLQ")
    void propagatesWriteLockConflictInsteadOfSwallowingIt() throws Exception {
        IndexWriterConfig config = new IndexWriterConfig(new SmartChineseAnalyzer());
        try (IndexWriter holder = new IndexWriter(FSDirectory.open(indexDir), config);
             PhotoSearchIndexService service = new PhotoSearchIndexService(indexDir.toString())) {
            holder.commit();

            assertThatThrownBy(() -> service.indexPhoto(document(
                    UUID.randomUUID(), UUID.randomUUID(), "标题", null, List.of("标签"), List.of(), null)))
                    .isInstanceOf(IllegalStateException.class)
                    .hasCauseInstanceOf(LockObtainFailedException.class);
        }
    }

    @Test
    @DisplayName("只读实例能读到另一个写者提交的段（API 读、Worker 写同一卷）")
    void readOnlyInstanceSeesCommitsFromAnotherWriter() throws Exception {
        UUID photoId = UUID.randomUUID();
        UUID ownerUserId = UUID.randomUUID();
        try (PhotoSearchIndexService writer = new PhotoSearchIndexService(indexDir.toString());
             PhotoSearchIndexService readerSide = new PhotoSearchIndexService(indexDir.toString())) {
            // 写侧打开 IndexWriter 并提交，读侧实例从未写过，只能靠重新打开目录读到新段。
            writer.indexPhoto(document(photoId, ownerUserId, "sunset", "sunset", List.of("sunset"), List.of(), null));
            // 同一照片重复索引必须替换文档，不能累积成多份命中。
            writer.indexPhoto(document(
                    photoId, ownerUserId, "sunset", "sunset", List.of("sunset", "sea"), List.of(), null));
            assertThat(writer.search(ownerUserId, "sunset", 10)).as("写侧自身可读且未重复").containsExactly(photoId);
            assertThat(readerSide.search(ownerUserId, "sunset", 10)).as("只读实例可见").containsExactly(photoId);

            // 只有写者能提交删除；只读实例随后必须看到删除后的空结果。
            writer.deletePhoto(photoId);
            assertThat(readerSide.search(ownerUserId, "sunset", 10)).isEmpty();
        }
    }

    @Test
    @DisplayName("独占索引卷时写入与删除正常完成")
    void writesAndDeletesWhenHoldingTheIndexExclusively() throws Exception {
        PhotoSearchIndexService service = new PhotoSearchIndexService(indexDir.toString());
        try {
            UUID photoId = UUID.randomUUID();
            UUID ownerUserId = UUID.randomUUID();
            service.indexPhoto(document(
                    photoId,
                    ownerUserId,
                    "sunset ridge",
                    "黄昏的海边",
                    List.of("travel"),
                    List.of(),
                    null
            ));
            service.indexPhoto(document(
                    photoId,
                    ownerUserId,
                    "sunset ridge",
                    "黄昏的海边",
                    List.of("travel", "sea"),
                    List.of(),
                    null
            ));
            service.deletePhoto(photoId);
            service.deletePhotos(List.of(photoId, UUID.randomUUID()));
        } finally {
            service.close();
        }

        // 写入侧失败已经改为冒泡，正常路径不应留下任何异常。
        assertThat(java.nio.file.Files.exists(indexDir)).isTrue();
    }

    @Test
    @DisplayName("共享目录下的多租户隔离：ownerUserId 精确项是唯一屏障")
    void searchIsPerOwnerWithinTheSharedDirectory() throws Exception {
        UUID firstOwner = UUID.randomUUID();
        UUID secondOwner = UUID.randomUUID();
        UUID thirdOwner = UUID.randomUUID();
        UUID firstPhoto = UUID.randomUUID();
        UUID secondPhoto = UUID.randomUUID();
        PhotoSearchIndexService service = new PhotoSearchIndexService(indexDir.toString());
        try {
            // 两人写入同一个目录：照片索引不像文件索引按用户分目录，
            // ownerUserId 一旦被分词，过滤条件就可能被同名片段命中，因此必须逐租户精确匹配。
            service.indexPhoto(document(
                    firstPhoto,
                    firstOwner,
                    "sunset ridge",
                    "黄昏的海边",
                    List.of("travel"),
                    List.of(),
                    null
            ));
            service.indexPhoto(document(
                    secondPhoto,
                    secondOwner,
                    "sunset ridge",
                    "黄昏的海边",
                    List.of("travel"),
                    List.of(),
                    null
            ));

            assertThat(service.search(firstOwner, "sunset", 10)).containsExactly(firstPhoto);
            assertThat(service.search(secondOwner, "sunset", 10)).containsExactly(secondPhoto);
            assertThat(service.search(thirdOwner, "sunset", 10)).isEmpty();

            service.deletePhoto(firstPhoto);
            assertThat(service.search(secondOwner, "sunset", 10)).containsExactly(secondPhoto);
            assertThat(service.search(firstOwner, "sunset", 10)).isEmpty();
        } finally {
            service.close();
        }
    }

    @Test
    @DisplayName("AI 标签与图中文字可通过中文词元命中")
    void searchMatchesAiLabelsAndOcrTextWithChineseTokens() throws Exception {
        UUID ownerUserId = UUID.randomUUID();
        UUID invoicePhoto = UUID.randomUUID();
        UUID catPhoto = UUID.randomUUID();
        PhotoSearchIndexService service = new PhotoSearchIndexService(indexDir.toString());
        try {
            service.indexPhoto(new PhotoIndexDocument(
                    invoicePhoto,
                    ownerUserId,
                    "扫描件",
                    null,
                    List.of(),
                    List.of("document 文档 发票 身份证 快递单 合同"),
                    "增值税发票 号码 12345"
            ));
            service.indexPhoto(new PhotoIndexDocument(
                    catPhoto,
                    ownerUserId,
                    "IMG_001",
                    null,
                    List.of(),
                    List.of("cat 猫 猫咪 小猫 宠物"),
                    null
            ));

            assertThat(service.search(ownerUserId, "发票", 10)).containsExactly(invoicePhoto);
            assertThat(service.search(ownerUserId, "猫咪", 10)).containsExactly(catPhoto);
            assertThat(service.search(ownerUserId, "身份证", 10)).containsExactly(invoicePhoto);
            assertThat(service.search(ownerUserId, "航班", 10)).isEmpty();
        } finally {
            service.close();
        }
    }

    @Test
    @DisplayName("批量索引只提交一次且可立即检索")
    void batchIndexCommitsOnceAndIsSearchable() throws Exception {
        UUID ownerUserId = UUID.randomUUID();
        UUID firstPhoto = UUID.randomUUID();
        UUID secondPhoto = UUID.randomUUID();
        PhotoSearchIndexService service = new PhotoSearchIndexService(indexDir.toString());
        try {
            service.indexPhotosBatch(List.of(
                    document(firstPhoto, ownerUserId, "猫咪", null, List.of(), List.of("cat 猫"), null),
                    document(secondPhoto, ownerUserId, "狗狗", null, List.of(), List.of("dog 狗"), null)
            ));

            assertThat(service.search(ownerUserId, "猫", 10)).containsExactly(firstPhoto);
            assertThat(service.search(ownerUserId, "狗", 10)).containsExactly(secondPhoto);
        } finally {
            service.close();
        }
    }

    private PhotoIndexDocument document(
            UUID photoId,
            UUID ownerUserId,
            String title,
            String description,
            List<String> tags,
            List<String> aiLabels,
            String ocrText
    ) {
        return new PhotoIndexDocument(
                photoId,
                ownerUserId,
                title,
                description,
                tags,
                aiLabels,
                ocrText
        );
    }
}
