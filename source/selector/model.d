module selector.model;

import fuzzed.model : Model;
import std.algorithm : max, min;
import std.range : empty;
import std.uni : graphemeStride;

enum Navigation
{
    up,
    down,
    pageUp,
    pageDown,
    first,
    last,
}

/// UI-independent selector state: the filtered list, the highlighted row and the outcome.
final class Selector
{
    private Model model;
    private int highlighted_;
    private int pageSize_ = 10;
    string selection;
    bool chosen;
    bool closed;

    this(string[] lines)
    {
        model = new Model;
        model.setData(lines);
    }

    string query() const
    {
        return model.pattern;
    }

    int highlighted() const
    {
        return highlighted_;
    }

    int count() const
    {
        return cast(int) model.matches.length;
    }

    int totalCount() const
    {
        return cast(int) model.all.length;
    }

    string row(int index) const
    {
        return model.matches[index].value;
    }

    /// Grapheme positions of the row that match the query.
    const(ulong)[] matchedPositions(int index) const
    {
        return model.matches[index].positions;
    }

    void pageSize(int rows)
    {
        pageSize_ = max(1, rows);
    }

    void filter(string newQuery)
    {
        model.update(newQuery);
        highlighted_ = 0;
    }

    /// Appends typed text to the query.
    void type(string text)
    {
        filter(query ~ text);
    }

    /// Removes the last grapheme of the query.
    void backspace()
    {
        size_t offset;
        size_t last;
        while (offset < query.length)
        {
            last = offset;
            offset += graphemeStride(query, offset);
        }
        filter(query[0 .. last]);
    }

    void navigate(Navigation direction)
    {
        if (count == 0)
        {
            return;
        }
        final switch (direction)
        {
        case Navigation.down:
            highlighted_ = min(count - 1, highlighted_ + 1);
            break;
        case Navigation.up:
            highlighted_ = max(0, highlighted_ - 1);
            break;
        case Navigation.pageDown:
            highlighted_ = min(count - 1, highlighted_ + pageSize_);
            break;
        case Navigation.pageUp:
            highlighted_ = max(0, highlighted_ - pageSize_);
            break;
        case Navigation.first:
            highlighted_ = 0;
            break;
        case Navigation.last:
            highlighted_ = count - 1;
            break;
        }
    }

    void highlight(int index)
    {
        if (index >= 0 && index < count)
        {
            highlighted_ = index;
        }
    }

    void accept()
    {
        if (highlighted_ < 0 || highlighted_ >= count)
        {
            return;
        }
        selection = row(highlighted_);
        chosen = true;
        closed = true;
    }

    /// Clears a non-empty query first; otherwise closes without a selection.
    void cancel()
    {
        if (!query.empty)
        {
            filter("");
            return;
        }
        closed = true;
    }
}

/// A run of text that is either all matched or all unmatched.
struct Segment
{
    string text;
    bool matched;
}

/// Splits `text` into runs, marking the graphemes at `matchedPositions`.
Segment[] segments(string text, const(ulong)[] matchedPositions)
{
    Segment[] result;
    size_t offset;
    size_t position;
    size_t matchIndex;
    while (offset < text.length)
    {
        const next = offset + graphemeStride(text, offset);
        const matched = matchIndex < matchedPositions.length
            && matchedPositions[matchIndex] == position;
        if (matched)
        {
            ++matchIndex;
        }
        if (!result.empty && result[$ - 1].matched == matched)
        {
            result[$ - 1].text = text[offset - result[$ - 1].text.length .. next];
        }
        else
        {
            result ~= Segment(text[offset .. next], matched);
        }
        offset = next;
        ++position;
    }
    return result;
}
