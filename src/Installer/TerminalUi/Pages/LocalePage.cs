using System.Collections.ObjectModel;
using IOKode.OpinionatedArch.CommandLine;
using Terminal.Gui.Views;

#pragma warning disable CS0618

namespace IOKode.OpinionatedArch.Installer.TerminalUi.Pages;

internal sealed class LocalePage : IInstallerPage
{
    public void Render(TerminalInstallerContext context)
    {
        context.State.StepIndex = 6;
        context.SetContent("Locale");
        context.Form.AddInstruction("The focused selector is marked with '>'. Type a timezone city/region name inside the timezone selector.");
        var keymaps = new ObservableCollection<string>(TerminalUiHelpers.Lines(ShellCommand.Capture(context.Live, "localectl", "list-keymaps")));
        var keymapIndex = TerminalUiHelpers.IndexOf(keymaps, context.State.ConsoleKeymap);
        ListView keymapList = null!;
        ListView timezoneList = null!;
        var timezoneSource = new ObservableCollection<string>(context.State.ListTimezones());
        keymapList = context.Form.AddSelector("Console keymap", keymaps, 2, 7, keymapIndex, delegate(int selected)
        {
            context.State.ConsoleKeymap = keymaps[selected];
            context.State.Config.ConsoleKeymap = context.State.ConsoleKeymap;
            context.SetNextEnabled(context.State.LocaleSelected());
        }, delegate
        {
            context.Form.SelectCurrent(keymapList, delegate(int selected)
            {
                context.State.ConsoleKeymap = keymaps[selected];
                context.State.Config.ConsoleKeymap = context.State.ConsoleKeymap;
            });
            timezoneList.SetFocus();
            context.SetNextEnabled(context.State.LocaleSelected());
        });
        var timezoneIndex = TerminalUiHelpers.IndexOf(timezoneSource, context.State.Timezone);
        timezoneList = context.Form.AddSelector("Timezone", timezoneSource, 11, 10, timezoneIndex, delegate(int selected)
        {
            context.State.Timezone = timezoneSource[selected];
            context.State.Config.Timezone = context.State.Timezone;
            context.SetNextEnabled(context.State.LocaleSelected());
        }, delegate
        {
            if (!context.Form.SelectCurrent(timezoneList, delegate(int selected)
            {
                context.State.Timezone = timezoneSource[selected];
                context.State.Config.Timezone = context.State.Timezone;
            }))
            {
                context.ShowError("No timezone matches the current search.");
                return;
            }
            context.SetNextEnabled(context.State.LocaleSelected());
            if (context.State.LocaleSelected())
            {
                context.Navigator.ShowIdentity();
            }
        });
        context.SetNavigation(context.Navigator.ShowUsers, delegate
        {
            if (!context.State.LocaleSelected())
            {
                context.ShowError("Select both locale options.");
                return;
            }
            context.Navigator.ShowIdentity();
        }, nextEnabled: context.State.LocaleSelected());
        if (timezoneList.KeystrokeNavigator is not null)
        {
            timezoneList.KeystrokeNavigator.Matcher = new TimezoneSuffixNavigatorMatcher();
        }
        keymapList.SetFocus();
    }
}
