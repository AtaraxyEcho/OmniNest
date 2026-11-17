package com.omninest.modules.reader.service;

import java.io.ByteArrayInputStream;
import java.nio.charset.StandardCharsets;
import javax.xml.XMLConstants;
import javax.xml.parsers.DocumentBuilder;
import javax.xml.parsers.DocumentBuilderFactory;
import lombok.extern.slf4j.Slf4j;
import org.w3c.dom.Document;
import org.xml.sax.ErrorHandler;
import org.xml.sax.InputSource;
import org.xml.sax.SAXException;
import org.xml.sax.SAXParseException;

/**
 * Reader 模块 XML 安全解析入口，统一限制外部资源和实体展开。
 *
 * @author OmniNest
 */
@Slf4j
final class ReaderXmlSafety {

    private static final int MAX_XML_CHARACTERS = 5 * 1024 * 1024;
    private static final String COMMENT_START = "<!--";
    private static final String COMMENT_END = "-->";
    private static final String CDATA_START = "<![CDATA[";
    private static final String CDATA_END = "]]>";
    private static final String ENTITY_EXPANSION_LIMIT =
            "http://www.oracle.com/xml/jaxp/properties/entityExpansionLimit";
    private static final String TOTAL_ENTITY_SIZE_LIMIT =
            "http://www.oracle.com/xml/jaxp/properties/totalEntitySizeLimit";
    private static final String MAX_GENERAL_ENTITY_SIZE_LIMIT =
            "http://www.oracle.com/xml/jaxp/properties/maxGeneralEntitySizeLimit";

    private ReaderXmlSafety() {
    }

    /**
     * 在禁止外部资源和内部实体声明的条件下解析 XML。
     *
     * <p>注释内容违反 XML 规则的文档先丢掉这些注释再解析：注释不参与任何元数据、
     * 目录或正文取值，丢掉它不改变 DOM 里能读到的东西。
     *
     * @param xml XML 内容
     * @return DOM 文档
     */
    static Document parse(String xml) {
        validateInput(xml);
        String parseable = stripIllegalComments(xml);
        try {
            DocumentBuilderFactory factory = createFactory();
            DocumentBuilder builder = factory.newDocumentBuilder();
            builder.setEntityResolver((publicId, systemId) -> new InputSource(new ByteArrayInputStream(new byte[0])));
            builder.setErrorHandler(new StrictErrorHandler());
            return builder.parse(new InputSource(
                    new ByteArrayInputStream((parseable == null ? xml : parseable).getBytes(StandardCharsets.UTF_8))
            ));
        } catch (Exception exception) {
            throw new IllegalArgumentException("XML 解析失败: " + exception.getMessage(), exception);
        }
    }

    /**
     * 剔除内容里违反 XML 注释规则的注释。
     *
     * <p>Kindle 与 MOBI 转换出来的 OPF 会把整段厂商元数据写进注释保留，里面常带
     * {@code --}（如 {@code shishuoxinyuyizhu--（精）国民阅读经典}），而 XML 1.0 规定
     * 注释内容不得出现 {@code --}、不得以 {@code -} 收尾，严格解析器遇到即判死，
     * 一本书的目录与正文因此全部读不出来。客户端用的 XML 解析器对注释里的
     * {@code --} 本就宽容，受影响的只有后端这份章节清单。
     *
     * <p>注释的收尾以第一个 {@code -->} 为准，与容错解析器的取法一致；找不到收尾的注释
     * 不猜它的范围，交给严格解析正常报错，避免把注释之后的正文一并吞掉。
     *
     * @param xml XML 内容
     * @return 剔除非法注释后的内容；没有非法注释时返回 null，表示原文可直接解析
     */
    private static String stripIllegalComments(String xml) {
        StringBuilder result = null;
        int copied = 0;
        int index = 0;
        while (index < xml.length()) {
            if (xml.startsWith(CDATA_START, index)) {
                int cdataEnd = xml.indexOf(CDATA_END, index + CDATA_START.length());
                // CDATA 里的 <!-- 是字面文本，整段跳过；未收尾时跳到内容末尾交给解析器报错。
                index = cdataEnd < 0 ? xml.length() : cdataEnd + CDATA_END.length();
                continue;
            }
            if (!xml.startsWith(COMMENT_START, index)) {
                index++;
                continue;
            }
            int bodyStart = index + COMMENT_START.length();
            int terminator = xml.indexOf(COMMENT_END, bodyStart);
            if (terminator < 0) {
                break;
            }
            int next = terminator + COMMENT_END.length();
            String body = xml.substring(bodyStart, terminator);
            if (body.contains("--") || body.endsWith("-")) {
                if (result == null) {
                    result = new StringBuilder(xml.length());
                }
                result.append(xml, copied, index);
                copied = next;
            }
            index = next;
        }
        if (result == null) {
            return null;
        }
        result.append(xml, copied, xml.length());
        return result.toString();
    }

    private static DocumentBuilderFactory createFactory() throws Exception {
        DocumentBuilderFactory factory = DocumentBuilderFactory.newInstance();
        factory.setNamespaceAware(true);
        factory.setXIncludeAware(false);
        factory.setExpandEntityReferences(false);
        factory.setFeature(XMLConstants.FEATURE_SECURE_PROCESSING, true);
        // EPUB 章节常带外部 DOCTYPE 声明，只允许声明存在，不读取其外部资源。
        factory.setFeature("http://apache.org/xml/features/disallow-doctype-decl", false);
        factory.setFeature("http://xml.org/sax/features/external-general-entities", false);
        factory.setFeature("http://xml.org/sax/features/external-parameter-entities", false);
        factory.setFeature("http://apache.org/xml/features/nonvalidating/load-external-dtd", false);
        setAttributeIfSupported(factory, XMLConstants.ACCESS_EXTERNAL_DTD, "");
        setAttributeIfSupported(factory, XMLConstants.ACCESS_EXTERNAL_SCHEMA, "");
        setAttributeIfSupported(factory, ENTITY_EXPANSION_LIMIT, "64");
        setAttributeIfSupported(factory, TOTAL_ENTITY_SIZE_LIMIT, "65536");
        setAttributeIfSupported(factory, MAX_GENERAL_ENTITY_SIZE_LIMIT, "16384");
        return factory;
    }

    private static void validateInput(String xml) {
        if (xml == null || xml.isBlank()) {
            throw new IllegalArgumentException("XML 内容为空");
        }
        if (xml.length() > MAX_XML_CHARACTERS) {
            throw new IllegalArgumentException("XML 内容超过安全上限");
        }
        if (xml.contains("<!ENTITY") || hasInternalDoctypeSubset(xml)) {
            throw new IllegalArgumentException("XML 不允许包含内部实体声明");
        }
    }

    private static boolean hasInternalDoctypeSubset(String xml) {
        int start = xml.indexOf("<!DOCTYPE");
        if (start < 0) {
            return false;
        }
        boolean quoted = false;
        char quote = 0;
        for (int index = start + 9; index < xml.length(); index++) {
            char current = xml.charAt(index);
            if (quoted) {
                if (current == quote) {
                    quoted = false;
                }
                continue;
            }
            if (current == '\'' || current == '"') {
                quoted = true;
                quote = current;
            } else if (current == '[') {
                return true;
            } else if (current == '>') {
                return false;
            }
        }
        return false;
    }

    private static void setAttributeIfSupported(DocumentBuilderFactory factory, String name, String value) {
        try {
            factory.setAttribute(name, value);
        } catch (IllegalArgumentException exception) {
            log.debug("当前 XML 实现不支持属性 {}，跳过: {}", name, exception.getMessage());
        }
    }

    /**
     * 将 XML 语法错误转换为异常，避免解析器向标准错误流输出内容。
     *
     * @author OmniNest
     */
    private static final class StrictErrorHandler implements ErrorHandler {

        @Override
        public void warning(SAXParseException exception) throws SAXException {
            throw exception;
        }

        @Override
        public void error(SAXParseException exception) throws SAXException {
            throw exception;
        }

        @Override
        public void fatalError(SAXParseException exception) throws SAXException {
            throw exception;
        }
    }
}
