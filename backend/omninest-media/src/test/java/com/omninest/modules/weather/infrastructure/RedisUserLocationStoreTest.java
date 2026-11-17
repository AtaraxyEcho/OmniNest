package com.omninest.modules.weather.infrastructure;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import com.omninest.common.util.RedisUtil;
import com.omninest.modules.weather.service.UserLocationStore.UserLocationSnapshot;
import java.time.Duration;
import java.time.Instant;
import java.util.UUID;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;
import org.mockito.Mockito;

/**
 * 验证 Redis 用户位置适配器的序列化契约。
 *
 * @author OmniNest
 */
class RedisUserLocationStoreTest {

    private static final UUID USER_ID = UUID.fromString("10000000-0000-0000-0000-000000000001");
    private static final String KEY = "weather:user:location:" + USER_ID;

    private final RedisUtil redisUtil = Mockito.mock(RedisUtil.class);
    private final RedisUserLocationStore store = new RedisUserLocationStore(redisUtil);

    @Test
    void savePreservesExistingJsonShapeAndTtl() {
        Instant reportedAt = Instant.parse("2026-07-22T07:00:00Z");
        ArgumentCaptor<String> payloadCaptor = ArgumentCaptor.forClass(String.class);

        store.save(
                USER_ID,
                new UserLocationSnapshot("121.4737,31.2304", "device", reportedAt),
                Duration.ofDays(7)
        );

        verify(redisUtil).set(
                Mockito.eq(KEY),
                payloadCaptor.capture(),
                Mockito.eq(Duration.ofDays(7))
        );
        assertThat(payloadCaptor.getValue())
                .contains("\"latLon\":\"121.4737,31.2304\"")
                .contains("\"source\":\"device\"")
                .contains("\"ts\":" + reportedAt.toEpochMilli());
    }

    @Test
    void findParsesStoredSnapshot() {
        when(redisUtil.get(KEY)).thenReturn(
                "{\"latLon\":\"121.4737,31.2304\",\"source\":\"device\",\"ts\":1784703600000}"
        );

        UserLocationSnapshot snapshot = store.find(USER_ID).orElseThrow();

        assertThat(snapshot.latLon()).isEqualTo("121.4737,31.2304");
        assertThat(snapshot.source()).isEqualTo("device");
        assertThat(snapshot.reportedAt()).isEqualTo(Instant.ofEpochMilli(1784703600000L));
    }
}
