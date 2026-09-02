shader_type sky;

uniform vec3 sky_top_color : source_color = vec3(0.385, 0.454, 0.55);
uniform vec3 sky_horizon_color : source_color = vec3(0.646, 0.655, 0.67);
uniform vec3 ground_color : source_color = vec3(0.2, 0.169, 0.133);
// Elevation of the sun disc above the horizon — set this directly, fully
// independent of whatever angle the actual DirectionalLight3D is tilted to
// for shadow/bounce-lighting purposes.
uniform float sun_angle : hint_range(0.0, 90.0) = 15.0;
// Compass-direction (azimuth) of the sun, as a horizontal XZ vector. Set
// every frame by sun_orbit.gd from the light's own horizontal facing, so
// the sun disc sweeps around the sky in sync with the light's rotation —
// while sun_angle above keeps its height independent of the light's tilt.
uniform vec2 sun_azimuth_dir = vec2(1.0, 0.0);
uniform float cloud_density : hint_range(0.0, 1.0) = 0.5;
uniform float cloud_speed_1 : hint_range(0.0, 2.0) = 0.1;
uniform float cloud_speed_2 : hint_range(0.0, 2.0) = 0.07;
uniform vec2 cloud_dir_1 = vec2(1.0, 1.0);
uniform vec2 cloud_dir_2 = vec2(-1.0, 1.0);
uniform float cloud_aspect : hint_range(0.02, 2.0) = 1.0;
uniform vec3 cloud_color_1 : source_color = vec3(0.8, 0.9, 1.0);
uniform vec3 cloud_color_2 : source_color = vec3(1.0, 0.9, 0.8);
uniform sampler2D noise_texture;
uniform sampler2D sun_texture;
uniform vec2 cloud_scale_1 = vec2(1.0, 1.0);
uniform vec2 cloud_scale_2 = vec2(1.0, 1.0);

// Ground mottling — reuses noise_texture (no separate texture to assign).
// Unlike the cloud projection above (safe for dir.y > 0, representing
// something far overhead), this one is safe for dir.y < 0 because the ground
// really is a flat plane at a fixed height underfoot, so dividing by height
// is the geometrically correct projection here rather than an approximation.
uniform vec2 ground_texture_scale = vec2(0.3, 0.3);
uniform vec2 ground_texture_speed = vec2(0.0, 0.0);
uniform float ground_texture_strength : hint_range(0.0, 1.0) = 0.15;
uniform vec3 ground_texture_color : source_color = vec3(0.12, 0.1, 0.08);


vec3 get_sky_color(vec3 dir) {
    float horizon_factor = clamp(dir.y, -1.0, 1.0);
    float blend = smoothstep(-0.1, 0.2, horizon_factor);
    vec3 base_color = mix(ground_color, mix(sky_horizon_color, sky_top_color, blend), blend);

    // Fade clouds out near/below the horizon so they don't stretch into
    // noise once dir.xz/safe_y blows up down there.
    float sky_visibility = smoothstep(-0.05, 0.15, dir.y);

    // Mirror image of the cloud fade above, so the two meet exactly at the
    // horizon with no gap or overlap. There WILL be a seam where this
    // wraps around behind the camera — accepted tradeoff for texturing the
    // ground without adding real geometry — but ordinary texture
    // minification blurs it out near the horizon instead of sharpening it,
    // since the projected UV changes fastest per screen-pixel right there.
    float ground_visibility = 1.0 - sky_visibility;
    if (ground_visibility > 0.0) {
        float ground_safe_y = min(dir.y - 0.5, -0.01);
        vec2 ground_uv = dir.xz / ground_safe_y * ground_texture_scale + TIME * ground_texture_speed;
        float ground_noise = texture(noise_texture, ground_uv).r;
        base_color = mix(base_color, ground_texture_color, ground_noise * ground_texture_strength * ground_visibility);
    }

    float safe_y = max(dir.y + 0.5, 0.01);
    vec2 cloud_uv1 = dir.xz / safe_y * cloud_scale_1;
    cloud_uv1.x *= cloud_aspect;
    cloud_uv1 += TIME * cloud_speed_1 * cloud_dir_1;
    float noise1 = texture(noise_texture, cloud_uv1).r;
    float cloud_mask1 = smoothstep(1.0 - cloud_density, 1.0, noise1) * sky_visibility;

    vec2 cloud_uv2 = dir.xz / safe_y * cloud_scale_2;
    cloud_uv2.x *= cloud_aspect;
    cloud_uv2 += TIME * cloud_speed_2 * cloud_dir_2;
    float noise2 = texture(noise_texture, cloud_uv2).r;
    float cloud_mask2 = smoothstep(1.0 - cloud_density, 1.0, noise2) * sky_visibility;

    // Tint each cloud layer by its color
    vec3 cloud_tint_1 = mix(base_color, cloud_color_1, cloud_mask1 * 0.6);
    vec3 cloud_tint_2 = mix(base_color, cloud_color_2, cloud_mask2 * 0.6);

    // Blend both cloud layers
    vec3 final_color = max(cloud_tint_1, cloud_tint_2);

    // Sun disk — azimuth (compass direction) comes from the light via
    // sun_azimuth_dir, elevation comes purely from sun_angle. The two are
    // independent: this lets the light sit at whatever tilt looks best for
    // shadows while the visual sun keeps whatever height you dial in here.
    float sun_el = radians(sun_angle);
    vec2 az = length(sun_azimuth_dir) > 0.0001 ? normalize(sun_azimuth_dir) : vec2(1.0, 0.0);
    vec3 sun_direction = normalize(vec3(az.x * cos(sun_el), sin(sun_el), az.y * cos(sun_el)));
    float sun_size = 0.025; // Controls sun size (try adjusting for your texture)
    float angle_to_sun = acos(dot(normalize(dir), sun_direction));

    if (angle_to_sun < sun_size) {
        // Project direction onto sun disk for UV mapping
        vec3 rel = dir - sun_direction;
        vec3 up = abs(sun_direction.y) < 0.99 ? vec3(0.0, 1.0, 0.0) : vec3(1.0, 0.0, 0.0);
        vec3 right = normalize(cross(up, sun_direction));
        vec3 sun_up = normalize(cross(sun_direction, right));
        float u = dot(rel, right) / sun_size * 0.5 + 0.5;
        float v = dot(rel, sun_up) / sun_size * 0.5 + 0.5;
        if (u >= 0.0 && u <= 1.0 && v >= 0.0 && v <= 1.0) {
            vec2 sun_uv = vec2(u, v);
            vec4 sun_tex_color = texture(sun_texture, sun_uv);
            // Blend sun texture over sky using its alpha
            final_color = mix(final_color, sun_tex_color.rgb, sun_tex_color.a);
        }
    }



    return final_color;
}

void sky() {
    vec3 dir = normalize(EYEDIR);
    COLOR = get_sky_color(dir);
}