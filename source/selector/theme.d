/// Theme and accent selection, independent of Clay and raylib so it can be unit tested.
module selector.theme;

import std.algorithm : canFind;
import std.exception : enforce;
import std.format : format;
import std.math : pow;
import std.string : join;

struct Rgb
{
    ubyte red;
    ubyte green;
    ubyte blue;
}

enum ThemeName
{
    standard,
    zenburn,
}

/// Accent names of the default theme.
immutable string[] standardAccents = [
    "neutral", "violet", "blue", "green", "amber", "orange", "coral", "rose"
];

immutable string[] zenburnAccents = [
    "yellow", "cyan", "green", "orange", "red", "magenta", "blue"
];

struct Palette
{
    Rgb background;
    Rgb surface;
    Rgb surfaceRaised;
    Rgb foreground;
    Rgb secondary;
    Rgb muted;
}

immutable Palette standard = Palette(Rgb(0x16, 0x16, 0x1a), Rgb(0x22, 0x22,
        0x28), Rgb(0x2e, 0x2e, 0x36), Rgb(0xec, 0xec, 0xf1), Rgb(0xb4, 0xb4,
        0xbf), Rgb(0x80, 0x80, 0x8c));

immutable Palette zenburn = Palette(Rgb(0x3f, 0x3f, 0x3f), Rgb(0x4f, 0x4f,
        0x4f), Rgb(0x5f, 0x5f, 0x5f), Rgb(0xdc, 0xdc, 0xcc), Rgb(0xc3, 0xc3,
        0xb3), Rgb(0xa3, 0xa3, 0x93));

Palette palette(ThemeName theme)
{
    return theme == ThemeName.zenburn ? zenburn : standard;
}

ThemeName parseTheme(string name)
{
    switch (name)
    {
    case "default":
        return ThemeName.standard;
    case "zenburn":
        return ThemeName.zenburn;
    default:
        throw new Exception(format!"Unknown theme '%s' (expected default or zenburn)"(name));
    }
}

/// Defaults to violet for the default theme and yellow for zenburn when `name` is empty.
string resolveAccent(ThemeName theme, string name)
{
    auto accents = theme == ThemeName.zenburn ? zenburnAccents : standardAccents;
    if (name.length == 0)
    {
        return accents[theme == ThemeName.zenburn ? 0 : 1];
    }
    enforce(accents.canFind(name),
            format!"Unknown accent '%s' for this theme (expected one of: %s)"(name,
                accents.join(", ")));
    return name;
}

Rgb accentColor(ThemeName theme, string name)
{
    return theme == ThemeName.zenburn ? zenburnAccent(name) : standardAccent(name);
}

Rgb standardAccent(string name)
{
    switch (name)
    {
    case "neutral":
        return Rgb(0xa1, 0xa1, 0xaa);
    case "violet":
        return Rgb(0x8b, 0x7c, 0xf6);
    case "blue":
        return Rgb(0x4f, 0x8f, 0xf7);
    case "green":
        return Rgb(0x3e, 0xc7, 0x6c);
    case "amber":
        return Rgb(0xf5, 0xb0, 0x2e);
    case "orange":
        return Rgb(0xf9, 0x82, 0x3a);
    case "coral":
        return Rgb(0xff, 0x7f, 0x6e);
    case "rose":
        return Rgb(0xf4, 0x5d, 0x7e);
    default:
        throw new Exception(format!"Unknown accent '%s'"(name));
    }
}

Rgb zenburnAccent(string name)
{
    switch (name)
    {
    case "yellow":
        return Rgb(0xf0, 0xdf, 0xaf);
    case "cyan":
        return Rgb(0x8c, 0xd0, 0xd3);
    case "green":
        return Rgb(0x7f, 0x9f, 0x7f);
    case "orange":
        return Rgb(0xdf, 0xaf, 0x8f);
    case "red":
        return Rgb(0xcc, 0x93, 0x93);
    case "magenta":
        return Rgb(0xdc, 0x8c, 0xc3);
    case "blue":
        return Rgb(0x94, 0xbf, 0xf3);
    default:
        throw new Exception(format!"Unknown zenburn accent '%s'"(name));
    }
}

private double linearized(ubyte channel)
{
    const value = channel / 255.0;
    return value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4);
}

/// WCAG contrast ratio between two colors.
double contrastRatio(Rgb first, Rgb second)
{
    double luminance(Rgb color)
    {
        return 0.2126 * linearized(color.red) + 0.7152 * linearized(
                color.green) + 0.0722 * linearized(color.blue);
    }

    const a = luminance(first);
    const b = luminance(second);
    return (a > b ? a + 0.05 : b + 0.05) / (a > b ? b + 0.05 : a + 0.05);
}

/// Linear mix: `amount` 0 gives `from`, 1 gives `to`.
Rgb mix(Rgb from, Rgb to, double amount)
{
    ubyte channel(ubyte a, ubyte b)
    {
        return cast(ubyte)(a + (b - a) * amount + 0.5);
    }

    return Rgb(channel(from.red, to.red), channel(from.green, to.green),
            channel(from.blue, to.blue));
}
