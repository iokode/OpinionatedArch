// Opening the encrypted secret store an installation is handed.
//
// A dotfiles map declares the secrets its renders need and never carries their
// values, so a machine being installed has to be given them from outside. What
// it is given is one encrypted file, as
// `docs/tools/oparch-dotfiles-sync/002-secret-store-archive.md` specifies.
//
// This is a port for the same reason `root.common.Shell` is one: the work
// happens somewhere else — in `age`, because BAML's standard library has no
// `scrypt` to derive the key with — and a port is what keeps that from being
// visible anywhere above it. It is also what makes the form and the phase
// testable with no `age` and no passphrase.

interface Secrets {
    /// Whether `path` is a sealed store at all, which is answerable from its
    /// first bytes and without a passphrase.
    ///
    /// It is a question of its own because the answers are acted on
    /// differently: a file that is not a store is answered by choosing another
    /// one, and there is no reason to ask for a passphrase before knowing that.
    /// What is wrong with it needs no words from here — the caller is the one
    /// that knows what the operator called the file.
    function sealed(self, path: string) -> bool throws never

    /// Opens `sealed` with `passphrase` and writes what was inside it to
    /// `plain`. Returns what went wrong, or "" when nothing did.
    ///
    /// Decrypting is all of it. What comes out is an archive, and unpacking one
    /// is something this project already does, through the shell and with the
    /// same refusal of entries that would land outside where they are put — so
    /// the archive is handed back rather than opened here.
    ///
    /// A passphrase that is wrong and a file that is not a store are both
    /// failures, and what tells them apart is what they say: the first is
    /// retyped, the second is answered by choosing another file.
    function unseal(self, sealed: string, passphrase: string, plain: string) -> string throws never
}

/// Opens the store with `age`, through the shell every other command goes
/// through.
///
/// `age` asks a terminal for a passphrase and nothing else, except through its
/// `batchpass` plugin, which reads one from the descriptor `AGE_PASSPHRASE_FD`
/// names. The plugin is a process of its own that speaks to `age` over its own
/// standard input, so descriptor 0 is taken: the passphrase arrives on this
/// command's standard input, as every other secret here does, and `sh` moves it
/// to descriptor 3 before `age` starts. It is in no command line and in no
/// environment.
class AgeSecrets {
    shell: root.common.Shell,

    implements Secrets {
        function sealed(self, path: string) -> bool {
            self.shell.capture("age-inspect", [path]).exit_code == 0
        }
        function unseal(self, sealed: string, passphrase: string, plain: string) -> string {
            let opened = self.shell.feed("sh", age_decrypt_args(sealed, plain), passphrase);
            if (opened.exit_code == 0) {
                return "";
            }
            age_refusal(opened)
        }
    }
}

/// What `sh` is given: the script, the name it runs under, and the two paths as
/// its positional parameters, so that neither path is ever read as shell.
function age_decrypt_args(sealed: string, plain: string) -> string[] {
    [
        "-c",
        "exec 3<&0 0</dev/null; AGE_PASSPHRASE_FD=3 exec age -d -j batchpass -o \"$1\" \"$2\"",
        "sh", plain, sealed,
    ]
}

/// What a refusal from `age` means. It says which of the two it is only in
/// words, so the words are what is read.
function age_refusal(result: root.common.CommandResult) -> string {
    if (result.stderr.includes("incorrect passphrase")) {
        return "The passphrase does not open the secret store.";
    }
    if (result.stderr.includes("failed to read header")) {
        return "That file is not an encrypted secret store.";
    }
    let said = (result.stderr.lines().at(0) ?? "").trim();
    if (said == "") {
        return `Opening the secret store failed with exit code ${result.exit_code}.`;
    }
    `Opening the secret store failed: ${said}`
}

/// Opens nothing, and records that it was asked to. The passphrase is not kept,
/// for the reason `RecordingShell` does not keep what it is fed: a test that
/// could assert on it is a test that has written one down.
class RecordingSecrets {
    opened: string[],
    /// Archives that refuse to open, and what they say when they refuse.
    refusals: map<string, string>,
    /// Paths that are not sealed stores at all.
    unsealed: string[],

    implements Secrets {
        function sealed(self, path: string) -> bool {
            !self.unsealed.includes(path)
        }
        function unseal(self, sealed: string, passphrase: string, plain: string) -> string {
            self.opened.push(`${sealed} -> ${plain}`);
            self.refusals.get(sealed) ?? ""
        }
    }
}

function recording_secrets() -> RecordingSecrets {
    RecordingSecrets { opened: [], refusals: {}, unsealed: [] }
}

test "a file that is not a store is known to be one before anything is typed" {
    let secrets = recording_secrets();
    let _ = secrets.unsealed.push("/tmp/oparch/store.dfsec");

    assert.is_true(!secrets.sealed("/tmp/oparch/store.dfsec"));
    assert.is_true(secrets.sealed("/tmp/oparch/other.dfsec"))
}

test "a recorded unsealing says where it was asked to put things" {
    let secrets = recording_secrets();

    assert.equal(secrets.unseal("/tmp/oparch/store.dfsec", "a b c", "/tmp/oparch/store.tar"), "");
    assert.equal(secrets.opened, ["/tmp/oparch/store.dfsec -> /tmp/oparch/store.tar"])
}

test "an archive that refuses says so, and the passphrase is nowhere" {
    let secrets = recording_secrets();
    let _ = secrets.refusals.set("/tmp/oparch/store.dfsec", "incorrect passphrase");

    assert.equal(secrets.unseal("/tmp/oparch/store.dfsec", "wrong words", "/tmp/oparch/store.tar"),
                 "incorrect passphrase");
    assert.is_true(!secrets.opened.join(" ").includes("wrong words"))
}

function age_shell() -> root.common.RecordingShell {
    root.common.RecordingShell { commands: [], streamed: [], fed: [], replies: {}, exit_codes: {} }
}

test "whether a file is a store is asked of age-inspect, which needs no passphrase" {
    let shell = age_shell();
    let _ = shell.exit_codes.set("age-inspect /tmp/oparch/not-a-store.png", 1);
    let secrets = AgeSecrets { shell: shell };

    assert.is_true(secrets.sealed("/tmp/oparch/store.dfsec"));
    assert.is_true(!secrets.sealed("/tmp/oparch/not-a-store.png"));
    assert.equal(shell.fed, [])
}

test "age is given the passphrase on its standard input and nowhere else" {
    let shell = age_shell();
    let secrets = AgeSecrets { shell: shell };

    assert.equal(secrets.unseal("/tmp/oparch/store.dfsec", "sixteen words from the short list",
                                "/tmp/oparch/store.tar"), "");

    assert.equal(shell.fed.length(), 1);
    assert.is_true((shell.fed.at(0) ?? "").includes("AGE_PASSPHRASE_FD=3 exec age -d -j batchpass"));
    //# the paths are positional parameters, output first, and never part of
    //# the script
    assert.is_true((shell.fed.at(0) ?? "").ends_with(" sh /tmp/oparch/store.tar /tmp/oparch/store.dfsec"));
    assert.is_true(!shell.commands.join(" ").includes("sixteen words"))
}

test "a store age will not open is reported, and nothing is claimed to have opened" {
    let shell = age_shell();
    let line = `sh ${age_decrypt_args("/tmp/oparch/store.dfsec", "/tmp/oparch/store.tar").join(" ")}`;
    let _ = shell.exit_codes.set(line, 1);
    let secrets = AgeSecrets { shell: shell };

    //# the recording shell says nothing on standard error, so what is reported
    //# is the exit code; what age's words mean is held below
    assert.equal(secrets.unseal("/tmp/oparch/store.dfsec", "wrong words", "/tmp/oparch/store.tar"),
                 "Opening the secret store failed with exit code 1.")
}

test "age's refusals are told apart by what it says" {
    let wrong = root.common.CommandResult {
        exit_code: 1, stdout: "",
        stderr: "age: error: batchpass plugin: incorrect passphrase\n"
            + "age: report unexpected or unhelpful errors at https://filippo.io/age/report\n",
    };
    let not_a_store = root.common.CommandResult {
        exit_code: 1, stdout: "",
        stderr: "age: error: failed to read header: parsing age header: unexpected intro: \"x\"\n",
    };
    let other = root.common.CommandResult {
        exit_code: 1, stdout: "", stderr: "age: error: no identity matched any of the recipients\n",
    };

    assert.equal(age_refusal(wrong), "The passphrase does not open the secret store.");
    assert.equal(age_refusal(not_a_store), "That file is not an encrypted secret store.");
    assert.equal(age_refusal(other),
                 "Opening the secret store failed: age: error: no identity matched any of the recipients")
}
