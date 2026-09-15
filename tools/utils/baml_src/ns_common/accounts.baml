// Names of accounts: what a username may be, and what a work context may be
// named. The installer checks the names it is given and a tool that creates a
// work context checks the one it is given, and both check them here.

/// Lowercase letters, digits, underscore and dash; must start with a lowercase
/// letter or underscore; 1..32 chars.
function validate_username(username: string) -> bool {
    if (username.length() <= 0 || username.length() > 32) {
        return false;
    }
    let first = username.at(0) ?? "";
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

/// Why a name cannot be a work context's, or "" when it can. A work context is
/// named by the account that carries it, so the name has to be a valid
/// username, and `system` is reserved.
function work_context_name_error(name: string) -> string {
    if (!validate_username(name)) {
        return `Invalid work context name: ${name}`;
    }
    if (name == "system") {
        return "Work context name 'system' is reserved.";
    }
    ""
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

test "a work context is named like an account, and not system" {
    assert.equal(work_context_name_error("personal"), "");
    assert.equal(work_context_name_error("Bad"), "Invalid work context name: Bad");
    assert.equal(work_context_name_error("system"), "Work context name 'system' is reserved.")
}
