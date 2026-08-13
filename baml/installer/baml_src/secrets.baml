// Opening the encrypted secret store an installation is handed.
//
// A dotfiles map declares the secrets its renders need and never carries their
// values, so a machine being installed has to be given them from outside. What
// it is given is one encrypted file, as
// `docs/tools/oparch-dotfiles-sync/002-secret-store-archive.md` specifies.
//
// This is a port for the same reason `root.common.Shell` is one: the work
// happens somewhere BAML cannot reach — its standard library carries no
// cryptography at all — and a port is what keeps that from being visible
// anywhere above it. It is also what makes the form and the phase testable with
// no host, no bridge and no passphrase.

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
    /// the archive is handed back rather than opened here, and the one thing
    /// that has to happen outside BAML is the only thing that does.
    ///
    /// A passphrase that is wrong and a file that is not a store are both
    /// failures, and what tells them apart is what they say: the first is
    /// retyped, the second is answered by choosing another file.
    function unseal(self, sealed: string, passphrase: string, plain: string) -> string throws never
}

/// Wraps the closure the host passes at the entrypoint, for the reason
/// `root.common.HostShell` wraps its own: an interface does not cross a
/// generated SDK boundary.
class HostSecrets {
    on_sealed: (string) -> bool throws never,
    on_unseal: (string, string, string) -> string throws never,
    implements Secrets {
        function sealed(self, path: string) -> bool {
            self.on_sealed(path)
        }
        function unseal(self, sealed: string, passphrase: string, plain: string) -> string {
            self.on_unseal(sealed, passphrase, plain)
        }
    }
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
