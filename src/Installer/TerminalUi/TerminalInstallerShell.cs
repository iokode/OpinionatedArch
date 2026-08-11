using System;
using Terminal.Gui.Drawing;
using Terminal.Gui.Drivers;
using Terminal.Gui.Input;
using Terminal.Gui.ViewBase;
using Terminal.Gui.Views;

#pragma warning disable CS0618

namespace IOKode.OpinionatedArch.Installer.TerminalUi;

internal sealed class TerminalInstallerShell
{
    private readonly TerminalInstallerState _state;
    private Shortcut _previousShortcut = null!;
    private Shortcut _installShortcut = null!;
    private Shortcut _verboseShortcut = null!;
    private bool _nextEnabled;
    private Action? _previousAction;
    private Action? _nextAction;

    public TerminalInstallerShell(TerminalInstallerState state)
    {
        _state = state;
    }

    public Window Window { get; private set; } = null!;

    public FrameView ContentPanel { get; private set; } = null!;

    private FrameView StepsPanel { get; set; } = null!;

    public void Build(TerminalInstallerContext context)
    {
        Window = new Window
        {
            X = 0,
            Y = 0,
            Width = Dim.Fill(),
            Height = Dim.Fill(),
            BorderStyle = LineStyle.None
        };

        StepsPanel = new FrameView
        {
            Title = "Steps",
            X = 0,
            Y = 0,
            Width = 28,
            Height = Dim.Fill(),
            BorderStyle = LineStyle.Single
        };
        ContentPanel = new FrameView
        {
            X = 28,
            Y = 0,
            Width = Dim.Fill(),
            Height = Dim.Fill(),
            BorderStyle = LineStyle.None
        };
        _previousShortcut = new Shortcut(new Key(KeyCode.F1), "Previous", RunPrevious, string.Empty);
        _installShortcut = new Shortcut(new Key(KeyCode.F2), "Install", RunInstall, string.Empty) { Enabled = false };
        _verboseShortcut = new Shortcut(new Key(KeyCode.F4), "Verbose: 0", context.ShowVerboseDialog, string.Empty);
        var statusBar = new StatusBar(new[]
        {
            _previousShortcut,
            _installShortcut,
            new Shortcut(new Key(KeyCode.F3), "About", context.ShowAbout, string.Empty),
            _verboseShortcut,
            new Shortcut(new Key(KeyCode.F5), "Open file", context.OpenConfigFile, string.Empty),
            new Shortcut(new Key(KeyCode.F6), "Exit", context.ConfirmExit, string.Empty),
            new Shortcut(new Key(KeyCode.F7), "Shutdown", context.ShowShutdownDialog, string.Empty)
        });

        Window.Add(StepsPanel, ContentPanel, statusBar);
        UpdateVerboseStatus();
        RenderSteps();
    }

    public void SetContent(string title)
    {
        ContentPanel.RemoveAll();
        ContentPanel.Title = title;
        RenderSteps();
    }

    public void SetNavigation(Action? previous, Action? next, bool nextEnabled = true)
    {
        _previousAction = previous;
        _nextAction = next;
        _previousShortcut.Enabled = previous is not null;
        _nextEnabled = next is not null && nextEnabled;
        _installShortcut.Enabled = false;
        RenderSteps();
    }

    public void SetNextEnabled(bool enabled)
    {
        _nextEnabled = _nextAction is not null && enabled;
    }

    public void EnableInstall()
    {
        _installShortcut.Enabled = true;
    }

    public void UpdateVerboseStatus()
    {
        _verboseShortcut.Text = $"Verbose: {(int)_state.Verbose}";
    }

    public void RunNext()
    {
        if (_nextEnabled)
        {
            _nextAction?.Invoke();
        }
    }

    private void RunPrevious()
    {
        if (_previousShortcut.Enabled)
        {
            _previousAction?.Invoke();
        }
    }

    private void RunInstall()
    {
        if (_state.StepIndex == 10)
        {
            RunNext();
        }
    }

    private void RenderSteps()
    {
        StepsPanel.RemoveAll();
        for (var index = 0; index < _state.Steps.Count; index++)
        {
            var marker = index < _state.StepIndex ? "✓" : index == _state.StepIndex ? ">" : " ";
            StepsPanel.Add(new Label
            {
                Text = $"{marker} {_state.Steps[index]}",
                X = 1,
                Y = index + 1,
                Width = Dim.Fill(),
                Height = 1
            });
        }
    }
}
