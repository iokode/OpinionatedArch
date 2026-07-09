using System.Collections.Generic;

namespace IOKode.OpinionatedArch.Installer.TerminalUi;

internal static class TerminalUiHelpers
{
    public static int? IndexOf(IReadOnlyList<string> values, string value)
    {
        for (var index = 0; index < values.Count; index++)
        {
            if (values[index] == value)
            {
                return index;
            }
        }
        return null;
    }

    public static List<string> Lines(string value)
    {
        var lines = new List<string>();
        foreach (var line in value.Split('\n'))
        {
            var clean = line.TrimEnd('\r');
            if (clean.Length > 0)
            {
                lines.Add(clean);
            }
        }
        return lines;
    }
}
