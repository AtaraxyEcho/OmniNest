package com.omninest.modules.photos.repository;

import java.math.BigDecimal;
import java.time.Instant;
import java.util.UUID;

/**
 * 回填候选投影：仅取游标推进与逆地理编码所需字段。
 *
 * @author OmniNest
 */
public interface GeocodeBackfillRow {
    UUID getId();

    BigDecimal getGpsLatitude();

    BigDecimal getGpsLongitude();

    Instant getCreatedAt();
}
