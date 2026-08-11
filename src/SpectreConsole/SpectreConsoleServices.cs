using IOKode.OpinionatedArch.CommandLine;
using IOKode.OpinionatedFramework.ServiceContainer;
using Microsoft.Extensions.DependencyInjection;

namespace IOKode.OpinionatedArch.SpectreConsole;

public static class SpectreConsoleServices
{
    public static void Initialize()
    {
        Container.Services.AddSingleton<ILog, SpectreLog>();
        Container.Services.AddSingleton<ICommandStatus, SpectreCommandStatus>();
        Container.Initialize();
    }
}
