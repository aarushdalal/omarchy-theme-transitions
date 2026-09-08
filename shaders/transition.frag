#version 440

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float progress;
    int mode;
    float aspect;
    vec4 accent;
};

layout(binding = 1) uniform sampler2D source;
layout(binding = 2) uniform sampler2D incoming;

void main() {
    vec2 uv = qt_TexCoord0;
    vec4 colOld = texture(source, uv);
    vec4 colNew = texture(incoming, uv);
    vec4 result = colOld;

    if (mode == 0) {
        // Mode 0: Color Morph (Pure hardware crossfade)
        result = mix(colOld, colNew, progress);
    } else if (mode == 1) {
        // Mode 1: Aurora Flow (Diagonal sweeping borealis wave with luminous beam)
        float slant = 0.45;
        float front = (progress * 1.6 - 0.3) + (uv.y - 0.5) * slant;
        float m = smoothstep(front - 0.015, front + 0.015, uv.x);
        float d1 = (uv.x - front) * 12.0;
        float beam = exp(-d1 * d1) * 0.45;
        float d2 = (uv.x - front) * 80.0;
        float shimmer = exp(-d2 * d2) * 0.7 * (1.0 - abs(progress - 0.5) * 2.0);
        vec4 auroraColor = mix(accent, vec4(1.0, 1.0, 1.0, 1.0), shimmer * 0.5);
        result = mix(colNew, colOld, m) + auroraColor * (beam + shimmer);
    } else if (mode == 2) {
        // Mode 2: Ink Spread (Radial fluid blossom expanding from center)
        vec2 d = (uv - vec2(0.5, 0.5)) * vec2(aspect, 1.0);
        float r = length(d);
        float maxR = 1.35 * progress;
        float m = smoothstep(maxR - 0.02, maxR + 0.02, r);
        float dr = (r - maxR) * 35.0;
        float ring = exp(-dr * dr) * (1.0 - progress) * 0.8;
        result = mix(colNew, colOld, m) + accent * ring;
    } else if (mode == 3) {
        // Mode 3: Prism Shift (Corner diagonal sweep with chromatic dispersion)
        float d = (uv.x * aspect + uv.y) / (aspect + 1.0);
        float sweep = progress * 1.25;
        float m = smoothstep(sweep - 0.02, sweep + 0.02, d);
        float disp = sin(progress * 3.14159) * 0.012;
        vec2 off = vec2(disp, disp * 0.5);
        float rCol = texture(incoming, uv - off).r;
        float gCol = colNew.g; // Reuse already sampled green channel
        float bCol = texture(incoming, uv + off).b;
        vec4 dispNew = vec4(rCol, gCol, bCol, colNew.a);
        float ds = (d - sweep) * 25.0;
        float sheen = exp(-ds * ds) * sin(progress * 3.14159) * 0.5;
        result = mix(dispNew, colOld, m) + accent * sheen;
    } else if (mode == 4) {
        // Mode 4: Liquid Transform (Viscous elastic fluid boundary)
        vec2 d = (uv - vec2(0.5, 0.5)) * vec2(aspect, 1.0);
        float angle = atan(d.y, d.x);
        float wobble = sin(angle * 6.0 + progress * 8.0) * 0.035 * (1.0 - progress);
        float r = length(d) + wobble;
        float maxR = 1.4 * progress;
        float m = smoothstep(maxR - 0.025, maxR + 0.025, r);
        float dm = (r - maxR) * 25.0;
        float meniscus = exp(-dm * dm) * (1.0 - progress) * 0.7;
        result = mix(colNew, colOld, m) + accent * meniscus;
    } else if (mode == 5) {
        // Mode 5: Atmospheric Fade (Cinematic luminance exposure dip and bloom)
        float dip = 1.0 - sin(progress * 3.14159) * 0.35;
        vec4 dippedOld = colOld * dip;
        float bloom = sin(progress * 3.14159) * 0.15;
        result = mix(dippedOld, colNew, progress) + accent * bloom;
    } else if (mode == 6) {
        // Mode 6: Material Repaint (Precision architectural CAD laser scan curtain)
        float scanY = progress;
        float m = step(uv.y, scanY);
        float dy = (uv.y - scanY) * 120.0;
        float laser = exp(-dy * dy) * 1.2;
        float trail = clamp((scanY - uv.y) * 8.0, 0.0, 1.0) * (1.0 - progress) * 0.15;
        vec4 laserCol = mix(accent, vec4(1.0, 1.0, 1.0, 1.0), laser * 0.6);
        result = mix(colOld, colNew, m) + laserCol * laser + accent * trail;
    } else if (mode == 7) {
        // Mode 7: Reality Shift (Dimensional quantum phase slice wave)
        float sliceY = progress;
        float m = step(uv.y, sliceY);
        float dist = abs(uv.y - sliceY);
        float glitch = (dist < 0.03) ? sin(uv.y * 180.0) * 0.02 * sin(progress * 3.14159) : 0.0;
        vec4 glitchedNew = (abs(glitch) > 0.0001) ? texture(incoming, vec2(uv.x + glitch, uv.y)) : colNew;
        float ds = dist * 90.0;
        float slice = exp(-ds * ds);
        result = mix(colOld, glitchedNew, m) + vec4(1.0, 1.0, 1.0, 1.0) * slice * 0.8 + accent * slice * 0.4;
    } else {
        // Fallback: Slanted wipe
        float slant = -0.18;
        float center = 0.5 + (uv.y - 0.5) * slant;
        float reach = 0.5 + abs(slant) * 0.5 + 0.02;
        float spread = reach * progress;
        float left = center - spread;
        float right = center + spread;
        float m = (uv.x >= left && uv.x <= right) ? 1.0 : 0.0;
        result = mix(colOld, colNew, m);
    }

    fragColor = result * qt_Opacity;
}
