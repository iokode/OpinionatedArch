// Selector evaluation. User and hostname are separate dimensions: login
// contexts and physical machines are different things.

/// The context one entry is evaluated against. `username` is null while
/// evaluating a global target, which no user selector can match.
class SelectorContext {
    hostname: string,
    username: string?,
}

function global_context(hostname: string) -> SelectorContext {
    SelectorContext { hostname: hostname, username: null }
}

function user_context(hostname: string, username: string) -> SelectorContext {
    SelectorContext { hostname: hostname, username: username }
}

/// Matching is exact and case-sensitive; listed values are OR-ed.
function selector_matches(selector: Selector, context: SelectorContext) -> bool {
    let subject = if (selector.dimension == "host") {
        context.hostname
    } else {
        context.username
    };
    if let value: string = subject {
        selector.values.includes(value)
    } else {
        false
    }
}

/// Different dimensions are AND-ed, and a matching `except` clause vetoes.
function selectors_pass(selectors: Selector[], context: SelectorContext) -> bool {
    selectors
        .every(
            (selector) -> {
                let matched = selector_matches(selector, context);
                if (selector.negate) {
                    !matched
                } else {
                    matched
                }
            },
        )
}

function user_selectors(selectors: Selector[]) -> Selector[] {
    selectors
        .filter(
            (selector) -> {
                selector.dimension == "user"
            },
        )
}

test "selector evaluation" {
    let loc = SourceLoc { file: "t.dfmap", line: 1 };
    let for_desktop = Selector { negate: false, dimension: "host", values: ["desktop"], loc: loc };
    let for_users = Selector { negate: false, dimension: "user", values: ["personal", "work"], loc: loc };
    let except_work = Selector { negate: true, dimension: "user", values: ["work"], loc: loc };

    assert.is_true(selectors_pass([for_desktop], user_context("desktop", "work")));
    assert.is_true(!selectors_pass([for_desktop], user_context("laptop", "work")));
    assert.is_true(selectors_pass([for_desktop, for_users], user_context("desktop", "work")));
    assert.is_true(!selectors_pass([for_desktop, except_work], user_context("desktop", "work")));
    assert.is_true(selectors_pass([for_desktop, except_work], user_context("desktop", "personal")));
    assert.is_true(!selectors_pass([for_users], global_context("desktop")));
    assert.is_true(selectors_pass([], global_context("desktop")));
    assert.equal(user_selectors([for_desktop, except_work]).length(), 1)
}
