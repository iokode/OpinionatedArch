using System;
using System.Collections.Generic;
using System.IO;
using System.Text;

namespace IOKode.OpinionatedArch.Installer;

internal static class TextFiles
{
    public static string Trim(string value)
    {
        return value.Trim();
    }

    public static void ReplaceInFile(string path, string from, string to)
    {
        File.WriteAllText(path, File.ReadAllText(path).Replace(from, to));
    }

    public static void ReplaceLinePrefix(string path, string prefix, string replacement)
    {
        var lines = new List<string>();
        foreach (var line in File.ReadAllLines(path))
        {
            if (line.StartsWith(prefix, StringComparison.Ordinal))
            {
                lines.Add(replacement);
            }
            else
            {
                lines.Add(line);
            }
        }
        File.WriteAllText(path, string.Join('\n', lines) + "\n");
    }

    public static void AppendToFile(string path, string content)
    {
        File.AppendAllText(path, content);
    }

    public static string ShellSingleQuote(string value)
    {
        return $"'{value.Replace("'", "'\\''")}'";
    }

    public static string ParseShellValue(string value)
    {
        var parsed = new StringBuilder();
        var inSingleQuote = false;
        for (var index = 0; index < value.Length;)
        {
            var character = value[index];
            if (inSingleQuote)
            {
                if (character == '\'')
                {
                    inSingleQuote = false;
                }
                else
                {
                    parsed.Append(character);
                }
                index++;
                continue;
            }

            if (character == '\'')
            {
                inSingleQuote = true;
                index++;
            }
            else if (character == '\\')
            {
                if (index + 1 >= value.Length)
                {
                    throw new FormatException("trailing escape in install state value");
                }
                parsed.Append(value[index + 1]);
                index += 2;
            }
            else
            {
                parsed.Append(character);
                index++;
            }
        }
        if (inSingleQuote)
        {
            throw new FormatException("unterminated quote in install state value");
        }
        return parsed.ToString();
    }
}
