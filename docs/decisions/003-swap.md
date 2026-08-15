# Swap

## Context

The machines running this system can have different memory and storage capacities, and they can require different swap behavior depending on current workload.

## Decision

Because of that variability, both swap sizes are configurable rather than fixed by this project: how much compressed swap the machine keeps in RAM, and how large the single swapfile an installation leaves inside `/swap`. Either may be zero, and a machine with both at zero has no swap at all.

zram compresses with `zstd`.

The compressed swap in RAM is used before the swapfile on disk.

Hibernation is not supported. A machine suspends to RAM and never writes its memory out to swap.

## Why

- Using swapfiles inside `/swap` is required because the disk layout has no swap partition.
- One swapfile is what an installation leaves because a second one answers a need that has not appeared yet, and answering it later costs a file and a line in the mount table, with nothing about the layout to change.
- The two sizes are configurable because they follow the memory and the storage of the machine, which this project cannot know in advance; fixed here, they would be wrong on most machines and would have to be undone before they could be right.
- The compressed swap in RAM is used before the swapfile because compressing a page and keeping it in memory is orders of magnitude faster than writing it to disk. The disk is where pages go when the compressed pool is full, and not before.
- Hibernation is not supported because resuming from a swapfile inside an encrypted container is difficult to arrange and to keep working, and a distribution released now can assume the firmware of the machines it runs on suspends to RAM.
- `zstd` is chosen for zram because its compression ratio is around a third higher than the kernel default, which turns the same reserved memory into meaningfully more usable pages and so defers falling back to the disk swapfile, which is orders of magnitude slower than any difference between compression algorithms. Its cost lands on compression, which happens under memory pressure and is already a slow path, while decompression stays fast and that is what runs in the page-fault path. A faster algorithm such as `lz4` would only be preferable on a CPU weak enough for compression to compete with useful work.

## Considerations

- Swap sizes must be selected from memory, storage, and workload expectations.
- The swapfile does not have to be as large as the machine's memory. That rule exists so that hibernation has somewhere to write the whole of RAM, and nothing here hibernates.
- With no compressed swap, no compression algorithm applies. With no swapfile, `/swap` stays empty until someone puts one there.
- Additional swapfiles may be created manually later inside `/swap`.

