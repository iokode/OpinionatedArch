using System.Collections.Generic;
using IOKode.OpinionatedArch.CommandLine;
using Spectre.Console;

namespace IOKode.OpinionatedArch.SpectreConsole;

internal sealed class SpectreLog : ILog
{
    public void Info(string message)
    {
        if (ShellCommand.Verbose == VerboseLevel.Progress)
        {
            AnsiConsole.MarkupLine($"[blue][[INFO]][/] {Markup.Escape(message)}");
        }
    }

    public void Warn(string message)
    {
        AnsiConsole.MarkupLine($"[yellow][[WARN]][/] {Markup.Escape(message)}");
    }

    public void Error(string message)
    {
        AnsiConsole.MarkupLine($"[red][[ERROR]][/] {Markup.Escape(message)}");
    }

    public void Exec(string program, IEnumerable<string> args)
    {
        AnsiConsole.MarkupLine($"[green][[EXEC]][/] {Markup.Escape(program)} {Markup.Escape(FormatArgs(args))}");
    }

    private static string FormatArgs(IEnumerable<string> args)
    {
        return string.Join(" ", args);
    }
}
