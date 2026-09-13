package com.omninest.modules.reader.service;

import com.omninest.modules.file.dto.FileDescriptor;
import com.omninest.modules.reader.service.model.ReaderCoverDraft;
import java.awt.image.BufferedImage;
import java.io.ByteArrayOutputStream;
import java.io.IOException;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.apache.pdfbox.Loader;
import org.apache.pdfbox.pdmodel.PDDocument;
import org.apache.pdfbox.rendering.ImageType;
import org.apache.pdfbox.rendering.PDFRenderer;
import org.springframework.stereotype.Service;

/**
 * PDF 元数据提取：页数与首页封面图。
 *
 * @author OmniNest
 */
@Slf4j
@Service
@RequiredArgsConstructor
public class ReaderPdfMetadataService {

    private final ReaderEpubArchiveStager archiveStager;

    /**
     * 解析 PDF 页数并渲染首页为 PNG 封面。
     *
     * @param fileNode 文件描述符
     * @return 元数据；失败时返回 null，不阻断导入
     */
    public PdfMetadata extract(FileDescriptor fileNode) {
        try (ReaderEpubArchiveStager.StagedArchive staged = archiveStager.stage(fileNode);
                PDDocument document = Loader.loadPDF(staged.path().toFile())) {
            int pageCount = document.getNumberOfPages();
            byte[] cover = null;
            if (pageCount > 0) {
                PDFRenderer renderer = new PDFRenderer(document);
                BufferedImage image = renderer.renderImageWithDPI(0, 72, ImageType.RGB);
                ByteArrayOutputStream output = new ByteArrayOutputStream();
                javax.imageio.ImageIO.write(image, "png", output);
                cover = output.toByteArray();
            }
            return new PdfMetadata(pageCount, cover);
        } catch (IOException | RuntimeException exception) {
            log.warn("PDF 元数据提取失败: fileId={}", fileNode.id(), exception);
            return null;
        }
    }

    /**
     * PDF 解析结果。
     *
     * @param pageCount 总页数
     * @param coverPng 首页 PNG 封面，可能为 null
     */
    public record PdfMetadata(int pageCount, byte[] coverPng) {

        public ReaderCoverDraft toCoverDraft() {
            if (coverPng == null || coverPng.length == 0) {
                return null;
            }
            return new ReaderCoverDraft(coverPng, "image/png", "page-1.png");
        }
    }
}
