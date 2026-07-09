using System;

namespace IOKode.OpinionatedArch.CommandLine;

public interface ICommandStatus
{
    void Run(string title, Action action);
}
