using System.Collections.Generic;

namespace IOKode.OpinionatedArch.Installer;

internal sealed class InstallConfig
{
    public string TargetDisk { get; set; } = string.Empty;
    public string InstallMode { get; set; } = string.Empty;
    public List<string> PreservedHomeUsers { get; } = new List<string>();
    public string StartupPolicy { get; set; } = string.Empty;
    public string UcodePackage { get; set; } = string.Empty;
    public string GpuDriver { get; set; } = string.Empty;
    public ulong ZramSwapGb { get; set; }
    public ulong DiskSwapfileGb { get; set; }
    public List<string> LoginUsers { get; } = new List<string>();
    public string SharedSecret { get; set; } = string.Empty;
    public string ConsoleKeymap { get; set; } = string.Empty;
    public string Timezone { get; set; } = string.Empty;
    public string HostnameValue { get; set; } = string.Empty;
    public string ClonePublicDotfiles { get; set; } = string.Empty;
    public string DotfilesRepositoryUrl { get; set; } = string.Empty;
    public string IncludeReturnMessage { get; set; } = string.Empty;
    public List<string> ReturnMessageLanguages { get; } = new List<string>();
    public string OwnerName { get; set; } = string.Empty;
    public string OwnerPhone { get; set; } = string.Empty;
    public string OwnerEmail { get; set; } = string.Empty;
    public string OwnerReturnAddress { get; set; } = string.Empty;
    public string IncludeLogo { get; set; } = string.Empty;
    public string LogoUrl { get; set; } = string.Empty;
    public string RootPartUuid { get; set; } = string.Empty;
}

internal sealed class DiskTarget
{
    public required string Path { get; init; }

    public required string Size { get; init; }

    public required string Model { get; init; }
}
