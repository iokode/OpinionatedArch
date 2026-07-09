using System;
using System.Collections.Generic;
using System.IO;
using IOKode.OpinionatedArch.CommandLine;
using IOKode.OpinionatedFramework.Facades;

namespace IOKode.OpinionatedArch.Installer;

internal static class InstallerInput
{
    public static InstallConfig LoadConfig(Target live, string assetDirectory, string configFile, string logoLocalPath)
    {
        if (!File.Exists(configFile))
        {
            throw new FileNotFoundException("Config file not found.", configFile);
        }

        var values = new Dictionary<string, string>();
        foreach (var rawLine in File.ReadAllLines(configFile))
        {
            var line = TextFiles.Trim(rawLine.TrimEnd('\r'));
            if (line.Length == 0 || line.StartsWith('#'))
            {
                continue;
            }
            var separator = line.IndexOf('=');
            if (separator < 0)
            {
                throw new FormatException($"Invalid config line (expected key=value): {line}");
            }
            var key = TextFiles.Trim(line[..separator]);
            var value = TextFiles.Trim(line[(separator + 1)..]);
            if ((value.StartsWith('"') && value.EndsWith('"')) || (value.StartsWith('\'') && value.EndsWith('\'')))
            {
                value = value[1..^1];
            }
            if (!AllowedConfigKeys.Contains(key))
            {
                throw new InvalidDataException($"Unknown key in config file: {key}");
            }
            values[key] = value;
        }

        var config = new InstallConfig
        {
            TargetDisk = ValueOrEmpty(values, "TARGET_DISK"),
            InstallMode = ValueOrEmpty(values, "INSTALL_MODE"),
            StartupPolicy = ValueOrEmpty(values, "STARTUP_POLICY"),
            UcodePackage = ValueOrEmpty(values, "UCODE_PACKAGE"),
            GpuDriver = ValueOrEmpty(values, "GPU_DRIVER"),
            ZramSwapGb = ParseUIntOrMax(ValueOrEmpty(values, "ZRAM_SWAP_GB")),
            DiskSwapfileGb = ParseUIntOrMax(ValueOrEmpty(values, "DISK_SWAPFILE_GB")),
            SharedSecret = ValueOrEmpty(values, "SHARED_SECRET"),
            ConsoleKeymap = ValueOrEmpty(values, "CONSOLE_KEYMAP"),
            Timezone = ValueOrEmpty(values, "TIMEZONE"),
            HostnameValue = ValueOrEmpty(values, "HOSTNAME_VALUE"),
            ClonePublicDotfiles = values.GetValueOrDefault("CLONE_PUBLIC_DOTFILES", "no"),
            DotfilesRepositoryUrl = ValueOrEmpty(values, "DOTFILES_REPOSITORY_URL"),
            IncludeReturnMessage = values.GetValueOrDefault("INCLUDE_RETURN_MESSAGE", "no"),
            OwnerName = ValueOrEmpty(values, "OWNER_NAME"),
            OwnerPhone = ValueOrEmpty(values, "OWNER_PHONE"),
            OwnerEmail = ValueOrEmpty(values, "OWNER_EMAIL"),
            OwnerReturnAddress = ValueOrEmpty(values, "OWNER_RETURN_ADDRESS"),
            IncludeLogo = values.GetValueOrDefault("INCLUDE_LOGO", "no"),
            LogoUrl = ValueOrEmpty(values, "LOGO_URL")
        };
        config.PreservedHomeUsers.AddRange(ParseOptionalUsersCsv(ValueOrEmpty(values, "PRESERVED_HOME_USERS_CSV")));
        config.LoginUsers.AddRange(ParseLoginUsersCsv(ValueOrEmpty(values, "LOGIN_USERS_CSV")));
        if (config.IncludeReturnMessage == "yes")
        {
            config.ReturnMessageLanguages.AddRange(ParseReturnMessageLanguagesCsv(assetDirectory, ValueOrEmpty(values, "RETURN_MESSAGE_LANGUAGES_CSV")));
        }
        ValidateConfig(live, assetDirectory, config);
        PrepareConfigLogo(live, config, logoLocalPath);
        return config;
    }

    public static void ValidateConfig(Target live, string assetDirectory, InstallConfig config)
    {
        if (!ShellCommand.CommandSucceeds(live, "test", "-b", config.TargetDisk))
        {
            throw new Exception("TARGET_DISK must be an existing block device.");
        }
        if (config.InstallMode is not ("wipe-all" or "keep-homes"))
        {
            throw new Exception("INSTALL_MODE must be wipe-all or keep-homes.");
        }
        if (config.StartupPolicy is not ("manual" or "automatic"))
        {
            throw new Exception("STARTUP_POLICY must be manual or automatic.");
        }
        if (config.UcodePackage is not ("intel-ucode" or "amd-ucode" or "none"))
        {
            throw new Exception("UCODE_PACKAGE must be intel-ucode, amd-ucode, or none.");
        }
        if (config.GpuDriver is not ("nvidia" or "nvidia-open" or "nouveau" or "none"))
        {
            throw new Exception("GPU_DRIVER must be nvidia, nvidia-open, nouveau, or none.");
        }
        if (config.ZramSwapGb == ulong.MaxValue)
        {
            throw new Exception("ZRAM_SWAP_GB must be a non-negative integer.");
        }
        if (config.DiskSwapfileGb == ulong.MaxValue)
        {
            throw new Exception("DISK_SWAPFILE_GB must be a non-negative integer.");
        }
        if (string.IsNullOrEmpty(config.SharedSecret))
        {
            throw new Exception("SHARED_SECRET cannot be empty.");
        }
        if (string.IsNullOrEmpty(config.ConsoleKeymap))
        {
            throw new Exception("CONSOLE_KEYMAP cannot be empty.");
        }
        if (!File.Exists(Path.Combine("/usr/share/zoneinfo", config.Timezone)))
        {
            throw new Exception($"Invalid TIMEZONE: {config.Timezone}");
        }
        if (!ValidateHostname(config.HostnameValue))
        {
            throw new Exception("Invalid HOSTNAME_VALUE.");
        }
        if (config.ClonePublicDotfiles is not ("yes" or "no"))
        {
            throw new Exception("CLONE_PUBLIC_DOTFILES must be yes or no.");
        }
        if (config.ClonePublicDotfiles == "yes" && string.IsNullOrEmpty(config.DotfilesRepositoryUrl))
        {
            throw new Exception("DOTFILES_REPOSITORY_URL is required when CLONE_PUBLIC_DOTFILES=yes.");
        }
        if (config.ClonePublicDotfiles == "no" && !string.IsNullOrEmpty(config.DotfilesRepositoryUrl))
        {
            throw new Exception("DOTFILES_REPOSITORY_URL requires CLONE_PUBLIC_DOTFILES=yes.");
        }
        if (config.IncludeReturnMessage is not ("yes" or "no"))
        {
            throw new Exception("INCLUDE_RETURN_MESSAGE must be yes or no.");
        }
        if (config.IncludeReturnMessage == "yes")
        {
            if (string.IsNullOrEmpty(config.OwnerName) || string.IsNullOrEmpty(config.OwnerPhone) || string.IsNullOrEmpty(config.OwnerEmail) || string.IsNullOrEmpty(config.OwnerReturnAddress))
            {
                throw new Exception("OWNER_NAME, OWNER_PHONE, OWNER_EMAIL, and OWNER_RETURN_ADDRESS cannot be empty.");
            }
            ValidateReturnMessageLanguages(assetDirectory, config.ReturnMessageLanguages);
        }
        else
        {
            config.ReturnMessageLanguages.Clear();
        }
        if (config.IncludeLogo is not ("yes" or "no"))
        {
            throw new Exception("INCLUDE_LOGO must be yes or no.");
        }
        if (config.IncludeReturnMessage != "yes")
        {
            config.IncludeLogo = "no";
            config.LogoUrl = string.Empty;
        }
    }

    public static bool DownloadLogo(Target live, string url, string logoLocalPath)
    {
        try
        {
            ShellCommand.Run(live, "curl", "-fL", "--retry", "2", "--connect-timeout", "10", "-o", logoLocalPath, url);
            return true;
        }
        catch (ShellCommandException)
        {
            return false;
        }
        catch (IOException)
        {
            return false;
        }
    }

    public static List<string> ParseLoginUsersCsv(string rawUsers)
    {
        var loginUsers = new List<string>();
        foreach (var token in rawUsers.Split(','))
        {
            var clean = TextFiles.Trim(token);
            if (clean.Length == 0)
            {
                continue;
            }
            if (!ValidateUsername(clean))
            {
                throw new ArgumentException($"Invalid username: {clean}", nameof(rawUsers));
            }
            if (clean == "system")
            {
                throw new ArgumentException("Username 'system' is reserved.", nameof(rawUsers));
            }
            if (!loginUsers.Contains(clean))
            {
                loginUsers.Add(clean);
            }
        }
        if (loginUsers.Count == 0)
        {
            throw new ArgumentException("At least one valid login username is required.", nameof(rawUsers));
        }
        return loginUsers;
    }

    public static List<string> ParseOptionalUsersCsv(string rawUsers)
    {
        var clean = TextFiles.Trim(rawUsers);
        return clean.Length == 0 ? new List<string>() : ParseLoginUsersCsv(clean);
    }

    public static List<string> ListReturnMessageLanguages(string assetDirectory)
    {
        var templateDir = Path.Combine(assetDirectory, "returning-templates");
        var templateCodes = new List<string>();
        foreach (var templatePath in Directory.EnumerateFiles(templateDir, "*.tpl"))
        {
            var code = Path.GetFileNameWithoutExtension(templatePath) ?? string.Empty;
            if (code.Length > 0)
            {
                templateCodes.Add(code);
            }
        }
        templateCodes.Sort(StringComparer.Ordinal);
        if (templateCodes.Count == 0)
        {
            throw new Exception("No return-message templates found.");
        }
        return templateCodes;
    }

    public static List<string> ListTimezones()
    {
        var root = "/usr/share/zoneinfo";
        var timezones = new List<string>();
        foreach (var timezonePath in Directory.EnumerateFiles(root, "*", SearchOption.AllDirectories))
        {
            timezones.Add(Path.GetRelativePath(root, timezonePath));
        }
        timezones.Sort(StringComparer.Ordinal);
        return timezones;
    }

    public static bool ValidateHostname(string hostname)
    {
        if (hostname.Length is <= 0 or > 63 || !char.IsAsciiLetterOrDigit(hostname[0]))
        {
            return false;
        }
        foreach (var character in hostname)
        {
            if (!char.IsAsciiLetterOrDigit(character) && character is not ('.' or '-'))
            {
                return false;
            }
        }
        return true;
    }

    public static bool ValidateUsername(string username)
    {
        if (username.Length is <= 0 or > 32 || (!char.IsAsciiLetterLower(username[0]) && username[0] != '_'))
        {
            return false;
        }
        foreach (var character in username)
        {
            if (!char.IsAsciiLetterLower(character) && !char.IsAsciiDigit(character) && character is not ('_' or '-'))
            {
                return false;
            }
        }
        return true;
    }

    private static void PrepareConfigLogo(Target live, InstallConfig config, string logoLocalPath)
    {
        if (config.IncludeReturnMessage != "yes")
        {
            config.IncludeLogo = "no";
            config.LogoUrl = string.Empty;
        }
        else if (config.IncludeLogo == "yes")
        {
            if (string.IsNullOrEmpty(config.LogoUrl))
            {
                throw new Exception("LOGO_URL is required when INCLUDE_LOGO=yes.");
            }
            if (!DownloadLogo(live, config.LogoUrl, logoLocalPath))
            {
                throw new Exception("Logo download failed from LOGO_URL in config file.");
            }
            Log.Info($"Logo downloaded to {logoLocalPath}.");
        }
        else
        {
            config.LogoUrl = string.Empty;
        }
    }

    private static List<string> ParseReturnMessageLanguagesCsv(string assetDirectory, string rawLanguages)
    {
        var languages = new List<string>();
        foreach (var token in rawLanguages.Split(','))
        {
            var clean = TextFiles.Trim(token);
            if (clean.Length == 0)
            {
                continue;
            }
            if (clean.Length != 2 || !AllAsciiLowercase(clean))
            {
                throw new ArgumentException($"Invalid return-message language code: {clean}", nameof(rawLanguages));
            }
            var templatePath = Path.Combine(assetDirectory, "returning-templates", $"{clean}.tpl");
            if (!File.Exists(templatePath))
            {
                throw new FileNotFoundException("Return-message template not found.", templatePath);
            }
            if (!languages.Contains(clean))
            {
                languages.Add(clean);
            }
        }
        ValidateReturnMessageLanguages(assetDirectory, languages);
        return languages;
    }

    private static void ValidateReturnMessageLanguages(string assetDirectory, IReadOnlyList<string> languages)
    {
        if (languages.Count is < 1 or > 4)
        {
            throw new ArgumentException("RETURN_MESSAGE_LANGUAGES_CSV must include between 1 and 4 languages.", nameof(languages));
        }
        foreach (var language in languages)
        {
            if (language.Length != 2 || !AllAsciiLowercase(language))
            {
                throw new ArgumentException($"Invalid return-message language code: {language}", nameof(languages));
            }
            var templatePath = Path.Combine(assetDirectory, "returning-templates", $"{language}.tpl");
            if (!File.Exists(templatePath))
            {
                throw new FileNotFoundException("Return-message template not found.", templatePath);
            }
        }
    }

    private static bool AllAsciiLowercase(string value)
    {
        foreach (var character in value)
        {
            if (!char.IsAsciiLetterLower(character))
            {
                return false;
            }
        }
        return true;
    }

    private static string ValueOrEmpty(IReadOnlyDictionary<string, string> values, string key)
    {
        return values.GetValueOrDefault(key, string.Empty);
    }

    private static ulong ParseUIntOrMax(string value)
    {
        return ulong.TryParse(value, out var parsed) ? parsed : ulong.MaxValue;
    }

    private static readonly HashSet<string> AllowedConfigKeys = new(StringComparer.Ordinal)
    {
        "TARGET_DISK",
        "INSTALL_MODE",
        "PRESERVED_HOME_USERS_CSV",
        "STARTUP_POLICY",
        "UCODE_PACKAGE",
        "GPU_DRIVER",
        "ZRAM_SWAP_GB",
        "DISK_SWAPFILE_GB",
        "LOGIN_USERS_CSV",
        "SHARED_SECRET",
        "CONSOLE_KEYMAP",
        "TIMEZONE",
        "HOSTNAME_VALUE",
        "CLONE_PUBLIC_DOTFILES",
        "DOTFILES_REPOSITORY_URL",
        "INCLUDE_RETURN_MESSAGE",
        "RETURN_MESSAGE_LANGUAGES_CSV",
        "OWNER_NAME",
        "OWNER_PHONE",
        "OWNER_EMAIL",
        "OWNER_RETURN_ADDRESS",
        "INCLUDE_LOGO",
        "LOGO_URL"
    };
}

file static class StringExtensions
{
    public static List<string> Lines(this string value)
    {
        var lines = new List<string>();
        foreach (var line in value.Split('\n'))
        {
            var clean = line.TrimEnd('\r');
            if (clean.Length > 0)
            {
                lines.Add(clean);
            }
        }
        return lines;
    }
}
