using System.Collections.Generic;
using IOKode.OpinionatedFramework.Facades;

namespace IOKode.OpinionatedArch.CommandLine;

[AddToFacade("Log")]
public interface ILog
{
    void Info(string message);

    void Warn(string message);

    void Error(string message);

    void Exec(string program, IEnumerable<string> args);
}
