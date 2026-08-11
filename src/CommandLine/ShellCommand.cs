using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Diagnostics;
using System.IO;
using System.Linq;
using IOKode.OpinionatedFramework.Facades;
using IOKode.OpinionatedFramework.ServiceLocation;

namespace IOKode.OpinionatedArch.CommandLine;

public static class ShellCommand
{
    public static VerboseLevel Verbose { get; set; }

    public static void Run(Target target, string program, params string[] args)
    {
        var command = BuildCommand(target, program, args, null);
        LogExecIfVerbose(command);
        var captureOutput = Verbose != VerboseLevel.Debug;
        var result = RunProcess(target, command.Program, command.Arguments, null, captureOutput, null);
        if (result.ExitCode != 0)
        {
            if (Verbose == VerboseLevel.Progress)
            {
                File.WriteAllText("/tmp/oparch-cmd.log", result.Output);
                PrintLastLines(result.Output, 120);
            }
            throw new ShellCommandException(command.Program, command.Arguments, result.ExitCode)
            {
                Target = target,
                Program = command.Program,
                Arguments = command.Arguments,
                ExitCode = result.ExitCode,
                Output = result.Output
            };
        }
    }

    public static void RunWithInput(Target target, string? title, string input, string program, params string[] args)
    {
        var command = BuildCommand(target, program, args, null);
        if (Verbose == VerboseLevel.Progress && title is not null)
        {
            Locator.Resolve<ICommandStatus>().Run(title, delegate
            {
                var result = RunProcess(target, command.Program, command.Arguments, input, true, null);
                if (result.ExitCode != 0)
                {
                    File.WriteAllText("/tmp/oparch-cmd.log", result.Output);
                    throw new ShellCommandException(command.Program, command.Arguments, result.ExitCode)
                    {
                        Target = target,
                        Program = command.Program,
                        Arguments = command.Arguments,
                        ExitCode = result.ExitCode,
                        Output = result.Output
                    };
                }
            });
            return;
        }

        LogExecIfVerbose(command);
        var commandResult = RunProcess(target, command.Program, command.Arguments, input, Verbose != VerboseLevel.Debug, null);
        if (commandResult.ExitCode != 0)
        {
            if (Verbose == VerboseLevel.Progress)
            {
                File.WriteAllText("/tmp/oparch-cmd.log", commandResult.Output);
                PrintLastLines(commandResult.Output, 120);
            }
            throw new ShellCommandException(command.Program, command.Arguments, commandResult.ExitCode)
            {
                Target = target,
                Program = command.Program,
                Arguments = command.Arguments,
                ExitCode = commandResult.ExitCode,
                Output = commandResult.Output
            };
        }
    }

    public static void Working(Target target, string progressMessage, string program, params string[] args)
    {
        var command = BuildCommand(target, program, args, null);
        if (Verbose == VerboseLevel.Progress)
        {
            Locator.Resolve<ICommandStatus>().Run(progressMessage, delegate
            {
                var result = RunProcess(target, command.Program, command.Arguments, null, true, null);
                if (result.ExitCode != 0)
                {
                    File.WriteAllText("/tmp/oparch-cmd.log", result.Output);
                    PrintLastLines(result.Output, 120);
                    throw new ShellCommandException(command.Program, command.Arguments, result.ExitCode)
                    {
                        Target = target,
                        Program = command.Program,
                        Arguments = command.Arguments,
                        ExitCode = result.ExitCode,
                        Output = result.Output
                    };
                }
            });
            return;
        }
        LogExecIfVerbose(command);
        var verboseResult = RunProcess(target, command.Program, command.Arguments, null, Verbose != VerboseLevel.Debug, null);
        if (verboseResult.ExitCode != 0)
        {
            throw new ShellCommandException(command.Program, command.Arguments, verboseResult.ExitCode)
            {
                Target = target,
                Program = command.Program,
                Arguments = command.Arguments,
                ExitCode = verboseResult.ExitCode,
                Output = verboseResult.Output
            };
        }
    }

    public static string Capture(Target target, string program, params string[] args)
    {
        var command = BuildCommand(target, program, args, null);
        LogExecIfVerbose(command);
        var result = RunProcess(target, command.Program, command.Arguments, null, true, null);
        PrintOutputIfFullVerbose(result);
        if (result.ExitCode != 0)
        {
            throw new ShellCommandException(command.Program, command.Arguments, result.ExitCode)
            {
                Target = target,
                Program = command.Program,
                Arguments = command.Arguments,
                ExitCode = result.ExitCode,
                Output = result.Output
            };
        }
        return result.StandardOutput;
    }

    public static string CaptureWithInputAndEnvironment(Target target, string program, string[] args, string input, IReadOnlyDictionary<string, string> environment)
    {
        var command = BuildCommand(target, program, args, environment);
        LogExecIfVerbose(command);
        var result = RunProcess(target, command.Program, command.Arguments, input, true, command.Environment);
        PrintOutputIfFullVerbose(result);
        if (result.ExitCode != 0)
        {
            throw new ShellCommandException(command.Program, command.Arguments, result.ExitCode)
            {
                Target = target,
                Program = command.Program,
                Arguments = command.Arguments,
                ExitCode = result.ExitCode,
                Output = result.Output
            };
        }
        return result.StandardOutput;
    }

    public static bool CommandSucceeds(Target target, string program, params string[] args)
    {
        var command = BuildCommand(target, program, args, null);
        LogExecIfVerbose(command);
        var result = RunProcess(target, command.Program, command.Arguments, null, true, null);
        PrintOutputIfFullVerbose(result);
        return result.ExitCode == 0;
    }

    private static void LogExecIfVerbose(PreparedCommand command)
    {
        if (Verbose != VerboseLevel.Progress)
        {
            Log.Exec(command.Program, command.Arguments);
        }
    }

    private static void PrintOutputIfFullVerbose(CommandResult result)
    {
        if (Verbose == VerboseLevel.Debug && !string.IsNullOrEmpty(result.Output))
        {
            Console.Write(result.Output);
        }
    }

    private static PreparedCommand BuildCommand(Target target, string program, IReadOnlyList<string> args, IReadOnlyDictionary<string, string>? environment)
    {
        if (!target.UsesChroot)
        {
            return new PreparedCommand
            {
                Program = program,
                Arguments = args,
                Environment = environment
            };
        }

        var chrootArgs = new List<string> { target.RootPath };
        IReadOnlyDictionary<string, string>? processEnvironment = null;
        if (environment is not null && environment.Count > 0)
        {
            chrootArgs.Add("env");
            foreach (var (key, value) in environment)
            {
                chrootArgs.Add($"{key}={value}");
            }
        }
        chrootArgs.Add(program);
        chrootArgs.AddRange(args);
        return new PreparedCommand
        {
            Program = "arch-chroot",
            Arguments = chrootArgs,
            Environment = processEnvironment
        };
    }

    private static CommandResult RunProcess(Target target, string program, IReadOnlyList<string> args, string? input, bool captureOutput, IReadOnlyDictionary<string, string>? environment)
    {
        var startInfo = new ProcessStartInfo(program)
        {
            RedirectStandardInput = input is not null,
            RedirectStandardOutput = captureOutput,
            RedirectStandardError = captureOutput,
            UseShellExecute = false
        };
        foreach (var arg in args)
        {
            startInfo.ArgumentList.Add(arg);
        }
        if (environment is not null)
        {
            foreach (var (key, value) in environment)
            {
                startInfo.Environment[key] = value;
            }
        }

        Process? process;
        try
        {
            process = Process.Start(startInfo);
        }
        catch (Win32Exception error)
        {
            throw new ShellCommandException(program, args, error)
            {
                Target = target,
                Program = program,
                Arguments = args,
                ExitCode = null,
                Output = null
            };
        }

        using var runningProcess = process ?? throw new ShellCommandException(program, args, (int?)null)
        {
            Target = target,
            Program = program,
            Arguments = args,
            ExitCode = null,
            Output = null
        };
        if (input is not null)
        {
            runningProcess.StandardInput.Write(input);
            runningProcess.StandardInput.Close();
        }

        var stdout = captureOutput ? runningProcess.StandardOutput.ReadToEnd() : string.Empty;
        var stderr = captureOutput ? runningProcess.StandardError.ReadToEnd() : string.Empty;
        runningProcess.WaitForExit();
        return new CommandResult
        {
            ExitCode = runningProcess.ExitCode,
            StandardOutput = stdout,
            StandardError = stderr,
            Output = stdout + stderr
        };
    }

    private static void PrintLastLines(string content, int count)
    {
        var lines = content.Split('\n');
        foreach (var line in lines.Skip(Math.Max(0, lines.Length - count)))
        {
            if (!string.IsNullOrEmpty(line))
            {
                Console.Error.WriteLine(line);
            }
        }
    }

    private sealed class CommandResult
    {
        public required int ExitCode { get; init; }

        public required string StandardOutput { get; init; }

        public required string StandardError { get; init; }

        public required string Output { get; init; }
    }

    private sealed class PreparedCommand
    {
        public required string Program { get; init; }

        public required IReadOnlyList<string> Arguments { get; init; }

        public required IReadOnlyDictionary<string, string>? Environment { get; init; }
    }
}
