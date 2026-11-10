module selector.theme_test;

import selector.theme;
import std.algorithm : all;
import std.exception : assertThrown;
import unit_threaded.assertions;

@("theme names")
unittest
{
    parseTheme("default").shouldEqual(ThemeName.standard);
    parseTheme("zenburn").shouldEqual(ThemeName.zenburn);
    assertThrown(parseTheme("solarized"));
}

@("accents default per theme and are validated against the theme")
unittest
{
    resolveAccent(ThemeName.standard, "").shouldEqual("violet");
    resolveAccent(ThemeName.zenburn, "").shouldEqual("yellow");
    resolveAccent(ThemeName.standard, "rose").shouldEqual("rose");
    resolveAccent(ThemeName.zenburn, "cyan").shouldEqual("cyan");
    assertThrown(resolveAccent(ThemeName.standard, "yellow"));
    assertThrown(resolveAccent(ThemeName.zenburn, "violet"));
}

@("every accent name maps to a color")
unittest
{
    foreach (name; zenburnAccents)
    {
        accentColor(ThemeName.zenburn, name);
    }
    foreach (name; standardAccents)
    {
        accentColor(ThemeName.standard, name);
    }
}

@("text is legible on the surfaces of every theme")
unittest
{
    foreach (theme; [ThemeName.standard, ThemeName.zenburn])
    {
        const colors = palette(theme);
        foreach (surface; [
            colors.background, colors.surface, colors.surfaceRaised
        ])
        {
            (contrastRatio(colors.foreground, surface) >= 4.5).shouldBeTrue;
            (contrastRatio(colors.secondary, surface) >= 3.0).shouldBeTrue;
        }
        (contrastRatio(colors.foreground, colors.background) >= 6.0).shouldBeTrue;
    }
}

@("accents stand out from the background")
unittest
{
    zenburnAccents.all!(name => contrastRatio(zenburnAccent(name),
            zenburn.background) >= 3.0).shouldBeTrue;
    standardAccents.all!(name => contrastRatio(standardAccent(name),
            standard.background) >= 3.0).shouldBeTrue;
}

@("contrast of identical colors is one")
unittest
{
    contrastRatio(zenburn.background, zenburn.background).shouldEqual(1.0);
}
