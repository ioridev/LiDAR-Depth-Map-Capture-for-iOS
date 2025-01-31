#include <metal_stdlib>
using namespace metal;

float3 hue2rgb(float hue) {
    float r = fabs(hue * 6.0 - 3.0) - 1.0;
    float g = 2.0 - fabs(hue * 6.0 - 2.0);
    float b = 2.0 - fabs(hue * 6.0 - 4.0);
    return saturate(float3(r, g, b));
}

inline float3 colorForValue(float normalized)
{
    // near=red => normalized=0 => hue=0.0
    // far=blue => normalized=1 => hue=0.66
    float hue = 0.66 * clamp(normalized, 0.0, 1.0);
    return hue2rgb(hue);
}

// use the allowed classes to determine whether to leave original or not
// allowed_classes = [8, 7, 1, 19, 25, 22, 18, 21, 3, 6, 9, 2, 5, 23, 112, 4, 24)
kernel void SemanticMapToColor(texture2d<uint, access::read> semantic_map [[ texture(0) ]],
                               texture2d<float, access::read> depth_map [[ texture(1) ]],
                               texture2d<float, access::read_write> image [[ texture(2) ]],
                               const device float &min_depth        [[ buffer(0) ]],
                               const device float &max_depth        [[ buffer(1) ]],
                               const device uint  &n_classes        [[ buffer(2) ]],
                               uint2 gid [[thread_position_in_grid]]) {
    uint class_id = semantic_map.read(gid).r;

    // Hardcoded allowed_classes
    constexpr uint allowed_classes[] = {8, 7, 1, 19, 25, 22, 18, 21, 3, 6, 9, 2, 5, 23, 112, 4, 24};
    constexpr uint allowed_classes_count = sizeof(allowed_classes) / sizeof(uint);

    // Check if class_id is in allowed_classes
    bool is_allowed = false;
    for (uint i = 0; i < allowed_classes_count; ++i) {
        if (allowed_classes[i] == class_id) {
            is_allowed = true;
            break;
        }
    }

    // Calculate new color based on class_id
    float hue = float(class_id) / float(n_classes);
    float3 new_rgb = hue2rgb(hue);

    // Read the original color
    float3 original_rgb = image.read(gid).rgb;

    // Read from the depth map
    float raw_depth = depth_map.read(gid).r;
    float normalized_depth = (raw_depth - min_depth) / (max_depth - min_depth);

    // Update the "original" with depth map colors no matter what
    float3 depth_color = is_allowed ? mix(original_rgb, colorForValue(normalized_depth), 0.8) : mix(original_rgb, colorForValue(normalized_depth), 0.3);

    // Blend the colors if allowed, otherwise keep the original
    float3 final_rgb = is_allowed ? mix(depth_color, new_rgb, 0.1) : depth_color;

    // Write the resulting color back to the image
    image.write(float4(final_rgb, 1.0), gid);
}
