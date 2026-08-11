using System;

namespace IOKode.OpinionatedArch.Installer.TerminalUi.Pages;

internal sealed class SummaryPage : IInstallerPage
{
    public void Render(TerminalInstallerContext context)
    {
        context.State.StepIndex = 10;
        context.SetContent("Summary");
        var summary = context.State.BuildSummary();
        var y = 1;
        foreach (var line in summary.Split('\n'))
        {
            context.Form.AddLabel(line, y++);
        }
        context.Form.AddLabel("Press F2 to start the installation", y + 1);
        context.SetNavigation(context.Navigator.ShowReturnMessage, delegate
        {
            try
            {
                InstallerInput.ValidateConfig(context.Live, context.AssetDirectory, context.State.Config);
                context.State.Result = context.State.Config;
                context.Stop();
            }
            catch (Exception error)
            {
                context.ShowError(error.Message);
            }
        });
        context.EnableInstall();
    }
}
