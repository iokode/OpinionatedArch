using System.Collections.ObjectModel;
using Terminal.Gui.Views;

#pragma warning disable CS0618

namespace IOKode.OpinionatedArch.Installer.TerminalUi.Pages;

internal sealed class StartupPage : IInstallerPage
{
    public void Render(TerminalInstallerContext context)
    {
        context.State.StepIndex = 2;
        context.SetContent("Startup policy");
        context.Form.AddInstruction("Use arrow keys to choose an option. Press Enter to select and continue.");
        var choices = new ObservableCollection<string>(new[] { "manual", "automatic" });
        ListView list = null!;
        list = context.Form.AddSelector("Startup policy", choices, 2, 12, context.State.StartupPolicyIndex, delegate(int selected)
        {
            context.State.StartupPolicyIndex = selected;
            context.State.Config.StartupPolicy = choices[selected];
            context.SetNextEnabled(true);
        }, delegate
        {
            context.Form.SelectCurrent(list, delegate(int selected)
            {
                context.State.StartupPolicyIndex = selected;
                context.State.Config.StartupPolicy = choices[selected];
            });
            context.Navigator.ShowHardware();
        });
        context.SetNavigation(context.Navigator.ShowInstallMode, delegate
        {
            if (context.State.StartupPolicyIndex is null)
            {
                context.ShowError("Select startup policy before continuing.");
                return;
            }
            context.Navigator.ShowHardware();
        }, nextEnabled: context.State.StartupPolicyIndex is not null);
        list.SetFocus();
    }
}
