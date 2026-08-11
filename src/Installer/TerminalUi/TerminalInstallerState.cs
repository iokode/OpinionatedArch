using System.Collections.Generic;
using System.Text;
using IOKode.OpinionatedArch.CommandLine;

namespace IOKode.OpinionatedArch.Installer.TerminalUi;

internal sealed class TerminalInstallerState
{
    public const int ReturnMessageFocusInclude = 0;
    public const int ReturnMessageFocusOwnerName = 1;
    public const int ReturnMessageFocusOwnerPhone = 2;
    public const int ReturnMessageFocusOwnerEmail = 3;
    public const int ReturnMessageFocusOwnerAddress = 4;
    public const int ReturnMessageFocusLogo = 5;
    public const int ReturnMessageFocusLogoUrl = 6;

    private readonly List<string> _timezones = new();

    public IReadOnlyList<string> Steps { get; } = new[]
    {
        "Disk",
        "Install mode",
        "Startup",
        "Hardware",
        "Swap",
        "Users",
        "Locale",
        "Identity",
        "Dotfiles",
        "Return message",
        "Summary"
    };

    public InstallConfig Config { get; set; } = new();

    public InstallConfig? Result { get; set; }

    public VerboseLevel Verbose { get; set; }

    public int StepIndex { get; set; }

    public int? TargetDiskIndex { get; set; }

    public int? InstallModeIndex { get; set; }

    public int? StartupPolicyIndex { get; set; }

    public int? UcodeIndex { get; set; }

    public int? GpuIndex { get; set; }

    public int? DotfilesIndex { get; set; }

    public int? ReturnMessageIndex { get; set; }

    public int? LogoIndex { get; set; }

    public string ZramSwapText { get; set; } = "0";

    public string DiskSwapText { get; set; } = "0";

    public string LoginUsersCsv { get; set; } = string.Empty;

    public string SharedSecret { get; set; } = string.Empty;

    public string SharedSecretConfirmation { get; set; } = string.Empty;

    public string ConsoleKeymap { get; set; } = string.Empty;

    public string Timezone { get; set; } = string.Empty;

    public string Hostname { get; set; } = string.Empty;

    public string DotfilesRepositoryUrl { get; set; } = string.Empty;

    public string OwnerName { get; set; } = string.Empty;

    public string OwnerPhone { get; set; } = string.Empty;

    public string OwnerEmail { get; set; } = string.Empty;

    public string OwnerReturnAddress { get; set; } = string.Empty;

    public string LogoUrl { get; set; } = string.Empty;

    public bool DotfilesFocusRepository { get; set; }

    public int ReturnMessageFocus { get; set; }

    public bool HardwareSelected()
    {
        return UcodeIndex is not null && GpuIndex is not null;
    }

    public bool LocaleSelected()
    {
        return !string.IsNullOrEmpty(ConsoleKeymap) && !string.IsNullOrEmpty(Timezone);
    }

    public List<string> ListTimezones()
    {
        if (_timezones.Count == 0)
        {
            _timezones.AddRange(InstallerInput.ListTimezones());
        }
        return new List<string>(_timezones);
    }

    public void CommitReturnMessageState()
    {
        if (Config.IncludeReturnMessage == "yes")
        {
            Config.OwnerName = OwnerName;
            Config.OwnerPhone = OwnerPhone;
            Config.OwnerEmail = OwnerEmail;
            Config.OwnerReturnAddress = OwnerReturnAddress;
            Config.LogoUrl = Config.IncludeLogo == "yes" ? LogoUrl : string.Empty;
        }
        else
        {
            ClearReturnMessageDetails();
        }
    }

    public void ClearReturnMessageDetails()
    {
        OwnerName = string.Empty;
        OwnerPhone = string.Empty;
        OwnerEmail = string.Empty;
        OwnerReturnAddress = string.Empty;
        LogoUrl = string.Empty;
        LogoIndex = null;
        Config.OwnerName = string.Empty;
        Config.OwnerPhone = string.Empty;
        Config.OwnerEmail = string.Empty;
        Config.OwnerReturnAddress = string.Empty;
        Config.ReturnMessageLanguages.Clear();
        Config.IncludeLogo = "no";
        Config.LogoUrl = string.Empty;
    }

    public void SynchronizeFromConfig()
    {
        InstallModeIndex = Config.InstallMode == "wipe-all" ? 0 : Config.InstallMode == "keep-homes" ? 1 : null;
        StartupPolicyIndex = Config.StartupPolicy == "manual" ? 0 : Config.StartupPolicy == "automatic" ? 1 : null;
        UcodeIndex = Config.UcodePackage == "intel-ucode" ? 0 : Config.UcodePackage == "amd-ucode" ? 1 : Config.UcodePackage == "none" ? 2 : null;
        GpuIndex = Config.GpuDriver == "nvidia" ? 0 : Config.GpuDriver == "nvidia-open" ? 1 : Config.GpuDriver == "nouveau" ? 2 : Config.GpuDriver == "none" ? 3 : null;
        DotfilesIndex = Config.ClonePublicDotfiles == "yes" ? 0 : Config.ClonePublicDotfiles == "no" ? 1 : null;
        ReturnMessageIndex = Config.IncludeReturnMessage == "yes" ? 0 : Config.IncludeReturnMessage == "no" ? 1 : null;
        LogoIndex = Config.IncludeLogo == "yes" ? 0 : Config.IncludeLogo == "no" ? 1 : null;
        ZramSwapText = Config.ZramSwapGb.ToString();
        DiskSwapText = Config.DiskSwapfileGb.ToString();
        LoginUsersCsv = string.Join(",", Config.LoginUsers);
        SharedSecret = Config.SharedSecret;
        SharedSecretConfirmation = Config.SharedSecret;
        ConsoleKeymap = Config.ConsoleKeymap;
        Timezone = Config.Timezone;
        Hostname = Config.HostnameValue;
        DotfilesRepositoryUrl = Config.DotfilesRepositoryUrl;
        OwnerName = Config.OwnerName;
        OwnerPhone = Config.OwnerPhone;
        OwnerEmail = Config.OwnerEmail;
        OwnerReturnAddress = Config.OwnerReturnAddress;
        LogoUrl = Config.LogoUrl;
    }

    public string BuildSummary()
    {
        var summary = new StringBuilder();
        summary.AppendLine($"target disk: {Config.TargetDisk}");
        summary.AppendLine($"install mode: {Config.InstallMode}");
        summary.AppendLine($"preserved home users: {string.Join(", ", Config.PreservedHomeUsers)}");
        summary.AppendLine($"startup policy: {Config.StartupPolicy}");
        summary.AppendLine($"ucode package: {Config.UcodePackage}");
        summary.AppendLine($"gpu driver: {Config.GpuDriver}");
        summary.AppendLine($"zram size (GB): {Config.ZramSwapGb}");
        summary.AppendLine($"disk swapfile size (GB): {Config.DiskSwapfileGb}");
        summary.AppendLine($"login users: {string.Join(", ", Config.LoginUsers)}");
        summary.AppendLine($"keymap: {Config.ConsoleKeymap}");
        summary.AppendLine($"timezone: {Config.Timezone}");
        summary.AppendLine($"hostname: {Config.HostnameValue}");
        summary.AppendLine($"clone public dotfiles: {Config.ClonePublicDotfiles}");
        summary.AppendLine($"dotfiles repository URL: {Config.DotfilesRepositoryUrl}");
        summary.AppendLine($"include return message: {Config.IncludeReturnMessage}");
        if (Config.IncludeReturnMessage == "yes")
        {
            summary.AppendLine($"return-message languages: {string.Join(", ", Config.ReturnMessageLanguages)}");
        }
        summary.AppendLine($"include logo: {Config.IncludeLogo}");
        return summary.ToString();
    }
}
