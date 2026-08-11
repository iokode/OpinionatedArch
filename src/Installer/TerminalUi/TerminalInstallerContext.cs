using System;
using System.Collections.ObjectModel;
using System.IO;
using IOKode.OpinionatedArch.CommandLine;
using IOKode.OpinionatedArch.Installer.TerminalUi.Controls;
using Terminal.Gui.App;
using Terminal.Gui.Views;

#pragma warning disable CS0618

namespace IOKode.OpinionatedArch.Installer.TerminalUi;

internal sealed class TerminalInstallerContext
{
    private readonly TerminalForm _form;

    public TerminalInstallerContext()
    {
        _form = new TerminalForm(this);
    }

    public required Target Live { get; init; }

    public required string AssetDirectory { get; init; }

    public required string LogoLocalPath { get; init; }

    public required TerminalInstallerState State { get; init; }

    public required TerminalInstallerShell Shell { get; init; }

    public required TerminalInstallerNavigator Navigator { get; init; }

    public required IApplication App { get; init; }

    public TerminalForm Form => _form;

    public void SetContent(string title)
    {
        Shell.SetContent(title);
    }

    public void SetNavigation(Action? previous, Action? next, bool nextEnabled = true)
    {
        Shell.SetNavigation(previous, next, nextEnabled);
    }

    public void SetNextEnabled(bool enabled)
    {
        Shell.SetNextEnabled(enabled);
    }

    public void EnableInstall()
    {
        Shell.EnableInstall();
    }

    public void RunNext()
    {
        Shell.RunNext();
    }

    public void Stop()
    {
        Shell.Window.RequestStop();
    }

    public void ShowAbout()
    {
        MessageBox.Query(App, "About", "OpinionatedArch installer", "OK");
    }

    public void ShowError(string message)
    {
        MessageBox.Query(App, "Error", message, "OK");
    }

    public void ShowVerboseDialog()
    {
        var dialog = new Dialog
        {
            Title = "Verbose level",
            Width = 76,
            Height = 12
        };
        var choices = new ObservableCollection<string>(new[]
        {
            "0 - progress: show high-level statements only",
            "1 - commands: show [EXEC] without command output",
            "2 - debug: show [EXEC] and command output"
        });
        var list = new ListView
        {
            X = 1,
            Y = 1,
            Width = Terminal.Gui.ViewBase.Dim.Fill(),
            Height = 5
        };
        list.SetSource(choices);
        var selectedVerbose = (int)State.Verbose;
        list.SelectedItem = selectedVerbose >= 0 && selectedVerbose < choices.Count ? selectedVerbose : 0;
        list.KeyBindings.ReplaceCommands(Terminal.Gui.Input.Key.Enter, Terminal.Gui.Input.Command.Accept);
        list.Accepted += (_, _) =>
        {
            State.Verbose = (VerboseLevel)(list.SelectedItem ?? 0);
            ShellCommand.Verbose = State.Verbose;
            Shell.UpdateVerboseStatus();
            dialog.RequestStop();
        };
        dialog.Add(list);
        list.SetFocus();
        App.Run(dialog, _ => false);
    }

    public void ConfirmExit()
    {
        var result = MessageBox.Query(App, "Exit", "Exit installer?", "Cancel", "Exit");
        if (result == 1)
        {
            Shell.Window.RequestStop();
        }
    }

    public void ShowShutdownDialog()
    {
        var result = MessageBox.Query(App, "Shutdown", "Choose an action:", "Cancel", "Poweroff", "Reboot");
        try
        {
            if (result == 1)
            {
                ShellCommand.Run(Live, "systemctl", "poweroff");
            }
            else if (result == 2)
            {
                ShellCommand.Run(Live, "systemctl", "reboot");
            }
        }
        catch (Exception error)
        {
            ShowError(error.Message);
        }
    }

    public void OpenConfigFile()
    {
        var dialog = new OpenDialog
        {
            Title = "Open config file",
            AllowsMultipleSelection = false,
            MustExist = true,
            OpenMode = OpenMode.File,
            Path = Directory.GetCurrentDirectory()
        };
        App.Run(dialog, _ => false);
        if (dialog.Canceled || dialog.FilePaths.Count == 0)
        {
            return;
        }
        try
        {
            State.Config = InstallerInput.LoadConfig(Live, AssetDirectory, dialog.FilePaths[0], LogoLocalPath);
            State.SynchronizeFromConfig();
            Navigator.ShowSummary();
        }
        catch (Exception error)
        {
            ShowError(error.Message);
        }
    }
}
