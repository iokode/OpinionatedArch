namespace IOKode.OpinionatedArch.CommandLine;

public sealed class Target
{
    private Target()
    {
    }

    public required string RootPath { get; init; }

    public required bool UsesChroot { get; init; }

    public static Target Local()
    {
        return new Target
        {
            RootPath = "/",
            UsesChroot = false
        };
    }

    public static Target Chroot(string rootPath)
    {
        return new Target
        {
            RootPath = rootPath,
            UsesChroot = true
        };
    }
}
