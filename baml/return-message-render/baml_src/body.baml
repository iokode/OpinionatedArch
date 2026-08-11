// Turning a message into markup.
//
// The words come from a template package and the values from an operator, so
// both are escaped. The only markup here is what this file writes: the style a
// theme asks for around each value, and the icon its kind puts in front of it.
// That is what makes `kind` mean something without letting a package decide
// how anything looks.

/// The kind a package declares for one of its fields.
function kind_of(package: root.return_message.TemplatePackage, field: string) -> string {
    for (let declared in package.fields) {
        if (declared.name == field) {
            return declared.kind;
        }
    }
    "text"
}

/// One substituted value: its icon, a space, and the value itself, each in the
/// style its kind asks for.
function value_markup(theme: root.return_message.Theme, package: root.return_message.TemplatePackage,
                      field: string, value: string, inner: int) -> string {
    let decoration = root.return_message.decoration_for(theme, kind_of(package, field));

    let text_style = if (decoration.text_style == "") {
        root.return_message.style_named(theme, theme.body_style)
    } else {
        root.return_message.style_named(theme, decoration.text_style)
    };
    let drawn = span(theme, text_style, point_size(theme, text_style, inner), escape_markup(value));

    if (decoration.icon_glyph == "") {
        return drawn;
    }
    let icon_style = root.return_message.style_named(theme, decoration.icon_style);
    span(theme, icon_style, point_size(theme, icon_style, inner), escape_markup(decoration.icon_glyph))
        + " " + drawn
}

/// Replaces every reference in a piece of text, escaping everything around it.
function substitute_markup(theme: root.return_message.Theme,
                           package: root.return_message.TemplatePackage, text: string,
                           values: map<string, string>, inner: int) -> string {
    let out = "";
    let rest = text;

    while (true) {
        if let open: int = rest.index_of("{{") {
            out = out + escape_markup(rest.substring(0, open));
            let after = rest.substring(open + 2, rest.length());
            if let close: int = after.index_of("}}") {
                let field = after.substring(0, close).trim();
                out = out + value_markup(theme, package, field, values.get(field) ?? "", inner);
                rest = after.substring(close + 2, after.length());
            } else {
                return out + escape_markup(after);
            }
        } else {
            return out + escape_markup(rest);
        }
    }
    out
}

/// The message of one language as markup, with its unanswered optional regions
/// gone. The words are the package's; every tag around them is this tool's.
function render_markup(theme: root.return_message.Theme,
                       package: root.return_message.TemplatePackage, body: string,
                       values: map<string, string>, inner: int) -> string {
    let split = root.return_message.split_body(body);
    if (split.error != "") {
        return "";
    }

    let out = "";
    for (let piece in split.pieces) {
        if (piece.optional) {
            let complete = true;
            for (let name in root.return_message.referenced_fields(piece.text)) {
                if ((values.get(name) ?? "") == "") {
                    complete = false;
                }
            }
            if (complete) {
                out = out + substitute_markup(theme, package, piece.text, values, inner);
            }
        } else {
            out = out + substitute_markup(theme, package, piece.text, values, inner);
        }
    }
    out.trim()
}

/// The paragraphs of a message. A blank line in the package's text is what
/// separates them, and the theme is what says how much air they get.
function paragraphs(markup: string) -> string[] {
    let found: string[] = [];
    for (let piece in markup.split("\n\n")) {
        let trimmed = piece.trim();
        if (trimmed != "") {
            found.push(trimmed);
        }
    }
    found
}

/// Wraps a piece of markup in a style. Everything drawn has to be inside a
/// span of its own: what is left outside one is drawn with ImageMagick's
/// defaults, which is a small black serif and not what any theme asked for.
function wrap_style(theme: root.return_message.Theme, style_name: string,
                    markup: string, inner: int) -> string {
    let style = root.return_message.style_named(theme, style_name);
    span(theme, style, point_size(theme, style, inner), markup)
}

/// A whole run in one style, for the texts that carry no values: the language's
/// own name and the password prompt.
function plain_markup(theme: root.return_message.Theme, style_name: string,
                      text: string, inner: int) -> string {
    let style = root.return_message.style_named(theme, style_name);
    span(theme, style, point_size(theme, style, inner), escape_markup(text))
}

// -------------------------------------------------------------------- tests

function test_package() -> root.return_message.TemplatePackage {
    root.return_message.parse_manifest(root.return_message.sample_manifest()).package
}

test "kind_of answers with what the package declared" {
    assert.equal(kind_of(test_package(), "phone"), "phone");
    assert.equal(kind_of(test_package(), "owner_name"), "text");
    assert.equal(kind_of(test_package(), "unknown"), "text")
}

test "a value is wrapped in the style its kind asks for" {
    let theme = sample_test_theme();
    let markup = render_markup(theme, test_package(), "Call {{phone}}.",
                               { "phone": "+376 000 000" }, 1824);

    //# the words around it are plain, the value is not
    assert.is_true(markup.starts_with("Call <span"));
    assert.is_true(markup.includes(">+376 000 000</span>"));
    assert.is_true(markup.ends_with("."))
}

test "a value whose kind the theme does not decorate is drawn as the body" {
    let theme = sample_test_theme();
    let body = root.return_message.style_named(theme, theme.body_style);
    let markup = render_markup(theme, test_package(), "{{owner_name}}", { "owner_name": "Ivan" }, 1824);

    assert.equal(markup, span(theme, body, point_size(theme, body, 1824), "Ivan"))
}

test "what a package or an operator wrote can never become markup" {
    let theme = sample_test_theme();
    let markup = render_markup(theme, test_package(), "A <b>bold</b> claim by {{owner_name}}",
                               { "owner_name": "Smith & Sons" }, 1824);

    assert.is_true(markup.starts_with("A &lt;b&gt;bold&lt;/b&gt; claim by "));
    assert.is_true(markup.includes("Smith &amp; Sons"));
    //# the only tags left are the ones this tool opened
    assert.equal(markup.split("<span").length() - 1, 1)
}

test "an unanswered optional region takes its words out of the markup" {
    let theme = sample_test_theme();
    let markup = render_markup(theme, test_package(), "Call {{owner_name}}[[ or {{phone}}]].",
                               { "owner_name": "Ivan" }, 1824);
    assert.is_true(!markup.includes(" or "));
    assert.is_true(markup.ends_with("."))
}

test "a paragraph is wrapped in the body style, and its values override it" {
    let theme = sample_test_theme();
    let markup = wrap_style(theme, theme.body_style,
                            render_markup(theme, test_package(), "Call {{phone}}.",
                                          { "phone": "+376 000 000" }, 1824),
                            1824);
    let body = root.return_message.style_named(theme, theme.body_style);

    //# the words are inside the body's span
    assert.is_true(markup.starts_with(`<span font_family="${root.return_message.family_of(theme, body)}"`));
    assert.is_true(markup.includes(">Call <span"));
    assert.is_true(markup.ends_with("</span>"))
}

test "paragraphs are what a blank line separates" {
    assert.equal(paragraphs("one\ntwo\n\nthree\n"), ["one\ntwo", "three"]);
    assert.equal(paragraphs("only one"), ["only one"]);
    assert.equal(paragraphs("   "), [])
}
