using System.Globalization;
using System.Text;

namespace MyERP.Api.Common;

/// <summary>Tìm kiếm không dấu trong bộ nhớ (dữ liệu đã tải về): "Nguyễn Văn Ân" -> "nguyen van an".</summary>
public static class TextSearch
{
    public static string Fold(string? text)
    {
        if (string.IsNullOrWhiteSpace(text)) return "";
        var normalized = text.Trim().ToLowerInvariant().Replace('đ', 'd').Normalize(NormalizationForm.FormD);
        var sb = new StringBuilder(normalized.Length);
        foreach (var c in normalized)
            if (CharUnicodeInfo.GetUnicodeCategory(c) != UnicodeCategory.NonSpacingMark) sb.Append(c);
        return sb.ToString().Normalize(NormalizationForm.FormC);
    }
}
