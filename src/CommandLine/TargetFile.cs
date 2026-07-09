using System;
using System.Collections.Generic;
using System.IO;
using System.Runtime.Versioning;

namespace IOKode.OpinionatedArch.CommandLine;

public static class TargetFile
{
    public static string Path(Target target, string absolutePath)
    {
        if (!System.IO.Path.IsPathRooted(absolutePath))
        {
            throw new ArgumentException("Path must be absolute.", nameof(absolutePath));
        }
        if (target.RootPath == "/")
        {
            return absolutePath;
        }
        return System.IO.Path.Combine(target.RootPath, absolutePath.TrimStart('/'));
    }

    public static void WriteAllText(Target target, string path, string content)
    {
        File.WriteAllText(Path(target, path), content);
    }

    public static string ReadAllText(Target target, string path)
    {
        return File.ReadAllText(Path(target, path));
    }

    public static string[] ReadAllLines(Target target, string path)
    {
        return File.ReadAllLines(Path(target, path));
    }

    public static IEnumerable<string> ReadLines(Target target, string path)
    {
        return File.ReadLines(Path(target, path));
    }

    public static void AppendToFile(Target target, string path, string content)
    {
        File.AppendAllText(Path(target, path), content);
    }

    public static void ReplaceInFile(Target target, string path, string from, string to)
    {
        File.WriteAllText(Path(target, path), File.ReadAllText(Path(target, path)).Replace(from, to));
    }

    public static void ReplaceLinePrefix(Target target, string path, string prefix, string replacement)
    {
        var lines = new List<string>();
        foreach (var line in File.ReadAllLines(Path(target, path)))
        {
            lines.Add(line.StartsWith(prefix, StringComparison.Ordinal) ? replacement : line);
        }
        File.WriteAllText(Path(target, path), string.Join('\n', lines) + "\n");
    }

    public static bool Exists(Target target, string path)
    {
        return File.Exists(Path(target, path));
    }

    public static void CreateDirectory(Target target, string path)
    {
        Directory.CreateDirectory(Path(target, path));
    }

    public static void CreateSymbolicLink(Target target, string path, string targetPath)
    {
        File.CreateSymbolicLink(Path(target, path), targetPath);
    }

    [SupportedOSPlatform("linux")]
    public static void SetUnixFileMode(Target target, string path, UnixFileMode mode)
    {
        File.SetUnixFileMode(Path(target, path), mode);
    }
}
