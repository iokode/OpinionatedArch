namespace IOKode.OpinionatedArch.Installer.TerminalUi.Pages;

internal sealed class IdentityPage : IInstallerPage
{
    public void Render(TerminalInstallerContext context)
    {
        context.State.StepIndex = 7;
        context.SetContent("Identity");
        context.Form.AddTextField("Hostname:", 2, context.State.Hostname, value => context.State.Hostname = value).SetFocus();
        context.SetNavigation(context.Navigator.ShowLocale, delegate
        {
            if (!InstallerInput.ValidateHostname(context.State.Hostname))
            {
                context.ShowError("Invalid hostname format.");
                return;
            }
            context.State.Config.HostnameValue = context.State.Hostname;
            context.Navigator.ShowDotfiles();
        });
    }
}
