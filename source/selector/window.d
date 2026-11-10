module selector.window;

import clay_c;
import core.stdc.stdio : fprintf, stderr;
import selector.model : Navigation, segments, Selector;
import selector.theme : accentColor, palette, Palette, Rgb, ThemeName;
import selector.typeface : Typeface;
import std.algorithm : clamp, max, min;
import std.array : array;
import std.exception : enforce;
import std.file : read;
import std.format : format;
import std.math : round;
import std.range : chain, iota;
import std.string : toStringz;
import std.utf : encode;

private enum rowHeight = 34;

private enum FontId : ushort
{
    text,
    small,
    hint,
}

/// Text larger than CUI's default: body 16 instead of 13; cui-selector uses the same.
private enum fontScale = 16.0 / 13;

/// Font sizes in em per FontId: CUI's text_body, text_sm and text_xs, times fontScale.
private immutable double[] emSizes = [
    13 * fontScale, 12 * fontScale, 11 * fontScale
];

private Clay_String clayString(string text)
{
    return Clay_String(false, cast(int) text.length, text.ptr);
}

private Clay_ElementId id(string label)
{
    return Clay__HashString(clayString(label), 0);
}

private Clay_Color clayColor(Rgb color, ubyte alpha = 255)
{
    return Clay_Color(color.red, color.green, color.blue, alpha);
}

private Color rayColor(Clay_Color color)
{
    return Color(cast(ubyte) color.r, cast(ubyte) color.g, cast(ubyte) color.b, cast(ubyte) color.a);
}

private Clay_SizingAxis grow()
{
    Clay_SizingAxis axis;
    axis.type = CLAY__SIZING_TYPE_GROW;
    return axis;
}

private Clay_SizingAxis fixed(float size)
{
    Clay_SizingAxis axis;
    axis.type = CLAY__SIZING_TYPE_FIXED;
    axis.size.minMax = Clay_SizingMinMax(size, size);
    return axis;
}

private Clay_SizingAxis percent(float value)
{
    Clay_SizingAxis axis;
    axis.type = CLAY__SIZING_TYPE_PERCENT;
    axis.size.percent = value;
    return axis;
}

private Clay_CornerRadius corners(float radius)
{
    return Clay_CornerRadius(radius, radius, radius, radius);
}

/// The CLAY() macro of clay.h, which ImportC cannot translate.
private void element(Clay_ElementDeclaration declaration, scope void delegate() children = null)
{
    Clay__OpenElement();
    Clay__ConfigureOpenElement(declaration);
    if (children !is null)
    {
        children();
    }
    Clay__CloseElement();
}

private void element(Clay_ElementId elementId,
        Clay_ElementDeclaration declaration, scope void delegate() children = null)
{
    Clay__OpenElementWithId(elementId);
    Clay__ConfigureOpenElement(declaration);
    if (children !is null)
    {
        children();
    }
    Clay__CloseElement();
}

private extern (C) Clay_Dimensions measureText(Clay_StringSlice slice,
        Clay_TextElementConfig* config, void* userData)
{
    auto typeface = (cast(Typeface*) userData)[config.fontId];
    return Clay_Dimensions(typeface.layout(slice.chars[0 .. slice.length]), typeface.lineHeight);
}

private extern (C) void reportClayError(Clay_ErrorData error)
{
    fprintf(stderr, "clay: %.*s\n", error.errorText.length, error.errorText.chars);
}

/// Runs the selector in a raylib window laid out by Clay until a line is chosen or the window is closed.
final class SelectorWindow
{
    private Selector selector;
    private Palette colors;
    private Rgb accent;
    private Typeface[emSizes.length] typefaces;
    private ubyte[] clayMemory;
    // Clay keeps only a pointer to its text; this keeps the GC from collecting it before rendering.
    private string statusText;
    private int firstVisible;
    private int visibleRows = 10;
    private float wheelRows = 0;
    private bool highlightChanged = true;

    /// `fontPath` replaces the embedded Inter font when it is not null.
    this(Selector selector, string title, bool hidden = false,
            ThemeName theme = ThemeName.standard, string accent = "violet", string fontPath = null)
    {
        this.selector = selector;
        colors = palette(theme);
        this.accent = accentColor(theme, accent);

        // A font may lack some requested codepoints; raylib warns about each font load otherwise.
        SetTraceLogLevel(LOG_ERROR);
        SetConfigFlags(FLAG_WINDOW_UNDECORATED | FLAG_MSAA_4X_HINT | (hidden ? FLAG_WINDOW_HIDDEN
                : 0));
        InitWindow(760, 560, title.toStringz);
        enforce(IsWindowReady(), "Could not create the raylib window");
        SetExitKey(KEY_NULL);
        SetTargetFPS(60);

        static immutable embeddedFont = cast(immutable(ubyte)[]) import("Inter-Regular.ttf");
        const fontData = fontPath is null ? embeddedFont : cast(const(ubyte)[]) read(fontPath);
        // Latin, general punctuation (…) and arrows (↑ ↓).
        auto codepoints = chain(iota(32, 0x250), iota(0x2010, 0x2030), iota(0x2190, 0x2194)).array;
        foreach (index, em; emSizes)
        {
            typefaces[index] = new Typeface(fontData, em, codepoints);
        }

        clayMemory = new ubyte[Clay_MinMemorySize()];
        Clay_Initialize(Clay_CreateArenaWithCapacityAndMemory(clayMemory.length, clayMemory.ptr),
                Clay_Dimensions(GetScreenWidth(), GetScreenHeight()),
                Clay_ErrorHandler(&reportClayError, null));
        Clay_SetMeasureTextFunction(&measureText, typefaces.ptr);
    }

    private void text(string value, Rgb color, FontId font = FontId.text)
    {
        Clay_TextElementConfig config;
        config.textColor = clayColor(color);
        config.fontId = font;
        config.fontSize = cast(ushort) typefaces[font].font.baseSize;
        config.wrapMode = CLAY_TEXT_WRAP_NONE;
        Clay__OpenTextElement(clayString(value), config);
    }

    void close()
    {
        foreach (typeface; typefaces)
        {
            typeface.unload;
        }
        CloseWindow();
    }

    void run()
    {
        while (!selector.closed && !WindowShouldClose())
        {
            handleInput;
            auto commands = layout;
            BeginDrawing();
            render(commands);
            EndDrawing();
        }
    }

    /// Renders one frame offscreen and writes it to `path`; the format follows the extension (e.g. .png).
    void screenshot(string path)
    {
        auto target = LoadRenderTexture(GetScreenWidth(), GetScreenHeight());
        scope (exit)
        {
            UnloadRenderTexture(target);
        }
        // The first layout measures the list, the second one fills it.
        layout;
        auto commands = layout;
        BeginTextureMode(target);
        render(commands);
        EndTextureMode();
        auto image = LoadImageFromTexture(target.texture);
        scope (exit)
        {
            UnloadImage(image);
        }
        ImageFlipVertical(&image);
        enforce(ExportImage(image, path.toStringz), "Could not write " ~ path);
    }

    private void handleInput()
    {
        void navigate(Navigation direction)
        {
            selector.navigate(direction);
            highlightChanged = true;
        }

        void edited()
        {
            firstVisible = 0;
            highlightChanged = true;
        }

        for (auto codepoint = GetCharPressed(); codepoint != 0; codepoint = GetCharPressed())
        {
            char[4] buffer;
            const length = encode(buffer, cast(dchar) codepoint);
            selector.type(buffer[0 .. length].idup);
            edited;
        }
        // The key queue keeps taps shorter than a frame, which IsKeyPressed misses.
        int[] keys;
        for (auto key = GetKeyPressed(); key != 0; key = GetKeyPressed())
        {
            keys ~= key;
        }
        foreach (key; [
            KEY_BACKSPACE, KEY_DOWN, KEY_UP, KEY_PAGE_DOWN, KEY_PAGE_UP, KEY_N,
            KEY_P
        ])
        {
            if (IsKeyPressedRepeat(key))
            {
                keys ~= key;
            }
        }
        const control = IsKeyDown(KEY_LEFT_CONTROL) || IsKeyDown(KEY_RIGHT_CONTROL);
        foreach (key; keys)
        {
            switch (key)
            {
            case KEY_BACKSPACE:
                selector.backspace;
                edited;
                break;
            case KEY_DOWN:
                navigate(Navigation.down);
                break;
            case KEY_UP:
                navigate(Navigation.up);
                break;
            case KEY_N:
                if (control)
                {
                    navigate(Navigation.down);
                }
                break;
            case KEY_P:
                if (control)
                {
                    navigate(Navigation.up);
                }
                break;
            case KEY_PAGE_DOWN:
                navigate(Navigation.pageDown);
                break;
            case KEY_PAGE_UP:
                navigate(Navigation.pageUp);
                break;
            case KEY_ENTER:
            case KEY_KP_ENTER:
                selector.accept;
                break;
            case KEY_ESCAPE:
                selector.cancel;
                edited;
                break;
            case KEY_F12:
                Clay_SetDebugModeEnabled(!Clay_IsDebugModeEnabled());
                break;
            default:
                break;
            }
        }
        const wheel = GetMouseWheelMoveV();
        // Trackpads report fractions of a notch; keep the remainder for the next frame.
        wheelRows += wheel.y * 3;
        const rows = cast(int) wheelRows;
        firstVisible -= rows;
        wheelRows -= rows;
        const mouse = GetMousePosition();
        Clay_SetPointerState(Clay_Vector2(mouse.x, mouse.y), IsMouseButtonDown(MOUSE_BUTTON_LEFT));
        // Scrolls the panes of Clay's debug view under the pointer; the result list scrolls itself above.
        Clay_UpdateScrollContainers(false, Clay_Vector2(wheel.x * 20, wheel.y * 20), GetFrameTime());
    }

    private void updateVisibleRows()
    {
        // Bounds are from the previous layout; until then the default is used.
        auto list = Clay_GetElementData(id("list"));
        if (list.found)
        {
            visibleRows = max(1, cast(int)(list.boundingBox.height / rowHeight));
        }
        selector.pageSize = visibleRows - 1;
        if (highlightChanged && list.found)
        {
            const highlighted = selector.highlighted;
            if (highlighted < firstVisible)
            {
                firstVisible = highlighted;
            }
            else if (highlighted >= firstVisible + visibleRows)
            {
                firstVisible = highlighted - visibleRows + 1;
            }
            highlightChanged = false;
        }
        firstVisible = clamp(firstVisible, 0, max(0, selector.count - visibleRows));
    }

    private Clay_RenderCommandArray layout()
    {
        Clay_SetLayoutDimensions(Clay_Dimensions(GetScreenWidth(), GetScreenHeight()));
        updateVisibleRows;
        Clay_BeginLayout();
        Clay_ElementDeclaration root;
        root.layout.sizing = Clay_Sizing(grow, grow);
        root.layout.padding = Clay_Padding(16, 16, 16, 16);
        root.layout.childGap = 10;
        root.layout.layoutDirection = CLAY_TOP_TO_BOTTOM;
        root.backgroundColor = clayColor(colors.background);
        element(root, () { searchField; statusLine; resultList; });
        return Clay_EndLayout(GetFrameTime());
    }

    private void searchField()
    {
        Clay_ElementDeclaration field;
        field.layout.sizing = Clay_Sizing(grow, fixed(40));
        field.layout.padding = Clay_Padding(12, 12, 0, 0);
        field.layout.childGap = 1;
        field.layout.childAlignment.y = CLAY_ALIGN_Y_CENTER;
        field.backgroundColor = clayColor(colors.surface);
        field.cornerRadius = corners(8);
        field.border.color = clayColor(accent);
        field.border.width = Clay_BorderWidth(1, 1, 1, 1, 0);
        // shortcut: a query wider than the field is clipped at the right, caret included; scroll it when that matters.
        field.clip.horizontal = true;
        element(field, () {
            if (selector.query.length != 0)
            {
                text(selector.query, colors.foreground);
            }
            Clay_ElementDeclaration caret;
            caret.layout.sizing = Clay_Sizing(fixed(2), fixed(typefaces[FontId.text].lineHeight));
            caret.backgroundColor = clayColor(accent);
            element(caret);
            if (selector.query.length == 0)
            {
                text("Type to filter…", colors.muted);
            }
        });
    }

    private void statusLine()
    {
        Clay_ElementDeclaration row;
        row.layout.sizing.width = grow;
        row.layout.childGap = 12;
        row.layout.childAlignment.y = CLAY_ALIGN_Y_CENTER;
        statusText = format("%d / %d", selector.count, selector.totalCount);
        element(row, () {
            text(statusText, colors.muted, FontId.small);
            foreach (key; ["↑ ↓", "Enter", "Esc"])
            {
                Clay_ElementDeclaration hint;
                hint.layout.padding = Clay_Padding(6, 6, 2, 2);
                hint.backgroundColor = clayColor(colors.surfaceRaised);
                hint.cornerRadius = corners(4);
                element(hint, () { text(key, colors.secondary, FontId.hint); });
            }
        });
    }

    private void resultList()
    {
        if (selector.count == 0)
        {
            text("No matches", colors.muted);
            return;
        }
        Clay_ElementDeclaration list;
        list.layout.sizing = Clay_Sizing(grow, grow);
        list.layout.childGap = 4;
        element(id("list"), list, () {
            Clay_ElementDeclaration rows;
            rows.layout.sizing = Clay_Sizing(grow, grow);
            rows.layout.layoutDirection = CLAY_TOP_TO_BOTTOM;
            element(rows, () {
                foreach (index; firstVisible .. min(selector.count, firstVisible + visibleRows))
                {
                    resultRow(index);
                }
            });
            scrollbar;
        });
    }

    private void resultRow(int index)
    {
        auto rowId = Clay__HashStringWithOffset(clayString("row"), index, 0);
        // Hover data is from the previous layout, which drew the same rows unless the list moved.
        const hovered = Clay_PointerOver(rowId);
        if (hovered && IsMouseButtonPressed(MOUSE_BUTTON_LEFT))
        {
            selector.highlight(index);
            selector.accept;
        }
        Clay_ElementDeclaration row;
        row.layout.sizing = Clay_Sizing(grow, fixed(rowHeight));
        row.layout.padding = Clay_Padding(10, 10, 0, 0);
        row.layout.childAlignment.y = CLAY_ALIGN_Y_CENTER;
        row.cornerRadius = corners(8);
        // shortcut: long rows are clipped without an ellipsis; add one if paths get cut off often.
        row.clip.horizontal = true;
        if (index == selector.highlighted)
        {
            row.backgroundColor = clayColor(accent, 0x38);
        }
        else if (hovered)
        {
            row.backgroundColor = clayColor(colors.surface);
        }
        element(rowId, row, () {
            foreach (segment; segments(selector.row(index), selector.matchedPositions(index)))
            {
                text(segment.text, segment.matched ? accent : colors.foreground);
            }
        });
    }

    /// A thin scrollbar: a spacer above the thumb, both sized as a fraction of the track.
    private void scrollbar()
    {
        const count = selector.count;
        if (count <= visibleRows)
        {
            return;
        }
        const thumb = max(0.04f, cast(float) visibleRows / count);
        Clay_ElementDeclaration track;
        track.layout.sizing = Clay_Sizing(fixed(6), grow);
        track.layout.layoutDirection = CLAY_TOP_TO_BOTTOM;
        track.backgroundColor = clayColor(colors.foreground, 20);
        track.cornerRadius = corners(3);
        element(track, () {
            Clay_ElementDeclaration spacer;
            spacer.layout.sizing = Clay_Sizing(grow,
                percent(min(cast(float) firstVisible / count, 1 - thumb)));
            element(spacer);
            Clay_ElementDeclaration bar;
            bar.layout.sizing = Clay_Sizing(grow, percent(thumb));
            bar.backgroundColor = clayColor(colors.foreground, 90);
            bar.cornerRadius = corners(3);
            element(bar);
        });
    }

    private void render(Clay_RenderCommandArray commands)
    {
        static float roundness(Rectangle bounds, float radius)
        {
            return min(1.0f, 2 * radius / min(bounds.width, bounds.height));
        }

        ClearBackground(rayColor(clayColor(colors.background)));
        foreach (index; 0 .. commands.length)
        {
            auto command = Clay_RenderCommandArray_Get(&commands, index);
            const box = command.boundingBox;
            const bounds = Rectangle(box.x, box.y, box.width, box.height);
            switch (command.commandType)
            {
            case CLAY_RENDER_COMMAND_TYPE_RECTANGLE:
                const rectangle = command.renderData.rectangle;
                DrawRectangleRounded(bounds, roundness(bounds,
                        rectangle.cornerRadius.topLeft), 8, rayColor(rectangle.backgroundColor));
                break;
            case CLAY_RENDER_COMMAND_TYPE_BORDER:
                const border = command.renderData.border;
                DrawRectangleRoundedLinesEx(bounds, roundness(bounds,
                        border.cornerRadius.topLeft), 8, border.width.top, rayColor(border.color));
                break;
            case CLAY_RENDER_COMMAND_TYPE_TEXT:
                const data = command.renderData.text;
                typefaces[data.fontId].draw(data.stringContents.chars[0 .. data.stringContents.length],
                        box.x, box.y, rayColor(data.textColor));
                break;
            case CLAY_RENDER_COMMAND_TYPE_SCISSOR_START:
                // raylib scissors do not nest; the layout has no nested clip elements.
                BeginScissorMode(cast(int) round(box.x), cast(int) round(box.y),
                        cast(int) round(box.width), cast(int) round(box.height));
                break;
            case CLAY_RENDER_COMMAND_TYPE_SCISSOR_END:
                EndScissorMode();
                break;
            default:
                break;
            }
        }
    }
}
