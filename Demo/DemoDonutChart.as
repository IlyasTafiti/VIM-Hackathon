// DemoDonutChart.as - Interactive donut chart with click-to-select
//
// Based on the built-in DonutChart card widget, extended with:
// - Click callback for element selection
// - Visual highlight on selected segment
// - Improved label handling for long text

#include "../widgets/cards/Card.as"
#include "../widgets/cards/CardUtils.as"
#include "DemoCardTypes.as"

class DemoDonutChart : Card
{
    array<CardItem> items;

    // Callbacks
    CardItemClickCallback@ onItemClicked = null;
    CardColorCallback@ onColorClicked = null;
    CardShuffleCallback@ onShuffleClicked = null;
    int selectedIndex = -1;
    bool colorsApplied = false;

    // Chart sizing - 0 means auto-fit to available space
    float chartRadius    = 0.0f;
    float ringThickness  = 0.0f;  // 0 = auto (30% of radius)
    float gapAngle       = 0.02f; // radians gap between segments
    int   arcSegments    = 64;

    // Legend
    float legendDotRadius = 5.0f;
    float legendSpacing   = 20.0f;
    float legendGap       = 6.0f;
    int   legendMaxChars  = 28;

    // Hover
    float hoverGrow = 4.0f;

    // Selection highlight
    float selectedGrow = 6.0f;

    DemoDonutChart()
    {
        super();
        paddingX = 16.0f;
        paddingY = 12.0f;
        rounding = 10.0f;
        glowEnabled = true;
    }

    void RenderHeaderControls() override
    {
        if (onColorClicked is null) return;

        // Icon codes (Segoe MDL2 Assets)
        string iconShuffle = "\xEE\xA2\xB1";  // E8B1 = shuffle
        string iconColor   = "\xEE\x9E\x90";  // E790 = color palette
        string iconClear   = "\xEF\x95\xB0";  // F570 = clear

        string colorHover = colorsApplied ? "Clear Colors" : "Apply Colors";

        // Measure both buttons for right-alignment
        float2 shuffleSize = Style::GetIconButtonSize(iconShuffle);
        float2 colorSize = Style::GetIconButtonSize(iconColor);
        float spacing = ImGui::GetStyle().ItemSpacing.x;
        float totalW = shuffleSize.x + spacing + colorSize.x;

        float availX = ImGui::GetContentRegionAvail().x;
        float rightPad = headerPadX;
        if (availX > totalW + rightPad)
            ImGui::SetCursorPosX(ImGui::GetCursorPosX() + availX - totalW - rightPad);

        // Shuffle button
        color iconTextColor = Style::GetColorText();
        string shuffleId = iconShuffle + "##shuffle_" + title;
        if (VimFlex::IconButtonTransparent(shuffleId, iconTextColor, true, float2(0, 0), "Shuffle Colors"))
        {
            if (onShuffleClicked !is null)
                onShuffleClicked();
        }

        ImGui::SameLine();

        // Color/Clear toggle button
        string colorId = iconColor + "##color_" + title;
        if (VimFlex::IconButtonTransparentToggle(colorId, iconTextColor, colorsApplied, true, float2(0, 0), colorHover))
        {
            onColorClicked();
        }
    }

    bool RenderBody(const float2&in dims) override
    {
        if (items.length() == 0)
        {
            ImGui::TextDisabled("No data");
            return false;
        }

        float total = 0;
        for (uint i = 0; i < items.length(); i++)
            total += items[i].value;

        if (total <= 0)
        {
            ImGui::TextDisabled("No data");
            return false;
        }

        auto@ dl = ImGui::GetWindowDrawList();
        float2 origin = ImGui::GetCursorScreenPos();

        // Auto-size radius to fit available width
        float radius = chartRadius;
        if (radius <= 0)
            radius = dims.x * 0.32f;

        // Constrain radius by available height when fillHeight is active
        if (dims.y > 0)
        {
            // Give donut 65% of space, legend gets 35%
            float donutSpace = dims.y * 0.65f;
            float overhead = 8.0f + selectedGrow;
            float maxRadius = (donutSpace - overhead) * 0.5f;
            if (maxRadius > 0 && maxRadius < radius)
                radius = maxRadius;
        }

        if (radius < 30) radius = 30;

        float thickness = ringThickness;
        if (thickness <= 0)
            thickness = radius * 0.30f;
        if (thickness > radius - 10) thickness = radius - 10;

        // Center the donut horizontally
        float centerX = origin.x + dims.x * 0.5f;
        float centerY = origin.y + radius + 8.0f;
        float2 center = float2(centerX, centerY);

        float outerR = radius;
        float innerR = radius - thickness;
        if (innerR < 10) innerR = 10;

        float PI = 3.14159265f;
        float startAngle = -PI * 0.5f; // start from top

        int hoveredIndex = -1;

        // Detect hover
        float2 mousePos = ImGui::GetMousePos();
        float dx = mousePos.x - centerX;
        float dy = mousePos.y - centerY;
        float mouseDist = Math::Sqrt(dx * dx + dy * dy);
        float mouseAngle = Math::ATan2(dy, dx);

        if (mouseAngle < startAngle)
            mouseAngle += 2.0f * PI;

        float maxGrow = Math::Max(hoverGrow, selectedGrow);
        if (mouseDist >= innerR - maxGrow && mouseDist <= outerR + maxGrow)
        {
            float checkAngle = startAngle;
            for (uint i = 0; i < items.length(); i++)
            {
                float fraction = items[i].value / total;
                float sweep = fraction * 2.0f * PI;
                float segStart = checkAngle + gapAngle * 0.5f;
                float segEnd = checkAngle + sweep - gapAngle * 0.5f;

                float normMouse = mouseAngle;
                float normStart = segStart;
                float normEnd = segEnd;

                if (normStart < startAngle) normStart += 2.0f * PI;
                if (normEnd < startAngle) normEnd += 2.0f * PI;
                if (normMouse < startAngle) normMouse += 2.0f * PI;

                if (normMouse >= normStart && normMouse <= normEnd)
                {
                    hoveredIndex = int(i);
                    break;
                }

                checkAngle += sweep;
            }
        }

        // Handle click
        if (hoveredIndex >= 0 && ImGui::IsMouseClicked(ImGuiMouseButton_ImGuiMouseButton_Left))
        {
            selectedIndex = hoveredIndex;
            if (onItemClicked !is null)
            {
                onItemClicked(hoveredIndex, items[hoveredIndex].label);
            }
        }

        // Draw segments
        float angle = startAngle;
        for (uint i = 0; i < items.length(); i++)
        {
            float fraction = items[i].value / total;
            float sweep = fraction * 2.0f * PI;

            float segStart = angle + gapAngle * 0.5f;
            float segEnd = angle + sweep - gapAngle * 0.5f;

            if (segEnd <= segStart)
            {
                angle += sweep;
                continue;
            }

            bool isHovered = (int(i) == hoveredIndex);
            bool isSelected = (int(i) == selectedIndex);

            float oR = outerR;
            float iR = innerR;
            if (isSelected)
            {
                oR += selectedGrow;
                iR -= selectedGrow * 0.5f;
            }
            else if (isHovered)
            {
                oR += hoverGrow;
                iR -= hoverGrow * 0.5f;
            }

            DrawArcSegment(dl, center, iR, oR, segStart, segEnd,
                items[i].itemColor, isHovered || isSelected);

            // Draw selection outline for selected segment
            if (isSelected)
            {
                DrawArcOutline(dl, center, oR, segStart, segEnd,
                    color(255, 255, 255, 180), 2.0f);
            }

            angle += sweep;
        }

        // Center text showing selected item
        if (selectedIndex >= 0 && selectedIndex < int(items.length()))
        {
            string centerText = CardFormatInt(int(items[selectedIndex].value));
            ImGui::PushFont(Style::GetFontBoldLarge());
            float2 textSize = ImGui::CalcTextSize(centerText);
            float2 textPos = float2(centerX - textSize.x * 0.5f, centerY - textSize.y * 0.5f);
            dl.AddText(textPos, items[selectedIndex].itemColor, centerText);
            ImGui::PopFont();
        }

        // Tooltip on hover
        if (hoveredIndex >= 0)
        {
            float pct = 100.0f * items[hoveredIndex].value / total;
            ImGui::BeginTooltip();
            ImGui::PushStyleColor(ImGuiCol_Text, items[hoveredIndex].itemColor);
            ImGui::Text(items[hoveredIndex].label);
            ImGui::PopStyleColor();
            ImGui::Separator();
            ImGui::Text("Count: " + CardFormatInt(int(items[hoveredIndex].value)));
            ImGui::Text("Share: " + CardFormatPercent(pct, 1));
            ImGui::EndTooltip();
        }

        // Legend - wrapping horizontal rows
        float donutBottom = centerY + outerR + selectedGrow + 12.0f;
        float lineHeight = ImGui::GetTextLineHeight();
        float maxRowW = dims.x;

        // Calculate max legend Y boundary
        float legendMaxY = origin.y + dims.y - 8.0f;
        if (dims.y <= 0)
            legendMaxY = origin.y + 10000.0f; // no constraint

        // Measure item widths
        uint itemCount = items.length();
        array<float> itemWidths(itemCount);
        for (uint i = 0; i < itemCount; i++)
        {
            string lbl = TruncateLabel(items[i].label);
            float2 textSize = ImGui::CalcTextSize(lbl);
            float itemW = legendDotRadius * 2.0f + legendGap + textSize.x;
            itemWidths[i] = itemW;
        }

        // Render legend items, wrapping as needed, stopping if out of space
        float curX = 0;
        float curY = donutBottom;
        uint rowStart = 0;
        bool legendTruncated = false;

        for (uint i = 0; i < items.length(); i++)
        {
            float itemW = itemWidths[i] + (i < items.length() - 1 ? legendSpacing : 0);

            if (curX + itemWidths[i] > maxRowW && curX > 0)
            {
                // Check if this row fits
                if (curY + lineHeight > legendMaxY)
                {
                    legendTruncated = true;
                    break;
                }
                RenderLegendRow(dl, origin.x, curY, dims.x, rowStart, i, itemWidths, lineHeight);
                curY += lineHeight + 4.0f;
                curX = 0;
                rowStart = i;
            }

            curX += itemW;
        }

        // Render last row if it fits
        if (!legendTruncated && rowStart < items.length() && curY + lineHeight <= legendMaxY)
            RenderLegendRow(dl, origin.x, curY, dims.x, rowStart, items.length(), itemWidths, lineHeight);

        float legendBottom = curY + lineHeight;

        // Final dummy to claim the full height
        float totalH = legendBottom - origin.y + 8.0f;
        ImGui::SetCursorScreenPos(origin);
        ImGui::Dummy(float2(dims.x, totalH));

        return false;
    }

    private void RenderLegendRow(ImGui::ImDrawList@ dl, float originX, float y,
        float availW, uint startIdx, uint endIdx, array<float>& itemWidths, float lineH)
    {
        // Calculate row width
        float rowW = 0;
        for (uint i = startIdx; i < endIdx; i++)
        {
            rowW += itemWidths[i];
            if (i < endIdx - 1) rowW += legendSpacing;
        }

        float x = originX + (availW - rowW) * 0.5f;

        for (uint i = startIdx; i < endIdx; i++)
        {
            bool isSelected = (int(i) == selectedIndex);
            bool isHovered = false;

            // Invisible button for click detection over the entire legend item
            ImGui::SetCursorScreenPos(float2(x, y));
            string btnId = "##legend_" + i;
            if (ImGui::InvisibleButton(btnId, float2(itemWidths[i], lineH)))
            {
                selectedIndex = int(i);
                if (onItemClicked !is null)
                    onItemClicked(int(i), items[i].label);
            }
            isHovered = ImGui::IsItemHovered();
            if (isHovered)
                ImGui::SetMouseCursor(int(ImGuiMouseCursor::ImGuiMouseCursor_Hand));

            // Dot
            float dotCY = y + lineH * 0.5f;
            float dotR = isSelected ? legendDotRadius + 2.0f : legendDotRadius;
            if (isHovered && !isSelected) dotR = legendDotRadius + 1.0f;
            dl.AddCircleFilled(float2(x + legendDotRadius, dotCY),
                dotR, items[i].itemColor, 12);

            // Label
            string lbl = TruncateLabel(items[i].label);
            float textX = x + legendDotRadius * 2.0f + legendGap;
            color textCol = (isSelected || isHovered) ? CardTextPrimary() : CardTextSecondary();
            dl.AddText(float2(textX, y), textCol, lbl);

            x += itemWidths[i] + legendSpacing;
        }
    }

    private string TruncateLabel(const string&in label)
    {
        if (int(label.length()) <= legendMaxChars)
            return label;
        return label.substr(0, legendMaxChars - 3) + "...";
    }

    private void DrawArcSegment(ImGui::ImDrawList@ dl, const float2&in center,
        float innerR, float outerR, float startAng, float endAng,
        const color&in col, bool highlighted)
    {
        color fillColor = highlighted ? BrightenColor(col) : col;

        int totalPoints = 2 * (arcSegments + 1);
        array<float2> points(totalPoints);
        // Outer arc forward
        for (int i = 0; i <= arcSegments; i++)
        {
            float a = startAng + (endAng - startAng) * float(i) / float(arcSegments);
            points[i] = float2(
                center.x + Math::Cos(a) * outerR,
                center.y + Math::Sin(a) * outerR);
        }
        // Inner arc backward
        for (int i = arcSegments; i >= 0; i--)
        {
            float a = startAng + (endAng - startAng) * float(i) / float(arcSegments);
            points[arcSegments + 1 + (arcSegments - i)] = float2(
                center.x + Math::Cos(a) * innerR,
                center.y + Math::Sin(a) * innerR);
        }

        dl.AddConcavePolyFilled(points, fillColor);
    }

    private void DrawArcOutline(ImGui::ImDrawList@ dl, const float2&in center,
        float radius, float startAng, float endAng,
        const color&in col, float lineThickness)
    {
        for (int i = 0; i < arcSegments; i++)
        {
            float a0 = startAng + (endAng - startAng) * float(i) / float(arcSegments);
            float a1 = startAng + (endAng - startAng) * float(i + 1) / float(arcSegments);
            float2 p0 = float2(center.x + Math::Cos(a0) * radius, center.y + Math::Sin(a0) * radius);
            float2 p1 = float2(center.x + Math::Cos(a1) * radius, center.y + Math::Sin(a1) * radius);
            dl.AddLine(p0, p1, col, lineThickness);
        }
    }

    private color BrightenColor(const color&in c)
    {
        uint8 r = c.x + uint8((255 - c.x) / 4);
        uint8 g = c.y + uint8((255 - c.y) / 4);
        uint8 b = c.z + uint8((255 - c.z) / 4);
        return color(r, g, b, c.w);
    }
}
