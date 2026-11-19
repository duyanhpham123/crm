using System.Text.RegularExpressions;

namespace MyERP.Api.Common;

/// <summary>Chuẩn hóa số điện thoại Việt Nam để so trùng: "+84 912.345.678" thành "0912345678".</summary>
public static partial class PhoneNumber
{
    public static string? Normalize(string? raw)
    {
        if (string.IsNullOrWhiteSpace(raw)) return null;
        var digits = NonDigits().Replace(raw, "");
        if (raw.TrimStart().StartsWith('+') && digits.StartsWith("84")) digits = "0" + digits[2..];
        else if (digits.StartsWith("84") && digits.Length == 11) digits = "0" + digits[2..];
        return digits;
    }

    public static bool IsValid(string? raw) => Normalize(raw) is { } d && ValidVn().IsMatch(d);

    [GeneratedRegex("[^0-9]")]
    private static partial Regex NonDigits();

    // Di động 10 số (03, 05, 07, 08, 09) hoặc cố định 11 số (02x)
    [GeneratedRegex("^(0[35789][0-9]{8}|02[0-9]{9})$")]
    private static partial Regex ValidVn();
}
