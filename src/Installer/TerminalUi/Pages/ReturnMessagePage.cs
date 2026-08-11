using System;
using System.Collections.ObjectModel;
using Terminal.Gui.ViewBase;
using Terminal.Gui.Views;

#pragma warning disable CS0618

namespace IOKode.OpinionatedArch.Installer.TerminalUi.Pages;

internal sealed class ReturnMessagePage : IInstallerPage
{
    public void Render(TerminalInstallerContext context)
    {
        context.State.StepIndex = 9;
        context.SetContent("Return message");
        context.Form.AddInstruction("Return-message details appear only when the return message is enabled.");
        var includeChoices = new ObservableCollection<string>(new[] { "yes", "no" });
        ListView includeList = null!;
        TextField? ownerNameField = null;
        TextField? ownerPhoneField = null;
        TextField? ownerEmailField = null;
        TextField? ownerAddressField = null;
        ListView? logoList = null;
        TextField? logoUrlField = null;
        includeList = context.Form.AddSelector("Include pre-boot return message?", includeChoices, 2, 4, context.State.ReturnMessageIndex, delegate(int selected)
        {
            context.State.ReturnMessageIndex = selected;
            context.State.Config.IncludeReturnMessage = includeChoices[selected];
            if (context.State.Config.IncludeReturnMessage == "no")
            {
                context.State.ReturnMessageFocus = TerminalInstallerState.ReturnMessageFocusInclude;
                context.State.ClearReturnMessageDetails();
            }
            else
            {
                context.State.ReturnMessageFocus = TerminalInstallerState.ReturnMessageFocusOwnerName;
            }
            context.Navigator.ShowReturnMessage();
        }, delegate
        {
            context.Form.SelectCurrent(includeList, delegate(int selected)
            {
                context.State.ReturnMessageIndex = selected;
                context.State.Config.IncludeReturnMessage = includeChoices[selected];
            });
            if (context.State.Config.IncludeReturnMessage == "yes")
            {
                context.State.ReturnMessageFocus = TerminalInstallerState.ReturnMessageFocusOwnerName;
                context.Navigator.ShowReturnMessage();
            }
            else
            {
                context.State.ReturnMessageFocus = TerminalInstallerState.ReturnMessageFocusInclude;
                context.State.ClearReturnMessageDetails();
                context.State.CommitReturnMessageState();
                context.Navigator.ShowSummary();
            }
        });
        includeList.HasFocusChanged += (_, _) =>
        {
            if (includeList.HasFocus)
            {
                context.State.ReturnMessageFocus = TerminalInstallerState.ReturnMessageFocusInclude;
            }
        };
        if (context.State.Config.IncludeReturnMessage == "yes")
        {
            ownerNameField = context.Form.AddTextField("Owner name:", 8, context.State.OwnerName, value => context.State.OwnerName = value, accepted: () => ownerPhoneField?.SetFocus());
            ownerPhoneField = context.Form.AddTextField("Owner phone:", 10, context.State.OwnerPhone, value => context.State.OwnerPhone = value, accepted: () => ownerEmailField?.SetFocus());
            ownerEmailField = context.Form.AddTextField("Owner email:", 12, context.State.OwnerEmail, value => context.State.OwnerEmail = value, accepted: () => ownerAddressField?.SetFocus());
            ownerAddressField = context.Form.AddTextField("Owner return address:", 14, context.State.OwnerReturnAddress, value => context.State.OwnerReturnAddress = value, accepted: () => logoList?.SetFocus());
            ownerNameField.HasFocusChanged += (_, _) => UpdateReturnMessageFocus(context, ownerNameField, TerminalInstallerState.ReturnMessageFocusOwnerName);
            ownerPhoneField.HasFocusChanged += (_, _) => UpdateReturnMessageFocus(context, ownerPhoneField, TerminalInstallerState.ReturnMessageFocusOwnerPhone);
            ownerEmailField.HasFocusChanged += (_, _) => UpdateReturnMessageFocus(context, ownerEmailField, TerminalInstallerState.ReturnMessageFocusOwnerEmail);
            ownerAddressField.HasFocusChanged += (_, _) => UpdateReturnMessageFocus(context, ownerAddressField, TerminalInstallerState.ReturnMessageFocusOwnerAddress);
            context.Form.AddLabel("Return-message languages:", 16);
            context.Form.AddLanguageChecks(17);
            var logoChoices = new ObservableCollection<string>(new[] { "yes", "no" });
            logoList = context.Form.AddSelector("Include company logo?", logoChoices, 20, 4, context.State.LogoIndex, delegate(int selected)
            {
                context.State.LogoIndex = selected;
                context.State.Config.IncludeLogo = logoChoices[selected];
                if (context.State.Config.IncludeLogo == "no")
                {
                    context.State.ReturnMessageFocus = TerminalInstallerState.ReturnMessageFocusLogo;
                    context.State.LogoUrl = string.Empty;
                    context.State.Config.LogoUrl = string.Empty;
                }
                else
                {
                    context.State.ReturnMessageFocus = TerminalInstallerState.ReturnMessageFocusLogoUrl;
                }
                context.Navigator.ShowReturnMessage();
            }, delegate
            {
                if (logoList is null)
                {
                    return;
                }
                context.Form.SelectCurrent(logoList, delegate(int selected)
                {
                    context.State.LogoIndex = selected;
                    context.State.Config.IncludeLogo = logoChoices[selected];
                });
                if (context.State.Config.IncludeLogo == "yes")
                {
                    context.State.ReturnMessageFocus = TerminalInstallerState.ReturnMessageFocusLogoUrl;
                    context.Navigator.ShowReturnMessage();
                }
                else
                {
                    context.State.ReturnMessageFocus = TerminalInstallerState.ReturnMessageFocusLogo;
                    context.State.LogoUrl = string.Empty;
                    context.State.Config.LogoUrl = string.Empty;
                    context.State.CommitReturnMessageState();
                    context.Navigator.ShowSummary();
                }
            });
            logoList.HasFocusChanged += (_, _) =>
            {
                if (logoList.HasFocus)
                {
                    context.State.ReturnMessageFocus = TerminalInstallerState.ReturnMessageFocusLogo;
                }
            };
            if (context.State.Config.IncludeLogo == "yes")
            {
                logoUrlField = context.Form.AddTextField("Logo URL:", 26, context.State.LogoUrl, value => context.State.LogoUrl = value);
                logoUrlField.HasFocusChanged += (_, _) => UpdateReturnMessageFocus(context, logoUrlField, TerminalInstallerState.ReturnMessageFocusLogoUrl);
            }
            FocusReturnMessagePart(context, includeList, ownerNameField, ownerPhoneField, ownerEmailField, ownerAddressField, logoList, logoUrlField);
        }
        else
        {
            includeList.SetFocus();
        }
        context.SetNavigation(delegate
        {
            if (context.State.Config.IncludeReturnMessage == "yes" && context.State.ReturnMessageFocus > TerminalInstallerState.ReturnMessageFocusInclude)
            {
                context.State.ReturnMessageFocus--;
                FocusReturnMessagePart(context, includeList, ownerNameField, ownerPhoneField, ownerEmailField, ownerAddressField, logoList, logoUrlField);
            }
            else
            {
                context.Navigator.ShowDotfiles();
            }
        }, delegate
        {
            if (context.State.ReturnMessageIndex is null)
            {
                context.ShowError("Select whether to include a return message.");
                return;
            }
            context.State.CommitReturnMessageState();
            try
            {
                InstallerInput.ValidateConfig(context.Live, context.AssetDirectory, context.State.Config);
                if (context.State.Config.IncludeLogo == "yes" && !InstallerInput.DownloadLogo(context.Live, context.State.Config.LogoUrl, context.LogoLocalPath))
                {
                    context.ShowError("Logo download failed.");
                    return;
                }
                context.Navigator.ShowSummary();
            }
            catch (Exception error)
            {
                context.ShowError(error.Message);
            }
        }, nextEnabled: context.State.ReturnMessageIndex is not null);
    }

    private static void UpdateReturnMessageFocus(TerminalInstallerContext context, View view, int focus)
    {
        if (view.HasFocus)
        {
            context.State.ReturnMessageFocus = focus;
        }
    }

    private static void FocusReturnMessagePart(TerminalInstallerContext context, ListView includeList, TextField? ownerNameField, TextField? ownerPhoneField, TextField? ownerEmailField, TextField? ownerAddressField, ListView? logoList, TextField? logoUrlField)
    {
        switch (context.State.ReturnMessageFocus)
        {
            case TerminalInstallerState.ReturnMessageFocusOwnerName:
                ownerNameField?.SetFocus();
                break;
            case TerminalInstallerState.ReturnMessageFocusOwnerPhone:
                ownerPhoneField?.SetFocus();
                break;
            case TerminalInstallerState.ReturnMessageFocusOwnerEmail:
                ownerEmailField?.SetFocus();
                break;
            case TerminalInstallerState.ReturnMessageFocusOwnerAddress:
                ownerAddressField?.SetFocus();
                break;
            case TerminalInstallerState.ReturnMessageFocusLogo:
                logoList?.SetFocus();
                break;
            case TerminalInstallerState.ReturnMessageFocusLogoUrl:
                logoUrlField?.SetFocus();
                break;
            default:
                includeList.SetFocus();
                break;
        }
    }
}
