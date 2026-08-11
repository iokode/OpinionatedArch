namespace IOKode.OpinionatedArch.CommandLine;

public sealed class InputValidationResult
{
    private InputValidationResult()
    {
    }

    public required bool Successful { get; init; }

    public required string ErrorMessage { get; init; }

    public static InputValidationResult Success()
    {
        return new InputValidationResult
        {
            Successful = true,
            ErrorMessage = string.Empty
        };
    }

    public static InputValidationResult Error(string message)
    {
        return new InputValidationResult
        {
            Successful = false,
            ErrorMessage = message
        };
    }
}
