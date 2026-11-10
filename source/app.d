import argparse : Description, NamedArgument;
import argparse.api.cli : CLI;
import argparse.config : Config;
import core.sys.posix.unistd : isatty;
import selector.model : Navigation, Selector;
import selector.theme : parseTheme, resolveAccent;
import selector.window : SelectorWindow;
import std.array : array;
import std.exception : enforce;
import std.file : exists;
import std.path : expandTilde;
import std.stdio : stderr, stdin, stdout;

private string[] sampleLines()
{
    return [
        "source/app.d", "source/selector/model.d", "source/selector/window.d",
        "source/clay_c.c", "tests/runner.d", "tests/selector/model_test.d",
        "flake.nix", "flake.lock", "dub.sdl", "dub.selections.json", "readme.org",
        "LICENSE", ".gitignore", ".envrc", "out/main/clay-selector/clay-selector",
        "out/tests/clay-selector/clay-selector-tests",
    ];
}

/// A font at ~/.config/picker/font.ttf replaces the built-in Inter.
private string userFont()
{
    auto path = "~/.config/picker/font.ttf".expandTilde;
    return path.exists ? path : null;
}

struct Options
{
    @(NamedArgument.Description("Use built-in sample lines instead of stdin"))
    bool demo;
    @(NamedArgument.Description("Initial filter text"))
    string query;
    @(NamedArgument.Description("Move the highlight down this many rows first (for screenshots)"))
    int down;
    @(NamedArgument.Description("Render headlessly to this image file (e.g. .png) and exit"))
    string screenshot;
    @(NamedArgument.Description("Color theme: default or zenburn"))
    string theme = "default";
    @(NamedArgument.Description("Accent color. default: neutral, violet, blue, green, amber, orange, coral, rose; "
            ~ "zenburn: yellow, cyan, green, orange, red, magenta, blue"))
    string accent;
}

int run(Options options)
{
    try
    {
        auto theme = parseTheme(options.theme);
        auto accent = resolveAccent(theme, options.accent);
        auto lines = options.demo || isatty(0) ? sampleLines : stdin.byLineCopy.array;
        enforce(lines.length != 0, "No input lines");
        auto selector = new Selector(lines);
        auto window = new SelectorWindow(selector, "clay-selector",
                options.screenshot.length != 0, theme, accent, userFont);
        scope (exit)
        {
            window.close;
        }
        selector.filter(options.query);
        foreach (_; 0 .. options.down)
        {
            selector.navigate(Navigation.down);
        }
        if (options.screenshot.length != 0)
        {
            window.screenshot(options.screenshot);
            return 0;
        }
        window.run;
        if (!selector.chosen)
        {
            return 1;
        }
        stdout.writeln(selector.selection);
        return 0;
    }
    catch (Exception failure)
    {
        stderr.writeln("clay-selector: ", failure.msg);
        return 2;
    }
}

mixin CLI!(Options).main!(run);
