// DemoConstants.as - Color palette for BIM Analytics Dashboard

#include "../widgets/cards/CardUtils.as"

// Color palette for chart segments (vibrant and distinct).
// Ordered so that consecutive entries have maximum perceptual contrast.
// when applying color overrides via MaterialService.SetMaterialOverride().
const array<color> DEMO_PALETTE =
{
    color(74, 144, 217, 255),   // Blue
    color(244, 63, 94, 255),    // Rose
    color(52, 211, 153, 255),   // Emerald
    color(245, 158, 11, 255),   // Amber
    color(139, 92, 246, 255),   // Violet
    color(45, 212, 191, 255),   // Teal
    color(236, 72, 153, 255),   // Pink
    color(74, 222, 128, 255),   // Green
    color(251, 146, 60, 255),   // Orange
    color(96, 165, 250, 255),   // Light Blue
    color(248, 113, 113, 255),  // Red
    color(34, 211, 238, 255),   // Cyan
    color(167, 139, 250, 255),  // Lavender
    color(56, 189, 248, 255),   // Sky
    color(99, 102, 241, 255)    // Indigo
};

// Label and color for elements with no associated category/level/room
const string UNKNOWN_LABEL = "<unknown>";
const color UNKNOWN_COLOR = color(229, 229, 229, 255);//color(195, 221, 239, 255);

// Get a palette color by index with optional seed offset (wraps around).
// Returns UNKNOWN_COLOR if the label matches UNKNOWN_LABEL.
color GetDemoColor(uint index, uint seed = 0)
{
    return DEMO_PALETTE[(index + seed) % DEMO_PALETTE.length()];
}

color GetDemoColorForLabel(const string&in label, uint index, uint seed = 0)
{
    if (label == UNKNOWN_LABEL) return UNKNOWN_COLOR;
    return GetDemoColor(index, seed);
}
