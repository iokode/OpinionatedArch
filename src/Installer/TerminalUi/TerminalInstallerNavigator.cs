using IOKode.OpinionatedArch.Installer.TerminalUi.Pages;

namespace IOKode.OpinionatedArch.Installer.TerminalUi;

internal sealed class TerminalInstallerNavigator
{
    private TerminalInstallerContext _context = null!;

    public void Initialize(TerminalInstallerContext context)
    {
        _context = context;
    }

    public void ShowDisk() => new DiskPage().Render(_context);

    public void ShowInstallMode() => new InstallModePage().Render(_context);

    public void ShowStartup() => new StartupPage().Render(_context);

    public void ShowHardware() => new HardwarePage().Render(_context);

    public void ShowSwap() => new SwapPage().Render(_context);

    public void ShowUsers() => new UsersPage().Render(_context);

    public void ShowLocale() => new LocalePage().Render(_context);

    public void ShowIdentity() => new IdentityPage().Render(_context);

    public void ShowDotfiles() => new DotfilesPage().Render(_context);

    public void ShowReturnMessage() => new ReturnMessagePage().Render(_context);

    public void ShowSummary() => new SummaryPage().Render(_context);
}
