module selector.model_test;

import selector.model;
import unit_threaded.assertions;

@("filtering keeps matches in input order and reports grapheme positions")
unittest
{
    auto selector = new Selector(["xaxb", "zzz", "Ab"]);
    selector.filter("ab");
    selector.count.shouldEqual(2);
    selector.row(1).shouldEqual("Ab");
    selector.matchedPositions(1).shouldEqual([0, 1]);
}

@("empty query keeps input order")
unittest
{
    auto selector = new Selector(["c", "a", "b"]);
    selector.row(0).shouldEqual("c");
    selector.row(2).shouldEqual("b");
}

@("navigation is clamped and accept selects the highlighted row")
unittest
{
    auto selector = new Selector(["alpha", "beta", "gamma"]);
    selector.pageSize = 2;
    selector.navigate(Navigation.up);
    selector.highlighted.shouldEqual(0);
    selector.navigate(Navigation.pageDown);
    selector.navigate(Navigation.pageDown);
    selector.highlighted.shouldEqual(2);
    selector.accept;
    selector.chosen.shouldBeTrue;
    selector.selection.shouldEqual("gamma");
}

@("cancel clears the query before closing")
unittest
{
    auto selector = new Selector(["alpha"]);
    selector.filter("al");
    selector.cancel;
    selector.query.shouldEqual("");
    selector.closed.shouldBeFalse;
    selector.cancel;
    selector.closed.shouldBeTrue;
    selector.chosen.shouldBeFalse;
}

@("accept with no matches does nothing")
unittest
{
    auto selector = new Selector(["alpha"]);
    selector.filter("zzz");
    selector.accept;
    selector.closed.shouldBeFalse;
}

@("typing and backspace edit the query by grapheme")
unittest
{
    auto selector = new Selector(["noe\u0308l", "noel"]);
    selector.type("e\u0308");
    selector.count.shouldEqual(1);
    selector.backspace;
    selector.query.shouldEqual("");
    selector.count.shouldEqual(2);
    selector.backspace;
    selector.query.shouldEqual("");
}

@("segments split a row into matched and unmatched runs")
unittest
{
    segments("abcde", [1, 2, 4]).shouldEqual([
        Segment("a", false), Segment("bc", true), Segment("d", false),
        Segment("e", true)
    ]);
    segments("noe\u0308l", [2]).shouldEqual([
        Segment("no", false), Segment("e\u0308", true), Segment("l", false)
    ]);
    segments("", []).length.shouldEqual(0);
}
