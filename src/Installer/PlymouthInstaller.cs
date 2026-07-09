using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using IOKode.OpinionatedArch.CommandLine;

namespace IOKode.OpinionatedArch.Installer;

internal static class PlymouthInstaller
{
    private const string AssetDirectory = "/usr/lib/opinionatedarch/assets";
    private const string TempDirectory = "/usr/lib/opinionatedarch/tmp";
    private const string ScriptFile = "/usr/share/plymouth/themes/opinionatedarch/opinionatedarch.script";

    public static void ConfigureDefaults(Target target, InstallConfig config)
    {
        if (config.IncludeReturnMessage != "yes")
        {
            return;
        }
        foreach (var directory in new[] { "/etc/opinionatedarch", "/etc/initcpio/hooks", "/etc/initcpio/install", "/usr/share/plymouth/themes/opinionatedarch", "/usr/share/fonts/opinionatedarch" })
        {
            ShellCommand.Run(target, "install", "-d", "-m", "755", directory);
        }
        TargetFile.WriteAllText(target, "/etc/opinionatedarch/ownership.env", $"OWNER_NAME={config.OwnerName}\nOWNER_PHONE={config.OwnerPhone}\nOWNER_EMAIL={config.OwnerEmail}\nOWNER_RETURN_ADDRESS={config.OwnerReturnAddress}\nINCLUDE_LOGO={config.IncludeLogo}\nRETURN_MESSAGE_LANGUAGES_CSV={string.Join(',', config.ReturnMessageLanguages)}\n");
        ShellCommand.Run(target, "cp", $"{AssetDirectory}/initcpio/hooks/opinionatedarch-plymouth-locale", "/etc/initcpio/hooks/opinionatedarch-plymouth-locale");
        ShellCommand.Run(target, "cp", $"{AssetDirectory}/initcpio/install/opinionatedarch-plymouth-locale", "/etc/initcpio/install/opinionatedarch-plymouth-locale");
        ShellCommand.Run(target, "cp", $"{AssetDirectory}/initcpio/install/opinionatedarch-plymouth-font", "/etc/initcpio/install/opinionatedarch-plymouth-font");
        ShellCommand.Run(target, "cp", $"{AssetDirectory}/plymouth/opinionatedarch/fonts/OpenSans.ttf", "/usr/share/fonts/opinionatedarch/OpenSans.ttf");
        ShellCommand.Run(target, "cp", $"{AssetDirectory}/plymouth/opinionatedarch/fonts/OFL.txt", "/usr/share/fonts/opinionatedarch/OpenSans-OFL.txt");
        ShellCommand.Run(target, "fc-cache", "-f", "/usr/share/fonts/opinionatedarch");
        ShellCommand.Run(target, "cp", $"{AssetDirectory}/plymouth/opinionatedarch/opinionatedarch.plymouth", "/usr/share/plymouth/themes/opinionatedarch/opinionatedarch.plymouth");
        ShellCommand.Run(target, "cp", $"{AssetDirectory}/plymouth/opinionatedarch/script-base.script", ScriptFile);
        var plymouthFont = string.Empty;
        foreach (var line in TargetFile.ReadLines(target, "/usr/share/plymouth/themes/opinionatedarch/opinionatedarch.plymouth"))
        {
            if (line.StartsWith("Font=", StringComparison.Ordinal))
            {
                plymouthFont = line[5..];
                break;
            }
        }
        TargetFile.AppendToFile(target, ScriptFile, $"theme_font = \"{EscapeString(plymouthFont)}\";\n");
        foreach (var image in new[] { "box-full.png", "box-half.png", "box-quarter.png", "box-password.png" })
        {
            ShellCommand.Run(target, "cp", $"{AssetDirectory}/plymouth/opinionatedarch/{image}", $"/usr/share/plymouth/themes/opinionatedarch/{image}");
        }
        if (config.IncludeLogo == "yes")
        {
            ShellCommand.Run(target, "cp", $"{TempDirectory}/logo.png", "/usr/share/plymouth/themes/opinionatedarch/logo.png");
            TargetFile.AppendToFile(target, ScriptFile, TargetFile.ReadAllText(target, $"{AssetDirectory}/plymouth/opinionatedarch/script-logo.script"));
        }
        RenderLanguageBlocks(target, config);
        TargetFile.AppendToFile(target, ScriptFile, TargetFile.ReadAllText(target, $"{AssetDirectory}/plymouth/opinionatedarch/script-password.script"));
        ShellCommand.Run(target, "plymouth-set-default-theme", "opinionatedarch");
    }

    private static string EscapeString(string value)
    {
        return value.Replace("\\", "\\\\").Replace("\"", "\\\"");
    }

    private static void WriteText(Target target, string name, string text, string x, string y, string red, string green, string blue)
    {
        var escaped = EscapeString(text);
        TargetFile.AppendToFile(target, ScriptFile, $"{name}_image = Image.Text(\"{escaped}\", {red}, {green}, {blue}, 1.0, theme_font);\n");
        TargetFile.AppendToFile(target, ScriptFile, $"{name}_sprite = Sprite({name}_image);\n");
        TargetFile.AppendToFile(target, ScriptFile, $"{name}_sprite.SetPosition({x}, {y}, 10);\n");
    }

    private static void WriteBox(Target target, string name, string x, string y, string width, string height, string imageFile)
    {
        TargetFile.AppendToFile(target, ScriptFile, $"{name}_image = Image(\"{imageFile}\").Scale({width}, {height});\n");
        TargetFile.AppendToFile(target, ScriptFile, $"{name}_sprite = Sprite({name}_image);\n");
        TargetFile.AppendToFile(target, ScriptFile, $"{name}_sprite.SetPosition({x}, {y}, 8);\n");
    }

    private static void RenderTemplate(Target target, InstallConfig config, string languageCode, int blockIndex, string blockX, string blockY, string blockWidth, string blockHeight, int wrapWidth, string boxImage)
    {
        var templateFile = $"{AssetDirectory}/returning-templates/{languageCode}.tpl";
        if (!TargetFile.Exists(target, templateFile))
        {
            throw new FileNotFoundException("Return-message template not found in target.", templateFile);
        }
        var templateLines = TargetFile.ReadAllLines(target, templateFile);
        var languageName = templateLines.FirstOrDefault() ?? string.Empty;
        var messageText = string.Join('\n', templateLines.Skip(2))
            .Replace("{{OWNER_NAME}}", config.OwnerName)
            .Replace("{{OWNER_PHONE}}", config.OwnerPhone)
            .Replace("{{OWNER_EMAIL}}", config.OwnerEmail)
            .Replace("{{OWNER_RETURN_ADDRESS}}", config.OwnerReturnAddress);

        WriteBox(target, $"box_{blockIndex}", $"{blockX} + 8", $"{blockY} + 8", $"{blockWidth} - 16", $"{blockHeight} - 16", boxImage);
        WriteText(target, $"title_{blockIndex}_base", languageName, $"{blockX} + 24", $"{blockY} + 18", "0.72", "0.84", "1.0");
        WriteText(target, $"title_{blockIndex}_bold", languageName, $"{blockX} + 25", $"{blockY} + 18", "0.72", "0.84", "1.0");

        var lineIndex = 0;
        foreach (var wrappedLine in messageText.Split('\n'))
        {
            var folded = ShellCommand.CaptureWithInputAndEnvironment(target, "fold", new[] { "-s", "-w", wrapWidth.ToString() }, wrappedLine + "\n", new Dictionary<string, string> { ["LC_ALL"] = "C.UTF-8" });
            foreach (var renderedLine in folded.Split('\n'))
            {
                if (renderedLine.Length == 0)
                {
                    continue;
                }
                WriteText(target, $"message_{blockIndex}_{lineIndex}", renderedLine, $"{blockX} + 24", $"{blockY} + 58 + ({lineIndex} * 24)", "1.0", "1.0", "1.0");
                lineIndex++;
            }
        }
    }

    private static void RenderLanguageBlocks(Target target, InstallConfig config)
    {
        var languageCount = config.ReturnMessageLanguages.Count;
        if (languageCount is < 1 or > 4)
        {
            throw new Exception("Return-message theme requires between 1 and 4 languages.");
        }
        TargetFile.AppendToFile(target, ScriptFile, """
            screen_width = Window.GetWidth();
            screen_height = Window.GetHeight();
            content_x = 80;
            content_y = 150;
            content_width = screen_width - 160;
            box_gap = 24;
            password_box_height = 62;
            password_box_y = screen_height - 136;
            password_text_y = password_box_y + 20;
            content_height = password_box_y - content_y + 8 - box_gap;
            column_gap = box_gap - 16;
            row_gap = box_gap - 16;
            column_width = (content_width - column_gap) / 2;
            half_height = (content_height - row_gap) / 2;
            right_column_x = content_x + column_width + column_gap;
            bottom_row_y = content_y + half_height + row_gap;

            """);
        var languages = config.ReturnMessageLanguages;
        switch (languageCount)
        {
            case 1:
                RenderTemplate(target, config, languages[0], 1, "content_x", "content_y", "content_width", "content_height", 76, "box-full.png");
                break;
            case 2:
                RenderTemplate(target, config, languages[0], 1, "content_x", "content_y", "content_width", "half_height", 76, "box-half.png");
                RenderTemplate(target, config, languages[1], 2, "content_x", "bottom_row_y", "content_width", "half_height", 76, "box-half.png");
                break;
            case 3:
                RenderTemplate(target, config, languages[0], 1, "content_x", "content_y", "content_width", "half_height", 76, "box-half.png");
                RenderTemplate(target, config, languages[1], 2, "content_x", "bottom_row_y", "column_width", "half_height", 34, "box-quarter.png");
                RenderTemplate(target, config, languages[2], 3, "right_column_x", "bottom_row_y", "column_width", "half_height", 34, "box-quarter.png");
                break;
            default:
                RenderTemplate(target, config, languages[0], 1, "content_x", "content_y", "column_width", "half_height", 55, "box-quarter.png");
                RenderTemplate(target, config, languages[1], 2, "right_column_x", "content_y", "column_width", "half_height", 55, "box-quarter.png");
                RenderTemplate(target, config, languages[2], 3, "content_x", "bottom_row_y", "column_width", "half_height", 55, "box-quarter.png");
                RenderTemplate(target, config, languages[3], 4, "right_column_x", "bottom_row_y", "column_width", "half_height", 55, "box-quarter.png");
                break;
        }
    }
}
