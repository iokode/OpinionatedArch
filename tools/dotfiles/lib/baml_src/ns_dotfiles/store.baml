// What a plan needs from the secret store.

/// What the plan needs from the store: each file once, relative to the store's
/// root, in a stable order. This is the list an archive of a store has to
/// satisfy, and an empty one is the answer that no store is needed at all.
function required_secret_files(plan: Plan) -> string[] {
    let wanted: string[] = [];
    for (let planned in plan.targets) {
        for (let relative in planned.secret_files) {
            if (!wanted.includes(relative)) {
                wanted.push(relative);
            }
        }
    }
    wanted
        .sort_by_key(
            (entry) -> {
                entry
            },
        )
}
