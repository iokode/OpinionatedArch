using System;
using System.Collections.Generic;
using System.Linq;
using IOKode.OpinionatedArch.CommandLine;
using IOKode.OpinionatedFramework.Facades;

namespace IOKode.OpinionatedArch.Installer;

internal static class Disk
{
    public static List<DiskTarget> ListInstallTargets(Target live)
    {
        var output = ShellCommand.Capture(live, "lsblk", "-dpno", "NAME,TYPE");
        var disks = new List<DiskTarget>();
        foreach (var line in output.Split('\n', StringSplitOptions.RemoveEmptyEntries))
        {
            var fields = line.Split((char[]?)null, StringSplitOptions.RemoveEmptyEntries);
            if (fields.Length == 2 && fields[1] == "disk")
            {
                var path = fields[0];
                disks.Add(new DiskTarget
                {
                    Path = path,
                    Size = ReadLsblkField(live, path, "SIZE"),
                    Model = ReadLsblkField(live, path, "MODEL")
                });
            }
        }

        if (disks.Count == 0)
        {
            throw new Exception("No selectable disks found.");
        }

        return disks;
    }

    public static string FormatDiskLabel(DiskTarget disk)
    {
        return string.IsNullOrEmpty(disk.Model)
            ? $"{disk.Path} ({disk.Size})"
            : $"{disk.Path} ({disk.Size}, {disk.Model})";
    }

    public static void PrepareLayout(Target live, Target target, InstallConfig config)
    {
        if (config.InstallMode == "keep-homes")
        {
            throw new NotSupportedException("keep-homes install mode is not supported yet.");
        }

        ShellCommand.Run(live, "wipefs", "-af", config.TargetDisk);
        ShellCommand.Run(live, "sgdisk", "--zap-all", config.TargetDisk);
        ShellCommand.Run(live, "sgdisk", "-n", "1:0:+1G", "-t", "1:ef00", "-c", "1:EFI", config.TargetDisk);
        ShellCommand.Run(live, "sgdisk", "-n", "2:0:0", "-t", "2:8300", "-c", "2:CRYPTROOT", config.TargetDisk);

        var efiPart = PartitionPath(config.TargetDisk, 1);
        var rootPart = PartitionPath(config.TargetDisk, 2);

        ShellCommand.Run(live, "partprobe", config.TargetDisk);
        ShellCommand.Run(live, "udevadm", "settle");
        ShellCommand.Working(live, $"Formatting EFI partition {efiPart}...", "mkfs.fat", "-F32", efiPart);
        ShellCommand.RunWithInput(live, $"Creating LUKS2 container on {rootPart}...", config.SharedSecret, "cryptsetup",
            "luksFormat", "--type", "luks2", "--batch-mode", "--key-file", "-", rootPart);
        ShellCommand.RunWithInput(live, $"Opening LUKS2 container on {rootPart}...", config.SharedSecret, "cryptsetup",
            "open", "--key-file", "-", rootPart, "cryptroot");
        ShellCommand.Working(live, "Creating Btrfs filesystem...", "mkfs.btrfs", "-f", "/dev/mapper/cryptroot");

        ShellCommand.Run(live, "mount", "/dev/mapper/cryptroot", target.RootPath);
        foreach (var subvolume in new[]
                     { "@", "@recovery", "home", "@snapshots", "@log", "@pkg", "@dotfiles", "@swap" })
        {
            ShellCommand.Run(live, "btrfs", "subvolume", "create", TargetFile.Path(target, $"/{subvolume}"));
        }

        foreach (var user in config.LoginUsers)
        {
            ShellCommand.Run(live, "btrfs", "subvolume", "create", TargetFile.Path(target, $"/home/@{user}"));
        }

        ShellCommand.Run(live, "umount", target.RootPath);

        ShellCommand.Run(live, "mount", "-o", "subvol=@", "/dev/mapper/cryptroot", target.RootPath);
        foreach (var directory in new[]
                 {
                     "/boot", "/home", "/var", "/var/log", "/var/cache", "/var/cache/pacman", "/var/cache/pacman/pkg",
                     "/snapshots", "/dotfiles", "/swap"
                 })
        {
            TargetFile.CreateDirectory(target, directory);
        }

        ShellCommand.Run(live, "mount", "-o", "subvol=@log", "/dev/mapper/cryptroot",
            TargetFile.Path(target, "/var/log"));
        ShellCommand.Run(live, "mount", "-o", "subvol=@pkg", "/dev/mapper/cryptroot",
            TargetFile.Path(target, "/var/cache/pacman/pkg"));
        ShellCommand.Run(live, "mount", "-o", "subvol=@snapshots", "/dev/mapper/cryptroot",
            TargetFile.Path(target, "/snapshots"));
        ShellCommand.Run(live, "mount", "-o", "subvol=@dotfiles", "/dev/mapper/cryptroot",
            TargetFile.Path(target, "/dotfiles"));
        ShellCommand.Run(live, "mount", "-o", "subvol=@swap", "/dev/mapper/cryptroot",
            TargetFile.Path(target, "/swap"));
        TargetFile.CreateDirectory(target, "/snapshots/system/automatic");
        TargetFile.CreateDirectory(target, "/snapshots/system/manual");
        foreach (var user in config.LoginUsers)
        {
            TargetFile.CreateDirectory(target, $"/home/{user}");
            ShellCommand.Run(live, "mount", "-o", $"subvol=home/@{user}", "/dev/mapper/cryptroot",
                TargetFile.Path(target, $"/home/{user}"));
            TargetFile.CreateDirectory(target, $"/snapshots/home/{user}/automatic");
            TargetFile.CreateDirectory(target, $"/snapshots/home/{user}/manual");
        }

        ShellCommand.Run(live, "mount", efiPart, TargetFile.Path(target, "/boot"));

        config.RootPartUuid =
            TextFiles.Trim(ShellCommand.Capture(live, "blkid", "-s", "UUID", "-o", "value", rootPart));
        Log.Info("Disk layout is ready.");
    }

    private static string ReadLsblkField(Target live, string path, string field)
    {
        try
        {
            return TextFiles.Trim(
                ShellCommand.Capture(live, "lsblk", "-dno", field, path).Split('\n').FirstOrDefault() ?? string.Empty);
        }
        catch
        {
            return string.Empty;
        }
    }

    private static string PartitionPath(string disk, byte index)
    {
        return disk.Contains("nvme", StringComparison.Ordinal) || disk.Contains("mmcblk", StringComparison.Ordinal) ||
               disk.Contains("loop", StringComparison.Ordinal)
            ? $"{disk}p{index}"
            : $"{disk}{index}";
    }
}
