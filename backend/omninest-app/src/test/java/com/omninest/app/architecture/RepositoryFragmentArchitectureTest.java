package com.omninest.app.architecture;

import static org.assertj.core.api.Assertions.assertThat;

import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.HashSet;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.regex.Matcher;
import java.util.regex.Pattern;
import java.util.stream.Stream;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

/**
 * 仓储片段（Spring Data fragment）契约闸门。
 *
 * <p>钉住的是「片段接口被拼进仓储之后是否仍会被 Spring Data 当成片段」这件事，
 * 对应的缺陷是一次真实启动失败：片段接口标了 {@code @NoRepositoryBean}，
 * {@code FragmentMetadata#isCandidate} 直接把它排除在片段之外，其方法退回派生查询解析，
 * 于是一个走 {@code *Impl} 自定义实现的方法在启动时被拿去解析
 * {@code PhotoItem} 上的同名属性，整个应用上下文 refresh 中止。
 * 这类失败只在启动时暴露、且报错点离真正原因隔了三层 Bean 依赖，因此用静态闸门兜住。</p>
 *
 * <p>两条判据都来自 Spring Data 4.1.1 的实现，不做主观推断：</p>
 * <ul>
 *   <li>{@code org.springframework.data.repository.config.FragmentMetadata#isCandidate}
 *       用 {@code !hasAnnotation(NoRepositoryBean)} 过滤片段候选；</li>
 *   <li>{@code RepositoryBeanDefinitionBuilder#detectRepositoryFragmentConfiguration}
 *       找不到 {@code <片段>Impl} 时返回空，片段不注册，方法只能按派生查询解析；
 *       因此既无 {@code @Query} 又不符合 {@code PartTree} 派生前缀的方法必须配套实现。</li>
 * </ul>
 *
 * <p>反过来说，去掉 {@code @NoRepositoryBean} 不会让片段被误扫描成仓储：
 * {@code RepositoryComponentProvider} 的所有 include filter 都 AND 了
 * {@code InterfaceTypeFilter(Repository.class)}，不继承 {@code Repository} 的接口永远不是候选。</p>
 *
 * @author OmniNest
 */
class RepositoryFragmentArchitectureTest {

    /** Spring Data 自带仓储基类型：某个接口直接继承它们，说明它本身是仓储而不是片段。 */
    private static final Set<String> SPRING_REPOSITORY_TYPES = Set.of(
            "Repository",
            "CrudRepository",
            "ListCrudRepository",
            "PagingAndSortingRepository",
            "ListPagingAndSortingRepository",
            "JpaRepository",
            "JpaRepositoryImplementation",
            "JpaSpecificationExecutor",
            "MongoRepository",
            "ReactiveCrudRepository",
            "ReactiveSortingRepository");

    private static final Pattern PACKAGE_DECLARATION =
            Pattern.compile("(?m)^\\s*package\\s+([\\w.]+)\\s*;");

    private static final Pattern INTERFACE_DECLARATION =
            Pattern.compile("\\binterface\\s+(\\w+)([^{]*)\\{");

    private static final Pattern EXTENDS_CLAUSE =
            Pattern.compile("\\bextends\\b([^{]*)$");

    private static final Pattern TYPE_DECLARATION =
            Pattern.compile("\\b(?:class|enum|record)\\b");

    /** 带 {@code @} 才算注解：排除 {@code import org.springframework.data.repository.NoRepositoryBean;} 这行导入。 */
    private static final Pattern NO_REPOSITORY_BEAN = Pattern.compile("@(?:[\\w.]+\\.)?NoRepositoryBean\\b");

    /**
     * Spring Data {@code PartTree} 认可的派生查询前缀。
     *
     * <p>没有 {@code @Query} 但名字落在这个集合里的方法会被按方法名解析成查询，
     * 属于合法写法（例如回收站的 {@code countByOwnerUserIdAndDeletedAtIsNotNull}）；
     * 落在集合外的名字不是派生查询，只能由自定义实现承担。</p>
     */
    private static final Pattern DERIVED_QUERY_NAME = Pattern.compile(
            "^(?:find|read|get|query|search|stream|count|exists|delete|remove)\\w*$");

    /**
     * 片段接口只允许「方法全都有 {@code @Query} 或按方法名可派生」或「配套 {@code *Impl}」两种形态。
     *
     * <p>{@code PhotoItemImportLockQuery} 属于后者：它要用 PostgreSQL 事务级 advisory lock，
     * 无法表达成声明式查询；而 {@code lockContentHashForImport} 这种名字也不在
     * {@code PartTree} 的派生前缀里，没有实现就只能去解析实体属性。</p>
     */
    @Test
    @DisplayName("仓储片段不得标 @NoRepositoryBean，不可派生的方法必须配套 *Impl")
    void repositoryFragmentsMustStayDiscoverable() throws IOException {
        Map<String, InterfaceShape> byFqn = new LinkedHashMap<>();
        Map<String, List<InterfaceShape>> bySimpleName = new HashMap<>();
        for (Path file : mainJavaFiles()) {
            InterfaceShape shape = parseInterface(file);
            if (shape == null) {
                continue;
            }
            byFqn.put(shape.fqn(), shape);
            bySimpleName.computeIfAbsent(shape.simpleName(), key -> new ArrayList<>()).add(shape);
        }

        assertThat(byFqn.keySet())
                .as("解析器必须能定位到仓储与片段，否则闸门等于空转")
                .contains(
                        "com.omninest.modules.photos.repository.PhotoItemRepository",
                        "com.omninest.modules.photos.repository.PhotoItemBrowseQueries",
                        "com.omninest.modules.photos.repository.PhotoItemImportLockQuery");

        Set<String> repositoryInterfaces = repositoryInterfaces(byFqn, bySimpleName);
        List<InterfaceShape> fragments = fragments(repositoryInterfaces, byFqn, bySimpleName);

        assertThat(fragments.stream().map(InterfaceShape::simpleName).toList())
                .as("仓储片段是本闸门的唯一判定对象，识别不到就说明组合关系被判错了")
                .contains(
                        "PhotoItemBrowseQueries",
                        "PhotoItemTimelineQueries",
                        "PhotoItemTrashQueries",
                        "PhotoItemRelationQueries",
                        "PhotoItemImportLockQuery");

        assertThat(fragments.stream()
                .filter(InterfaceShape::noRepositoryBean)
                .map(shape -> relative(shape.file()) + " -> " + shape.simpleName())
                .toList())
                .as("片段接口标 @NoRepositoryBean 会被 Spring Data 排除在片段之外，"
                        + "其无 @Query 的方法将退回派生查询解析并在启动时失败")
                .isEmpty();

        List<String> missingCustomImplementation = new ArrayList<>();
        for (InterfaceShape fragment : fragments) {
            List<String> nonDerivable = fragment.queryLessMethods().stream()
                    .filter(method -> !DERIVED_QUERY_NAME.matcher(method).matches())
                    .toList();
            if (nonDerivable.isEmpty()) {
                continue;
            }
            Path implementation = fragment.file()
                    .resolveSibling(fragment.simpleName() + "Impl.java");
            if (Files.isRegularFile(implementation)) {
                continue;
            }
            nonDerivable.forEach(method -> missingCustomImplementation.add(
                    relative(fragment.file()) + "#" + method));
        }

        assertThat(missingCustomImplementation)
                .as("片段里既没有 @Query、名字也不符合派生前缀的方法必须由同包 <片段>Impl 实现，"
                        + "否则 Spring Data 会拿方法名去解析实体属性并让应用上下文启动失败")
                .isEmpty();
    }

    /**
     * 一个接口的静态形状：够判定「是不是片段」以及「有没有走自定义实现」。
     */
    private record InterfaceShape(
            Path file,
            String packageName,
            String simpleName,
            List<String> superInterfaces,
            boolean noRepositoryBean,
            List<String> queryLessMethods) {

        String fqn() {
            return packageName + "." + simpleName;
        }
    }

    private static List<InterfaceShape> fragments(
            Set<String> repositoryInterfaces,
            Map<String, InterfaceShape> byFqn,
            Map<String, List<InterfaceShape>> bySimpleName) {

        Map<String, InterfaceShape> fragments = new LinkedHashMap<>();
        for (String repositoryFqn : repositoryInterfaces) {
            InterfaceShape repository = byFqn.get(repositoryFqn);
            for (String superInterface : repository.superInterfaces()) {
                InterfaceShape resolved = resolve(superInterface, repository.packageName(), byFqn, bySimpleName);
                if (resolved == null || repositoryInterfaces.contains(resolved.fqn())) {
                    continue;
                }
                fragments.putIfAbsent(resolved.fqn(), resolved);
            }
        }
        return List.copyOf(fragments.values());
    }

    /**
     * 仓储判定：直接继承 Spring Data 仓储基类型，或间接继承本项目里已被判定为仓储的接口。
     */
    private static Set<String> repositoryInterfaces(
            Map<String, InterfaceShape> byFqn,
            Map<String, List<InterfaceShape>> bySimpleName) {

        Set<String> repositories = new HashSet<>();
        boolean changed = true;
        while (changed) {
            changed = false;
            for (InterfaceShape shape : byFqn.values()) {
                if (repositories.contains(shape.fqn()) || !extendsRepository(shape, repositories, byFqn, bySimpleName)) {
                    continue;
                }
                repositories.add(shape.fqn());
                changed = true;
            }
        }
        return repositories;
    }

    private static boolean extendsRepository(
            InterfaceShape shape,
            Set<String> repositories,
            Map<String, InterfaceShape> byFqn,
            Map<String, List<InterfaceShape>> bySimpleName) {

        for (String superInterface : shape.superInterfaces()) {
            if (SPRING_REPOSITORY_TYPES.contains(superInterface)) {
                return true;
            }
            InterfaceShape resolved = resolve(superInterface, shape.packageName(), byFqn, bySimpleName);
            if (resolved != null && repositories.contains(resolved.fqn())) {
                return true;
            }
        }
        return false;
    }

    /**
     * 按「同包优先、全局唯一兜底」解析父接口；解析不到说明是 JDK 或 Spring 的类型。
     */
    private static InterfaceShape resolve(
            String simpleName,
            String packageName,
            Map<String, InterfaceShape> byFqn,
            Map<String, List<InterfaceShape>> bySimpleName) {

        InterfaceShape samePackage = byFqn.get(packageName + "." + simpleName);
        if (samePackage != null) {
            return samePackage;
        }
        List<InterfaceShape> candidates = bySimpleName.getOrDefault(simpleName, List.of());
        return candidates.size() == 1 ? candidates.get(0) : null;
    }

    private static InterfaceShape parseInterface(Path file) throws IOException {
        String code = stripNonCode(Files.readString(file));

        Matcher packageMatcher = PACKAGE_DECLARATION.matcher(code);
        if (!packageMatcher.find()) {
            return null;
        }

        Matcher declaration = INTERFACE_DECLARATION.matcher(code);
        if (!declaration.find()) {
            return null;
        }
        // 本文件的顶层类型必须是接口：类里嵌套的接口不参与仓储组合判定。
        if (TYPE_DECLARATION.matcher(code.substring(0, declaration.start())).find()) {
            return null;
        }

        String simpleName = declaration.group(1);
        String body = interfaceBody(code, declaration.end() - 1);
        return new InterfaceShape(
                file,
                packageMatcher.group(1),
                simpleName,
                superInterfaces(declaration.group(2)),
                NO_REPOSITORY_BEAN.matcher(code.substring(0, declaration.start())).find(),
                queryLessMethods(body));
    }

    /**
     * 抽取接口自己的父接口名（去泛型、去包名前缀）。
     *
     * <p>{@code interface Foo<T extends Bar>} 里的 {@code extends} 属于类型参数，不是父接口，
     * 因此先剔掉尖括号内容再判 {@code extends} 子句。</p>
     */
    private static List<String> superInterfaces(String declarationClause) {
        Matcher matcher = EXTENDS_CLAUSE.matcher(withoutGenerics(declarationClause));
        if (!matcher.find()) {
            return List.of();
        }
        List<String> superInterfaces = new ArrayList<>();
        for (String part : matcher.group(1).split(",")) {
            String candidate = part.trim();
            if (candidate.isEmpty()) {
                continue;
            }
            int lastDot = candidate.lastIndexOf('.');
            superInterfaces.add(lastDot < 0 ? candidate : candidate.substring(lastDot + 1));
        }
        return superInterfaces;
    }

    /**
     * 找出既没有 {@code @Query} 也不是 {@code default}/{@code static} 的方法名。
     *
     * <p>接口体按「顶层分号」切成员，因此多行签名、{@code @Param} 参数注解、文本块 JPQL
     * 都不会把成员切碎；默认方法按配对右大括号收尾，避免把后一个方法的注解吸进来。</p>
     */
    private static List<String> queryLessMethods(String body) {
        List<String> methods = new ArrayList<>();
        for (String member : interfaceMembers(body)) {
            String remainder = stripLeadingAnnotations(member);
            String trimmed = remainder.trim();
            if (trimmed.isEmpty() || !trimmed.contains("(")) {
                continue;
            }
            if (trimmed.startsWith("default ") || trimmed.startsWith("static ") || trimmed.startsWith("private ")) {
                continue;
            }
            if (member.contains("@Query")) {
                continue;
            }
            String methodName = methodName(trimmed);
            if (methodName != null) {
                methods.add(methodName);
            }
        }
        return methods;
    }

    private static String methodName(String declaration) {
        int parenthesis = declaration.indexOf('(');
        if (parenthesis <= 0) {
            return null;
        }
        int cursor = parenthesis - 1;
        while (cursor >= 0 && Character.isWhitespace(declaration.charAt(cursor))) {
            cursor--;
        }
        int end = cursor;
        while (cursor >= 0 && Character.isJavaIdentifierPart(declaration.charAt(cursor))) {
            cursor--;
        }
        return end > cursor ? declaration.substring(cursor + 1, end + 1) : null;
    }

    private static List<String> interfaceMembers(String body) {
        List<String> members = new ArrayList<>();
        StringBuilder current = new StringBuilder();
        int parenthesisDepth = 0;
        int braceDepth = 0;
        for (int index = 0; index < body.length(); index++) {
            char character = body.charAt(index);
            if (character == '(' || character == '[') {
                parenthesisDepth++;
            } else if (character == ')' || character == ']') {
                parenthesisDepth--;
            } else if (character == '{') {
                braceDepth++;
            } else if (character == '}') {
                braceDepth--;
            }
            if (character == ';' && parenthesisDepth == 0 && braceDepth == 0) {
                members.add(current.toString());
                current.setLength(0);
                continue;
            }
            current.append(character);
            if (character == '}' && parenthesisDepth == 0 && braceDepth == 0) {
                members.add(current.toString());
                current.setLength(0);
            }
        }
        if (!current.toString().isBlank()) {
            members.add(current.toString());
        }
        return members;
    }

    /**
     * 去掉成员开头的注解（含带参注解的括号内容），剩下的第一个关键字决定成员种类。
     */
    private static String stripLeadingAnnotations(String member) {
        String remainder = member.stripLeading();
        while (remainder.startsWith("@")) {
            int cursor = 1;
            while (cursor < remainder.length() && Character.isJavaIdentifierPart(remainder.charAt(cursor))) {
                cursor++;
            }
            while (cursor < remainder.length() && Character.isWhitespace(remainder.charAt(cursor))) {
                cursor++;
            }
            if (cursor < remainder.length() && remainder.charAt(cursor) == '(') {
                int depth = 0;
                while (cursor < remainder.length()) {
                    char character = remainder.charAt(cursor);
                    if (character == '(') {
                        depth++;
                    } else if (character == ')') {
                        depth--;
                        if (depth == 0) {
                            cursor++;
                            break;
                        }
                    }
                    cursor++;
                }
            }
            remainder = remainder.substring(cursor).stripLeading();
        }
        return remainder;
    }

    private static String interfaceBody(String code, int braceIndex) {
        int depth = 0;
        for (int index = braceIndex; index < code.length(); index++) {
            char character = code.charAt(index);
            if (character == '{') {
                depth++;
            } else if (character == '}') {
                depth--;
                if (depth == 0) {
                    return code.substring(braceIndex + 1, index);
                }
            }
        }
        return code.substring(braceIndex + 1);
    }

    private static String withoutGenerics(String text) {
        StringBuilder result = new StringBuilder(text.length());
        int depth = 0;
        for (int index = 0; index < text.length(); index++) {
            char character = text.charAt(index);
            if (character == '<') {
                depth++;
                continue;
            }
            if (character == '>' && depth > 0) {
                depth--;
                continue;
            }
            if (depth == 0) {
                result.append(character);
            }
        }
        return result.toString();
    }

    /**
     * 把源码压成「只剩语法骨架」的形态：注释、字符串字面量与文本块都不参与判定。
     *
     * <p>片段里的 JPQL 文本块含冒号参数与 {@code ;} 以外的标点，不剔除会污染成员切分。</p>
     */
    private static String stripNonCode(String source) {
        StringBuilder result = new StringBuilder(source.length());
        int index = 0;
        while (index < source.length()) {
            char character = source.charAt(index);
            if (character == '/' && index + 1 < source.length() && source.charAt(index + 1) == '*') {
                int end = source.indexOf("*/", index + 2);
                index = end < 0 ? source.length() : end + 2;
                continue;
            }
            if (character == '/' && index + 1 < source.length() && source.charAt(index + 1) == '/') {
                int end = source.indexOf('\n', index + 2);
                index = end < 0 ? source.length() : end;
                continue;
            }
            if (character == '"' && source.startsWith("\"\"\"", index)) {
                int end = source.indexOf("\"\"\"", index + 3);
                result.append("\"\"");
                index = end < 0 ? source.length() : end + 3;
                continue;
            }
            if (character == '"' || character == '\'') {
                char quote = character;
                index++;
                while (index < source.length() && source.charAt(index) != quote) {
                    if (source.charAt(index) == '\\') {
                        index++;
                    }
                    index++;
                }
                index++;
                result.append(quote).append(quote);
                continue;
            }
            result.append(character);
            index++;
        }
        return result.toString();
    }

    private static Path backendRoot() {
        Path current = Path.of("").toAbsolutePath().normalize();
        for (int depth = 0; depth < 5 && current != null; depth++) {
            if (Files.isDirectory(current.resolve("omninest-common"))
                    && Files.isRegularFile(current.resolve("pom.xml"))) {
                return current;
            }
            current = current.getParent();
        }
        throw new IllegalStateException("无法定位 backend 根目录");
    }

    private static List<Path> mainJavaFiles() throws IOException {
        Path root = backendRoot();
        try (Stream<Path> walk = Files.walk(root)) {
            return walk.filter(Files::isRegularFile)
                    .filter(path -> path.toString().endsWith(".java"))
                    .filter(path -> path.toString().replace('\\', '/').contains("/src/main/java/"))
                    .toList();
        }
    }

    private static String relative(Path file) {
        return backendRoot().relativize(file).toString().replace('\\', '/');
    }
}
