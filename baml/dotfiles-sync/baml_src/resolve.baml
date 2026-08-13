// Value and secret resolution. Values are versioned in the map; secret values
// live only in the local secret store, outside `/dotfiles`.

class Resolved {
    text: string,
}

class Unresolved {
    message: string,
}

type Resolution = Resolved | Unresolved;

/// A secret declaration together with the store file its value would come from.
class SecretLocation {
    decl: SecretDecl,
    /// Where the file sits inside the store, which is what anything carrying a
    /// store from one machine to another has to hold.
    relative: string,
    path: string,
}

type SecretLookup = SecretLocation | Unresolved;

/// The root of the local dotfiles secret store.
function default_secrets_root() -> string {
    "/etc/oparch/dotfiles-sync/secrets"
}

function builtin_reference_names() -> string[] {
    ["USER", "HOME", "HOST"]
}

/// Every declared value and secret of the assembled map.
class Catalog {
    values: ValueDef[],
    secrets: SecretDecl[],
    secrets_root: string,

    function has_value(self, name: string) -> bool {
        self.values
            .some(
                (value) -> {
                    value.full_name() == name
                },
            )
    }

    function has_secret(self, name: string) -> bool {
        self.secrets
            .some(
                (secret) -> {
                    secret.full_name() == name
                },
            )
    }

    /// Default-plus-override resolution: a definition with no selectors is the
    /// default, a selector-qualified definition overrides it for every context
    /// its selectors match.
    function resolve_value(self, name: string, context: SelectorContext) -> Resolution {
        let definitions = self
            .values
            .filter(
                (value) -> {
                    value.full_name() == name
                },
            );
        if (definitions.length() == 0) {
            return Unresolved { message: `no value named '${name}' is declared` };
        }
        let qualified = definitions
            .filter(
                (value) -> {
                    value.selectors.length() > 0 && selectors_pass(value.selectors, context)
                },
            );
        if (qualified.length() > 1) {
            return Unresolved {
                message: `more than one selector-qualified definition of '${name}' matches this context`,
            };
        }
        if let only: ValueDef = qualified.at(0) {
            return Resolved { text: only.value };
        }
        let defaults = definitions
            .filter(
                (value) -> {
                    value.selectors.length() == 0
                },
            );
        if (defaults.length() > 1) {
            return Unresolved { message: `more than one default definition of '${name}' is declared` };
        }
        if let fallback: ValueDef = defaults.at(0) {
            Resolved { text: fallback.value }
        } else {
            Unresolved {
                message: `no definition of '${name}' matches this context and no default is declared`,
            }
        }
    }

    /// The store file a declared secret would be read from. The value itself is
    /// never part of the plan.
    function locate_secret(self, name: string, context: SelectorContext) -> SecretLookup {
        let declarations = self
            .secrets
            .filter(
                (secret) -> {
                    secret.full_name() == name && selectors_pass(secret.selectors, context)
                },
            );
        let declaration = declarations.at(0);
        if (declaration == null) {
            return Unresolved { message: `no secret named '${name}' is declared for this context` };
        }
        let scope = declaration.scope;
        if (
            declarations
                .some(
                    (other) -> {
                        other.scope != scope
                    },
                )
        ) {
            return Unresolved { message: `secret '${name}' is declared with conflicting scopes` };
        }
        if (scope == "user") {
            if let username: string = context.username {
                self.at_store(declaration, `user/${username}/${name}`)
            } else {
                Unresolved {
                    message: `user-scoped secret '${name}' is referenced by a global target`,
                }
            }
        } else {
            self.at_store(declaration, `global/${name}`)
        }
    }

    /// One place decides where inside the store a secret lives, so what is read
    /// and what an archive of the store has to carry can never disagree.
    function at_store(self, decl: SecretDecl, relative: string) -> SecretLocation {
        SecretLocation { decl: decl, relative: relative, path: `${self.secrets_root}/${relative}` }
    }

    /// A reference must resolve to exactly one declared value or secret.
    function classify_reference(self, name: string) -> Resolution {
        if (self.has_value(name) && self.has_secret(name)) {
            Unresolved { message: `'${name}' is declared both as a value and as a secret` }
        } else if (self.has_value(name)) {
            Resolved { text: "value" }
        } else if (self.has_secret(name)) {
            Resolved { text: "secret" }
        } else {
            Unresolved { message: `'${name}' is neither a declared value nor a declared secret` }
        }
    }
}

/// Reads a secret value from the store. One trailing newline is stripped, with
/// no other transformation.
function read_secret_value(files: root.common.Files, path: string) -> Resolution {
    if let text: string = files.read(path) {
        if (text.ends_with("\n")) {
            Resolved { text: text.substring(0, text.length() - 1) }
        } else {
            Resolved { text: text }
        }
    } else {
        Unresolved { message: `cannot read secret file '${path}'` }
    }
}

test "value resolution is default plus override" {
    let loc = SourceLoc { file: "t.dfmap", line: 1 };
    let for_iokode = Selector { negate: false, dimension: "user", values: ["iokode"], loc: loc };
    let for_test_machine = Selector { negate: false, dimension: "host", values: ["test-machine"], loc: loc };

    let catalog = Catalog {
        values: [
            ValueDef {
                category: "git",
                key: "email",
                value: "ivan@example.com",
                selectors: [],
                loc: loc,
            },
            ValueDef {
                category: "git",
                key: "email",
                value: "ivan@iokode.net",
                selectors: [for_iokode],
                loc: loc,
            },
            ValueDef {
                category: "git",
                key: "sign_commits",
                value: "true",
                selectors: [],
                loc: loc,
            },
            ValueDef {
                category: "git",
                key: "sign_commits",
                value: "false",
                selectors: [for_test_machine],
                loc: loc,
            },
        ],
        secrets: [
            SecretDecl { category: "github", key: "token", scope: "user", selectors: [], loc: loc },
            SecretDecl {
                category: "backup",
                key: "password",
                scope: "global",
                selectors: [],
                loc: loc,
            },
        ],
        secrets_root: default_secrets_root(),
    };

    let iokode = user_context("desktop", "iokode");
    let other = user_context("desktop", "work");
    let test_machine = user_context("test-machine", "work");

    assert.equal(catalog.resolve_value("git.email", iokode), Resolved { text: "ivan@iokode.net" });
    assert.equal(catalog.resolve_value("git.email", other), Resolved { text: "ivan@example.com" });
    assert.equal(catalog.resolve_value("git.sign_commits", other), Resolved { text: "true" });
    assert
        .equal(catalog.resolve_value("git.sign_commits", test_machine), Resolved { text: "false" });
    assert.is_true(catalog.resolve_value("git.missing", other) is Unresolved);

    assert
        .equal(
            catalog.locate_secret("github.token", iokode),
            SecretLocation {
                decl: SecretDecl {
                    category: "github",
                    key: "token",
                    scope: "user",
                    selectors: [],
                    loc: loc,
                },
                relative: "user/iokode/github.token",
                path: "/etc/oparch/dotfiles-sync/secrets/user/iokode/github.token",
            },
        );
    assert.is_true(catalog.locate_secret("github.token", global_context("desktop")) is Unresolved);
    assert.is_true(catalog.classify_reference("backup.password") is Resolved);
    assert.is_true(catalog.classify_reference("git.nothing") is Unresolved)
}
