// Where everything goes, worked out from the theme.
//
// Nothing here is a constant of this tool. The arrangement, the widths, the
// gaps and the sizes all come from the theme, as decided in
// `docs/decisions/017-return-message-themes.md`.

class MagickStep {
    args: string[],
}

/// What a panel takes on each side before its content starts.
function panel_inset(panel: root.return_message.Panel) -> int {
    panel.border_width + panel.padding
}

/// The width of each cell of a row, from its weights. The widths and the gaps
/// come to the canvas width exactly: the remainder of the division goes to the
/// last cell, so a row never ends a pixel short of the one above it.
function row_widths(theme: root.return_message.Theme, weights: int[]) -> int[] {
    let count = weights.length();
    let available = theme.canvas.width - theme.canvas.column_gap * (count - 1);

    let total = 0;
    for (let weight in weights) {
        total = total + weight;
    }

    let widths: int[] = [];
    let used = 0;
    let index = 0;
    for (let weight in weights) {
        index = index + 1;
        let width = if (index == count) {
            available - used
        } else {
            (available * weight) / total
        };
        widths.push(width);
        used = used + width;
    }
    widths
}

/// The width left for text inside a cell of that width.
function inner_width(theme: root.return_message.Theme, cell_width: int) -> int {
    cell_width - 2 * panel_inset(theme.language_panel)
}

/// The point size of the body in a block of that inner width. Every other size
/// in the theme is a multiple of this one, which is why a narrower column makes
/// its whole block smaller rather than only its longest line.
function body_point_size(theme: root.return_message.Theme, inner: int) -> int {
    root.common.round_to_int(inner * theme.canvas.body_size_ratio)
}

function point_size(theme: root.return_message.Theme, style: root.return_message.TextStyle,
                    inner: int) -> int {
    root.common.round_to_int(body_point_size(theme, inner) * style.size)
}

/// The languages of one row, with the width each of them gets.
class RowPlan {
    codes: string[],
    widths: int[],
}

function empty_rows() -> root.return_message.ArrangementRow[] {
    let empty: root.return_message.ArrangementRow[] = [];
    empty
}

/// The rows the theme lays this many languages out in, filled in the order the
/// values file listed them: row by row from the top, and left to right inside
/// a row.
function plan_rows(theme: root.return_message.Theme, codes: string[]) -> RowPlan[] {
    let plans: RowPlan[] = [];
    let arrangement = root.return_message.arrangement_for(theme, codes.length());
    if (arrangement == null) {
        return plans;
    }

    let taken = 0;
    for (let row in arrangement.rows) {
        let plan = RowPlan { codes: [], widths: row_widths(theme, row.weights) };
        for (let weight in row.weights) {
            plan.codes.push(codes.at(taken) ?? "");
            taken = taken + 1;
        }
        plans.push(plan);
    }
    plans
}

function sample_test_theme() -> root.return_message.Theme {
    root.return_message.parse_theme(root.return_message.sample_theme(), "/theme").theme
}

test "a row's widths and its gaps come to the canvas width" {
    let theme = sample_test_theme();

    assert.equal(row_widths(theme, [1]), [3840]);

    let two = row_widths(theme, [1, 1]);
    assert.equal(two, [1872, 1872]);
    assert.equal((two.at(0) ?? 0) + (two.at(1) ?? 0) + theme.canvas.column_gap, 3840)
}

test "weights divide a row in proportion, and the remainder lands on the last cell" {
    let theme = sample_test_theme();

    assert.equal(row_widths(theme, [2, 1]), [2496, 1248]);

    let thirds = row_widths(theme, [1, 1, 1]);
    assert.equal((thirds.at(0) ?? 0) + (thirds.at(1) ?? 0) + (thirds.at(2) ?? 0)
                     + 2 * theme.canvas.column_gap,
                 3840)
}

test "the body size follows the width of the block it falls in" {
    let theme = sample_test_theme();
    //# padding 64 and a border of 4, on each side
    assert.equal(inner_width(theme, 3840), 3704);

    let full = body_point_size(theme, inner_width(theme, 3840));
    let half = body_point_size(theme, inner_width(theme, 1872));
    assert.is_true(full > half);

    //# a style's size multiplies it, so a heading keeps its proportion anywhere
    let heading = root.return_message.style_named(theme, theme.language_heading_style);
    assert.equal(point_size(theme, heading, inner_width(theme, 3840)),
                 root.common.round_to_int(full * 1.25))
}

test "plan_rows places the languages the way the theme arranges them" {
    let theme = sample_test_theme();

    let grid = plan_rows(theme, ["ca", "en", "es", "fr"]);
    assert.equal(grid.length(), 2);
    assert.equal((grid.at(0))?.codes, ["ca", "en"]);
    assert.equal((grid.at(1))?.codes, ["es", "fr"]);
    assert.equal((grid.at(0))?.widths, [1872, 1872]);

    let one = plan_rows(theme, ["es"]);
    assert.equal(one.length(), 1);
    assert.equal((one.at(0))?.widths, [3840])
}

test "a number of languages the theme does not arrange plans nothing" {
    //# the sample theme arranges 1, 2 and 4
    assert.equal(plan_rows(sample_test_theme(), ["ca", "en", "es"]).length(), 0)
}
