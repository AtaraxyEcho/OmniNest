package com.omninest.modules.file.service;

import com.omninest.modules.file.domain.FileNode;
import com.omninest.modules.file.domain.FileTypeCategories;
import com.omninest.modules.file.domain.NodeType;
import com.omninest.modules.file.repository.FileNodeRepository;
import java.util.List;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.boot.ApplicationArguments;
import org.springframework.boot.ApplicationRunner;
import org.springframework.data.domain.PageRequest;
import org.springframework.data.domain.Slice;
import org.springframework.stereotype.Component;
import org.springframework.transaction.support.TransactionTemplate;

/**
 * 启动时补全历史 FILE 节点的业务分类。
 *
 * <p>仅处理 {@code category IS NULL} 的文件节点，分批短事务提交，幂等可重复执行。
 */
@Slf4j
@Component
@RequiredArgsConstructor
public class FileCategoryBackfillRunner implements ApplicationRunner {

    private static final int BATCH_SIZE = 200;

    private final FileNodeRepository fileNodeRepository;
    private final TransactionTemplate transactionTemplate;

    @Override
    public void run(ApplicationArguments args) {
        int updated = 0;
        while (true) {
            Integer batchCount = transactionTemplate.execute(status -> {
                Slice<FileNode> slice = fileNodeRepository.findMissingCategoryPage(
                        NodeType.FILE.getValue(), PageRequest.of(0, BATCH_SIZE));
                List<FileNode> nodes = slice.getContent();
                if (nodes.isEmpty()) {
                    return 0;
                }
                for (FileNode node : nodes) {
                    node.setCategory(FileTypeCategories.resolve(
                            node.getName(), node.getMimeType(), node.getNodeType()));
                }
                fileNodeRepository.saveAll(nodes);
                return nodes.size();
            });
            if (batchCount == null || batchCount == 0) {
                break;
            }
            updated += batchCount;
            if (batchCount < BATCH_SIZE) {
                break;
            }
        }
        if (updated > 0) {
            log.info("文件分类补全完成: count={}", updated);
        }
    }
}
