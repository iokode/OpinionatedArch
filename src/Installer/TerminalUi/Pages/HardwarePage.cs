using System.Collections.ObjectModel;
using Terminal.Gui.Views;

#pragma warning disable CS0618

namespace IOKode.OpinionatedArch.Installer.TerminalUi.Pages;

internal sealed class HardwarePage : IInstallerPage
{
    public void Render(TerminalInstallerContext context)
    {
        context.State.StepIndex = 3;
        context.SetContent("Hardware");
        context.Form.AddInstruction("Select both hardware options. Press Enter in the first selector to move to the second.");
        var ucodeChoices = new ObservableCollection<string>(new[] { "intel-ucode", "amd-ucode", "none" });
        var gpuChoices = new ObservableCollection<string>(new[] { "nvidia", "nvidia-open", "nouveau", "none" });
        ListView ucodeList = null!;
        ListView gpuList = null!;
        ucodeList = context.Form.AddSelector("Install ucode", ucodeChoices, 2, 5, context.State.UcodeIndex, delegate(int selected)
        {
            context.State.UcodeIndex = selected;
            context.State.Config.UcodePackage = ucodeChoices[selected];
            context.SetNextEnabled(context.State.HardwareSelected());
        }, delegate
        {
            context.Form.SelectCurrent(ucodeList, delegate(int selected)
            {
                context.State.UcodeIndex = selected;
                context.State.Config.UcodePackage = ucodeChoices[selected];
            });
            gpuList.SetFocus();
            context.SetNextEnabled(context.State.HardwareSelected());
        });
        gpuList = context.Form.AddSelector("GPU driver", gpuChoices, 8, 6, context.State.GpuIndex, delegate(int selected)
        {
            context.State.GpuIndex = selected;
            context.State.Config.GpuDriver = gpuChoices[selected];
            context.SetNextEnabled(context.State.HardwareSelected());
        }, delegate
        {
            context.Form.SelectCurrent(gpuList, delegate(int selected)
            {
                context.State.GpuIndex = selected;
                context.State.Config.GpuDriver = gpuChoices[selected];
            });
            context.SetNextEnabled(context.State.HardwareSelected());
            if (context.State.HardwareSelected())
            {
                context.Navigator.ShowSwap();
            }
        });
        context.SetNavigation(context.Navigator.ShowStartup, delegate
        {
            if (!context.State.HardwareSelected())
            {
                context.ShowError("Select both hardware options.");
                return;
            }
            context.Navigator.ShowSwap();
        }, nextEnabled: context.State.HardwareSelected());
        ucodeList.SetFocus();
    }
}
