package com.omninest.modules.photos.service;

import static org.assertj.core.api.Assertions.assertThat;

import java.io.ByteArrayInputStream;
import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.UncheckedIOException;
import java.nio.charset.StandardCharsets;
import org.junit.jupiter.api.Test;

/**
 * 动态照片 XMP 检测单元测试：构造带 APP1 XMP 段的最小 JPEG 校验三种标记路径。
 *
 * @author OmniNest
 */
class PhotoExifExtractorMotionTest {

    private final PhotoExifExtractor extractor = new PhotoExifExtractor();

    @Test
    void detectsLegacyMicroVideoWithOffset() {
        String xmp = """
                <?xpacket begin="﻿" id="W5M0MpCehiHzreSzNTczkc9d"?>
                <x:xmpmeta xmlns:x="adobe:ns:meta/">
                 <rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">
                  <rdf:Description rdf:about="" xmlns:GCamera="http://ns.google.com/photos/1.0/camera/"
                   GCamera:MicroVideo="1"
                   GCamera:MicroVideoVersion="1"
                   GCamera:MicroVideoOffset="123456"/>
                 </rdf:RDF>
                </x:xmpmeta>
                <?xpacket end="w"?>""";
        PhotoExifExtractor.ExifData exif = extractor.extract(jpegWithXmp(xmp));

        assertThat(exif.motion().detected()).isTrue();
        assertThat(exif.motion().microVideo()).isTrue();
        assertThat(exif.motion().motionPhoto()).isFalse();
        assertThat(exif.motion().microVideoOffset()).isEqualTo(123456L);
    }

    @Test
    void detectsModernMotionPhotoFlag() {
        String xmp = """
                <x:xmpmeta xmlns:x="adobe:ns:meta/">
                 <rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">
                  <rdf:Description rdf:about="" xmlns:GCamera="http://ns.google.com/photos/1.0/camera/"
                   GCamera:MotionPhoto="1"
                   GCamera:MotionPhotoVersion="1"/>
                 </rdf:RDF>
                </x:xmpmeta>""";
        PhotoExifExtractor.ExifData exif = extractor.extract(jpegWithXmp(xmp));

        assertThat(exif.motion().detected()).isTrue();
        assertThat(exif.motion().motionPhoto()).isTrue();
        assertThat(exif.motion().microVideo()).isFalse();
        assertThat(exif.motion().microVideoOffset()).isNull();
    }

    @Test
    void plainJpegHasNoMotionInfo() {
        PhotoExifExtractor.ExifData exif = extractor.extract(jpegWithXmp("<x:xmpmeta xmlns:x=\"adobe:ns:meta/\"/>"));

        assertThat(exif.motion().detected()).isFalse();
    }

    /**
     * 构造仅含 SOI + APP1(XMP) + EOI 的最小 JPEG；metadata-extractor 按段解析，
     * 图像数据缺失不影响 XMP 读取。
     */
    private InputStream jpegWithXmp(String xmp) {
        try {
            byte[] xmpBytes = xmp.getBytes(StandardCharsets.UTF_8);
            byte[] header = "http://ns.adobe.com/xap/1.0/\0".getBytes(StandardCharsets.US_ASCII);
            ByteArrayOutputStream out = new ByteArrayOutputStream();
            out.write(new byte[] {(byte) 0xFF, (byte) 0xD8});
            int segmentLength = header.length + xmpBytes.length + 2;
            out.write(new byte[] {(byte) 0xFF, (byte) 0xE1});
            out.write((segmentLength >> 8) & 0xFF);
            out.write(segmentLength & 0xFF);
            out.write(header);
            out.write(xmpBytes);
            out.write(new byte[] {(byte) 0xFF, (byte) 0xD9});
            return new ByteArrayInputStream(out.toByteArray());
        } catch (IOException ex) {
            throw new UncheckedIOException(ex);
        }
    }
}
