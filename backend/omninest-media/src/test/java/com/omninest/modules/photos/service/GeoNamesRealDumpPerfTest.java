package com.omninest.modules.photos.service;

import static org.junit.jupiter.api.Assertions.assertTrue;

import com.omninest.modules.photos.service.GeoNamesParser.Admin1Entry;
import com.omninest.modules.photos.service.GeoNamesParser.CityRow;
import com.omninest.modules.photos.service.GeoNamesParser.CountryEntry;
import java.io.IOException;
import java.io.InputStream;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.Random;
import java.util.concurrent.ThreadLocalRandom;

import org.junit.jupiter.api.Assumptions;
import org.junit.jupiter.api.BeforeAll;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.TestInstance;

/**
 * 真实 GeoNames dump 的解析与内存索引性能验证（方案 §84）。
 *
 * <p>依赖本地文件 data/geonames/（cities5000.txt 必需，
 * alternateNamesV2.txt 可选）；文件缺失时整类跳过，不影响常规测试。</p>
 */
@TestInstance(TestInstance.Lifecycle.PER_CLASS)
class GeoNamesRealDumpPerfTest {

    private static final String DUMP_RELATIVE = "data/geonames";

    private final GeoNamesParser parser = new GeoNamesParser();

    private Map<String, Admin1Entry> admin1ByCode;
    private Map<String, CountryEntry> countryByCode;
    private List<CityRow> cityRows;
    private GeoCitySnapshot snapshot;

    @BeforeAll
    void loadRealDump() throws IOException {
        Assumptions.assumeTrue(dumpDir() != null,
                "未找到真实 dump 目录 data/geonames，跳过性能验证");
        Path dumpDir = dumpDir();

        long parseStart = System.nanoTime();
        admin1ByCode = parser.parseAdmin1Codes(open(dumpDir, "admin1CodesASCII.txt"));
        countryByCode = parser.parseCountryInfo(open(dumpDir, "countryInfo.txt"));
        cityRows = new ArrayList<>(60_000);
        parser.streamCities(open(dumpDir, "cities5000.txt"), row -> cityRows.add(row));
        long parseMillis = (System.nanoTime() - parseStart) / 1_000_000;

        long buildStart = System.nanoTime();
        List<GeoCitySnapshot.Entry> entries = new ArrayList<>(cityRows.size());
        for (CityRow row : cityRows) {
            Admin1Entry admin1 = row.admin1Code() == null
                    ? null
                    : admin1ByCode.get(row.countryCode() + "." + row.admin1Code());
            CountryEntry country = countryByCode.get(row.countryCode());
            entries.add(new GeoCitySnapshot.Entry(
                    row.geonameId(),
                    row.name(),
                    row.name(),
                    row.countryCode(),
                    country == null ? row.countryCode() : country.nameEn(),
                    country == null ? row.countryCode() : country.nameEn(),
                    admin1 == null ? row.admin1Code() : admin1.nameEn(),
                    admin1 == null ? row.admin1Code() : admin1.nameEn(),
                    Math.toRadians(row.latitude().doubleValue()),
                    Math.toRadians(row.longitude().doubleValue())));
        }
        snapshot = GeoCitySnapshot.of("perf-test", List.copyOf(entries));
        long buildMillis = (System.nanoTime() - buildStart) / 1_000_000;

        System.out.printf("[perf] parsed cities=%d admin1=%d country=%d in %d ms; snapshot build %d ms%n",
                cityRows.size(), admin1ByCode.size(), countryByCode.size(), parseMillis, buildMillis);
    }

    private InputStream open(Path dumpDir, String fileName) throws IOException {
        return Files.newInputStream(dumpDir.resolve(fileName));
    }

    /** 从当前工作目录逐级向上探测 dump 目录，支持 surefire 与 IDE 两种工作目录。 */
    static Path dumpDir() {
        Path dir = Path.of("").toAbsolutePath();
        for (int i = 0; i < 4 && dir != null; i++) {
            Path candidate = dir.resolve(DUMP_RELATIVE);
            if (Files.isRegularFile(candidate.resolve("cities5000.txt"))) {
                return candidate;
            }
            dir = dir.getParent();
        }
        return null;
    }

    @Test
    void nearestMeetsLatencyTargets() {
        int warmup = 2_000;
        int samples = 10_000;
        for (int i = 0; i < warmup; i++) {
            double[] coordinate = randomCoordinate();
            GeoCityIndex.nearestInSnapshot(snapshot, coordinate[0], coordinate[1]);
        }

        long[] nanos = new long[samples];
        for (int i = 0; i < samples; i++) {
            double[] coordinate = randomCoordinate();
            long start = System.nanoTime();
            Optional<GeoCityMatch> match = GeoCityIndex.nearestInSnapshot(
                    snapshot, coordinate[0], coordinate[1]);
            nanos[i] = System.nanoTime() - start;
            if (i % 2_000 == 0) {
                assertTrue(match.isPresent(), "真实数据集坐标应可命中城市");
            }
        }

        double p50 = percentileNanos(nanos, 50);
        double p95 = percentileNanos(nanos, 95);
        System.out.printf("[perf] nearest P50=%.3f ms P95=%.3f ms (samples=%d, cities=%d)%n",
                p50 / 1_000_000.0, p95 / 1_000_000.0, samples, snapshot.cities().size());

        // 方案 §84 目标：P50 < 1ms，P95 < 2ms。
        assertTrue(p50 < 1_000_000, "P50 应低于 1ms，实际 " + p50 / 1_000_000.0 + " ms");
        assertTrue(p95 < 2_000_000, "P95 应低于 2ms，实际 " + p95 / 1_000_000.0 + " ms");
    }

    @Test
    void alternateNamesStreamsChineseCandidates() throws IOException {
        Path dumpDir = dumpDir();
        Assumptions.assumeTrue(
                dumpDir != null && Files.isRegularFile(dumpDir.resolve("alternateNamesV2.txt")),
                "缺少 alternateNamesV2.txt，跳过流式扫描验证");

        GeoLocationNameSelector selector = new GeoLocationNameSelector();
        long[] scanned = {0};
        long start = System.nanoTime();
        parser.streamAlternateNames(open(dumpDir, "alternateNamesV2.txt"), candidate -> {
            selector.offer(candidate.geonameId(), candidate.language(), candidate.name(),
                    candidate.preferred(), candidate.historic());
            scanned[0]++;
        });
        long millis = (System.nanoTime() - start) / 1_000_000;
        System.out.printf("[perf] alternateNames scanned=%d zhCollected=%d in %d ms%n",
                scanned[0], selector.collectedIds().size(), millis);
        assertTrue(scanned[0] > 1_000_000, "alternateNamesV2 应有百万级候选行");
    }

    /** 以真实城市坐标为圆心做 ±0.4° 抖动，模拟照片拍摄点分布。 */
    private double[] randomCoordinate() {
        CityRow anchor = cityRows.get(ThreadLocalRandom.current().nextInt(cityRows.size()));
        Random random = ThreadLocalRandom.current();
        return new double[] {
                anchor.latitude().doubleValue() + (random.nextDouble() - 0.5) * 0.8,
                anchor.longitude().doubleValue() + (random.nextDouble() - 0.5) * 0.8
        };
    }

    private double percentileNanos(long[] nanos, int percentile) {
        long[] sorted = nanos.clone();
        Arrays.sort(sorted);
        int index = (int) Math.ceil(percentile / 100.0 * sorted.length) - 1;
        return sorted[Math.max(0, Math.min(sorted.length - 1, index))];
    }
}
