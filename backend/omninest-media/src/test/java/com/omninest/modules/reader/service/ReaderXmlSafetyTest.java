package com.omninest.modules.reader.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import org.junit.jupiter.api.Test;
import org.w3c.dom.Document;

/**
 * Reader XML 安全解析测试。
 *
 * @author OmniNest
 */
class ReaderXmlSafetyTest {

    @Test
    void acceptsExternalDoctypeWithoutLoadingRemoteResource() {
        String xml = """
                <?xml version="1.0"?>
                <!DOCTYPE html SYSTEM "https://example.invalid/xhtml.dtd">
                <html xmlns="http://www.w3.org/1999/xhtml"><body>正文</body></html>
                """;

        assertThat(ReaderXmlSafety.parse(xml).getDocumentElement().getTextContent()).isEqualTo("正文");
    }

    @Test
    void rejectsInternalEntityDeclarations() {
        String xml = """
                <?xml version="1.0"?>
                <!DOCTYPE root [<!ENTITY payload "expanded">]>
                <root>&payload;</root>
                """;

        assertThatThrownBy(() -> ReaderXmlSafety.parse(xml))
                .isInstanceOf(IllegalArgumentException.class)
                .hasMessageContaining("内部实体");
    }

    /**
     * Kindle/MOBI 转换出的 OPF 会把厂商元数据整段留在注释里，其中含 {@code --}。
     * 这类注释必须忽略而不是判死整个文档，否则一本书的目录与正文都读不出来。
     */
    @Test
    void ignoresCommentsContainingDoubleDash() {
        String xml = """
                <?xml version="1.0" encoding="utf-8"?>
                <package xmlns:dc="http://purl.org/dc/elements/1.1/">
                <!-- BEGIN INFORMATION ONLY
                <dc:title>注释里的假标题</dc:title>
                <meta name="Title-Pronunciation" content="shishuoxinyuyizhu--（精）国民阅读经典" />
                -->
                <metadata>
                <dc:title>世说新语译注</dc:title>
                </metadata>
                </package>
                """;

        Document doc = ReaderXmlSafety.parse(xml);

        assertThat(doc.getElementsByTagNameNS("http://purl.org/dc/elements/1.1/", "title").item(0).getTextContent())
                .isEqualTo("世说新语译注");
    }

    @Test
    void ignoresCommentEndingWithDash() {
        String xml = """
                <root><!-- 收尾多一个横线 ---><child>正文</child></root>
                """;

        assertThat(ReaderXmlSafety.parse(xml).getDocumentElement().getTextContent()).isEqualTo("正文");
    }

    /**
     * 合法注释的原有边界不能被误判：只应剔除违反规则的那些，其余照旧由解析器忽略。
     *
     * <p>剔除动作发生在文本层，若把合法注释也当成非法一起删掉，注释里本来无害的
     * 引号与标签形状会连带消失，正文却仍在——测试用注释前后的文本都还在来锁住范围。
     */
    @Test
    void keepsLegalCommentsAndTheirNeighbours() {
        String xml = """
                <root><!-- 合法注释 <meta name="cover" content="x.jpg"/> -->
                <title>甲</title><!-- 内含 -- 的非法注释 --><title>乙</title></root>
                """;

        Document doc = ReaderXmlSafety.parse(xml);

        assertThat(doc.getElementsByTagName("title").getLength()).isEqualTo(2);
        assertThat(doc.getDocumentElement().getTextContent()).contains("甲").contains("乙");
    }

    /**
     * CDATA 里的 {@code <!--} 与 {@code --} 都是字面文本，不参与注释扫描。
     */
    @Test
    void doesNotRewriteContentInsideCdata() {
        String xml = """
                <root><script><![CDATA[<!-- a -- b -->]]></script></root>
                """;

        assertThat(ReaderXmlSafety.parse(xml).getDocumentElement().getTextContent())
                .isEqualTo("<!-- a -- b -->");
    }

    /**
     * 找不到收尾的注释不猜范围：宁可整本解析失败，也不能把注释之后的正文一起吞掉。
     */
    @Test
    void stillRejectsUnterminatedComment() {
        String xml = """
                <root><!-- 内含 -- 的非法注释 -->
                <title>甲</title>
                <!-- 没有收尾
                """;

        assertThatThrownBy(() -> ReaderXmlSafety.parse(xml))
                .isInstanceOf(IllegalArgumentException.class)
                .hasMessageContaining("XML 解析失败");
    }
}
