using System;
using System.IO;
using IOKode.OpinionatedArch.CommandLine;
using IOKode.OpinionatedArch.SpectreConsole;
using IOKode.OpinionatedFramework.Facades;

namespace IOKode.OpinionatedArch.Installer;

file static class Program
{
    private const string TempDirectory = "/tmp/oparch";
    private const string LogoLocalPath = "/tmp/oparch/logo.png";

    private static int Main()
    {
        try
        {
            SpectreConsoleServices.Initialize();
            Run();
            return 0;
        }
        catch (Exception error)
        {
            Log.Error(error.Message);
            return 1;
        }
    }

    private static void Run()
    {
        var live = Target.Local();
        var installerDirectory = AppContext.BaseDirectory;
        var assetDirectory = Path.Combine(installerDirectory, "assets");

        var config = new TerminalInstallerUi
        {
            Live = live,
            AssetDirectory = assetDirectory,
            TempDirectory = TempDirectory,
            LogoLocalPath = LogoLocalPath
        }.Collect();
        
        var target = Target.Chroot("/mnt");
        Disk.PrepareLayout(live, target, config);
        BootstrapInstaller.BaseSystem(live, target, config, installerDirectory);
        ChrootInstaller.ConfigureTarget(target, config);

        Log.Info("Installation completed. Review /mnt and reboot when ready.");
    }
}
