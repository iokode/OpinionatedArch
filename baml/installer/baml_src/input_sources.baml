// Where content the operator points at comes from, and how it is brought here.
//
// The dotfiles package, the return message's template package and its theme are
// not values: they are content held elsewhere. Bringing it here belongs to the
// installer and to nothing else, as decided in
// `docs/decisions/018-installer-input-sources.md` — `oparch-return-message-render`
// is handed directories and resolves none of this.

/// True when content is named by URL rather than by path.
function is_url(location: string) -> bool {
    location.starts_with("http://") || location.starts_with("https://")
}

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

/// An archive named by URL is downloaded and unpacked into `destination`, which
/// the caller chooses. Nothing else about the archive decides where its
/// contents land.
///
/// Both a template package and a theme are fetched this way, so `noun` is what
/// the failures call the thing that failed. The archive is staged beside the
/// directory it is unpacked into, so its name is the destination's and two
/// fetches for two different things never write over one another.
function fetch_package(shell: root.common.Shell, files: root.common.Files,
                       url: string, staging: string, destination: string, noun: string) -> string {
    let archive = `${destination}.tar`;
    files.mkdir(staging);

    let downloaded = shell.capture("curl",
        ["-fL", "--retry", "2", "--connect-timeout", "10", "-o", archive, url]);
    if (downloaded.exit_code != 0) {
        return `Downloading the ${noun} failed with exit code ${downloaded.exit_code}: ${url}`;
    }

    //# look before unpacking: an entry that escapes is refused, not extracted
    let listing = shell.capture("tar", ["-tf", archive]);
    if (listing.exit_code != 0) {
        return `The ${noun} is not a readable archive: ${url}`;
    }
    if let entry: string = escaping_entry(listing.stdout) {
        return `The ${noun} holds an entry that would be written outside it: ${entry}`;
    }

    files.mkdir(destination);
    let extracted = shell.capture("tar", ["-xf", archive, "-C", destination]);
    if (extracted.exit_code != 0) {
        return `Unpacking the ${noun} failed with exit code ${extracted.exit_code}.`;
    }
    ""
}

// ------------------------------------------------------- where content lands

/// Where a fetched package is unpacked. The caller chooses the staging
/// directory; the archive never influences it.
function fetched_package_directory(staging: string) -> string {
    root.common.in_directory(staging, "template-package")
}

/// Where a fetched theme is unpacked. The caller chooses this path; the archive
/// never influences it.
function fetched_theme_directory(staging: string) -> string {
    root.common.in_directory(staging, "theme")
}

/// The directory the template package is finally read from, which is also the
/// one the renderer is handed: the project's own, the one that was named, or
/// the one an archive was unpacked into.
function package_directory(asset_dir: string, template: string) -> string {
    if (template == "") {
        root.return_message.default_package_directory(asset_dir)
    } else if (is_url(template)) {
        fetched_package_directory(live_staging_dir())
    } else {
        template
    }
}

/// The same, for the theme.
function theme_directory(asset_dir: string, theme: string) -> string {
    if (theme == "") {
        root.return_message.default_theme_directory(asset_dir)
    } else if (is_url(theme)) {
        fetched_theme_directory(live_staging_dir())
    } else {
        theme
    }
}

// ------------------------------------------------------------- resolving it

/// The package a configuration asks for: its own, or the project's. A package
/// named by URL is fetched first, and read from where it was unpacked.
function resolve_package(shell: root.common.Shell, files: root.common.Files,
                         asset_dir: string, template: string,
                         staging: string) -> root.return_message.LoadedPackage {
    if (is_url(template)) {
        let destination = fetched_package_directory(staging);
        let problem = fetch_package(shell, files, template, staging, destination, "template package");
        if (problem != "") {
            return root.return_message.LoadedPackage {
                package: root.return_message.empty_package(), bodies: {}, error: problem,
            };
        }
        return root.return_message.load_package(files, destination);
    }
    root.return_message.load_package(files, package_directory(asset_dir, template))
}

/// The theme a configuration asks for, resolved exactly as the package is.
function resolve_theme(shell: root.common.Shell, files: root.common.Files,
                       asset_dir: string, theme: string,
                       staging: string) -> root.return_message.ThemeParse {
    if (is_url(theme)) {
        let destination = fetched_theme_directory(staging);
        let problem = fetch_package(shell, files, theme, staging, destination, "theme");
        if (problem != "") {
            return root.return_message.ThemeParse {
                theme: root.return_message.empty_theme(), error: problem,
            };
        }
        return root.return_message.load_theme(shell, files, destination);
    }
    root.return_message.load_theme(shell, files, theme_directory(asset_dir, theme))
}

// -------------------------------------------------------------------- tests

test "is_url tells a URL from a path" {
    assert.is_true(is_url("https://example.invalid/pkg.tar"));
    assert.is_true(!is_url("/home/ivan/andorra"));
    assert.is_true(!is_url(""))
}

test "escaping_entry names the first bad entry of a listing" {
    assert.is_true(escaping_entry("manifest.yaml\nes.txt\n") == null);
    assert.equal(escaping_entry("manifest.yaml\n../../etc/passwd\nes.txt\n"), "../../etc/passwd")
}

test "fetch_package refuses an archive before unpacking it" {
    let shell = root.common.RecordingShell {
        commands: [], fed: [], streamed: [], exit_codes: {},
        replies: { "tar -tf /tmp/oparch/package.tar": "manifest.yaml\n../escape.txt\n" },
    };

    assert.equal(
        fetch_package(shell, root.common.recording_files(), "https://example.invalid/pkg.tar",
                      "/tmp/oparch", "/tmp/oparch/package", "template package"),
        "The template package holds an entry that would be written outside it: ../escape.txt");
    assert.is_true(!shell.commands.includes(
        "tar -xf /tmp/oparch/package.tar -C /tmp/oparch/package"))
}

test "fetch_package downloads, inspects and unpacks in that order" {
    let shell = root.common.RecordingShell {
        commands: [], fed: [], streamed: [], exit_codes: {},
        replies: { "tar -tf /tmp/oparch/package.tar": "manifest.yaml\nes.txt\n" },
    };

    assert.equal(
        fetch_package(shell, root.common.recording_files(), "https://example.invalid/pkg.tar",
                      "/tmp/oparch", "/tmp/oparch/package", "template package"),
        "");
    assert.equal(shell.commands, [
        "curl -fL --retry 2 --connect-timeout 10 -o /tmp/oparch/package.tar"
            + " https://example.invalid/pkg.tar",
        "tar -tf /tmp/oparch/package.tar",
        "tar -xf /tmp/oparch/package.tar -C /tmp/oparch/package",
    ])
}

test "fetch_package reports a download that failed" {
    let shell = root.common.RecordingShell {
        commands: [], fed: [], streamed: [], replies: {}, exit_codes: {},
    };
    let _ = shell.exit_codes.set(
        "curl -fL --retry 2 --connect-timeout 10 -o /tmp/oparch/package.tar"
            + " https://example.invalid/pkg.tar", 22);

    assert.equal(
        fetch_package(shell, root.common.recording_files(), "https://example.invalid/pkg.tar",
                      "/tmp/oparch", "/tmp/oparch/package", "template package"),
        "Downloading the template package failed with exit code 22: https://example.invalid/pkg.tar")
}

test "what a fetch failed at is named by the thing that was fetched" {
    let shell = root.common.RecordingShell {
        commands: [], fed: [], streamed: [], replies: {}, exit_codes: {},
    };
    let _ = shell.exit_codes.set(
        "curl -fL --retry 2 --connect-timeout 10 -o /tmp/oparch/theme.tar"
            + " https://example.invalid/theme.tar", 22);

    assert.equal(
        fetch_package(shell, root.common.recording_files(), "https://example.invalid/theme.tar",
                      "/tmp/oparch", "/tmp/oparch/theme", "theme"),
        "Downloading the theme failed with exit code 22: https://example.invalid/theme.tar")
}

test "resolve_package unpacks a URL into the staging directory it was given" {
    let shell = root.common.RecordingShell {
        commands: [], fed: [], streamed: [], exit_codes: {},
        replies: { "tar -tf /tmp/oparch/template-package.tar": "manifest.yaml\n" },
    };
    let files = root.common.recording_files();
    files.write("/tmp/oparch/template-package/manifest.yaml", root.return_message.sample_manifest());
    files.write("/tmp/oparch/template-package/es.txt", "Hola {{owner_name}}");
    files.write("/tmp/oparch/template-package/ca.txt", "Hola {{owner_name}}");

    let loaded = resolve_package(shell, files, "/assets", "https://example.invalid/pkg.tar",
                                 "/tmp/oparch");

    assert.equal(loaded.error, "");
    assert.is_true(shell.commands.includes(
        "tar -xf /tmp/oparch/template-package.tar -C /tmp/oparch/template-package"))
}

test "the directory the renderer is handed is where the content ended up" {
    //# the project's own, one that was named, and one that was unpacked
    assert.equal(package_directory("/assets", ""), "/assets/return-message");
    assert.equal(package_directory("/assets", "/home/ivan/andorra"), "/home/ivan/andorra");
    assert.equal(package_directory("/assets", "https://example.invalid/pkg.tar"),
                 "/tmp/oparch/template-package");

    assert.equal(theme_directory("/assets", ""), "/assets/return-message-theme");
    assert.equal(theme_directory("/assets", "/home/ivan/dark"), "/home/ivan/dark");
    assert.equal(theme_directory("/assets", "https://example.invalid/theme.tar"),
                 "/tmp/oparch/theme")
}
