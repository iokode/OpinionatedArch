using System.Collections.Generic;
using System.Collections.ObjectModel;
using Terminal.Gui.Views;

#pragma warning disable CS0618

namespace IOKode.OpinionatedArch.Installer.TerminalUi.Pages;

internal sealed class DiskPage : IInstallerPage
{
    public void Render(TerminalInstallerContext context)
    {
        context.State.StepIndex = 0;
        context.SetContent("Target disk");
        context.Form.AddInstruction("Use arrow keys to choose an option. Press Enter to select and continue.");
        var disks = Disk.ListInstallTargets(context.Live);
        var labels = new List<string>();
        for (var index = 0; index < disks.Count; index++)
        {
            labels.Add(Disk.FormatDiskLabel(disks[index]));
            if (context.State.Config.TargetDisk == disks[index].Path)
            {
                context.State.TargetDiskIndex = index;
            }
        }
        var source = new ObservableCollection<string>(labels);
        ListView list = null!;
        list = context.Form.AddSelector("Target disk", source, 2, 12, context.State.TargetDiskIndex, delegate(int selected)
        {
            context.State.TargetDiskIndex = selected;
            context.State.Config.TargetDisk = disks[selected].Path;
            context.SetNextEnabled(true);
        }, delegate
        {
            if (!context.Form.SelectCurrent(list, delegate(int selected)
            {
                context.State.TargetDiskIndex = selected;
                context.State.Config.TargetDisk = disks[selected].Path;
            }))
            {
                context.ShowError("No options are available.");
                return;
            }
            context.Navigator.ShowInstallMode();
        });
        context.SetNavigation(null, delegate
        {
            if (context.State.TargetDiskIndex is null)
            {
                context.ShowError("Select target disk before continuing.");
                return;
            }
            context.Navigator.ShowInstallMode();
        }, nextEnabled: context.State.TargetDiskIndex is not null);
        list.SetFocus();
    }
}
