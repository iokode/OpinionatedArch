// Template scanning and substitution. Raw single-line text substitution only:
// no shell evaluation, no command substitution, no conditions, no loops, no
// format-aware escaping and no functions.

class TextSegment {
    text: string,
}

class RefSegment {
    name: string,
}

type Segment = TextSegment | RefSegment;

/// Splits a template into literal text and `{{name}}` references.
///
/// A placeholder is escaped with a leading backslash: exactly one `\` is
/// removed and the remaining text, braces included, becomes literal. A `{{`
/// with no `}}` on the same line is literal text too, because substitution
/// never spans lines.
function scan_template(text: string) -> Segment[] {
    let segments: Segment[] = [];
    let rest = text;
    let scanning = true;
    while (scanning) {
        let open = rest.index_of("{{");
        if let start: int = open {
            let before = rest.slice(0, start);
            let after = rest.slice(start + 2, rest.length());
            let close = after.index_of("}}");
            let newline = after.index_of("\n");
            let terminated = if let end: int = close {
                if let line_end: int = newline {
                    line_end > end
                } else {
                    true
                }
            } else {
                false
            };
            if let end: int = close {
                if (terminated) {
                    let body = after.slice(0, end);
                    if (before != "") {
                        let _ = segments.push(TextSegment { text: before });
                    }
                    if (body.starts_with("\\")) {
                        //# escaped: drop one backslash and keep the braces literal
                        let _ = segments
                            .push(
                                TextSegment { text: "{{" + body.slice(1, body.length()) + "}}" },
                            );
                    } else {
                        let _ = segments.push(RefSegment { name: body });
                    }
                    rest = after.slice(end + 2, after.length());
                } else {
                    let _ = segments.push(TextSegment { text: before + "{{" });
                    rest = after;
                }
            } else {
                let _ = segments.push(TextSegment { text: before + "{{" });
                rest = after;
            }
        } else {
            if (rest != "") {
                let _ = segments.push(TextSegment { text: rest });
            }
            scanning = false;
        }
    }
    segments
}

/// Every `<category>.<key>` referenced by a template, without the built-ins and
/// without duplicates.
function template_references(text: string) -> string[] {
    let names: string[] = [];
    for (let segment in scan_template(text)) {
        if let reference: RefSegment = segment {
            if (!builtin_reference_names().includes(reference.name) && !names.includes(reference.name)) {
                let _ = names.push(reference.name);
            }
        }
    }
    names
}

/// The built-in `{{USER}}`, `{{HOME}}` and `{{HOST}}` references a template
/// uses, without duplicates.
function template_builtin_references(text: string) -> string[] {
    let names: string[] = [];
    for (let segment in scan_template(text)) {
        if let reference: RefSegment = segment {
            if (builtin_reference_names().includes(reference.name) && !names.includes(reference.name)) {
                let _ = names.push(reference.name);
            }
        }
    }
    names
}

/// Substitutes every reference of a scanned template. `substitutions` must
/// already hold a value for each referenced name.
function render_segments(segments: Segment[], substitutions: map<string, string>) -> Resolution {
    let out = "";
    for (let segment in segments) {
        let piece = match (segment) {
            let literal: TextSegment => Resolved { text: literal.text },
            let reference: RefSegment => {
                if let value: string = substitutions.get(reference.name) {
                    Resolved { text: value }
                } else {
                    Unresolved { message: `unresolved reference '{{${reference.name}}}'` }
                }
            },
        };
        match (piece) {
            let resolved: Resolved => {
                out = out + resolved.text;
            },
            let unresolved: Unresolved => {
                return unresolved;
            },
        }
    }
    Resolved { text: out }
}

test "template scanning and escaping" {
    let segments = scan_template("account = \"{{github.account}}\"\n");
    assert.equal(segments.length(), 3);
    assert.equal(segments.at(1) ?? TextSegment { text: "" }, RefSegment { name: "github.account" });

    assert
        .equal(
            template_references("{{USER}} {{git.email}} {{git.email}} {{github.token}}"),
            ["git.email", "github.token"],
        );

    let substitutions: map<string, string> = { "github.account": "personal-account", "github.token": "secret-value" };
    assert
        .equal(
            render_segments(
                scan_template("{\"account\":\"{{github.account}}\",\"pat\":\"{{github.token}}\"}"),
                substitutions,
            ),
            Resolved { text: "{\"account\":\"personal-account\",\"pat\":\"secret-value\"}" },
        );

    let empty: map<string, string> = {};
    assert
        .equal(
            render_segments(scan_template("{{\\git.email}}"), empty),
            Resolved { text: "{{git.email}}" },
        );
    assert
        .equal(
            render_segments(scan_template("{{\\\\git.email}}"), empty),
            Resolved { text: "{{\\git.email}}" },
        );
    assert
        .equal(
            render_segments(scan_template("{{\\\\\\git.email}}"), empty),
            Resolved { text: "{{\\\\git.email}}" },
        );
    assert
        .equal(
            render_segments(scan_template("a {{ unterminated\nb"), empty),
            Resolved { text: "a {{ unterminated\nb" },
        );
    assert.is_true(render_segments(scan_template("{{git.email}}"), empty) is Unresolved)
}
