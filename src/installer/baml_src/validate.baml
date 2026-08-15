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
    if (!(hostname.char_at(0)).is_ascii_alphanumeric()) {
        return false;
    }
    for (let character in hostname.chars()) {
        if (!character.is_ascii_alphanumeric() && character != "." && character != "-") {
            return false;
        }
    }
    true
}

/// Lowercase letters, digits, underscore and dash; must start with a lowercase
/// letter or underscore; 1..32 chars.
function validate_username(username: string) -> bool {
    if (username.length() <= 0 || username.length() > 32) {
        return false;
    }
    let first = username.char_at(0);
    if (!first.is_ascii_lowercase() && first != "_") {
        return false;
    }
    for (let character in username.chars()) {
        if (
            !character.is_ascii_lowercase()
                && !character.is_ascii_numeric()
                && character != "_"
                && character != "-"
        ) {
            return false;
        }
    }
    true
}

/// Parses the comma-separated work contexts. A work context is named by the
/// account that carries it, so the name has to be a valid username. Rejects
/// invalid and reserved names, drops duplicates, and requires at least one.
function parse_work_contexts_csv(raw: string) -> WorkContextsParse {
    let contexts: string[] = [];
    for (let token in raw.split(",")) {
        let name = token.trim();
        if (name == "") {
            continue;
        }
        if (!validate_username(name)) {
            return WorkContextsParse { work_contexts: [], error: `Invalid work context name: ${name}` };
        }
        if (name == "system") {
            return WorkContextsParse { work_contexts: [], error: "Work context name 'system' is reserved." };
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

/// Swap sizes: non-negative integers only.
function parse_size_gb(raw: string) -> int? {
    let text = raw.trim();
    if (text == "" || !text.is_ascii_numeric()) {
        return null;
    }
    root.common.parse_int(text)
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

test "validate_username follows the useradd rules" {
    assert.is_true(validate_username("ivan"));
    assert.is_true(validate_username("_svc"));
    assert.is_true(validate_username("user-1_2"));
    assert.is_true(!validate_username(""));
    assert.is_true(!validate_username("Ivan"));
    assert.is_true(!validate_username("1user"));
    assert.is_true(!validate_username("has space"));
    assert.is_true(!validate_username("x".repeat(33)))
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

test "parse_size_gb takes non-negative integers only" {
    assert.equal(parse_size_gb("0"), 0);
    assert.equal(parse_size_gb(" 16 "), 16);
    assert.is_true(parse_size_gb("") == null);
    assert.is_true(parse_size_gb("-1") == null);
    assert.is_true(parse_size_gb("1.5") == null);
    assert.is_true(parse_size_gb("many") == null)
}

