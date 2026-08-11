using System.Collections.Generic;
using System.IO;
using IOKode.OpinionatedArch.CommandLine;
using IOKode.OpinionatedFramework.Facades;

namespace IOKode.OpinionatedArch.Installer;

internal static class BootstrapInstaller
{
    private const string NetbootUrl = "https://archlinux.org/static/netboot/ipxe-arch.efi";
    private const string NetbootLocalPath = "/tmp/oparch/netbootx64.efi";
    private const string ChrootBundleDirectory = "/usr/lib/opinionatedarch";

    public static void BaseSystem(Target live, Target target, InstallConfig config, string installerDirectory)
    {
        var packages = new List<string>
        {
            "base",
            "linux",
            "linux-headers",
            "linux-firmware",
            "mkinitcpio",
            "iptables-nft",
            "btrfs-progs",
            "cryptsetup",
            "grub",
            "efibootmgr",
            "fzf",
            "sudo",
            "networkmanager",
            "snapper",
            "snap-pac"
        };
        if (config.UcodePackage != "none")
        {
            packages.Add(config.UcodePackage);
        }
        if (config.GpuDriver == "nvidia")
        {
            packages.Add("nvidia");
        }
        else if (config.GpuDriver == "nvidia-open")
        {
            packages.Add("nvidia-open");
        }
        if (config.IncludeReturnMessage == "yes")
        {
            packages.Add("plymouth");
            packages.Add("ttf-dejavu");
        }

        var pacstrapArgs = new List<string> { "-K", target.RootPath };
        pacstrapArgs.AddRange(packages);
        ShellCommand.Working(live, "Installing base system...", "pacstrap", pacstrapArgs.ToArray());
        TargetFile.WriteAllText(target, "/etc/fstab", ShellCommand.Capture(live, "genfstab", "-U", target.RootPath));
        StageNetbootBinary(live, target);
        StageInstallerBundle(live, target, installerDirectory);
        StageLiveTempAssets(live, target);
        Log.Info("Base system installed.");
    }

    private static void StageNetbootBinary(Target live, Target target)
    {
        ShellCommand.Working(live, "Downloading Arch netboot EFI binary...", "curl", "-fL", "--retry", "2", "--connect-timeout", "10", "-o", NetbootLocalPath, NetbootUrl);
        TargetFile.CreateDirectory(target, "/boot/EFI");
        TargetFile.CreateDirectory(target, "/boot/EFI/OpinionatedArch");
        ShellCommand.Run(live, "cp", NetbootLocalPath, TargetFile.Path(target, "/boot/EFI/OpinionatedArch/netbootx64.efi"));
        Log.Info($"Staged {NetbootLocalPath} to ESP.");
    }

    private static void StageLiveTempAssets(Target live, Target target)
    {
        TargetFile.CreateDirectory(target, $"{ChrootBundleDirectory}/tmp");
        ShellCommand.Working(live, "Staging /tmp/oparch for target...", "cp", "-a", "/tmp/oparch/.", $"{TargetFile.Path(target, ChrootBundleDirectory)}/tmp/");
        Log.Info($"Staged /tmp/oparch to {ChrootBundleDirectory}/tmp for target.");
    }

    private static void StageInstallerBundle(Target live, Target target, string installerDirectory)
    {
        TargetFile.CreateDirectory(target, ChrootBundleDirectory);
        ShellCommand.Working(live, "Staging installer bundle...", "cp", "-a", $"{installerDirectory}/.", TargetFile.Path(target, ChrootBundleDirectory));
        ShellCommand.Run(live, "chown", "-R", "root:root", TargetFile.Path(target, ChrootBundleDirectory));
        ShellCommand.Run(live, "find", TargetFile.Path(target, ChrootBundleDirectory), "-type", "d", "-exec", "chmod", "755", "{}", "+");
        ShellCommand.Run(live, "find", TargetFile.Path(target, ChrootBundleDirectory), "-type", "f", "-exec", "chmod", "644", "{}", "+");
        ShellCommand.Run(live, "chmod", "755", TargetFile.Path(target, $"{ChrootBundleDirectory}/oparch-install"));
        Log.Info($"Staged installer bundle to {ChrootBundleDirectory}.");
    }
}
