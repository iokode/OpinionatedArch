using System.Collections.ObjectModel;
using Terminal.Gui.Views;

#pragma warning disable CS0618

namespace IOKode.OpinionatedArch.Installer.TerminalUi.Pages;

internal sealed class DotfilesPage : IInstallerPage
{
    public void Render(TerminalInstallerContext context)
    {
        context.State.StepIndex = 8;
        context.SetContent("Dotfiles");
        context.Form.AddInstruction("The repository URL is requested only when dotfiles cloning is enabled.");
        var choices = new ObservableCollection<string>(new[] { "yes", "no" });
        ListView list = null!;
        TextField? repositoryField = null;
        list = context.Form.AddSelector("Clone public dotfiles repository?", choices, 2, 4, context.State.DotfilesIndex, delegate(int selected)
        {
            context.State.DotfilesIndex = selected;
            context.State.Config.ClonePublicDotfiles = choices[selected];
            if (context.State.Config.ClonePublicDotfiles == "no")
            {
                context.State.DotfilesFocusRepository = false;
                context.State.DotfilesRepositoryUrl = string.Empty;
                context.State.Config.DotfilesRepositoryUrl = string.Empty;
            }
            else
            {
                context.State.DotfilesFocusRepository = true;
            }
            context.Navigator.ShowDotfiles();
        }, delegate
        {
            context.Form.SelectCurrent(list, delegate(int selected)
            {
                context.State.DotfilesIndex = selected;
                context.State.Config.ClonePublicDotfiles = choices[selected];
            });
            if (context.State.Config.ClonePublicDotfiles == "yes")
            {
                context.State.DotfilesFocusRepository = true;
                context.Navigator.ShowDotfiles();
            }
            else
            {
                context.State.DotfilesFocusRepository = false;
                context.State.DotfilesRepositoryUrl = string.Empty;
                context.State.Config.DotfilesRepositoryUrl = string.Empty;
                context.Navigator.ShowReturnMessage();
            }
        });
        if (context.State.Config.ClonePublicDotfiles == "yes")
        {
            repositoryField = context.Form.AddTextField("Dotfiles repository URL:", 8, context.State.DotfilesRepositoryUrl, value => context.State.DotfilesRepositoryUrl = value);
            if (context.State.DotfilesFocusRepository)
            {
                repositoryField.SetFocus();
            }
            else
            {
                list.SetFocus();
            }
        }
        else
        {
            list.SetFocus();
        }
        context.SetNavigation(delegate
        {
            if (repositoryField is not null && repositoryField.HasFocus)
            {
                context.State.DotfilesFocusRepository = false;
                list.SetFocus();
            }
            else
            {
                context.Navigator.ShowIdentity();
            }
        }, delegate
        {
            if (context.State.DotfilesIndex is null)
            {
                context.ShowError("Select whether to clone dotfiles.");
                return;
            }
            context.State.Config.DotfilesRepositoryUrl = context.State.Config.ClonePublicDotfiles == "yes" ? context.State.DotfilesRepositoryUrl : string.Empty;
            if (context.State.Config.ClonePublicDotfiles == "yes" && string.IsNullOrEmpty(context.State.Config.DotfilesRepositoryUrl))
            {
                context.ShowError("Dotfiles repository URL is required when dotfiles cloning is enabled.");
                return;
            }
            context.Navigator.ShowReturnMessage();
        }, nextEnabled: context.State.DotfilesIndex is not null);
    }
}
