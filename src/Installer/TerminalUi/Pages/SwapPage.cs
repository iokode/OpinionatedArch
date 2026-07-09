namespace IOKode.OpinionatedArch.Installer.TerminalUi.Pages;

internal sealed class SwapPage : IInstallerPage
{
    public void Render(TerminalInstallerContext context)
    {
        context.State.StepIndex = 4;
        context.SetContent("Swap");
        context.Form.AddInstruction("Enter non-negative integer sizes in GB.");
        var zramSwapField = context.Form.AddTextField("zram size in GB:", 2, context.State.ZramSwapText, value => context.State.ZramSwapText = value);
        context.Form.AddTextField("disk swapfile size in GB:", 4, context.State.DiskSwapText, value => context.State.DiskSwapText = value);
        zramSwapField.SetFocus();
        context.SetNavigation(context.Navigator.ShowHardware, delegate
        {
            if (!ulong.TryParse(context.State.ZramSwapText, out var zramValue) || !ulong.TryParse(context.State.DiskSwapText, out var diskValue))
            {
                context.ShowError("Swap sizes must be non-negative integers.");
                return;
            }
            context.State.Config.ZramSwapGb = zramValue;
            context.State.Config.DiskSwapfileGb = diskValue;
            context.Navigator.ShowUsers();
        });
    }
}
