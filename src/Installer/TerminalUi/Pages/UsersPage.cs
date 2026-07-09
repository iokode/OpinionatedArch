using System;

namespace IOKode.OpinionatedArch.Installer.TerminalUi.Pages;

internal sealed class UsersPage : IInstallerPage
{
    public void Render(TerminalInstallerContext context)
    {
        context.State.StepIndex = 5;
        context.SetContent("Users");
        context.Form.AddInstruction("A shared secret is required and must be confirmed here.");
        var loginUsersField = context.Form.AddTextField("Login usernames (comma-separated):", 2, context.State.LoginUsersCsv, value => context.State.LoginUsersCsv = value);
        context.Form.AddTextField("Shared secret:", 4, context.State.SharedSecret, value => context.State.SharedSecret = value, true);
        context.Form.AddTextField("Confirm shared secret:", 6, context.State.SharedSecretConfirmation, value => context.State.SharedSecretConfirmation = value, true);
        loginUsersField.SetFocus();
        context.SetNavigation(context.Navigator.ShowSwap, delegate
        {
            if (string.IsNullOrEmpty(context.State.SharedSecret))
            {
                context.ShowError("Shared secret is required.");
                return;
            }
            if (context.State.SharedSecret != context.State.SharedSecretConfirmation)
            {
                context.ShowError("Shared secret values do not match.");
                return;
            }
            try
            {
                context.State.Config.LoginUsers.Clear();
                context.State.Config.LoginUsers.AddRange(InstallerInput.ParseLoginUsersCsv(context.State.LoginUsersCsv));
                context.State.Config.SharedSecret = context.State.SharedSecret;
                context.Navigator.ShowLocale();
            }
            catch (Exception error)
            {
                context.ShowError(error.Message);
            }
        });
    }
}
