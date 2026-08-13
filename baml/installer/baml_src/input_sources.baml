// Where content the operator points at comes from, and how it is brought here.
//
// The dotfiles package, the return message's template package and its theme are
// not values: they are content held elsewhere. Bringing it here belongs to the
// installer and to nothing else, as decided in
// `docs/tools/oparch-installer/003-input-sources.md` — `oparch-return-message-render`
// is handed directories and resolves none of this.
//
// Every origin but the project's own ends in the same place: a directory under
// the staging path that the installer chose. A local origin is copied rather
// than read where it lies, because what it came from is unmounted when the
// installation starts, and may be on the disk that is about to be erased.

/// The first entry of a listing that would be written outside the directory the
/// archive is extracted into, if any. Checked before extracting rather than
/// trusted to `tar`. What counts as escaping is the same rule a theme's own
/// file names follow, so it is asked of the format rather than repeated here.
function escaping_entry(listing: string) -> string? {
    for (let entry in root.common.nonempty_lines(listing)) {
        if (root.return_message.entry_escapes(entry)) {
            return entry;
        }
    }
    null
}

/// Unpacks an archive into `destination`, refusing it whole if any entry would
/// land anywhere else. Nothing the archive carries decides where it goes.
function unpack_archive(shell: root.common.Shell, files: root.common.Files,
                        archive: string, destination: string, noun: string) -> string {
    let listing = shell.capture("tar", ["-tf", archive]);
    if (listing.exit_code != 0) {
        return `The ${noun} is not a readable archive: ${archive}`;
    }
    if let entry: string = escaping_entry(listing.stdout) {
        return `The ${noun} holds an entry that would be written outside it: ${entry}`;
    }

    files.mkdir(destination);
    let extracted = shell.capture("tar", ["-xf", archive, "-C", destination]);
    if (extracted.exit_code != 0) {
        return root.common.must(extracted, `Unpacking the ${noun}`);
    }
    ""
}

/// Brings the content of `source` into `destination`, whatever its origin.
/// `noun` is what the failures call the thing that failed.
///
/// The project's own content is already where it belongs, so nothing is done
/// for it: what is read is the asset directory, and the caller knows that.
function bring_here(shell: root.common.Shell, files: root.common.Files,
                    source: Source, staging: string, destination: string,
                    noun: string) -> string {
    if (is_default_source(source)) {
        return "";
    }
    files.mkdir(staging);

    if (source.origin == "git") {
        //# one revision is all that is read, and a history is not the content
        let cloned = shell.capture("git", ["clone", "--depth", "1", source.location, destination]);
        return root.common.must(cloned, `Cloning the ${noun} from ${source.location}`);
    }

    if (source.origin == "tar") {
        //# the archive is staged beside the directory it is unpacked into, so
        //# two fetches for two different things never write over one another
        let archive = `${destination}.tar`;
        let downloaded = shell.capture("curl",
            ["-fL", "--retry", "2", "--connect-timeout", "10", "-o", archive, source.location]);
        let fetched = root.common.must(downloaded, `Downloading the ${noun} from ${source.location}`);
        if (fetched != "") {
            return fetched;
        }
        return unpack_archive(shell, files, archive, destination, noun);
    }

    //# local: a directory or an archive, and which one is a fact of the
    //# filesystem rather than of what was typed
    if (shell.capture("test", ["-d", source.location]).exit_code == 0) {
        files.mkdir(destination);
        //# the contents, not the directory: what lands here is the package
        let copied = shell.capture("cp", ["-r", `${source.location}/.`, destination]);
        return root.common.must(copied, `Copying the ${noun} from ${source.location}`);
    }
    if (!files.exists(source.location)) {
        return `The ${noun} is not there: ${source.location}`;
    }
    unpack_archive(shell, files, source.location, destination, noun)
}

// ------------------------------------------------------- where content lands

/// Where a package that was brought here is put. The caller chooses the
/// staging directory and the name; nothing an archive or a repository carries
/// influences either.
function staged_package_directory(staging: string) -> string {
    root.common.in_directory(staging, "template-package")
}

/// The same, for a theme.
function staged_theme_directory(staging: string) -> string {
    root.common.in_directory(staging, "theme")
}

/// The same, for the dotfiles package.
function staged_dotfiles_directory(staging: string) -> string {
    root.common.in_directory(staging, "dotfiles")
}

/// The directory the template package is finally read from, which is also the
/// one the renderer is handed: the project's own, or the staging directory
/// everything else was brought into.
function package_directory(asset_dir: string, template: Source) -> string {
    if (is_default_source(template)) {
        root.return_message.default_package_directory(asset_dir)
    } else {
        staged_package_directory(live_staging_dir())
    }
}

/// The same, for the theme.
function theme_directory(asset_dir: string, theme: Source) -> string {
    if (is_default_source(theme)) {
        root.return_message.default_theme_directory(asset_dir)
    } else {
        staged_theme_directory(live_staging_dir())
    }
}

// ------------------------------------------------------------- resolving it

/// Brings every source a configuration names into the staging directory.
///
/// This is the unattended counterpart of the pickers: there is nobody choosing,
/// so the moment the installer learns what the content is, is the moment the
/// file is checked. It happens before anything is written, which is what makes
/// it safe for a file to name a path on the disk that is about to be erased, or
/// on a medium that will be unmounted when the installation starts.
function bring_every_source(shell: root.common.Shell, files: root.common.Files,
                            config: InstallConfig, staging: string) -> string {
    if let dotfiles: Source = config.dotfiles {
        let problem = bring_here(shell, files, dotfiles, staging,
                                 staged_dotfiles_directory(staging), "dotfiles package");
        if (problem != "") {
            return problem;
        }
    }

    if let message: ReturnMessageInput = config.return_message {
        let package = bring_here(shell, files, message.template, staging,
                                 staged_package_directory(staging), "template package");
        if (package != "") {
            return package;
        }
        let theme = bring_here(shell, files, message.theme, staging,
                               staged_theme_directory(staging), "theme");
        if (theme != "") {
            return theme;
        }
    }
    ""
}

/// The template package a configuration asks for, brought here and read.
function resolve_package(shell: root.common.Shell, files: root.common.Files,
                         asset_dir: string, template: Source,
                         staging: string) -> root.return_message.LoadedPackage {
    let problem = bring_here(shell, files, template, staging,
                             staged_package_directory(staging), "template package");
    if (problem != "") {
        return root.return_message.LoadedPackage {
            package: root.return_message.empty_package(), bodies: {}, error: problem,
        };
    }
    root.return_message.load_package(files, package_directory(asset_dir, template))
}

/// The theme a configuration asks for, brought here exactly as the package is.
function resolve_theme(shell: root.common.Shell, files: root.common.Files,
                       asset_dir: string, theme: Source,
                       staging: string) -> root.return_message.ThemeParse {
    let problem = bring_here(shell, files, theme, staging,
                             staged_theme_directory(staging), "theme");
    if (problem != "") {
        return root.return_message.ThemeParse {
            theme: root.return_message.empty_theme(), error: problem,
        };
    }
    root.return_message.load_theme(shell, files, theme_directory(asset_dir, theme))
}

// -------------------------------------------------------------------- tests

function fetching_shell() -> root.common.RecordingShell {
    root.common.RecordingShell {
        commands: [], fed: [], streamed: [], exit_codes: {}, replies: {},
    }
}

test "escaping_entry names the first bad entry of a listing" {
    assert.is_true(escaping_entry("manifest.yaml\nes.txt\n") == null);
    assert.equal(escaping_entry("manifest.yaml\n../../etc/passwd\nes.txt\n"), "../../etc/passwd")
}

test "the project's own content is not brought anywhere" {
    let shell = fetching_shell();

    assert.equal(bring_here(shell, root.common.recording_files(), default_source(),
                            "/tmp/oparch", "/tmp/oparch/theme", "theme"),
                 "");
    assert.equal(shell.commands, [])
}

test "a repository is cloned at one revision" {
    let shell = fetching_shell();

    assert.equal(
        bring_here(shell, root.common.recording_files(),
                   source_at("git", "https://example.invalid/dotfiles.git"),
                   "/tmp/oparch", "/tmp/oparch/dotfiles", "dotfiles package"),
        "");
    assert.equal(shell.commands, [
        "git clone --depth 1 https://example.invalid/dotfiles.git /tmp/oparch/dotfiles",
    ])
}

test "a clone that failed is reported with what was asked for" {
    let shell = fetching_shell();
    let _ = shell.exit_codes.set(
        "git clone --depth 1 https://example.invalid/gone.git /tmp/oparch/dotfiles", 128);

    assert.equal(
        bring_here(shell, root.common.recording_files(),
                   source_at("git", "https://example.invalid/gone.git"),
                   "/tmp/oparch", "/tmp/oparch/dotfiles", "dotfiles package"),
        "Cloning the dotfiles package from https://example.invalid/gone.git"
            + " failed with exit code 128.")
}

test "a remote archive is downloaded, inspected and unpacked in that order" {
    let shell = fetching_shell();
    let _ = shell.replies.set("tar -tf /tmp/oparch/template-package.tar", "manifest.yaml\nes.txt\n");

    assert.equal(
        bring_here(shell, root.common.recording_files(),
                   source_at("tar", "https://example.invalid/pkg.tar"),
                   "/tmp/oparch", "/tmp/oparch/template-package", "template package"),
        "");
    assert.equal(shell.commands, [
        "curl -fL --retry 2 --connect-timeout 10 -o /tmp/oparch/template-package.tar"
            + " https://example.invalid/pkg.tar",
        "tar -tf /tmp/oparch/template-package.tar",
        "tar -xf /tmp/oparch/template-package.tar -C /tmp/oparch/template-package",
    ])
}

test "a download that failed is reported and nothing is unpacked" {
    let shell = fetching_shell();
    let _ = shell.exit_codes.set(
        "curl -fL --retry 2 --connect-timeout 10 -o /tmp/oparch/theme.tar"
            + " https://example.invalid/theme.tar", 22);

    assert.equal(
        bring_here(shell, root.common.recording_files(),
                   source_at("tar", "https://example.invalid/theme.tar"),
                   "/tmp/oparch", "/tmp/oparch/theme", "theme"),
        "Downloading the theme from https://example.invalid/theme.tar"
            + " failed with exit code 22.");
    assert.equal(shell.commands.length(), 1)
}

test "an archive is refused whole before anything is unpacked" {
    let shell = fetching_shell();
    let _ = shell.replies.set("tar -tf /tmp/oparch/template-package.tar",
                              "manifest.yaml\n../escape.txt\n");

    assert.equal(
        bring_here(shell, root.common.recording_files(),
                   source_at("tar", "https://example.invalid/pkg.tar"),
                   "/tmp/oparch", "/tmp/oparch/template-package", "template package"),
        "The template package holds an entry that would be written outside it: ../escape.txt");
    assert.is_true(!shell.commands.includes(
        "tar -xf /tmp/oparch/template-package.tar -C /tmp/oparch/template-package"))
}

test "a local directory is copied here, contents and all" {
    let shell = fetching_shell();

    assert.equal(
        bring_here(shell, root.common.recording_files(),
                   source_at("local", "/run/oparch/media/sdb1/andorra"),
                   "/tmp/oparch", "/tmp/oparch/template-package", "template package"),
        "");
    //# `test -d` is what tells a directory from an archive, not the name
    assert.equal(shell.commands, [
        "test -d /run/oparch/media/sdb1/andorra",
        "cp -r /run/oparch/media/sdb1/andorra/. /tmp/oparch/template-package",
    ])
}

test "a local archive is unpacked here rather than read where it lies" {
    let shell = fetching_shell();
    let _ = shell.exit_codes.set("test -d /run/oparch/media/sdb1/andorra.tar", 1);
    let _ = shell.replies.set("tar -tf /run/oparch/media/sdb1/andorra.tar", "manifest.yaml\n");
    let files = root.common.recording_files();
    files.present.push("/run/oparch/media/sdb1/andorra.tar");

    assert.equal(
        bring_here(shell, files,
                   source_at("local", "/run/oparch/media/sdb1/andorra.tar"),
                   "/tmp/oparch", "/tmp/oparch/theme", "theme"),
        "");
    assert.equal(shell.commands, [
        "test -d /run/oparch/media/sdb1/andorra.tar",
        "tar -tf /run/oparch/media/sdb1/andorra.tar",
        "tar -xf /run/oparch/media/sdb1/andorra.tar -C /tmp/oparch/theme",
    ])
}

test "a local location that is neither a directory nor a file is reported" {
    let shell = fetching_shell();
    let _ = shell.exit_codes.set("test -d /run/oparch/media/sdb1/gone", 1);

    assert.equal(
        bring_here(shell, root.common.recording_files(),
                   source_at("local", "/run/oparch/media/sdb1/gone"),
                   "/tmp/oparch", "/tmp/oparch/theme", "theme"),
        "The theme is not there: /run/oparch/media/sdb1/gone")
}

test "the directory the renderer is handed is where the content ended up" {
    let brought = source_at("tar", "https://example.invalid/pkg.tar");

    assert.equal(package_directory("/assets", default_source()),
                 "/assets/return-message");
    assert.equal(package_directory("/assets", brought), "/tmp/oparch/template-package");

    assert.equal(theme_directory("/assets", default_source()),
                 "/assets/return-message-theme");
    assert.equal(theme_directory("/assets", source_at("local", "/media/pen/dark")),
                 "/tmp/oparch/theme")
}

test "resolve_package reads what was brought into the staging directory" {
    let shell = fetching_shell();
    let _ = shell.replies.set("tar -tf /tmp/oparch/template-package.tar", "manifest.yaml\n");
    let files = root.common.recording_files();
    files.write("/tmp/oparch/template-package/manifest.yaml", root.return_message.sample_manifest());
    files.write("/tmp/oparch/template-package/es.txt", "Hola {{owner_name}}");
    files.write("/tmp/oparch/template-package/ca.txt", "Hola {{owner_name}}");

    let loaded = resolve_package(shell, files, "/assets",
                                 source_at("tar", "https://example.invalid/pkg.tar"),
                                 "/tmp/oparch");

    assert.equal(loaded.error, "");
    assert.is_true(shell.commands.includes(
        "tar -xf /tmp/oparch/template-package.tar -C /tmp/oparch/template-package"))
}
