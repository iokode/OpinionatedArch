using System;
using System.Collections.Generic;

namespace IOKode.OpinionatedArch.CommandLine;

public sealed class ShellCommandException : Exception
{
    public ShellCommandException(string program, IReadOnlyList<string> arguments, int? exitCode)
        : base(BuildMessage(program, arguments, exitCode))
    {
    }

    public ShellCommandException(string program, IReadOnlyList<string> arguments, Exception innerException)
        : base(BuildMessage(program, arguments, null), innerException)
    {
    }

    public required Target Target { get; init; }

    public required string Program { get; init; }

    public required IReadOnlyList<string> Arguments { get; init; }

    public required int? ExitCode { get; init; }

    public required string? Output { get; init; }

    private static string BuildMessage(string program, IReadOnlyList<string> arguments, int? exitCode)
    {
        var formattedArguments = string.Join(" ", arguments);
        if (exitCode is null)
        {
            return $"failed to start command: {program} {formattedArguments}";
        }

        return $"command failed with exit code {exitCode}: {program} {formattedArguments}";
    }
}
