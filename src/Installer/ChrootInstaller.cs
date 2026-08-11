using System;
using System.Collections.Generic;
using System.IO;
using IOKode.OpinionatedArch.CommandLine;

namespace IOKode.OpinionatedArch.Installer;

internal static class ChrootInstaller
{
    public static void ConfigureTarget(Target target, InstallConfig config)
    {
        ConfigureLocaleAndTime(target, config);
        ConfigureIdentity(target, config);
        ConfigureUsersAndGroups(target, config);
        ConfigureNetworkStack(target);
        ConfigureSnapshots(target);
        ConfigureDiskSwapfile(target, config);
        PlymouthInstaller.ConfigureDefaults(target, config);
        ConfigureInitramfs(target, config);
        ConfigureGrub(target, config);
        ShellCommand.Run(target, "bash", "-c", "chmod ugo+x /usr/lib/opinionatedarch/bin/*");
        ShellCommand.Run(target, "rm", "-rf", "/usr/lib/opinionatedarch/tmp");
    }

    private static void ConfigureLocaleAndTime(Target target, InstallConfig config)
    {
        TargetFile.ReplaceInFile(target, "/etc/locale.gen", "#en_US.UTF-8 UTF-8", "en_US.UTF-8 UTF-8");
        ShellCommand.Run(target, "locale-gen");
        TargetFile.WriteAllText(target, "/etc/locale.conf", "LANG=en_US.UTF-8\n");
        TargetFile.WriteAllText(target, "/etc/vconsole.conf", $"KEYMAP={config.ConsoleKeymap}\n");
        TargetFile.CreateSymbolicLink(target, "/etc/localtime", $"/usr/share/zoneinfo/{config.Timezone}");
        ShellCommand.Run(target, "hwclock", "--systohc", "--utc");
    }

    private static void ConfigureIdentity(Target target, InstallConfig config)
    {
        TargetFile.WriteAllText(target, "/etc/hostname", $"{config.HostnameValue}\n");
    }

    private static void ConfigureUsersAndGroups(Target target, InstallConfig config)
    {
        ShellCommand.Run(target, "groupadd", "dotfiles");
        ShellCommand.Run(target, "groupadd", "login-users");
        ShellCommand.Run(target, "install", "-d", "-m", "2775", "-o", "root", "-g", "dotfiles", "/dotfiles");
        foreach (var user in config.LoginUsers)
        {
            ShellCommand.Run(target, "useradd", "-M", "-d", $"/home/{user}", "-G", "wheel,dotfiles,login-users", "-s", "/bin/bash", user);
            ShellCommand.Run(target, "chown", "-R", $"{user}:{user}", $"/home/{user}");
            ShellCommand.RunWithInput(target, null, $"{user}:{config.SharedSecret}\n", "chpasswd");
        }
        ShellCommand.Run(target, "passwd", "-l", "root");
        TargetFile.WriteAllText(target, "/etc/sudoers.d/10-wheel", "%wheel ALL=(ALL:ALL) ALL\n");
        TargetFile.SetUnixFileMode(target, "/etc/sudoers.d/10-wheel", UnixFileMode.UserRead | UnixFileMode.GroupRead);
    }

    private static void ConfigureNetworkStack(Target target)
    {
        ShellCommand.Run(target, "systemctl", "enable", "NetworkManager.service");
        ShellCommand.Run(target, "systemctl", "enable", "systemd-resolved.service");
    }

    private static void ConfigureSnapshots(Target target)
    {
        ShellCommand.Run(target, "install", "-m", "755", "/usr/lib/opinionatedarch/bin/oparch-snapshot-system", "/usr/local/bin/oparch-snapshot-system");
        ShellCommand.Run(target, "install", "-m", "755", "/usr/lib/opinionatedarch/bin/oparch-snapshot-home", "/usr/local/bin/oparch-snapshot-home");
    }

    private static void ConfigureDiskSwapfile(Target target, InstallConfig config)
    {
        if (config.DiskSwapfileGb == 0)
        {
            return;
        }
        ShellCommand.Run(target, "btrfs", "filesystem", "mkswapfile", "--size", $"{config.DiskSwapfileGb}G", "/swap/swapfile");
        TargetFile.AppendToFile(target, "/etc/fstab", "/swap/swapfile none swap defaults 0 0\n");
    }

    private static void ConfigureInitramfs(Target target, InstallConfig config)
    {
        var replacement = config.IncludeReturnMessage == "yes"
            ? "HOOKS=(base udev autodetect microcode kms keyboard keymap block opinionatedarch-plymouth-locale plymouth opinionatedarch-plymouth-font encrypt filesystems)"
            : "HOOKS=(base udev autodetect microcode kms keyboard keymap block encrypt filesystems)";
        TargetFile.ReplaceLinePrefix(target, "/etc/mkinitcpio.conf", "HOOKS=", replacement);
        ShellCommand.Run(target, "mkinitcpio", "-P");
    }

    private static void ConfigureGrub(Target target, InstallConfig config)
    {
        var timeoutStyle = config.StartupPolicy == "manual" ? "menu" : "hidden";
        var timeoutValue = config.StartupPolicy == "manual" ? "-1" : "1";
        var linuxDefault = config.IncludeReturnMessage == "yes" ? "quiet splash" : "quiet";
        SetOrReplaceConfigKey(target, "/etc/default/grub", "GRUB_DEFAULT", "0");
        SetOrReplaceConfigKey(target, "/etc/default/grub", "GRUB_TIMEOUT_STYLE", timeoutStyle);
        SetOrReplaceConfigKey(target, "/etc/default/grub", "GRUB_TIMEOUT", timeoutValue);
        SetOrReplaceConfigKey(target, "/etc/default/grub", "GRUB_CMDLINE_LINUX_DEFAULT", $"\"{linuxDefault}\"");
        SetOrReplaceConfigKey(target, "/etc/default/grub", "GRUB_CMDLINE_LINUX", $"\"cryptdevice=UUID={config.RootPartUuid}:cryptroot root=/dev/mapper/cryptroot\"");
        TargetFile.WriteAllText(target, "/etc/grub.d/40_custom", """
            #!/bin/sh
            exec tail -n +3 $0

            menuentry 'Netboot Arch' {
              search --no-floppy --file --set=root /EFI/OpinionatedArch/netbootx64.efi
              chainloader /EFI/OpinionatedArch/netbootx64.efi
            }

            menuentry 'EFI firmware' {
              fwsetup
            }

            menuentry 'Shutdown' {
              halt
            }
            """);
        TargetFile.SetUnixFileMode(target, "/etc/grub.d/40_custom", UnixFileMode.UserRead | UnixFileMode.UserWrite | UnixFileMode.UserExecute | UnixFileMode.GroupRead | UnixFileMode.GroupExecute | UnixFileMode.OtherRead | UnixFileMode.OtherExecute);
        ShellCommand.Run(target, "grub-install", "--target=x86_64-efi", "--efi-directory=/boot", "--bootloader-id=OpinionatedArch");
        ShellCommand.Run(target, "grub-mkconfig", "-o", "/boot/grub/grub.cfg");
    }

    private static void SetOrReplaceConfigKey(Target target, string path, string key, string value)
    {
        var prefix = $"{key}=";
        var replaced = false;
        var lines = new List<string>();
        foreach (var line in TargetFile.ReadAllLines(target, path))
        {
            if (line.StartsWith(prefix, StringComparison.Ordinal))
            {
                lines.Add($"{key}={value}");
                replaced = true;
            }
            else
            {
                lines.Add(line);
            }
        }
        if (!replaced)
        {
            lines.Add($"{key}={value}");
        }
        TargetFile.WriteAllText(target, path, string.Join('\n', lines) + "\n");
    }
}
