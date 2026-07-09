using System;
using System.IO;
using System.Text;
using IOKode.OpinionatedArch.CommandLine;
using IOKode.OpinionatedArch.Installer.TerminalUi;
using Terminal.Gui.App;
using Terminal.Gui.Configuration;
using Terminal.Gui.Drivers;
using Terminal.Gui.ViewBase;
using Terminal.Gui.Views;

#pragma warning disable CS0618

namespace IOKode.OpinionatedArch.Installer;

internal sealed class TerminalInstallerUi
{
    public required Target Live { get; init; }

    public required string AssetDirectory { get; init; }

    public required string TempDirectory { get; init; }

    public required string LogoLocalPath { get; init; }

    public InstallConfig Collect()
    {
        Console.OutputEncoding = new UTF8Encoding();
        Dialog.DefaultShadow = ShadowStyles.None;
        Directory.CreateDirectory(TempDirectory);
        ConfigurationManager.RuntimeConfig = """
        {
          "ConfigurationManager.ThrowOnJsonErrors": true,
          "Theme": "Default",
          "Themes": [
            {
              "Default": {
                "Window.DefaultBorderStyle": "None",
                "FrameView.DefaultBorderStyle": "Single",
                "Dialog.DefaultBorderStyle": "Single",
                "MessageBox.DefaultBorderStyle": "Single",
                "Menu.DefaultBorderStyle": "Single",
                "MenuBar.DefaultBorderStyle": "None",
                "Button.DefaultShadow": "None",
                "Dialog.DefaultShadow": "None",
                "Window.DefaultShadow": "None",
                "StatusBar.DefaultSeparatorLineStyle": "Single",
                "Glyphs.LeftBracket": "[",
                "Glyphs.RightBracket": "]",
                "Glyphs.LeftDefaultIndicator": "U+0020",
                "Glyphs.RightDefaultIndicator": "U+0020",
                "Schemes": [
                  {
                    "Base": {
                      "Normal": { "Foreground": "White", "Background": "None", "Style": "None" },
                      "Focus": { "Foreground": "White", "Background": "Blue", "Style": "None" },
                      "Active": { "Foreground": "White", "Background": "Blue", "Style": "None" },
                      "ReadOnly": { "Foreground": "White", "Background": "None", "Style": "None" },
                      "Disabled": { "Foreground": "White", "Background": "None", "Style": "None" }
                    }
                  },
                  {
                    "Dialog": {
                      "Normal": { "Foreground": "White", "Background": "None", "Style": "None" },
                      "Focus": { "Foreground": "White", "Background": "Blue", "Style": "None" },
                      "Active": { "Foreground": "White", "Background": "Blue", "Style": "None" },
                      "ReadOnly": { "Foreground": "White", "Background": "None", "Style": "None" },
                      "Disabled": { "Foreground": "White", "Background": "None", "Style": "None" }
                    }
                  },
                  {
                    "Menu": {
                      "Normal": { "Foreground": "White", "Background": "None", "Style": "None" },
                      "Focus": { "Foreground": "White", "Background": "Blue", "Style": "None" },
                      "Active": { "Foreground": "White", "Background": "Blue", "Style": "None" },
                      "ReadOnly": { "Foreground": "White", "Background": "None", "Style": "None" },
                      "Disabled": { "Foreground": "White", "Background": "None", "Style": "None" }
                    }
                  }
                ]
              }
            }
          ]
        }
        """;
        ConfigurationManager.Enable(ConfigLocations.All);

        var app = Application.Create().Init(DriverRegistry.Names.DOTNET);
        app.Mouse.IsMouseDisabled = true;
        var state = new TerminalInstallerState();
        var shell = new TerminalInstallerShell(state);
        var navigator = new TerminalInstallerNavigator();
        var context = new TerminalInstallerContext
        {
            Live = Live,
            AssetDirectory = AssetDirectory,
            LogoLocalPath = LogoLocalPath,
            State = state,
            Shell = shell,
            Navigator = navigator,
            App = app
        };
        navigator.Initialize(context);
        try
        {
            shell.Build(context);
            navigator.ShowDisk();
            app.Run(shell.Window, _ => false);
        }
        finally
        {
            app.Dispose();
        }
        return state.Result ?? throw new OperationCanceledException("Installation aborted.");
    }
}
