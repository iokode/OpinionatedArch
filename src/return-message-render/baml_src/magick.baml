// The commands that draw the images, and the markup they draw from.
//
// Every function here builds an argument list and nothing else, so what would
// be run can be asserted without running it. Text always reaches ImageMagick
// as a file rather than as an argument, and the only markup in that file is
// the markup this tool wrote: whatever came from a template package or from an
// operator is escaped first.

function magick() -> string {
    "magick"
}

/// Pango's names for what a theme calls a weight and a slant.
function pango_weight(weight: string) -> string {
    if (weight == "regular") { "normal" } else { weight }
}

function pango_slant(slant: string) -> string {
    if (slant == "italic") { "italic" } else { "normal" }
}

/// Escapes what Pango markup would otherwise read as markup. This is what
/// keeps a template package data: its words can hold `<`, `&` or `>` and they
/// are drawn.
function escape_markup(text: string) -> string {
    text.replace_all("&", "&amp;").replace_all("<", "&lt;").replace_all(">", "&gt;")
}

/// A run of text in one style. The size travels in the span rather than on the
/// command line, so a style inside a line can differ from the line around it.
function span(theme: root.return_message.Theme, style: root.return_message.TextStyle,
              points: int, text: string) -> string {
    `<span font_family="${root.return_message.family_of(theme, style)}"`
        + ` font_weight="${pango_weight(style.weight)}"`
        + ` font_style="${pango_slant(style.slant)}"`
        + ` foreground="${style.color}" size="${points}pt">${text}</span>`
}

/// Draws a piece of markup at a fixed width, as tall as it needs to be.
function text_args(theme: root.return_message.Theme, source: string, width: int,
                   align: string, output: string) -> string[] {
    [
        "-background", "none",
        "-size", `${width}x`,
        "-interline-spacing", `${theme.spacing.line_gap}`,
        "-define", "pango:markup=true",
        "-define", `pango:align=${align}`,
        `pango:@${source}`,
        "+repage", "-depth", "8", output,
    ]
}

/// The same, sized to its content instead of to a width. The prompt is one
/// line, and its panel has to fit it rather than the other way round.
function fitted_text_args(theme: root.return_message.Theme, source: string,
                          align: string, output: string) -> string[] {
    [
        "-background", "none",
        "-interline-spacing", `${theme.spacing.line_gap}`,
        "-define", "pango:markup=true",
        "-define", `pango:align=${align}`,
        `pango:@${source}`,
        "+repage", "-depth", "8", output,
    ]
}

/// A panel of a given size with the content laid inside its padding. The panel
/// is drawn first and the content composited over it, so the corners stay
/// round whatever the content is.
function panel_args(panel: root.return_message.Panel, width: int, height: int,
                    content: string, output: string) -> string[] {
    let half = panel.border_width / 2;
    let stroke = if (panel.border_width > 0) { panel.border_color } else { "none" };
    let inset = panel_inset(panel);
    [
        "-size", `${width}x${height}`, "xc:none",
        "-fill", panel.fill,
        "-stroke", stroke,
        "-strokewidth", `${panel.border_width}`,
        "-draw", `roundrectangle ${half},${half} ${width - 1 - half},${height - 1 - half}`
            + ` ${panel.corner_radius},${panel.corner_radius}`,
        content, "-geometry", `+${inset}+${inset}`, "-composite",
        "+repage", "-depth", "8", output,
    ]
}

/// Joins images, each one after the first preceded by a gap. `-splice` is what
/// puts the gap there: appending on its own leaves none.
function joined_args(inputs: string[], gap: int, vertical: bool, output: string) -> string[] {
    let args: string[] = [];
    let index = 0;
    let edge = if (vertical) { "north" } else { "west" };
    let splice = if (vertical) { `0x${gap}` } else { `${gap}x0` };

    for (let input in inputs) {
        if (index == 0 || gap == 0) {
            args.push(input);
        } else {
            args.push("(");
            args.push(input);
            args.push("-background");
            args.push("none");
            args.push("-gravity");
            args.push(edge);
            args.push("-splice");
            args.push(splice);
            args.push(")");
        }
        index = index + 1;
    }

    args.push("-background");
    args.push("none");
    args.push("-gravity");
    args.push(if (vertical) { "center" } else { "north" });
    args.push(if (vertical) { "-append" } else { "+append" });
    args.push("+repage");
    args.push("-depth");
    args.push("8");
    args.push(output);
    args
}

/// Places an image across the canvas width, at the side its style asks for.
function place_args(theme: root.return_message.Theme, input: string, height: int,
                    align: string, output: string) -> string[] {
    let gravity = if (align == "center") { "center" } else { if (align == "right") { "east" } else { "west" } };
    [
        "-size", `${theme.canvas.width}x${height}`, "xc:none",
        input, "-gravity", gravity, "-composite",
        "+repage", "-depth", "8", output,
    ]
}

/// Fits a logo into the box the theme gives it, without distorting it.
function logo_args(theme: root.return_message.Theme, source: string, output: string) -> string[] {
    let box = (theme.logo)?.width ?? 0;
    [
        source,
        "-background", "none",
        "-resize", `${box}x`,
        "+repage", "-depth", "8", output,
    ]
}

/// The glyph that marks one typed character. It is drawn rather than written,
/// which `docs/decisions/010-preboot-ownership-message.md` requires.
function mask_args(theme: root.return_message.Theme, output: string) -> string[] {
    let mask = theme.password_mask;
    let side = mask.size;
    let shape = if (mask.shape == "square") {
        `rectangle 0,0 ${side - 1},${side - 1}`
    } else {
        `circle ${side / 2},${side / 2} ${side / 2},0`
    };
    [
        "-size", `${side}x${side}`, "xc:none",
        "-fill", mask.color,
        "-draw", shape,
        "+repage", "-depth", "8", output,
    ]
}

/// The height of an image, which the panel behind it has to know.
function image_height(shell: root.common.Shell, path: string) -> int {
    let result = shell.capture("identify", ["-format", "%h", path]);
    if (result.exit_code != 0) {
        return 0;
    }
    root.common.parse_int(result.stdout.trim()) ?? 0
}

test "escape_markup leaves a package's words as words" {
    assert.equal(escape_markup("Smith & Sons <of> Andorra"),
                 "Smith &amp; Sons &lt;of&gt; Andorra");
    assert.equal(escape_markup("100% sure"), "100% sure")
}

test "a span carries the family, the weight, the slant, the colour and the size" {
    let theme = sample_test_theme();
    let style = root.return_message.style_named(theme, "title");

    assert.equal(span(theme, style, 64, "Català"),
                 "<span font_family=\"Noto Sans\" font_weight=\"bold\" font_style=\"normal\""
                     + " foreground=\"#8FC2FF\" size=\"64pt\">Català</span>")
}

test "text is drawn from a file, never from an argument" {
    let theme = sample_test_theme();
    let args = text_args(theme, "/s/body-es.markup", 1824, "left", "/s/body-es.png");

    assert.is_true(args.includes("pango:@/s/body-es.markup"));
    assert.is_true(args.includes("pango:align=left"));
    assert.equal(args.at(args.length() - 1), "/s/body-es.png")
}

test "a panel is drawn to a size, with its content inside the padding" {
    let theme = sample_test_theme();
    let args = panel_args(theme.language_panel, 1872, 600, "/s/content.png", "/s/cell.png");

    assert.is_true(args.includes("-size"));
    assert.is_true(args.includes("1872x600"));
    assert.is_true(args.includes("roundrectangle 2,2 1869,597 32,32"));
    //# border 4 plus padding 64
    assert.is_true(args.includes("+68+68"))
}

test "a panel with no border draws no stroke" {
    let theme = sample_test_theme();
    let args = panel_args(theme.password_prompt_panel, 800, 200, "/s/c.png", "/s/o.png");
    assert.is_true(args.includes("none"))
}

test "joining puts a gap between images and none before the first" {
    let beside = joined_args(["/a.png", "/b.png"], 96, false, "/row.png");
    assert.equal(beside.at(0), "/a.png");
    assert.is_true(beside.includes("96x0"));
    assert.is_true(beside.includes("+append"));

    let stacked = joined_args(["/a.png", "/b.png"], 64, true, "/out.png");
    assert.is_true(stacked.includes("0x64"));
    assert.is_true(stacked.includes("-append"))
}

test "joining without a gap splices nothing" {
    let joined = joined_args(["/a.png", "/b.png"], 0, true, "/out.png");
    assert.is_true(!joined.includes("("));
    assert.equal(joined.slice(0, 2), ["/a.png", "/b.png"])
}

test "the mask is drawn as the shape the theme asks for" {
    let theme = sample_test_theme();
    assert.is_true(mask_args(theme, "/m.png").includes("circle 48,48 48,0"));
    assert.is_true(mask_args(theme, "/m.png").includes("96x96"))
}

test "image_height reads what identify reports" {
    let shell = root.common.RecordingShell {
        commands: [], streamed: [], fed: [], exit_codes: {},
        replies: { "identify -format %h /s/content.png": "612" },
    };
    assert.equal(image_height(shell, "/s/content.png"), 612);
    assert.equal(image_height(shell, "/s/absent.png"), 0)
}
