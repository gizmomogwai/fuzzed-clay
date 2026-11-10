/// Text rasterized and laid out like CUI: em-sized, gamma-boosted glyphs at whole pixels, float advances with kerning.
module selector.typeface;

import clay_c;
import std.algorithm : filter, map, max;
import std.array : array;
import std.exception : enforce;
import std.math : pow, round;
import std.range : iota;
import std.utf : byDchar;

/// Glyphs of one font at one size in a raylib atlas, plus the metrics raylib rounds away.
final class Typeface
{
    Font font;
    /// Pixels from the top of a line to the baseline.
    float ascent;
    float lineHeight;
    private float scale;
    private float[] advances;
    private stbtt_fontinfo info;
    // stb_truetype reads kerning from the font data, so it has to outlive `info`.
    private const(ubyte)[] data;

    /// `emPixels` is the size like CUI's and CSS's font sizes; raylib's are line heights.
    this(const(ubyte)[] data, float emPixels, const(int)[] codepoints)
    {
        static immutable ubyte[256] gamma = iota(256).map!(
                coverage => cast(ubyte)(pow(coverage / 255.0, 0.82) * 255 + 0.5)).array;

        this.data = data;
        const offset = stbtt_GetFontOffsetForIndex(data.ptr, 0);
        enforce(offset >= 0 && stbtt_InitFont(&info, data.ptr, offset) != 0,
                "Not a TrueType or OpenType font");
        scale = stbtt_ScaleForMappingEmToPixels(&info, emPixels);
        int ascender, descender, lineGap;
        stbtt_GetFontVMetrics(&info, &ascender, &descender, &lineGap);
        ascent = ascender * scale;
        lineHeight = (ascender - descender) * scale;

        // Without a glyph for a codepoint, raylib's GetGlyphIndex falls back to '?'.
        const available = codepoints.filter!(codepoint => stbtt_FindGlyphIndex(&info,
                codepoint) != 0).array;
        enforce(available.length != 0, "Font has none of the needed characters");
        // UnloadFont releases glyphs and their images with raylib's allocator.
        auto glyphs = cast(GlyphInfo*) MemAlloc(cast(uint)(GlyphInfo.sizeof * available.length));
        foreach (index, codepoint; available)
        {
            int advance, bearing;
            stbtt_GetCodepointHMetrics(&info, codepoint, &advance, &bearing);
            advances ~= advance * scale;
            int x0, y0, x1, y1;
            stbtt_GetCodepointBitmapBox(&info, codepoint, scale, scale, &x0, &y0, &x1, &y1);
            const width = max(0, x1 - x0);
            const height = max(0, y1 - y0);
            auto pixels = cast(ubyte*) MemAlloc(max(1, width * height));
            stbtt_MakeCodepointBitmap(&info, pixels, width, height, width,
                    scale, scale, codepoint);
            foreach (ref pixel; pixels[0 .. width * height])
            {
                pixel = gamma[pixel];
            }
            glyphs[index] = GlyphInfo(codepoint, x0, y0, 0, Image(pixels,
                    width, height, 1, PIXELFORMAT_UNCOMPRESSED_GRAYSCALE));
        }
        font.baseSize = cast(int) round(lineHeight);
        font.glyphCount = cast(int) available.length;
        font.glyphPadding = 4; // FONT_TTF_DEFAULT_CHARS_PADDING in raylib's rtext.c
        font.glyphs = glyphs;
        auto atlas = GenImageFontAtlas(glyphs, &font.recs, font.glyphCount,
                font.baseSize, font.glyphPadding, 0);
        font.texture = LoadTextureFromImage(atlas);
        UnloadImage(atlas);
    }

    void unload()
    {
        UnloadFont(font);
    }

    /// Calls `place` with each glyph index and its pen position; returns the width of `text`.
    float layout(const(char)[] text, scope void delegate(int glyphIndex, float x) place = null)
    {
        float pen = 0;
        dchar previous = 0;
        // byDchar turns invalid UTF-8 from stdin into U+FFFD instead of throwing.
        foreach (codepoint; text.byDchar)
        {
            if (previous != 0)
            {
                pen += stbtt_GetCodepointKernAdvance(&info, previous, codepoint) * scale;
            }
            const index = GetGlyphIndex(font, codepoint);
            if (place !is null)
            {
                place(index, pen);
            }
            pen += advances[index];
            previous = codepoint;
        }
        return pen;
    }

    /// Draws each glyph at a whole pixel, as CUI does, so the atlas texels map 1:1 to the screen.
    void draw(const(char)[] text, float x, float y, Color color)
    {
        const baseline = round(y + ascent);
        layout(text, (index, pen) {
            const glyph = font.glyphs[index];
            DrawTextureRec(font.texture, font.recs[index],
                Vector2(round(x + pen) + glyph.offsetX, baseline + glyph.offsetY), color);
        });
    }
}
