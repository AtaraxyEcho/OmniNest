package com.omninest.modules.reader.service;

import com.omninest.modules.file.dto.FileDescriptor;
import com.omninest.modules.reader.service.model.ReaderCoverDraft;
import java.awt.image.BufferedImage;
import java.io.ByteArrayOutputStream;
import java.io.IOException;
import javax.imageio.ImageIO;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.apache.pdfbox.Loader;
import org.apache.pdfbox.pdmodel.PDDocument;
import org.apache.pdfbox.pdmodel.common.PDRectangle;
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

    /**
     * 首页封面的像素预算：PDF 的 MediaBox 由文档自报，恶意超大页面按 72dpi
     * 会渲出数百 MB 位图，而 {@link OutOfMemoryError} 不是 Exception，
     * 下面的 catch 拦不住，进程按 {@code -XX:+ExitOnOutOfMemoryError} 直接退出。
     */
    private static final long MAX_COVER_PIXELS = 4_000_000L;

    /** 72dpi 下 1pt 恰好等于 1px，基准分辨率即 PDF 自报的页框尺寸。 */
    private static final float BASE_DPI = 72f;

    private static final float MIN_DPI = 4f;

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
            float coverDpi = pageCount > 0 ? coverDpi(document) : 0f;
            if (coverDpi > 0f) {
                PDFRenderer renderer = new PDFRenderer(document);
                BufferedImage image = renderer.renderImageWithDPI(0, coverDpi, ImageType.RGB);
                ByteArrayOutputStream output = new ByteArrayOutputStream();
                ImageIO.write(image, "png", output);
                cover = output.toByteArray();
            }
            return new PdfMetadata(pageCount, cover);
        } catch (IOException | RuntimeException exception) {
            log.warn("PDF 元数据提取失败: fileId={}", fileNode.id(), exception);
            return null;
        }
    }

    /**
     * 按页框尺寸换算可用的封面渲染 DPI；返回 0 表示跳过封面而不猜一个超限的位图。
     *
     * <p>缩放而不是拒绝：普通大页（如工程图 PDF）仍能拿到预算内的封面。</p>
     */
    private static float coverDpi(PDDocument document) {
        PDRectangle box = document.getPage(0).getMediaBox();
        if (box == null) {
            return 0f;
        }
        double pixels = (double) box.getWidth() * box.getHeight();
        if (!Double.isFinite(pixels) || pixels <= 0d) {
            return 0f;
        }
        if (pixels <= (double) MAX_COVER_PIXELS) {
            return BASE_DPI;
        }
        float scaled = (float) (BASE_DPI * Math.sqrt((double) MAX_COVER_PIXELS / pixels));
        if (scaled < MIN_DPI) {
            return 0f;
        }
        return scaled;
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
