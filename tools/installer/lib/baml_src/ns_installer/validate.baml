// Input rules, ported from InstallerInput.cs. All pure, all tested here.

/// A parse that either produced a value or an error message for the user.
class WorkContextsParse {
    work_contexts: string[],
    error: string,
}

/// Letters, digits, dots and dashes; must start alphanumeric; 1..63 chars.
function validate_hostname(hostname: string) -> bool {
    if (hostname.length() <= 0 || hostname.length() > 63) {
        return false;
    }
    if (!(hostname.at(0) ?? "").is_ascii_alphanumeric()) {
        return false;
    }
    for (let character in hostname.chars()) {
        if (!character.is_ascii_alphanumeric() && character != "." && character != "-") {
            return false;
        }
    }
    true
}

/// Parses the comma-separated work contexts. Rejects the names a work context
/// cannot take, which `root.common.work_context_name_error` decides, drops
/// duplicates, and requires at least one.
function parse_work_contexts_csv(raw: string) -> WorkContextsParse {
    let contexts: string[] = [];
    for (let token in raw.split(",")) {
        let name = token.trim();
        if (name == "") {
            continue;
        }
        let invalid = root.common.work_context_name_error(name);
        if (invalid != "") {
            return WorkContextsParse { work_contexts: [], error: invalid };
        }
        if (!contexts.includes(name)) {
            contexts.push(name);
        }
    }
    if (contexts.length() == 0) {
        return WorkContextsParse { work_contexts: [], error: "At least one valid work context name is required." };
    }
    WorkContextsParse { work_contexts: contexts, error: "" }
}

/// Same rules, but an empty list is allowed.
function parse_optional_work_contexts_csv(raw: string) -> WorkContextsParse {
    if (raw.trim() == "") {
        return WorkContextsParse { work_contexts: [], error: "" };
    }
    parse_work_contexts_csv(raw)
}

test "validate_hostname accepts what Arch accepts" {
    assert.is_true(validate_hostname("oparch"));
    assert.is_true(validate_hostname("oparch-01.local"));
    assert.is_true(validate_hostname("a"));
    assert.is_true(!validate_hostname(""));
    assert.is_true(!validate_hostname("-leading-dash"));
    assert.is_true(!validate_hostname(".leading-dot"));
    assert.is_true(!validate_hostname("has space"));
    assert.is_true(!validate_hostname("has_underscore"));
    assert.is_true(!validate_hostname("x".repeat(64)));
    assert.is_true(validate_hostname("x".repeat(63)))
}

test "parse_work_contexts_csv trims, dedupes and keeps order" {
    let parsed = parse_work_contexts_csv(" ivan , work ,ivan, ");
    assert.equal(parsed.error, "");
    assert.equal(parsed.work_contexts, ["ivan", "work"])
}

test "parse_work_contexts_csv rejects bad input" {
    assert
        .equal(
            parse_work_contexts_csv("").error,
            "At least one valid work context name is required.",
        );
    assert
        .equal(
            parse_work_contexts_csv("  ,  ").error,
            "At least one valid work context name is required.",
        );
    assert
        .equal(
            parse_work_contexts_csv("ivan,system").error,
            "Work context name 'system' is reserved.",
        );
    assert.equal(parse_work_contexts_csv("ivan,Bad").error, "Invalid work context name: Bad")
}

test "parse_optional_work_contexts_csv allows nothing at all" {
    let parsed = parse_optional_work_contexts_csv("   ");
    assert.equal(parsed.error, "");
    assert.equal(parsed.work_contexts, [])
}
