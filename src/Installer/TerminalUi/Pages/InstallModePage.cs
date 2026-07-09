using System.Collections.ObjectModel;
using Terminal.Gui.Views;

#pragma warning disable CS0618

namespace IOKode.OpinionatedArch.Installer.TerminalUi.Pages;

internal sealed class InstallModePage : IInstallerPage
{
    public void Render(TerminalInstallerContext context)
    {
        context.State.StepIndex = 1;
        context.SetContent("Install mode");
        context.Form.AddInstruction("Use arrow keys to choose an option. Press Enter to select and continue.");
        var choices = new ObservableCollection<string>(new[] { "wipe-all", "keep-homes" });
        ListView list = null!;
        list = context.Form.AddSelector("Install mode", choices, 2, 12, context.State.InstallModeIndex, delegate(int selected)
        {
            context.State.InstallModeIndex = selected;
            context.State.Config.InstallMode = choices[selected];
            context.SetNextEnabled(true);
        }, delegate
        {
            context.Form.SelectCurrent(list, delegate(int selected)
            {
                context.State.InstallModeIndex = selected;
                context.State.Config.InstallMode = choices[selected];
            });
            context.Navigator.ShowStartup();
        });
        context.SetNavigation(context.Navigator.ShowDisk, delegate
        {
            if (context.State.InstallModeIndex is null)
            {
                context.ShowError("Select install mode before continuing.");
                return;
            }
            context.Navigator.ShowStartup();
        }, nextEnabled: context.State.InstallModeIndex is not null);
        list.SetFocus();
    }
}
