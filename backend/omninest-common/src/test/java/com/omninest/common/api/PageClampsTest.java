package com.omninest.common.api;

import static org.assertj.core.api.Assertions.assertThat;

import java.util.List;
import java.util.stream.Collectors;
import java.util.stream.IntStream;
import org.junit.jupiter.api.Test;

/**
 * 内存列表分页窗口测试。
 *
 * @author OmniNest
 */
class PageClampsTest {

    private final List<Integer> items = IntStream.rangeClosed(1, 45).boxed().collect(Collectors.toList());

    @Test
    void sliceReturnsRequestedWindow() {
        assertThat(PageClamps.slice(items, 0, 20)).containsExactlyElementsOf(
                IntStream.rangeClosed(1, 20).boxed().collect(Collectors.toList()));
        assertThat(PageClamps.slice(items, 1, 20)).containsExactlyElementsOf(
                IntStream.rangeClosed(21, 40).boxed().collect(Collectors.toList()));
    }

    @Test
    void sliceReturnsPartialLastPage() {
        assertThat(PageClamps.slice(items, 2, 20)).containsExactly(41, 42, 43, 44, 45);
        assertThat(PageClamps.slice(items, 3, 20)).isEmpty();
    }

    @Test
    void sliceClampsOversizedPageAndRejectsNegativePage() {
        // 每页上限 200：请求 5000 也只会按上限开窗，避免越界偏移把整表偏移量算成负数。
        assertThat(PageClamps.slice(items, 0, 5000)).hasSize(45);
        assertThat(PageClamps.slice(items, -1, 20)).containsExactlyElementsOf(
                IntStream.rangeClosed(1, 20).boxed().collect(Collectors.toList()));
    }

    @Test
    void sliceTolerantOfHugePageNumber() {
        assertThat(PageClamps.slice(items, Integer.MAX_VALUE, 200)).isEmpty();
    }

    @Test
    void sliceHandlesEmptyAndNullList() {
        assertThat(PageClamps.slice(List.of(), 0, 20)).isEmpty();
        assertThat(PageClamps.slice(null, 0, 20)).isEmpty();
    }
}
