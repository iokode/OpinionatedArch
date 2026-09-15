// oparch-password-rotate.
//
// Rotates the shared secret of the encrypted container and every work context.
// The command is documented in `docs/tools/password/rotate/000-command.md`, and
// what it runs is the password library.
//
// There is no host program. Nothing here needs a terminal interface or the
// output of a command while it is still running, so `baml pack` turns this into
// the executable itself.

class Options {
    old_password: string,
    new_password: string,
    /// What is wrong with the command line, or "" when nothing is.
    error: string,
}

/// Reads the options. Everything before the first one is the invocation itself.
///
/// A value is taken as it comes, whatever it starts with: a secret that begins
/// with a dash is still the secret.
function parse_options(argv: string[]) -> Options {
    let args: string[] = [];
    let started = false;
    for (let argument in argv) {
        if (started || argument.starts_with("--")) {
            started = true;
            args.push(argument);
        }
    }

    let options = Options { old_password: "", new_password: "", error: "" };
    let old_given = false;
    let new_given = false;
    let index = 0;
    while (index < args.length()) {
        let name = args.at(index) ?? "";
        if (name != "--old-password" && name != "--new-password") {
            options.error = `unknown option '${name}'`;
            return options;
        }
        if let value: string = args.at(index + 1) {
            if (name == "--old-password") {
                options.old_password = value;
                old_given = true;
            } else {
                options.new_password = value;
                new_given = true;
            }
        } else {
            options.error = `option '${name}' requires a value`;
            return options;
        }
        index = index + 2;
    }

    if (!old_given) {
        options.error = "option '--old-password' is required";
    } else if (!new_given) {
        options.error = "option '--new-password' is required";
    }
    options
}

test "both secrets are read past what the runner puts in front" {
    let options = parse_options(["/usr/bin/oparch-password-rotate", "main",
                                 "--old-password", "old secret", "--new-password", "new secret"]);

    assert.equal(options.error, "");
    assert.equal(options.old_password, "old secret");
    assert.equal(options.new_password, "new secret")
}

test "a secret that begins with dashes is still the secret" {
    let options = parse_options(["oparch-password-rotate",
                                 "--old-password", "--old", "--new-password", "-new"]);

    assert.equal(options.error, "");
    assert.equal(options.old_password, "--old");
    assert.equal(options.new_password, "-new")
}

test "each secret is mandatory" {
    assert.equal(parse_options(["oparch-password-rotate", "--new-password", "new secret"]).error,
                 "option '--old-password' is required");
    assert.equal(parse_options(["oparch-password-rotate", "--old-password", "old secret"]).error,
                 "option '--new-password' is required");
    assert.equal(parse_options(["oparch-password-rotate"]).error,
                 "option '--old-password' is required")
}

test "an option left without a value is refused" {
    assert.equal(parse_options(["oparch-password-rotate", "--old-password"]).error,
                 "option '--old-password' requires a value")
}

test "an option nobody declared is refused rather than ignored" {
    assert.equal(parse_options(["oparch-password-rotate", "--force"]).error,
                 "unknown option '--force'")
}

/// ENTRYPOINT. `baml pack main` turns this file into the executable.
function main() -> null {
    let shell = root.common.system_shell();
    //# before anything else, the options included: a run that is not root's is
    //# refused whatever it was asked. The tool runs as root because what it
    //# changes is the header of the encrypted container and the passwords of
    //# the accounts
    let refused = root.common.require_root(shell, "oparch-password-rotate");
    if (refused != "") {
        baml.io.eprintln(`error: ${refused}`);
        return baml.sys.exit(1);
    }
    let options = parse_options(baml.sys.argv());
    if (options.error != "") {
        baml.io.eprintln(`error: ${options.error}`);
        return baml.sys.exit(2);
    }

    let rotation = root.password.rotate_shared_secret(shell, options.old_password,
                                                      options.new_password);
    if (!rotation.ok()) {
        //# the message is the only place an operator learns why, so what the
        //# failing command said goes with it
        baml.io.eprintln(`error: ${rotation.failure}`);
        for (let line in root.common.nonempty_lines(rotation.stderr)) {
            baml.io.eprintln(line);
        }
        return baml.sys.exit(1);
    }
    baml.sys.exit(0)
}
