// The review screen: every setting the form collected, one row each.

/// A source as the review screen shows it: what was chosen, and from where.
function describe_source(source: root.installer.Source) -> string {
    if (root.installer.is_default_source(source)) {
        return "the project's own";
    }
    `${source.origin}: ${source.location}`
}

/// One setting on the review screen. The label and the value are kept apart
/// because the screen draws them apart: aligned in two columns, and in two
/// colours. Joining them here would also have to be undone there, and a value
/// like `git: https://…` carries a colon of its own to be undone wrongly by.
class SummaryRow {
    label: string,
    value: string,
    /// True for a row that belongs to the one above it.
    nested: bool,
}

function row(label: string, value: string) -> SummaryRow {
    SummaryRow { label: label, value: value, nested: false }
}

function nested_row(label: string, value: string) -> SummaryRow {
    SummaryRow { label: label, value: value, nested: true }
}

/// The review screen, one row per setting.
function summary_rows(config: root.installer.InstallConfig) -> SummaryRow[] {
    let rows = [
        row("target disk", config.disk),
        row("install mode", config.install_mode),
        row("packages from", if (config.offline) { "the medium" } else { "the network" }),
        row("preserved work contexts", config.preserved_work_contexts.join(", ")),
        row("ucode package", config.ucode_package),
        row("gpu driver", config.gpu_driver),
        row("zram size (GB)", `${config.swap.zram_gb}`),
        row("disk swapfile size (GB)", `${config.swap.swapfile_gb}`),
        row("work contexts", config.work_contexts.join(", ")),
        row("keymap", config.console_keymap),
        row("timezone", config.timezone),
        row("hostname", config.hostname),
    ];

    if let dotfiles: root.installer.Source = config.dotfiles {
        rows.push(row("dotfiles package", describe_source(dotfiles)));
        //# the archive is named; what opens it is not, here or anywhere else
        if let store: root.installer.SecretStoreInput = config.secret_store {
            rows.push(nested_row("secret store", describe_source(store.archive)));
        }
    } else {
        rows.push(row("dotfiles package", "none"));
    }

    if let message: root.installer.ReturnMessageInput = config.return_message {
        let values = message.values;
        rows.push(row("return message", values.languages.join(", ")));
        rows.push(nested_row("template package", describe_source(message.template)));
        rows.push(nested_row("theme", describe_source(message.theme)));
        for (let name in values.fields.keys().sort_by_key((k) -> { k })) {
            rows.push(nested_row(name, values.fields.get(name) ?? ""));
        }
        if let logo: root.installer.Source = message.logo {
            rows.push(nested_row("logo", describe_source(logo)));
        }
    } else {
        rows.push(row("return message", "none"));
    }
    rows
}

/// What a row reads as, for a test that cares about the whole of it rather than
/// about the two halves.
function summary_line(at: SummaryRow) -> string {
    let indent = if (at.nested) { "  " } else { "" };
    `${indent}${at.label}: ${at.value}`
}

function summary_lines(config: root.installer.InstallConfig) -> string[] {
    let lines: string[] = [];
    for (let at in summary_rows(config)) {
        lines.push(summary_line(at));
    }
    lines
}

test "summary_lines describes an installation without optional sections" {
    let config = root.installer.empty_config();
    config.disk = "/dev/sda";
    let lines = summary_lines(config);

    assert.is_true(lines.includes("target disk: /dev/sda"));
    assert.is_true(lines.includes("dotfiles package: none"));
    assert.is_true(lines.includes("return message: none"))
}

test "summary_lines says where each source comes from" {
    let config = root.installer.empty_config();
    config.dotfiles = root.installer.source_at("git", "https://example.invalid/dotfiles.git");
    config.return_message = root.installer.empty_return_message_input();

    let lines = summary_lines(config);

    assert.is_true(lines.includes("dotfiles package: git: https://example.invalid/dotfiles.git"));
    //# the project's own is named as such, not as an empty location
    assert.is_true(lines.includes("  template package: the project's own"));
    assert.is_true(lines.includes("  theme: the project's own"))
}

test "summary_lines lists the return message fields it was given" {
    let config = root.installer.empty_config();
    config.return_message = root.installer.ReturnMessageInput {
        template: root.installer.default_source(),
        theme: root.installer.default_source(),
        values: root.return_message.ReturnMessageConfig {
            languages: ["es", "ca"],
            fields: { "phone": "+376 000 000", "owner_name": "Ivan" },
        },
    };
    let lines = summary_lines(config);

    assert.is_true(lines.includes("return message: es, ca"));
    assert.is_true(lines.includes("  owner_name: Ivan"));
    assert.is_true(lines.includes("  phone: +376 000 000"));
    assert.is_true(!lines.join("\n").includes("logo:"))
}
