using System;
using System.Text;
using Terminal.Gui.Input;
using Terminal.Gui.Views;

namespace IOKode.OpinionatedArch.Installer;

internal sealed class TimezoneSuffixNavigatorMatcher : ICollectionNavigatorMatcher
{
    public bool IsCompatibleKey(Key key)
    {
        return !key.IsAlt && !key.IsCtrl && key.AsRune != Rune.ReplacementChar;
    }

    public bool IsMatch(string search, object value)
    {
        var timezone = value.ToString() ?? string.Empty;
        var slash = timezone.LastIndexOf('/');
        var suffix = slash < 0 ? timezone : timezone[(slash + 1)..];
        return suffix.Contains(search, StringComparison.OrdinalIgnoreCase);
    }
}
