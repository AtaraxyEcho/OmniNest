#include <flutter/runtime_effect.glsl>

precision mediump float;

uniform vec2 uSize;
uniform float uTime;
uniform float uWeatherType;
uniform float uIntensity;
uniform float uWind;
uniform float uDayPhase;
uniform vec4 uBackground;
uniform vec4 uAccent;
uniform vec4 uAccentAlt;

out vec4 fragColor;

float hash(vec2 p) {
  p = fract(p * vec2(123.34, 456.21));
  p += dot(p, p + 45.32);
  return fract(p.x * p.y);
}

float noise(vec2 p) {
  vec2 i = floor(p);
  vec2 f = fract(p);
  f = f * f * (3.0 - 2.0 * f);
  float a = hash(i);
  float b = hash(i + vec2(1.0, 0.0));
  float c = hash(i + vec2(0.0, 1.0));
  float d = hash(i + vec2(1.0, 1.0));
  return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

float fbm(vec2 p) {
  float value = 0.0;
  float amplitude = 0.5;
  mat2 rotate = mat2(0.80, -0.60, 0.60, 0.80);
  for (int i = 0; i < 5; i++) {
    value += amplitude * noise(p);
    p = rotate * p * 2.02 + vec2(17.7, 9.2);
    amplitude *= 0.52;
  }
  return value;
}

float softBand(float value, float center, float width) {
  return 1.0 - smoothstep(width, width * 1.9, abs(value - center));
}

vec3 gradientSky(vec2 uv) {
  vec3 base = mix(uBackground.rgb, uAccent.rgb, 0.16 + uv.y * 0.12);
  vec3 lower = mix(base, vec3(0.015, 0.026, 0.034), smoothstep(0.34, 1.0, uv.y));
  vec3 dusk = mix(lower, vec3(0.18, 0.12, 0.18), 0.22 + (1.0 - uv.y) * 0.08);
  vec3 night = mix(lower, vec3(0.010, 0.018, 0.034), 0.60 + uv.y * 0.16);
  lower = mix(lower, dusk, smoothstep(0.18, 0.58, 1.0 - abs(uDayPhase - 0.5) * 2.0));
  lower = mix(lower, night, smoothstep(0.56, 1.0, uDayPhase));
  return lower;
}

vec3 weatherTint(vec3 color, vec2 uv, float cloud) {
  if (uWeatherType < 0.5) {
    return mix(color, vec3(0.30, 0.42, 0.46), 0.10);
  }
  if (uWeatherType < 1.5) {
    float transition = smoothstep(0.18, 0.58, 1.0 - abs(uDayPhase - 0.5) * 2.0);
    vec2 sunPosition = mix(vec2(0.68, 0.14), vec2(0.74, 0.27), transition);
    vec2 sun = uv - sunPosition;
    vec2 moon = uv - vec2(0.72, 0.16);
    float glow = exp(-dot(sun, sun) * 3.2);
    float halo = exp(-dot(sun, sun) * 11.0);
    float disk = exp(-dot(sun, sun) * 96.0);
    float moonGlow = exp(-dot(moon, moon) * 12.0);
    float moonDisk = exp(-dot(moon, moon) * 130.0);
    float dust = fbm(uv * 15.0 + vec2(uTime * 0.035, -uTime * 0.010));
    float ray = 1.0 - smoothstep(0.12, 0.88, abs((uv.x - sunPosition.x) * 0.42 + (uv.y - sunPosition.y)));
    vec3 clearSky = mix(vec3(0.34, 0.68, 0.92), vec3(0.08, 0.24, 0.42), smoothstep(0.12, 1.0, uv.y));
    vec3 duskSky = mix(vec3(0.54, 0.27, 0.22), vec3(0.10, 0.065, 0.14), smoothstep(0.05, 1.0, uv.y));
    vec3 nightSky = mix(vec3(0.035, 0.070, 0.14), vec3(0.010, 0.018, 0.040), smoothstep(0.05, 1.0, uv.y));
    color = mix(color, clearSky, 0.66 * (1.0 - transition * 0.64));
    color = mix(color, duskSky, transition * 0.82);
    color = mix(color, nightSky, smoothstep(0.56, 1.0, uDayPhase) * 0.76);
    float sunAmount = mix(1.0 - smoothstep(0.42, 0.90, uDayPhase), 0.42, transition);
    float moonAmount = smoothstep(0.56, 1.0, uDayPhase);
    color += vec3(0.78, 0.94, 1.0) * (1.0 - smoothstep(0.0, 1.0, uv.y)) * 0.08 * sunAmount * (1.0 - transition * 0.55);
    color += vec3(0.86, 0.96, 1.0) * glow * 0.17 * sunAmount * (1.0 - transition);
    color += vec3(1.0, 0.60, 0.30) * glow * 0.22 * transition;
    color += vec3(1.0, 0.97, 0.78) * halo * 0.10 * sunAmount * (1.0 - transition);
    color += vec3(1.0, 0.48, 0.22) * halo * 0.16 * transition;
    color += mix(vec3(1.0), vec3(1.0, 0.66, 0.34), transition) * disk * (0.36 * (1.0 - transition) + 0.25 * transition);
    color += vec3(0.72, 0.88, 1.0) * moonGlow * 0.16 * moonAmount;
    color += vec3(0.92, 0.97, 1.0) * moonDisk * 0.32 * moonAmount;
    color += vec3(1.0, 0.78, 0.46) * ray * (0.018 * sunAmount * (1.0 - transition) + 0.018 * transition);
    color += vec3(0.92, 0.98, 1.0) * smoothstep(0.58, 0.95, dust) * 0.036;
    color = mix(color, color * vec3(0.72, 0.58, 0.62), transition * 0.22);
    return color;
  }
  if (uWeatherType < 2.5) {
    color = mix(color, vec3(0.35, 0.45, 0.48), 0.16 + cloud * 0.20);
    return color;
  }
  if (uWeatherType < 3.5) {
    color = mix(color, vec3(0.12, 0.23, 0.30), 0.24 + uIntensity * 0.16);
    return color;
  }
  if (uWeatherType < 4.5) {
    color = mix(color, vec3(0.045, 0.065, 0.09), 0.54);
    return color;
  }
  if (uWeatherType < 5.5) {
    color = mix(color, vec3(0.55, 0.67, 0.72), 0.22);
    return color;
  }
  if (uWeatherType < 6.5) {
    color = mix(color, vec3(0.52, 0.63, 0.66), 0.32);
    return color;
  }
  if (uWeatherType < 7.5) {
    color = mix(color, vec3(0.48, 0.50, 0.48), 0.30 + uIntensity * 0.12);
    return color;
  }
  if (uWeatherType < 8.5) {
    color = mix(color, vec3(0.58, 0.49, 0.34), 0.34 + uIntensity * 0.14);
    return color;
  }
  if (uWeatherType < 9.5) {
    color = mix(color, vec3(0.72, 0.43, 0.20), 0.18 + uIntensity * 0.10);
    return color;
  }
  if (uWeatherType < 10.5) {
    color = mix(color, vec3(0.62, 0.78, 0.88), 0.22);
    return color;
  }
  return mix(color, vec3(0.36, 0.48, 0.52), 0.12);
}

float cloudMask(vec2 uv) {
  vec2 flow = vec2(uTime * 0.014 * uWind, uTime * 0.004);
  vec2 warped = uv * vec2(2.0, 1.05) + flow;
  float large = fbm(warped * 2.2);
  vec2 domain = vec2(fbm(warped * 3.0 + 5.0), fbm(warped * 3.0 - 2.0));
  float detail = fbm(warped * 4.5 + domain * 1.6);
  float high = smoothstep(0.36, 0.78, 1.0 - uv.y);
  return smoothstep(0.44, 0.78, large * 0.62 + detail * 0.48) * high;
}

float fogMask(vec2 uv) {
  vec2 flow = vec2(uTime * 0.016 * uWind, uTime * 0.003);
  float low = smoothstep(0.22, 0.98, uv.y);
  float veilA = fbm(vec2(uv.x * 2.0, uv.y * 5.0) + flow);
  float veilB = fbm(vec2(uv.x * 4.0 + 9.0, uv.y * 2.5) - flow * 0.7);
  return smoothstep(0.30, 0.82, veilA * 0.62 + veilB * 0.38) * low;
}

float dustMask(vec2 uv) {
  vec2 flow = vec2(uTime * (0.055 + uIntensity * 0.025) * max(abs(uWind), 0.25), uTime * 0.006);
  float lower = smoothstep(0.12, 0.98, uv.y);
  float veil = fbm(vec2(uv.x * 3.2, uv.y * 5.4) + flow);
  float grain = noise(uv * vec2(90.0, 70.0) + vec2(uTime * 1.8, -uTime * 0.2));
  return smoothstep(0.38, 0.86, veil * 0.78 + grain * 0.22) * lower;
}

float heatMask(vec2 uv) {
  float shimmer = fbm(vec2(uv.x * 12.0 + sin(uv.y * 18.0 + uTime * 0.45) * 0.32, uv.y * 6.0 - uTime * 0.35));
  float vertical = 1.0 - smoothstep(0.24, 1.0, uv.y);
  return smoothstep(0.48, 0.86, shimmer) * vertical;
}

float capsule(vec2 p, vec2 a, vec2 b, float radius) {
  vec2 pa = p - a;
  vec2 ba = b - a;
  float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
  return length(pa - ba * h) - radius;
}

float rainDropMask(vec2 local, float lane) {
  vec2 drop = local;
  drop.x *= 3.95;
  drop.y *= 1.18;
  drop.x -= drop.y * 0.012 * sign(uWind);
  float streak = 1.0 - smoothstep(0.0, 0.023, capsule(drop, vec2(0.0, -0.145), vec2(0.0, 0.092), 0.010));
  float core = 1.0 - smoothstep(0.0, 0.013, capsule(drop, vec2(0.0, -0.095), vec2(0.0, 0.052), 0.0045));
  float shine = 1.0 - smoothstep(0.0, 0.013, length(drop - vec2(-0.007, 0.014)));
  float glint = smoothstep(0.990, 1.0, sin(lane * 53.0 + uTime * 0.95));
  return streak * 0.56 + core * 0.24 + shine * (0.12 + glint * 0.08);
}

float rainLayer(vec2 uv, float scale, float speed, float slant, float threshold) {
  vec2 p = uv;
  p.x += p.y * slant;
  p.y -= uTime * speed;
  p *= scale;
  vec2 cell = floor(vec2(p.x, p.y * 0.42));
  float col = hash(cell);
  float lane = hash(cell + 17.0);
  vec2 local = fract(p + vec2(col * 0.32, col)) - 0.5;
  float mask = rainDropMask(local, lane);
  float dropout = smoothstep(0.48 + threshold, 0.98, lane);
  float verticalFade = smoothstep(0.02, 0.18, uv.y) * (1.0 - smoothstep(0.18, 1.0, uv.y));
  return mask * dropout * verticalFade;
}

float snowArm(vec2 p, float angle, float radius) {
  vec2 dir = vec2(cos(angle), sin(angle));
  vec2 normal = vec2(-dir.y, dir.x);
  float along = dot(p, dir);
  float across = abs(dot(p, normal));
  float width = radius * 0.055;
  float lengthMask = 1.0 - smoothstep(radius * 0.24, radius * 1.12, abs(along));
  float widthMask = 1.0 - smoothstep(0.0, width, across);
  return widthMask * lengthMask;
}

float snowLayer(vec2 uv) {
  float result = 0.0;
  float aspect = uSize.x / max(uSize.y, 1.0);
  float density = clamp(uIntensity, 0.0, 1.0);
  float bottomFade = 1.0 - smoothstep(0.78, 0.96, uv.y);
  for (int i = 0; i < 3; i++) {
    float layer = float(i);
    vec2 p = uv;
    float sway = sin(uTime * (0.18 + layer * 0.035) + uv.y * (4.0 + layer * 0.6) + layer);
    float softGust = fbm(vec2(uv.y * 2.4 + layer, uTime * 0.040)) - 0.5;
    p.x += sway * (0.0035 + layer * 0.002 + density * 0.003) + softGust * (0.004 + density * 0.005);
    p.x -= uTime * uWind * (0.0007 + layer * 0.0006 + density * 0.0008);
    p.y -= uTime * (0.0070 + layer * 0.0038 + density * 0.0085);
    p *= (4.8 + density * 2.0) + layer * (3.2 + density * 1.0);
    vec2 cell = floor(p);
    vec2 local = fract(p) - 0.5;
    float h = hash(cell + layer * 13.0);
    float visible = smoothstep(0.82 - density * 0.16, 0.996, hash(cell + 41.0));
    local += vec2(h - 0.5, fract(h * 7.1) - 0.5) * 0.44;
    float radius = 0.033 + layer * 0.010 + h * 0.018;
    vec2 shape = vec2(local.x * aspect, local.y);
    float dist = length(shape);
    float core = 1.0 - smoothstep(radius * 0.42, radius, dist);
    float glow = (1.0 - smoothstep(radius * 0.74, radius * 1.38, dist)) * 0.20;
    float starSeed = smoothstep(0.972 - density * 0.018, 0.998, h);
    float starRadius = radius * (1.95 + layer * 0.14);
    float star = (
      snowArm(shape, 0.0, starRadius) +
      snowArm(shape, 1.0471976, starRadius) +
      snowArm(shape, -1.0471976, starRadius)
    ) * starSeed * 0.42;
    float layerOpacity = (0.46 + density * 0.18) - layer * 0.070;
    result += (core * 0.92 + glow + star) * visible * layerOpacity * bottomFade;
  }
  return clamp(result, 0.0, 1.0);
}

float lightning(vec2 uv) {
  if (uWeatherType < 3.5 || uWeatherType > 4.5) {
    return 0.0;
  }
  float period = 8.7;
  float window = floor(uTime / period);
  float local = fract(uTime / period);
  float chance = hash(vec2(window, 23.0));
  if (chance < 0.64) {
    return 0.0;
  }
  float start = 0.12 + hash(vec2(window, 37.0)) * 0.58;
  float age = (local - start) * period;
  if (age < 0.0 || age > 0.16) {
    return 0.0;
  }
  float fade = 1.0 - age / 0.16;
  float pulse = fade * fade * (0.68 + 0.32 * (1.0 - smoothstep(0.0, 0.05, abs(age - 0.055))));
  vec2 p = uv - vec2(0.40 + hash(vec2(window, 3.0)) * 0.28, 0.05);
  float bolt = 0.0;
  float x = 0.0;
  for (int i = 0; i < 5; i++) {
    float y0 = float(i) * 0.10;
    float y1 = y0 + 0.12;
    float seg = smoothstep(y0 - 0.02, y0 + 0.02, p.y) *
        (1.0 - smoothstep(y1 - 0.02, y1 + 0.02, p.y));
    x += (hash(vec2(float(i), window)) - 0.5) * 0.052;
    bolt += seg * (1.0 - smoothstep(0.0, 0.020, abs(p.x - x)));
  }
  return bolt * pulse;
}

void main() {
  vec2 uv = FlutterFragCoord().xy / uSize;
  vec3 color = gradientSky(uv);
  float cloud = cloudMask(uv);
  color = weatherTint(color, uv, cloud);
  float snowOverlay = 0.0;

  if (uWeatherType > 1.5 && uWeatherType < 4.5) {
    vec3 cloudColor = uWeatherType > 3.5 ? vec3(0.18, 0.22, 0.25) : vec3(0.66, 0.77, 0.78);
    color = mix(color, cloudColor, cloud * (0.18 + uIntensity * 0.22));
  }

  if (uWeatherType > 2.5 && uWeatherType < 4.5) {
    float slant = 0.026 * uWind;
    float shower = 0.82 + 0.18 * sin(uTime * 0.47 + fbm(vec2(uTime * 0.035, 4.0)) * 6.283);
    float rain = rainLayer(uv, 15.0, 0.086 + uIntensity * 0.126, slant, 0.080);
    rain += rainLayer(uv + vec2(0.23, 0.0), 23.0, 0.124 + uIntensity * 0.166, slant, 0.060);
    rain += rainLayer(uv + vec2(0.47, 0.0), 31.0, 0.168 + uIntensity * 0.194, slant, 0.048) * 0.38;
    color += vec3(0.78, 0.92, 1.0) * rain * shower * (0.14 + uIntensity * 0.24);
    color += vec3(1.0) * rain * 0.028;
    color = mix(color, vec3(0.08, 0.14, 0.18), smoothstep(0.45, 1.0, uv.y) * 0.13);
  }

  if (uWeatherType > 4.5 && uWeatherType < 5.5) {
    color = mix(color, vec3(0.52, 0.62, 0.66), smoothstep(0.58, 1.0, uv.y) * 0.10);
    float snow = snowLayer(uv);
    snowOverlay = max(snowOverlay, snow);
  }

  if (uWeatherType > 5.5 && uWeatherType < 6.5) {
    float fog = fogMask(uv);
    color = mix(color, vec3(0.58, 0.68, 0.70), fog * 0.52);
  } else if (uWeatherType > 6.5 && uWeatherType < 7.5) {
    float haze = fogMask(uv);
    color = mix(color, vec3(0.56, 0.57, 0.54), haze * (0.36 + uIntensity * 0.18));
    color = mix(color, vec3(0.38, 0.40, 0.39), smoothstep(0.45, 1.0, uv.y) * 0.10);
  } else if (uWeatherType > 7.5 && uWeatherType < 8.5) {
    float dust = dustMask(uv);
    color = mix(color, vec3(0.68, 0.55, 0.34), dust * (0.32 + uIntensity * 0.22));
    color += vec3(0.78, 0.62, 0.34) * smoothstep(0.72, 0.96, dust) * 0.055;
  } else if (uWeatherType > 8.5 && uWeatherType < 9.5) {
    float heat = heatMask(uv);
    color = mix(color, vec3(0.78, 0.45, 0.20), heat * 0.16);
    color += vec3(1.0, 0.64, 0.30) * heat * 0.045;
  } else if (uWeatherType > 9.5 && uWeatherType < 10.5) {
    float cold = fogMask(uv) * 0.45;
    float snow = snowLayer(uv) * 0.34;
    color = mix(color, vec3(0.58, 0.76, 0.86), cold * 0.22);
    snowOverlay = max(snowOverlay, snow * 0.66);
  } else if (uWeatherType > 2.5 && uWeatherType < 5.5) {
    float mist = fogMask(uv) * 0.42;
    color = mix(color, vec3(0.55, 0.65, 0.68), mist * (0.18 + uIntensity * 0.18));
  }

  float bolt = lightning(uv);
    color += vec3(0.78, 0.88, 1.0) * bolt * 0.58;
    color += vec3(1.0) * bolt * 0.055;

  float vignette = 1.0 - smoothstep(0.18, 0.95, length(uv - vec2(0.52, 0.48)));
  color *= 0.72 + vignette * 0.34;
  color = mix(color, color * vec3(0.62, 0.72, 0.94), smoothstep(0.58, 1.0, uDayPhase) * 0.20);
  color = mix(color, vec3(1.0), clamp(snowOverlay * 0.90, 0.0, 0.78));
  color += vec3(1.0) * snowOverlay * 0.10;
  fragColor = vec4(color, 1.0);
}
