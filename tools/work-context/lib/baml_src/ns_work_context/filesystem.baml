// The filesystem a work context's home lives in: the device the system is
// mounted from, and the top level of that filesystem, which the installed system
// never mounts and which creating or deleting a home subvolume needs mounted.

/// A value read from the machine, or what stopped it from being read.
class Found {
    value: string,
    error: string,
}

/// The device `/` is mounted from, which holds every subvolume of the layout.
function root_device(shell: root.common.Shell) -> Found {
    let source = shell.capture("findmnt", ["-nvo", "SOURCE", "/"]);
    let unfound = root.common.must(source, "finding the device the system is mounted from");
    if (unfound != "") {
        return Found { value: "", error: unfound };
    }
    Found { value: source.stdout.trim(), error: "" }
}

/// The failures of several steps, in the order they happened, or "" when none
/// failed.
function joined_failures(failures: string[]) -> string {
    failures
        .filter(
            (failure) -> {
                failure != ""
            },
        )
        .join(" ")
}

/// Mounts the top level of the filesystem on a directory made for it, and
/// answers that directory. When it cannot be mounted, the directory is removed
/// again and what failed is the answer.
function mount_top_level(shell: root.common.Shell, device: string) -> Found {
    let made = shell.capture("mktemp", ["-d"]);
    let unmade = root.common.must(made, "making a directory to mount the top level of the filesystem on");
    if (unmade != "") {
        return Found { value: "", error: unmade };
    }
    let top = made.stdout.trim();

    let mounted = root.common.must(shell.capture("mount", ["-o", "subvolid=5", device, top]),
                                   "mounting the top level of the filesystem");
    if (mounted != "") {
        let removed = root.common.must(shell.capture("rmdir", [top]), `removing ${top}`);
        return Found { value: "", error: joined_failures([mounted, removed]) };
    }
    Found { value: top, error: "" }
}

/// Unmounts the top level from the directory it was mounted on, and removes
/// that directory. "" once both are done, or what failed.
function unmount_top_level(shell: root.common.Shell, top: string) -> string {
    let unmounted = root.common.must(shell.capture("umount", [top]),
                                     "unmounting the top level of the filesystem");
    //# a directory that is still a mount point cannot be removed, and saying
    //# that it could not be would only repeat the unmount that failed
    if (unmounted != "") {
        return unmounted;
    }
    root.common.must(shell.capture("rmdir", [top]), `removing ${top}`)
}
