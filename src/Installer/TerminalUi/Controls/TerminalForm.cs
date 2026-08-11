using System;
using System.Collections.ObjectModel;
using Terminal.Gui.ViewBase;
using Terminal.Gui.Views;

#pragma warning disable CS0618

namespace IOKode.OpinionatedArch.Installer.TerminalUi.Controls;

internal sealed class TerminalForm
{
    private readonly TerminalInstallerContext _context;

    public TerminalForm(TerminalInstallerContext context)
    {
        _context = context;
    }

    public void AddInstruction(string text)
    {
        AddLabel(text, 0);
    }

    public void AddLabel(string text, int y)
    {
        _context.Shell.ContentPanel.Add(new Label
        {
            Text = text,
            X = 1,
            Y = y,
            Width = Dim.Fill(),
            Height = 1
        });
    }

    public TextField AddTextField(string label, int y, string value, Action<string> changed, bool secret = false, Action? accepted = null)
    {
        AddLabel(label, y);
        var field = new TextField
        {
            X = 30,
            Y = y,
            Width = Dim.Fill(),
            Height = 1,
            Value = value,
            Secret = secret
        };
        field.ValueChanged += (_, _) => changed(FieldValue(field));
        field.Accepted += (_, _) => (accepted ?? _context.RunNext)();
        _context.Shell.ContentPanel.Add(field);
        return field;
    }

    public ListView AddSelector(string title, ObservableCollection<string> source, int y, int height, int? selectedIndex, Action<int> selected, Action accepted)
    {
        var frame = new FrameView
        {
            Title = $"  {title}",
            X = 1,
            Y = y,
            Width = Dim.Fill(),
            Height = height
        };
        var list = new ListView
        {
            X = 0,
            Y = 0,
            Width = Dim.Fill(),
            Height = Dim.Fill()
        };
        list.SetSource(source);
        if (source.Count > 0)
        {
            list.SelectedItem = selectedIndex is not null && selectedIndex.Value >= 0 && selectedIndex.Value < source.Count
                ? selectedIndex.Value
                : 0;
        }
        list.ValueChanged += (_, _) =>
        {
            var current = list.SelectedItem;
            if (current is not null && current.Value >= 0 && current.Value < source.Count)
            {
                selected(current.Value);
            }
        };
        list.Accepted += (_, _) => accepted();
        list.HasFocusChanged += (_, _) => frame.Title = list.HasFocus ? $"> {title}" : $"  {title}";
        frame.Add(list);
        _context.Shell.ContentPanel.Add(frame);
        return list;
    }

    public void AddLanguageChecks(int y)
    {
        var languages = InstallerInput.ListReturnMessageLanguages(_context.AssetDirectory);
        for (var index = 0; index < languages.Count; index++)
        {
            var language = languages[index];
            var checkBox = new CheckBox
            {
                Text = language,
                X = 1 + index * 8,
                Y = y,
                Width = 7,
                Height = 1,
                Value = _context.State.Config.ReturnMessageLanguages.Contains(language) ? CheckState.Checked : CheckState.UnChecked
            };
            checkBox.ValueChanged += (_, _) =>
            {
                if (checkBox.Value == CheckState.Checked && !_context.State.Config.ReturnMessageLanguages.Contains(language))
                {
                    _context.State.Config.ReturnMessageLanguages.Add(language);
                }
                else if (checkBox.Value != CheckState.Checked)
                {
                    _context.State.Config.ReturnMessageLanguages.Remove(language);
                }
            };
            _context.Shell.ContentPanel.Add(checkBox);
        }
    }

    public bool SelectCurrent(ListView list, Action<int> select)
    {
        var source = list.Source;
        if (source is null || source.Count == 0)
        {
            return false;
        }
        var current = list.SelectedItem ?? 0;
        if (current < 0 || current >= source.Count)
        {
            return false;
        }
        select(current);
        return true;
    }

    private static string FieldValue(TextField field)
    {
        return field.Value ?? string.Empty;
    }
}
