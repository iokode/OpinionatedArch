// Reading a return-message theme, as defined in
// `docs/tools/oparch-return-message-render/003-theme-format.md`.
//
// A theme decides everything visible except the words and the logo. Parsing is
// pure: the manifest arrives as text. The one thing that cannot be decided from
// the text alone is the family name of a font the theme carries, which is read
// from the font file when the theme is loaded.

class FontDeclaration {
    /// A family already on the machine. Empty when the theme carries the file.
    family: string,
    /// Path inside the package. Empty when the family is named.
    file: string,
    /// The family fontconfig will match, filled in when the theme is loaded.
    resolved_family: string,
}

/// A text style with every key resolved: no `extends` left, and colours as the
/// value rather than the name.
class TextStyle {
    font: string,
    color: string,
    size: float,
    weight: string,
    slant: string,
    align: string,
}

/// A style as written, before its chain is resolved. An empty string, or a
/// size of zero, means the key was not declared.
class PartialStyle {
    /// Name of the style this one takes what it does not declare from.
    inherits: string,
    font: string,
    color: string,
    size: float,
    weight: string,
    slant: string,
    align: string,
}

class KindDecoration {
    text_style: string,
    icon_glyph: string,
    icon_style: string,
}

class Panel {
    fill: string,
    border_color: string,
    border_width: int,
    corner_radius: int,
    padding: int,
}

class Canvas {
    width: int,
    row_gap: int,
    column_gap: int,
    body_size_ratio: float,
}

class Spacing {
    language_heading_gap: int,
    line_gap: int,
    paragraph_gap: int,
}

class LogoBox {
    width: int,
    gap: int,
    position: string,
}

class MaskShape {
    shape: string,
    size: int,
    color: string,
}

class ScreenValues {
    background_color: string,
    /// Path inside the package. Empty when the theme has no background image.
    background_image: string,
    fit: float,
    message_gap: int,
    mask_gap: int,
}

class ArrangementRow {
    weights: int[],
}

/// The rows one number of languages is laid out in.
class Arrangement {
    count: int,
    rows: ArrangementRow[],
}

class Theme {
    version: string,
    name: string,
    fonts: map<string, FontDeclaration>,
    styles: map<string, TextStyle>,
    language_heading_style: string,
    body_style: string,
    password_prompt_style: string,
    kinds: map<string, KindDecoration>,
    password_mask: MaskShape,
    language_panel: Panel,
    password_prompt_panel: Panel,
    canvas: Canvas,
    spacing: Spacing,
    /// Absent when the theme draws no logo.
    logo: LogoBox?,
    arrangements: Arrangement[],
    screen: ScreenValues,
    /// Where the theme was read from. Its fonts and its background image are
    /// inside, and it is what the font directory is pointed at while drawing.
    directory: string,
}

class ThemeParse {
    theme: Theme,
    error: string,
}

function supported_theme_major() -> int {
    0
}

function supported_theme_minor() -> int {
    1
}

function theme_top_keys() -> string[] {
    [
        "version", "name", "palette", "fonts", "styles", "elements", "kinds",
        "password_mask", "language_panel", "password_prompt_panel", "canvas",
        "spacing", "logo", "arrangement", "screen",
    ]
}

function style_weights() -> string[] {
    ["light", "regular", "medium", "semibold", "bold"]
}

function style_slants() -> string[] {
    ["upright", "italic"]
}

function style_alignments() -> string[] {
    ["left", "center", "right"]
}

function mask_shapes() -> string[] {
    ["circle", "square"]
}

function logo_positions() -> string[] {
    ["above", "below"]
}

function empty_theme() -> Theme {
    Theme {
        version: "", name: "", fonts: {}, styles: {},
        language_heading_style: "", body_style: "", password_prompt_style: "",
        kinds: {},
        password_mask: MaskShape { shape: "", size: 0, color: "" },
        language_panel: empty_panel(),
        password_prompt_panel: empty_panel(),
        canvas: Canvas { width: 0, row_gap: 0, column_gap: 0, body_size_ratio: 0.0 },
        spacing: Spacing { language_heading_gap: 0, line_gap: 0, paragraph_gap: 0 },
        logo: null,
        arrangements: [],
        screen: ScreenValues {
            background_color: "", background_image: "", fit: 0.0, message_gap: 0, mask_gap: 0,
        },
        directory: "",
    }
}

function empty_panel() -> Panel {
    Panel { fill: "", border_color: "", border_width: 0, corner_radius: 0, padding: 0 }
}

// ---------------------------------------------------------------- a reader
//
// Every key of a theme is required, so reading one is "give me this or say
// what is wrong". A reader carries the first thing that was wrong, which is
// what turns a section into a handful of lines instead of a check per key.

class Reader {
    entries: map<string, baml.json.json>,
    /// Names the section in an error message: `canvas.` or `styles.title.`.
    path: string,
    error: string,

    function fail(self, message: string) -> void {
        if (self.error == "") {
            self.error = message;
        }
    }

    /// Refuses a key the section does not define.
    function only(self, allowed: string[]) -> void {
        if let unknown: string = root.common.unknown_key(self.entries, allowed) {
            self.fail(`Unknown key in theme: ${self.path}${unknown}`);
        }
    }

    function present(self, key: string) -> bool {
        self.entries.keys().includes(key)
    }

    function need_text(self, key: string) -> string {
        if (!self.present(key)) {
            self.fail(`${self.path}${key} is required.`);
            return "";
        }
        let read = root.common.read_text(self.entries, key, `${self.path}${key}`);
        if (read.error != "") {
            self.fail(read.error);
            return "";
        }
        read.value
    }

    function need_one_of(self, key: string, allowed: string[]) -> string {
        let value = self.need_text(key);
        if (value != "" && !allowed.includes(value)) {
            self.fail(`${self.path}${key} must be one of ${allowed.join(", ")}: ${value}`);
            return "";
        }
        value
    }

    function need_int(self, key: string) -> int {
        if (!self.present(key)) {
            self.fail(`${self.path}${key} is required.`);
            return 0;
        }
        if let value: int = root.common.as_int(self.entries.get(key)) {
            if (value <= 0) {
                self.fail(`${self.path}${key} must be greater than zero.`);
                return 0;
            }
            return value;
        }
        self.fail(`${self.path}${key} must be a whole number.`);
        0
    }

    /// A size that may be zero, which is how a border or a radius says it is
    /// not there.
    function need_extent(self, key: string) -> int {
        if (!self.present(key)) {
            self.fail(`${self.path}${key} is required.`);
            return 0;
        }
        if let value: int = root.common.as_int(self.entries.get(key)) {
            if (value < 0) {
                self.fail(`${self.path}${key} cannot be negative.`);
                return 0;
            }
            return value;
        }
        self.fail(`${self.path}${key} must be a whole number.`);
        0
    }

    function need_fraction(self, key: string) -> float {
        if (!self.present(key)) {
            self.fail(`${self.path}${key} is required.`);
            return 0.0;
        }
        if let value: float = root.common.as_float(self.entries.get(key)) {
            if (value <= 0.0) {
                self.fail(`${self.path}${key} must be greater than zero.`);
                return 0.0;
            }
            return value;
        }
        self.fail(`${self.path}${key} must be a number.`);
        0.0
    }

    function need_color(self, key: string, palette: map<string, string>) -> string {
        let name = self.need_text(key);
        if (name == "") {
            return "";
        }
        if (name.starts_with("#")) {
            self.fail(`${self.path}${key} must name a colour declared in palette, not a colour: ${name}`);
            return "";
        }
        if let value: string = palette.get(name) {
            return value;
        }
        self.fail(`${self.path}${key} names a colour the palette does not declare: ${name}`);
        ""
    }

    /// A name that must be declared somewhere else in the theme.
    function need_reference(self, key: string, declared: string[], what: string) -> string {
        let name = self.need_text(key);
        if (name == "") {
            return "";
        }
        if (!declared.includes(name)) {
            self.fail(`${self.path}${key} names ${what} the theme does not declare: ${name}`);
            return "";
        }
        name
    }

    function need_map(self, key: string) -> map<string, baml.json.json> {
        if (!self.present(key)) {
            self.fail(`${self.path}${key} is required.`);
            return root.common.empty_json_map();
        }
        if let entries: map<string, baml.json.json> = root.common.as_map(self.entries.get(key)) {
            return entries;
        }
        self.fail(`${self.path}${key} must be a mapping.`);
        root.common.empty_json_map()
    }
}

function reader_for(entries: map<string, baml.json.json>, path: string) -> Reader {
    Reader { entries: entries, path: path, error: "" }
}

/// Reads a section as its own reader, so its errors name it.
function section(parent: Reader, key: string) -> Reader {
    reader_for(parent.need_map(key), `${key}.`)
}

// -------------------------------------------------------------- the manifest

function parse_theme(text: string, directory: string) -> ThemeParse {
    let document = baml.yaml.parse(text)
        catch (e) {
            _ => {
                return ThemeParse { theme: empty_theme(), error: `Invalid YAML: ${e.message}` };
            }
        };

    let top = root.common.as_map(document) ?? root.common.empty_json_map();
    if (root.common.as_map(document) == null) {
        return ThemeParse { theme: empty_theme(), error: "The manifest must be a mapping." };
    }

    let theme = empty_theme();
    theme.directory = directory;
    let reader = reader_for(top, "");
    reader.only(theme_top_keys());

    theme.version = reader.need_text("version");
    if (reader.error == "") {
        let problem = check_theme_version(theme.version);
        if (problem != "") {
            return ThemeParse { theme: theme, error: problem };
        }
    }
    theme.name = reader.need_text("name");

    let palette = read_palette(reader);
    let fonts_problem = read_fonts(reader, theme);
    if (fonts_problem != "") {
        reader.fail(fonts_problem);
    }
    let styles_problem = read_styles(reader, theme, palette);
    if (styles_problem != "") {
        reader.fail(styles_problem);
    }

    read_elements(reader, theme);
    read_kinds(reader, theme);
    read_mask(reader, theme, palette);
    theme.language_panel = read_panel(reader, "language_panel", palette);
    theme.password_prompt_panel = read_panel(reader, "password_prompt_panel", palette);
    read_canvas(reader, theme);
    read_spacing(reader, theme);
    read_logo(reader, theme);
    read_screen(reader, theme, palette);
    let arrangement_problem = read_arrangement(reader, theme);
    if (arrangement_problem != "") {
        reader.fail(arrangement_problem);
    }

    if (reader.error != "") {
        return ThemeParse { theme: theme, error: reader.error };
    }
    ThemeParse { theme: theme, error: "" }
}

function check_theme_version(version: string) -> string {
    if (version == "") {
        return "version is required.";
    }
    let parts = version.split(".");
    if (parts.length() != 2) {
        return `Invalid version: ${version}`;
    }
    let major = root.common.parse_int(parts.at(0) ?? "");
    let minor = root.common.parse_int(parts.at(1) ?? "");
    if (major == null || minor == null) {
        return `Invalid version: ${version}`;
    }
    if ((major ?? -1) != supported_theme_major()) {
        return `This theme needs format version ${major ?? 0}, which is not implemented here.`;
    }
    if ((minor ?? 0) > supported_theme_minor()) {
        return `This theme needs format version ${version}, and what is implemented here is up to`
            + ` ${supported_theme_major()}.${supported_theme_minor()}.`;
    }
    ""
}

/// Colours are declared once and named everywhere else, so this is the only
/// place a theme writes one.
function read_palette(reader: Reader) -> map<string, string> {
    let entries = reader.need_map("palette");
    let palette: map<string, string> = {};

    for (let name in entries.keys()) {
        if (!validate_theme_name(name)) {
            reader.fail(`Invalid name in theme: palette.${name}`);
            return palette;
        }
        let read = root.common.read_text(entries, name, `palette.${name}`);
        if (read.error != "") {
            reader.fail(read.error);
            return palette;
        }
        if (!validate_color(read.value)) {
            reader.fail(`palette.${name} must be #RRGGBB or #RRGGBBAA: ${read.value}`);
            return palette;
        }
        let _ = palette.set(name, read.value);
    }
    if (palette.keys().length() == 0) {
        reader.fail("palette declares no colour.");
    }
    palette
}

function read_fonts(reader: Reader, theme: Theme) -> string {
    let entries = reader.need_map("fonts");

    for (let name in entries.keys()) {
        if (!validate_theme_name(name)) {
            return `Invalid name in theme: fonts.${name}`;
        }
        let font = reader_for(root.common.as_map(entries.get(name)) ?? root.common.empty_json_map(),
                              `fonts.${name}.`);
        if (root.common.as_map(entries.get(name)) == null) {
            return `fonts.${name} must be a mapping.`;
        }
        font.only(["family", "file"]);
        if (font.error != "") {
            return font.error;
        }

        let has_family = font.present("family");
        let has_file = font.present("file");
        if (has_family && has_file) {
            return `fonts.${name} declares both family and file, and must declare one.`;
        }
        if (!has_family && !has_file) {
            return `fonts.${name} declares neither family nor file, and must declare one.`;
        }

        let family = if (has_family) { font.need_text("family") } else { "" };
        let file = if (has_file) { font.need_text("file") } else { "" };
        if (font.error != "") {
            return font.error;
        }
        if (has_file && entry_escapes(file)) {
            return `fonts.${name}.file points outside the theme: ${file}`;
        }

        let _ = theme.fonts.set(name, FontDeclaration {
            family: family, file: file, resolved_family: family,
        });
    }
    if (theme.fonts.keys().length() == 0) {
        return "fonts declares no font.";
    }
    ""
}

function read_styles(reader: Reader, theme: Theme, palette: map<string, string>) -> string {
    let entries = reader.need_map("styles");
    let partials: map<string, PartialStyle> = {};

    for (let name in entries.keys()) {
        if (!validate_theme_name(name)) {
            return `Invalid name in theme: styles.${name}`;
        }
        let style = reader_for(root.common.as_map(entries.get(name)) ?? root.common.empty_json_map(),
                               `styles.${name}.`);
        if (root.common.as_map(entries.get(name)) == null) {
            return `styles.${name} must be a mapping.`;
        }
        style.only(["extends", "font", "color_palette", "size", "weight", "slant", "align"]);
        if (style.error != "") {
            return style.error;
        }

        let partial = PartialStyle {
            inherits: "", font: "", color: "", size: 0.0, weight: "", slant: "", align: "",
        };
        if (style.present("extends")) {
            partial.inherits = style.need_text("extends");
        }
        if (style.present("font")) {
            partial.font = style.need_reference("font", theme.fonts.keys(), "a font");
        }
        if (style.present("color_palette")) {
            partial.color = style.need_color("color_palette", palette);
        }
        if (style.present("size")) {
            partial.size = style.need_fraction("size");
        }
        if (style.present("weight")) {
            partial.weight = style.need_one_of("weight", style_weights());
        }
        if (style.present("slant")) {
            partial.slant = style.need_one_of("slant", style_slants());
        }
        if (style.present("align")) {
            partial.align = style.need_one_of("align", style_alignments());
        }
        if (style.error != "") {
            return style.error;
        }
        let _ = partials.set(name, partial);
    }

    if (partials.keys().length() == 0) {
        return "styles declares no style.";
    }

    for (let name in partials.keys()) {
        let resolved = resolve_style(partials, name, []);
        if (resolved.error != "") {
            return resolved.error;
        }
        let _ = theme.styles.set(name, resolved.style);
    }
    ""
}

class StyleResolution {
    style: TextStyle,
    error: string,
}

/// Walks the `extends` chain, taking the first value declared for each key.
/// A chain that comes back to a style it already passed is an error, not a
/// loop, and a style still missing a key at the end of it is one too.
function resolve_style(partials: map<string, PartialStyle>, name: string, seen: string[]) -> StyleResolution {
    let blank = TextStyle { font: "", color: "", size: 0.0, weight: "", slant: "", align: "" };

    if (seen.includes(name)) {
        return StyleResolution { style: blank, error: `styles.${name} extends itself.` };
    }
    let partial = partials.get(name);
    if (partial == null) {
        return StyleResolution {
            style: blank,
            error: `styles.${name} extends a style the theme does not declare.`,
        };
    }
    let declared = partial;

    let inherited = if (declared.inherits == "") {
        blank
    } else {
        let walked = seen;
        walked.push(name);
        let parent = resolve_style(partials, declared.inherits, walked);
        if (parent.error != "") {
            return StyleResolution { style: blank, error: parent.error };
        }
        parent.style
    };

    let style = TextStyle {
        font: if (declared.font != "") { declared.font } else { inherited.font },
        color: if (declared.color != "") { declared.color } else { inherited.color },
        size: if (declared.size != 0.0) { declared.size } else { inherited.size },
        weight: if (declared.weight != "") { declared.weight } else { inherited.weight },
        slant: if (declared.slant != "") { declared.slant } else { inherited.slant },
        align: if (declared.align != "") { declared.align } else { inherited.align },
    };

    if (style.font == "" || style.color == "" || style.size == 0.0
            || style.weight == "" || style.slant == "" || style.align == "") {
        return StyleResolution {
            style: style,
            error: `styles.${name} does not declare every key, and extends nothing that does.`,
        };
    }
    StyleResolution { style: style, error: "" }
}

function read_elements(reader: Reader, theme: Theme) -> void {
    let elements = section(reader, "elements");
    elements.only(["language_heading_style", "body_style", "password_prompt_style"]);
    theme.language_heading_style =
        elements.need_reference("language_heading_style", theme.styles.keys(), "a style");
    theme.body_style = elements.need_reference("body_style", theme.styles.keys(), "a style");
    theme.password_prompt_style =
        elements.need_reference("password_prompt_style", theme.styles.keys(), "a style");
    if (elements.error != "") {
        reader.fail(elements.error);
    }
}

function read_kinds(reader: Reader, theme: Theme) -> void {
    if (!reader.present("kinds")) {
        return;
    }
    let entries = reader.need_map("kinds");

    for (let kind in entries.keys()) {
        if (!field_kinds().includes(kind)) {
            reader.fail(`kinds.${kind} is not a kind a template package declares.`);
            return;
        }
        let entry = reader_for(root.common.as_map(entries.get(kind)) ?? root.common.empty_json_map(),
                               `kinds.${kind}.`);
        if (root.common.as_map(entries.get(kind)) == null) {
            reader.fail(`kinds.${kind} must be a mapping.`);
            return;
        }
        entry.only(["text_style", "icon_glyph", "icon_style"]);

        let decoration = KindDecoration { text_style: "", icon_glyph: "", icon_style: "" };
        if (entry.present("text_style")) {
            decoration.text_style = entry.need_reference("text_style", theme.styles.keys(), "a style");
        }
        if (entry.present("icon_glyph") != entry.present("icon_style")) {
            entry.fail(`kinds.${kind} declares one of icon_glyph and icon_style, and needs both.`);
        }
        if (entry.present("icon_glyph")) {
            decoration.icon_glyph = entry.need_text("icon_glyph");
            decoration.icon_style = entry.need_reference("icon_style", theme.styles.keys(), "a style");
        }
        if (entry.error != "") {
            reader.fail(entry.error);
            return;
        }
        let _ = theme.kinds.set(kind, decoration);
    }
}

function read_mask(reader: Reader, theme: Theme, palette: map<string, string>) -> void {
    let mask = section(reader, "password_mask");
    mask.only(["shape", "size", "color_palette"]);
    theme.password_mask = MaskShape {
        shape: mask.need_one_of("shape", mask_shapes()),
        size: mask.need_int("size"),
        color: mask.need_color("color_palette", palette),
    };
    if (mask.error != "") {
        reader.fail(mask.error);
    }
}

function read_panel(reader: Reader, key: string, palette: map<string, string>) -> Panel {
    let panel = section(reader, key);
    panel.only(["fill_palette", "border", "corner_radius", "padding"]);

    let border = reader_for(panel.need_map("border"), `${key}.border.`);
    border.only(["color_palette", "width"]);

    let result = Panel {
        fill: panel.need_color("fill_palette", palette),
        border_color: border.need_color("color_palette", palette),
        border_width: border.need_extent("width"),
        corner_radius: panel.need_extent("corner_radius"),
        padding: panel.need_extent("padding"),
    };
    if (panel.error != "") {
        reader.fail(panel.error);
    }
    if (border.error != "") {
        reader.fail(border.error);
    }
    result
}

function read_canvas(reader: Reader, theme: Theme) -> void {
    let canvas = section(reader, "canvas");
    canvas.only(["width", "row_gap", "column_gap", "body_size_ratio"]);
    theme.canvas = Canvas {
        width: canvas.need_int("width"),
        row_gap: canvas.need_extent("row_gap"),
        column_gap: canvas.need_extent("column_gap"),
        body_size_ratio: canvas.need_fraction("body_size_ratio"),
    };
    if (canvas.error != "") {
        reader.fail(canvas.error);
    }
}

function read_spacing(reader: Reader, theme: Theme) -> void {
    let spacing = section(reader, "spacing");
    spacing.only(["language_heading_gap", "line_gap", "paragraph_gap"]);
    theme.spacing = Spacing {
        language_heading_gap: spacing.need_extent("language_heading_gap"),
        line_gap: spacing.need_extent("line_gap"),
        paragraph_gap: spacing.need_extent("paragraph_gap"),
    };
    if (spacing.error != "") {
        reader.fail(spacing.error);
    }
}

//# a theme with no logo section draws none, which is what a theme built around
//# a background that already carries one needs
function read_logo(reader: Reader, theme: Theme) -> void {
    if (!reader.present("logo")) {
        return;
    }
    let logo = section(reader, "logo");
    logo.only(["width", "gap", "position"]);
    theme.logo = LogoBox {
        width: logo.need_int("width"),
        gap: logo.need_extent("gap"),
        position: logo.need_one_of("position", logo_positions()),
    };
    if (logo.error != "") {
        reader.fail(logo.error);
    }
}

function read_screen(reader: Reader, theme: Theme, palette: map<string, string>) -> void {
    let screen = section(reader, "screen");
    screen.only(["background_palette", "background_image", "fit", "message_gap", "mask_gap"]);

    let image = if (screen.present("background_image")) {
        screen.need_text("background_image")
    } else {
        ""
    };
    if (image != "" && entry_escapes(image)) {
        screen.fail(`screen.background_image points outside the theme: ${image}`);
    }

    let fit = screen.need_fraction("fit");
    if (fit > 1.0) {
        screen.fail("screen.fit must be at most 1.");
    }

    //# the bottom-most layer of the screen, with nothing behind it to show
    let background = screen.need_color("background_palette", palette);
    if (background.length() == 9) {
        screen.fail(`screen.background_palette must name a colour without transparency,`
            + ` because nothing is drawn behind it: ${background}`);
    }

    theme.screen = ScreenValues {
        background_color: background,
        background_image: image,
        fit: fit,
        message_gap: screen.need_extent("message_gap"),
        mask_gap: screen.need_extent("mask_gap"),
    };
    if (screen.error != "") {
        reader.fail(screen.error);
    }
}

/// Every number of languages the theme accepts, with the rows it lays them out
/// in. This is what the number of selected languages is checked against.
function read_arrangement(reader: Reader, theme: Theme) -> string {
    let entries = reader.need_map("arrangement");

    for (let key in entries.keys()) {
        let count = root.common.parse_int(key);
        if (count == null || (count ?? 0) < 1) {
            return `arrangement.${key} is not a number of languages.`;
        }
        let rows = root.common.as_list(entries.get(key));
        if (rows == null) {
            return `arrangement.${key} must be a list of rows.`;
        }

        let arrangement = Arrangement { count: count ?? 0, rows: [] };
        let cells = 0;
        for (let raw_row in rows) {
            let weights = root.common.as_list(raw_row);
            if (weights == null) {
                return `arrangement.${key} must be a list of rows, each a list of weights.`;
            }
            let row = ArrangementRow { weights: [] };
            for (let raw_weight in weights) {
                if let weight: int = root.common.as_int(raw_weight) {
                    if (weight <= 0) {
                        return `arrangement.${key} has a weight that is not greater than zero.`;
                    }
                    row.weights.push(weight);
                } else {
                    return `arrangement.${key} has a weight that is not a whole number.`;
                }
            }
            if (row.weights.length() == 0) {
                return `arrangement.${key} has a row with no column.`;
            }
            cells = cells + row.weights.length();
            arrangement.rows.push(row);
        }

        if (arrangement.rows.length() == 0) {
            return `arrangement.${key} declares no row.`;
        }
        if (cells != arrangement.count) {
            return `arrangement.${key} lays out ${cells} languages, not ${arrangement.count}.`;
        }
        theme.arrangements.push(arrangement);
    }

    if (theme.arrangements.length() == 0) {
        return "arrangement declares no number of languages.";
    }
    ""
}

/// Lowercase letters, digits and `_`, starting with a letter. The rule field
/// names follow in a template package.
function validate_theme_name(name: string) -> bool {
    validate_field_name(name)
}

/// `#RRGGBB` or `#RRGGBBAA`.
function validate_color(value: string) -> bool {
    if (!value.starts_with("#")) {
        return false;
    }
    let digits = value.slice(1, value.length());
    if (digits.length() != 6 && digits.length() != 8) {
        return false;
    }
    for (let character in digits.chars()) {
        if (!character.is_ascii_numeric()
                && !"abcdefABCDEF".includes(character)) {
            return false;
        }
    }
    true
}

// ------------------------------------------------------------ what it answers

/// The rows for a number of languages, or nothing when the theme does not lay
/// that number out.
function arrangement_for(theme: Theme, count: int) -> Arrangement? {
    for (let arrangement in theme.arrangements) {
        if (arrangement.count == count) {
            return arrangement;
        }
    }
    null
}

/// The numbers of languages the theme accepts, in order, for an error message.
function accepted_counts(theme: Theme) -> int[] {
    let counts: int[] = [];
    for (let arrangement in theme.arrangements) {
        counts.push(arrangement.count);
    }
    counts.sort_by_key((c) -> { c })
}

function style_named(theme: Theme, name: string) -> TextStyle {
    theme.styles.get(name)
        ?? TextStyle { font: "", color: "", size: 1.0, weight: "regular", slant: "upright", align: "left" }
}

/// The family a style is drawn with, as fontconfig knows it.
function family_of(theme: Theme, style: TextStyle) -> string {
    (theme.fonts.get(style.font))?.resolved_family ?? ""
}

function decoration_for(theme: Theme, kind: string) -> KindDecoration {
    theme.kinds.get(kind) ?? KindDecoration { text_style: "", icon_glyph: "", icon_style: "" }
}

// ------------------------------------------------------------- loading a theme

/// Where the project's own theme lives inside the asset directory.
function default_theme_directory(asset_dir: string) -> string {
    root.common.in_directory(asset_dir, "return-message-theme")
}

/// Reads a theme from a directory and finishes what the text alone cannot
/// answer: the family of every font the theme carries, which is read from the
/// file, and that the files it names are really there.
function load_theme(shell: root.common.Shell, files: root.common.Files, directory: string) -> ThemeParse {
    let manifest_path = root.common.in_directory(directory, "manifest.yaml");
    let manifest_text = files.read(manifest_path);
    if (manifest_text == null) {
        return ThemeParse {
            theme: empty_theme(),
            error: `The theme has no manifest.yaml: ${manifest_path}`,
        };
    }

    let parsed = parse_theme(manifest_text, directory);
    if (parsed.error != "") {
        return parsed;
    }
    let theme = parsed.theme;

    for (let name in theme.fonts.keys()) {
        let font = theme.fonts.get(name) ?? FontDeclaration { family: "", file: "", resolved_family: "" };
        if (font.file == "") {
            continue;
        }
        let path = root.common.in_directory(directory, font.file);
        if (!files.exists(path)) {
            return ThemeParse { theme: theme, error: `The theme has no ${font.file}: ${path}` };
        }
        let scanned = shell.capture("fc-scan", ["--format", "%{family}\\n", path]);
        if (scanned.exit_code != 0) {
            return ThemeParse { theme: theme, error: `The theme's ${font.file} is not a readable font.` };
        }
        let family = first_family(scanned.stdout);
        if (family == "") {
            return ThemeParse { theme: theme, error: `The theme's ${font.file} declares no family name.` };
        }
        font.resolved_family = family;
        let _ = theme.fonts.set(name, font);
    }

    if (theme.screen.background_image != "") {
        let path = root.common.in_directory(directory, theme.screen.background_image);
        if (!files.exists(path)) {
            return ThemeParse {
                theme: theme,
                error: `The theme has no ${theme.screen.background_image}: ${path}`,
            };
        }
    }

    ThemeParse { theme: theme, error: "" }
}

/// `fc-scan` names a family once per face in the file, and a face may carry
/// several names. The first of the first is the one to ask fontconfig for.
function first_family(output: string) -> string {
    let lines = root.common.nonempty_lines(output);
    let first = lines.at(0) ?? "";
    (first.split(",").at(0) ?? "").trim()
}

// -------------------------------------------------------------------- tests

function sample_theme() -> string {
    "version: \"0.1\"\n"
        + "name: \"Test theme\"\n"
        + "palette:\n  ink: \"#E8EEF4\"\n  accent: \"#8FC2FF\"\n  panel: \"#12202C\"\n"
        + "fonts:\n  sans: { family: \"Noto Sans\" }\n"
        + "styles:\n"
        + "  regular: { font: sans, color_palette: ink, size: 1.0, weight: regular,"
        + " slant: upright, align: left }\n"
        + "  title: { extends: regular, color_palette: accent, size: 1.25, weight: bold }\n"
        + "  centered: { extends: regular, align: center }\n"
        + "elements:\n"
        + "  language_heading_style: title\n  body_style: regular\n  password_prompt_style: centered\n"
        + "kinds:\n  phone: { text_style: title }\n"
        + "password_mask: { shape: circle, size: 96, color_palette: ink }\n"
        + "language_panel: { fill_palette: panel, border: { color_palette: accent, width: 4 },"
        + " corner_radius: 32, padding: 64 }\n"
        + "password_prompt_panel: { fill_palette: panel, border: { color_palette: accent, width: 0 },"
        + " corner_radius: 24, padding: 48 }\n"
        + "canvas: { width: 3840, row_gap: 96, column_gap: 96, body_size_ratio: 0.0215 }\n"
        + "spacing: { language_heading_gap: 32, line_gap: 12, paragraph_gap: 64 }\n"
        + "logo: { width: 1200, gap: 120, position: above }\n"
        + "arrangement:\n  \"1\": [[1]]\n  \"2\": [[1], [1]]\n  \"4\": [[1, 1], [1, 1]]\n"
        + "screen: { background_palette: panel, fit: 0.85, message_gap: 120, mask_gap: 48 }\n"
}

test "parse_theme reads a theme" {
    let parsed = parse_theme(sample_theme(), "/theme");

    assert.equal(parsed.error, "");
    assert.equal(parsed.theme.name, "Test theme");
    assert.equal(parsed.theme.canvas.width, 3840);
    assert.equal(parsed.theme.spacing.paragraph_gap, 64);
    assert.equal(parsed.theme.language_panel.corner_radius, 32);
    assert.equal(parsed.theme.password_mask.color, "#E8EEF4");
    assert.equal((parsed.theme.logo)?.position, "above")
}

test "a style takes from the one it extends what it does not declare" {
    let theme = parse_theme(sample_theme(), "/theme").theme;
    let title = style_named(theme, "title");

    //# declared here
    assert.equal(title.color, "#8FC2FF");
    assert.equal(title.weight, "bold");
    //# taken from regular
    assert.equal(title.font, "sans");
    assert.equal(title.align, "left");
    assert.equal(style_named(theme, "centered").align, "center")
}

test "colours are resolved through the palette, never written where they are used" {
    let theme = parse_theme(sample_theme(), "/theme").theme;
    assert.equal(style_named(theme, "regular").color, "#E8EEF4");

    let literal = sample_theme().replace("color_palette: ink, size: 1.0", "color_palette: \"#FF0000\", size: 1.0");
    assert.equal(parse_theme(literal, "/theme").error,
                 "styles.regular.color_palette must name a colour declared in palette, not a colour: #FF0000")
}

test "a name the theme does not declare is refused wherever it is used" {
    assert.equal(parse_theme(sample_theme().replace("font: sans,", "font: serif,"), "/theme").error,
                 "styles.regular.font names a font the theme does not declare: serif");
    assert.equal(parse_theme(sample_theme().replace("body_style: regular", "body_style: plain"), "/theme").error,
                 "elements.body_style names a style the theme does not declare: plain");
    assert.equal(parse_theme(sample_theme().replace("color_palette: accent, size: 1.25", "color_palette: red, size: 1.25"), "/theme").error,
                 "styles.title.color_palette names a colour the palette does not declare: red")
}

test "a style that never declares every key is refused" {
    let incomplete = sample_theme().replace(
        "  regular: { font: sans, color_palette: ink, size: 1.0, weight: regular, slant: upright, align: left }",
        "  regular: { font: sans, color_palette: ink, size: 1.0 }");
    assert.equal(parse_theme(incomplete, "/theme").error,
                 "styles.regular does not declare every key, and extends nothing that does.")
}

test "a chain of extends that comes back on itself is refused" {
    let cycle = sample_theme().replace("  centered: { extends: regular, align: center }",
                                       "  centered: { extends: centered, align: center }");
    assert.equal(parse_theme(cycle, "/theme").error, "styles.centered extends itself.")
}

test "the arrangement says which numbers of languages the theme accepts" {
    let theme = parse_theme(sample_theme(), "/theme").theme;

    assert.equal(accepted_counts(theme), [1, 2, 4]);
    assert.is_true(arrangement_for(theme, 3) == null);

    let four = arrangement_for(theme, 4) ?? Arrangement { count: 0, rows: [] };
    assert.equal(four.rows.length(), 2);
    assert.equal((four.rows.at(0))?.weights, [1, 1])
}

test "an arrangement that does not lay out the number it is keyed by is refused" {
    assert.equal(parse_theme(sample_theme().replace("\"4\": [[1, 1], [1, 1]]", "\"4\": [[1, 1], [1]]"), "/theme").error,
                 "arrangement.4 lays out 3 languages, not 4.");
    assert.equal(parse_theme(sample_theme().replace("\"2\": [[1], [1]]", "\"2\": [[1], [0]]"), "/theme").error,
                 "arrangement.2 has a weight that is not greater than zero.")
}

test "a key the format does not define is refused" {
    assert.equal(parse_theme(sample_theme().replace("name: \"Test theme\"", "name: \"Test theme\"\nwat: 1"),
                             "/theme").error,
                 "Unknown key in theme: wat");
    assert.equal(parse_theme(sample_theme().replace("shape: circle, size: 96", "shape: circle, sized: 96"),
                             "/theme").error,
                 "Unknown key in theme: password_mask.sized")
}

test "a value outside its list, or of the wrong shape, is refused" {
    assert.equal(parse_theme(sample_theme().replace("shape: circle", "shape: triangle"), "/theme").error,
                 "password_mask.shape must be one of circle, square: triangle");
    assert.equal(parse_theme(sample_theme().replace("position: above", "position: sideways"), "/theme").error,
                 "logo.position must be one of above, below: sideways");
    assert.equal(parse_theme(sample_theme().replace("fit: 0.85", "fit: 1.5"), "/theme").error,
                 "screen.fit must be at most 1.");
    assert.equal(parse_theme(sample_theme().replace("ink: \"#E8EEF4\"", "ink: \"#GGGGGG\""), "/theme").error,
                 "palette.ink must be #RRGGBB or #RRGGBBAA: #GGGGGG")
}

test "the screen background refuses transparency, and nothing else does" {
    let transparent = sample_theme().replace("panel: \"#12202C\"", "panel: \"#12202CE6\"");
    assert.equal(parse_theme(transparent, "/theme").error,
                 "screen.background_palette must name a colour without transparency,"
                     + " because nothing is drawn behind it: #12202CE6");

    //# the same colour, with the same alpha, is what a panel is filled with
    let behind_the_panels = transparent.replace("background_palette: panel", "background_palette: ink");
    let parsed = parse_theme(behind_the_panels, "/theme");

    assert.equal(parsed.error, "");
    assert.equal(parsed.theme.language_panel.fill, "#12202CE6")
}

test "a kind outside the five a template package declares is refused" {
    assert.equal(parse_theme(sample_theme().replace("  phone: { text_style: title }",
                                                    "  fax: { text_style: title }"), "/theme").error,
                 "kinds.fax is not a kind a template package declares.")
}

test "an icon needs both its glyph and its style" {
    assert.equal(parse_theme(sample_theme().replace("  phone: { text_style: title }",
                                                    "  phone: { icon_glyph: \"A\" }"), "/theme").error,
                 "kinds.phone declares one of icon_glyph and icon_style, and needs both.")
}

test "a theme with no logo section draws none" {
    let bare = sample_theme().replace("logo: { width: 1200, gap: 120, position: above }\n", "");
    let parsed = parse_theme(bare, "/theme");

    assert.equal(parsed.error, "");
    assert.is_true(parsed.theme.logo == null)
}

test "a theme for a version that is not implemented is refused" {
    assert.equal(parse_theme(sample_theme().replace("version: \"0.1\"", "version: \"1.0\""), "/theme").error,
                 "This theme needs format version 1, which is not implemented here.")
}

test "load_theme reads the family of a font the theme carries" {
    let files = root.common.recording_files();
    files.write("/theme/manifest.yaml",
                sample_theme().replace("  sans: { family: \"Noto Sans\" }",
                                       "  sans: { family: \"Noto Sans\" }\n  icons: { file: \"fonts/icons.ttf\" }"));
    files.write("/theme/fonts/icons.ttf", "");
    let shell = root.common.RecordingShell {
        commands: [], streamed: [], fed: [], exit_codes: {},
        replies: { "fc-scan --format %{family}\\n /theme/fonts/icons.ttf": "Theme Icons\nTheme Icons\n" },
    };

    let loaded = load_theme(shell, files, "/theme");

    assert.equal(loaded.error, "");
    assert.equal((loaded.theme.fonts.get("icons"))?.resolved_family, "Theme Icons");
    //# a family named directly is not looked up
    assert.equal((loaded.theme.fonts.get("sans"))?.resolved_family, "Noto Sans")
}

test "load_theme reports a font file the theme names and does not carry" {
    let files = root.common.recording_files();
    files.write("/theme/manifest.yaml",
                sample_theme().replace("  sans: { family: \"Noto Sans\" }",
                                       "  sans: { file: \"fonts/absent.ttf\" }"));
    let shell = root.common.RecordingShell {
        commands: [], streamed: [], fed: [], exit_codes: {}, replies: {},
    };

    assert.equal(load_theme(shell, files, "/theme").error,
                 "The theme has no fonts/absent.ttf: /theme/fonts/absent.ttf");
    assert.equal(shell.commands, [])
}

test "load_theme reports a theme that is not there" {
    let shell = root.common.RecordingShell {
        commands: [], streamed: [], fed: [], exit_codes: {}, replies: {},
    };
    assert.equal(load_theme(shell, root.common.recording_files(), "/nowhere").error,
                 "The theme has no manifest.yaml: /nowhere/manifest.yaml")
}

test "first_family takes one name out of what fc-scan repeats" {
    assert.equal(first_family("Noto Sans\nNoto Sans\n"), "Noto Sans");
    assert.equal(first_family("Open Sans,Open Sans Regular\n"), "Open Sans");
    assert.equal(first_family(""), "")
}
