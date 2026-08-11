using System;
using IOKode.OpinionatedArch.CommandLine;
using Spectre.Console;

namespace IOKode.OpinionatedArch.SpectreConsole;

internal sealed class SpectreCommandStatus : ICommandStatus
{
    public void Run(string title, Action action)
    {
        AnsiConsole.Status().Spinner(Spinner.Known.Line).Start(title, delegate
        {
            action();
        });
    }
}
