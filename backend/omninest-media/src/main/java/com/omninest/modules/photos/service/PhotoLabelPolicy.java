package com.omninest.modules.photos.service;

import com.omninest.common.ai.ImageAnalysisGateway.BoundingBox;
import com.omninest.common.ai.ImageAnalysisGateway.ContentAnalysis;
import com.omninest.common.ai.ImageAnalysisGateway.ContentObservation;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import org.springframework.stereotype.Component;

/**
 * 将图像分析侧车结果映射为受控的照片标签。
 *
 * <p>该策略只做同一命名空间内的精确映射，不使用跨命名空间关键词推导。
 *
 * @author OmniNest
 */
@Component
public class PhotoLabelPolicy {

    public static final String SUBJECT = "SUBJECT";
    public static final String SCENE = "SCENE";
    public static final String STYLE = "STYLE";

    private static final float SUBJECT_MIN_CONFIDENCE = 0.65F;
    private static final float SCENE_MIN_CONFIDENCE = 0.55F;
    private static final float STYLE_MIN_CONFIDENCE = 0.70F;
    private static final int MAX_LABELS = 24;
    private static final int MAX_SCENE_LABELS = 1;
    private static final int MAX_STYLE_LABELS = 1;

    private static final Map<String, String> SUBJECT_CODES = Map.ofEntries(
            Map.entry("person", "person"),
            Map.entry("cat", "cat"),
            Map.entry("dog", "dog"),
            Map.entry("bird", "bird"),
            Map.entry("horse", "horse"),
            Map.entry("sheep", "sheep"),
            Map.entry("cow", "cow"),
            Map.entry("elephant", "elephant"),
            Map.entry("bear", "bear"),
            Map.entry("zebra", "zebra"),
            Map.entry("giraffe", "giraffe"),
            Map.entry("vehicle", "vehicle"),
            Map.entry("food", "food"),
            Map.entry("plant", "plant"),
            Map.entry("book", "book")
    );

    private static final Map<String, String> SCENE_CODES = Map.ofEntries(
            Map.entry("indoor", "indoor"),
            Map.entry("outdoor", "outdoor"),
            Map.entry("nature", "nature"),
            Map.entry("urban", "urban"),
            Map.entry("beach", "beach"),
            Map.entry("mountain", "mountain"),
            Map.entry("forest", "forest"),
            Map.entry("lake", "lake"),
            Map.entry("ocean", "ocean"),
            Map.entry("river", "river"),
            Map.entry("office", "office"),
            Map.entry("restaurant", "restaurant"),
            Map.entry("kitchen", "kitchen"),
            Map.entry("bedroom", "bedroom"),
            Map.entry("classroom", "classroom"),
            Map.entry("city", "city"),
            Map.entry("street", "street"),
            Map.entry("park", "park"),
            Map.entry("stadium", "stadium"),
            Map.entry("night", "night")
    );

    private static final Map<String, String> STYLE_CODES = Map.ofEntries(
            Map.entry("photograph", "photograph"),
            Map.entry("illustration", "illustration"),
            Map.entry("anime", "anime"),
            Map.entry("3d_render", "3d_render"),
            Map.entry("screenshot", "screenshot"),
            Map.entry("document", "document"),
            Map.entry("artwork", "artwork")
    );

    /**
     * 标签检索词单一事实源：中文同义词与英文检索词都从这里展开，
     * 避免索引、查询和前端展示各自维护一套口径。
     */
    private static final Map<String, String> SEARCH_SYNONYMS_BY_KEY = Map.ofEntries(
            Map.entry("SUBJECT:person", "人物 人像 人 合影 自拍 person people man woman child portrait"),
            Map.entry("SUBJECT:cat", "猫 猫咪 小猫 宠物 cat kitten"),
            Map.entry("SUBJECT:dog", "狗 狗狗 小狗 宠物 dog puppy"),
            Map.entry("SUBJECT:bird", "鸟 鸟类 飞鸟 bird"),
            Map.entry("SUBJECT:horse", "马 骏马 horse"),
            Map.entry("SUBJECT:sheep", "羊 绵羊 sheep"),
            Map.entry("SUBJECT:cow", "牛 奶牛 cow cattle"),
            Map.entry("SUBJECT:elephant", "大象 elephant"),
            Map.entry("SUBJECT:bear", "熊 bear"),
            Map.entry("SUBJECT:zebra", "斑马 zebra"),
            Map.entry("SUBJECT:giraffe", "长颈鹿 giraffe"),
            Map.entry("SUBJECT:vehicle", "汽车 车辆 车 公交 火车 自行车 摩托 vehicle car bus train bicycle"),
            Map.entry("SUBJECT:food", "食物 美食 饭菜 甜点 水果 food dish meal dessert fruit"),
            Map.entry("SUBJECT:plant", "植物 花 花草 树 plant flower tree"),
            Map.entry("SUBJECT:book", "书 书籍 图书 书架 book bookshelf"),
            Map.entry("SCENE:indoor", "室内 屋里 indoor room"),
            Map.entry("SCENE:outdoor", "室外 户外 outdoor"),
            Map.entry("SCENE:nature", "自然 自然风光 风景 山水 nature landscape"),
            Map.entry("SCENE:urban", "城市 都市 建筑 urban city building"),
            Map.entry("SCENE:beach", "海滩 海边 沙滩 海岸 beach coast seaside"),
            Map.entry("SCENE:mountain", "山 山峰 山区 山脉 mountain hill"),
            Map.entry("SCENE:forest", "森林 树林 forest woods"),
            Map.entry("SCENE:lake", "湖 湖泊 lake"),
            Map.entry("SCENE:ocean", "海洋 大海 海 ocean sea"),
            Map.entry("SCENE:river", "河 河流 小溪 river stream"),
            Map.entry("SCENE:office", "办公室 办公 工位 书桌 office desk"),
            Map.entry("SCENE:restaurant", "餐厅 饭店 咖啡馆 咖啡厅 restaurant cafe"),
            Map.entry("SCENE:kitchen", "厨房 kitchen"),
            Map.entry("SCENE:bedroom", "卧室 房间 bedroom"),
            Map.entry("SCENE:classroom", "教室 课堂 classroom"),
            Map.entry("SCENE:city", "城市 天际线 市中心 city skyline downtown"),
            Map.entry("SCENE:street", "街道 马路 道路 street road"),
            Map.entry("SCENE:park", "公园 花园 park garden"),
            Map.entry("SCENE:stadium", "体育场 球场 运动场 stadium sports field"),
            Map.entry("SCENE:night", "夜晚 夜景 夜间 night"),
            Map.entry("STYLE:photograph", "照片 摄影 实拍 photograph camera"),
            Map.entry("STYLE:illustration", "插画 绘画 素描 手绘 illustration drawing sketch"),
            Map.entry("STYLE:anime", "动漫 动画 卡通 漫画 anime cartoon comic"),
            Map.entry("STYLE:3d_render", "3d 渲染 三维 3d render"),
            Map.entry("STYLE:screenshot", "截图 屏幕截图 截屏 screenshot"),
            Map.entry("STYLE:document", "文档 文件 发票 身份证 快递单 合同 document invoice receipt"),
            Map.entry("STYLE:artwork", "艺术 艺术品 绘画 雕塑 油画 artwork painting sculpture")
    );

    /**
     * 生成稳定的自动标签。
     *
     * @param analysis 侧车结构化分析结果
     * @return 受控标签列表
     */
    public List<PhotoLabel> classify(ContentAnalysis analysis) {
        Map<String, PhotoLabel> labels = new LinkedHashMap<>();
        if (analysis == null || analysis.observations() == null) {
            return List.of();
        }
        for (ContentObservation observation : analysis.observations()) {
            if (observation == null || observation.namespace() == null
                    || observation.code() == null || !Float.isFinite(observation.confidence())) {
                continue;
            }
            String namespace = observation.namespace().trim().toUpperCase(Locale.ROOT);
            String code = normalize(observation.code());
            String mappedCode = switch (namespace) {
                case SUBJECT -> SUBJECT_CODES.get(code);
                case SCENE -> SCENE_CODES.get(code);
                case STYLE -> STYLE_CODES.get(code);
                default -> null;
            };
            if (mappedCode == null || observation.confidence() < minimumConfidence(namespace)) {
                continue;
            }
            String mapKey = key(namespace, mappedCode);
            PhotoLabel current = labels.get(mapKey);
            if (current == null || current.confidence() < observation.confidence()) {
                labels.put(mapKey, new PhotoLabel(
                        namespace,
                        mappedCode,
                        observation.confidence(),
                        observation.source(),
                        observation.boxes()
                ));
            }
        }
        List<PhotoLabel> candidates = labels.values().stream()
                .sorted(Comparator.comparing(PhotoLabel::confidence).reversed()
                        .thenComparing(PhotoLabel::namespace)
                        .thenComparing(PhotoLabel::code))
                .toList();
        List<PhotoLabel> result = new ArrayList<>();
        Map<String, Integer> namespaceCounts = new LinkedHashMap<>();
        for (PhotoLabel candidate : candidates) {
            int namespaceLimit = switch (candidate.namespace()) {
                case SCENE -> MAX_SCENE_LABELS;
                case STYLE -> MAX_STYLE_LABELS;
                default -> MAX_LABELS;
            };
            int count = namespaceCounts.getOrDefault(candidate.namespace(), 0);
            if (count >= namespaceLimit) {
                continue;
            }
            result.add(candidate);
            namespaceCounts.put(candidate.namespace(), count + 1);
            if (result.size() == MAX_LABELS) {
                break;
            }
        }
        return List.copyOf(result);
    }

    /**
     * 展开标签的检索词，供 Lucene 索引统一写入。
     *
     * @param namespace 命名空间
     * @param code 稳定编码
     * @return 编码本身与同义词列表
     */
    public List<String> expandSearchKeywords(String namespace, String code) {
        String normalizedNamespace = namespace == null
                ? ""
                : namespace.trim().toUpperCase(Locale.ROOT);
        String normalizedCode = normalize(code == null ? "" : code);
        if (normalizedNamespace.isEmpty() || normalizedCode.isEmpty()) {
            return List.of();
        }
        String synonyms = SEARCH_SYNONYMS_BY_KEY.get(key(normalizedNamespace, normalizedCode));
        String keywordText = normalizedCode.replace('_', ' ')
                + (synonyms == null ? "" : " " + synonyms);
        return List.of(keywordText);
    }

    private float minimumConfidence(String namespace) {        return switch (namespace) {
            case SUBJECT -> SUBJECT_MIN_CONFIDENCE;
            case SCENE -> SCENE_MIN_CONFIDENCE;
            case STYLE -> STYLE_MIN_CONFIDENCE;
            default -> 1.0F;
        };
    }

    private String normalize(String value) {
        return value.trim().toLowerCase(Locale.ROOT).replace('-', '_');
    }

    private String key(String namespace, String code) {
        return namespace + ":" + code;
    }

    /**
     * 结构化自动标签。
     *
     * @param namespace 命名空间
     * @param code 稳定编码
     * @param confidence 置信度
     * @param source 结果来源
     * @param boxes 边界框
     */
    public record PhotoLabel(
            String namespace,
            String code,
            float confidence,
            String source,
            List<BoundingBox> boxes
    ) {
        public PhotoLabel {
            boxes = boxes == null ? List.of() : List.copyOf(new ArrayList<>(boxes));
        }
    }
}
