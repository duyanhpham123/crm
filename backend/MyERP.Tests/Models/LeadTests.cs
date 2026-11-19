using MyERP.Api.Common;
using MyERP.Api.Models;
using MyERP.Api.Models.Entities.Crm;

namespace MyERP.Tests.Models;

public class LeadTests
{
    private static Lead NewLead(string? phone = "0912 345 678") =>
        Lead.Create(1, "LD2611-00001", 10, new LeadInfo("  Nguyễn Văn An ", " ", null, phone, "An@Example.VN", null, null, null, 5_000_000));

    [Fact]
    public void Create_normalizes_input()
    {
        var lead = NewLead();

        Assert.Equal("Nguyễn Văn An", lead.FullName);
        Assert.Null(lead.OrganizationName);
        Assert.Equal("0912345678", lead.Phone);
        Assert.Equal("an@example.vn", lead.Email);
        Assert.Equal(LeadStatuses.New, lead.Status);
        Assert.Equal(10, lead.OwnerUserId);
    }

    [Fact]
    public void Unqualified_requires_reason()
    {
        var lead = NewLead();

        var result = lead.ChangeStatus(LeadStatuses.Unqualified, "  ");

        Assert.True(result.IsFailure);
        Assert.Equal("lead.reason_required", result.Error!.Code);
        Assert.Equal(LeadStatuses.New, lead.Status);
    }

    [Fact]
    public void Leaving_unqualified_clears_reason()
    {
        var lead = NewLead();
        lead.ChangeStatus(LeadStatuses.Unqualified, "Không có ngân sách");

        lead.ChangeStatus(LeadStatuses.Contacted, null);

        Assert.Equal(LeadStatuses.Contacted, lead.Status);
        Assert.Null(lead.DisqualifyReason);
    }

    [Theory]
    [InlineData(LeadStatuses.Converted, "lead.convert_via_flow")]
    [InlineData("won", "lead.status_invalid")]
    public void Rejects_invalid_target_status(string status, string expectedCode)
    {
        var result = NewLead().ChangeStatus(status, null);

        Assert.True(result.IsFailure);
        Assert.Equal(expectedCode, result.Error!.Code);
    }

    [Theory]
    [InlineData("0912345678", "0912345678")]
    [InlineData("+84 912.345.678", "0912345678")]
    [InlineData("84912345678", "0912345678")]
    [InlineData("(024) 3826-1234", "02438261234")]
    [InlineData("   ", null)]
    public void Phone_normalization(string raw, string? expected)
        => Assert.Equal(expected, PhoneNumber.Normalize(raw));

    [Theory]
    [InlineData("0912345678", true)]
    [InlineData("+84 389 999 000", true)]
    [InlineData("02438261234", true)]
    [InlineData("0112345678", false)]
    [InlineData("12345", false)]
    public void Phone_validation(string raw, bool valid)
        => Assert.Equal(valid, PhoneNumber.IsValid(raw));
}
