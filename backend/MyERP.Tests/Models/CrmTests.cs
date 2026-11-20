using MyERP.Api.Models;
using MyERP.Api.Models.DTOs;
using MyERP.Api.Models.Entities.Crm;
using MyERP.Api.Models.Entities.MasterData;
using MyERP.Api.Validators;

namespace MyERP.Tests.Models;

public class CustomerTests
{
    private static PartnerInfo Info(string type = "company", string? phone = "+84 912 345 678", string? tax = " 0101234567 ") =>
        new(type, "  Công ty Hưng Thịnh ", null, tax, phone, " Info@HungThinh.VN ", null, null, null, null, 7, null, null);

    [Fact]
    public void Create_customer_normalizes_fields()
    {
        var p = Partner.CreateCustomer(1, "KH-000001", Info());

        Assert.True(p.IsCustomer);
        Assert.Equal("Công ty Hưng Thịnh", p.Name);
        Assert.Equal("0912345678", p.Phone);
        Assert.Equal("0101234567", p.TaxCode);
        Assert.Equal("info@hungthinh.vn", p.Email);
        Assert.Equal(7, p.OwnerUserId);
    }

    [Fact]
    public void Unknown_type_falls_back_to_company()
        => Assert.Equal(Partner.Company, Partner.CreateCustomer(1, "KH", Info(type: "alien")).PartnerType);

    [Fact]
    public void First_contact_becomes_primary_and_only_one_primary()
    {
        var p = Partner.CreateCustomer(1, "KH", Info());
        var a = p.AddContact(new ContactInfo("Anh A", null, null, null, null, false, null));
        Assert.True(a.IsPrimary);

        var b = p.AddContact(new ContactInfo("Chị B", null, null, null, null, true, null));

        Assert.True(b.IsPrimary);
        Assert.False(a.IsPrimary);
        Assert.Single(p.Contacts, c => c.IsPrimary);
    }

    [Theory]
    [InlineData("0101234567", true)]
    [InlineData("0101234567-001", true)]
    [InlineData("0101234567001", true)]
    [InlineData("12345", false)]
    [InlineData("MST0101234", false)]
    public void Tax_code_format(string tax, bool valid)
    {
        var result = new SaveCustomerRequestValidator().Validate(
            new SaveCustomerRequest("company", "Tên", null, tax, null, null, null, null, null, null, null, null));
        Assert.Equal(valid, result.IsValid);
    }
}

public class OpportunityTests
{
    private static readonly DateTime Now = new(2026, 11, 20, 8, 0, 0, DateTimeKind.Utc);
    private static readonly Stage New = Opportunity.TestStage(1, "open", 10);
    private static readonly Stage Negotiation = Opportunity.TestStage(5, "open", 80);
    private static readonly Stage Won = Opportunity.TestStage(6, "won", 100);
    private static readonly Stage Lost = Opportunity.TestStage(7, "lost", 0);

    private static Opportunity Create() => Opportunity.Create(1, "CH2611-00001", 10, null, New,
        new OpportunityInfo(" Triển khai ERP ", null, 500_000_000, null, null, 9, 3, null), Now).Value;

    [Fact]
    public void Create_takes_probability_from_stage_and_caps_priority()
    {
        var o = Create();

        Assert.Equal("Triển khai ERP", o.Name);
        Assert.Equal(10, o.Probability);
        Assert.Equal(3, o.Priority);
        Assert.Equal(OpportunityStatuses.Open, o.Status);
        Assert.Equal(50_000_000, o.WeightedRevenue);
    }

    [Fact]
    public void Cannot_create_in_closed_stage()
    {
        var result = Opportunity.Create(1, "CH", 10, null, Won, new OpportunityInfo("X", null, 0, null, null, 0, null, null), Now);
        Assert.True(result.IsFailure);
    }

    [Fact]
    public void Moving_to_won_closes_and_back_to_open_reopens()
    {
        var o = Create();

        var history = o.MoveTo(Won, null, null, 3, Now).Value;
        Assert.Equal(OpportunityStatuses.Won, o.Status);
        Assert.Equal(100, o.Probability);
        Assert.Equal(Now, o.ClosedAt);
        Assert.Equal(1, history!.FromStageId);
        Assert.Equal(6, history.ToStageId);

        o.MoveTo(Negotiation, null, null, 3, Now);
        Assert.Equal(OpportunityStatuses.Open, o.Status);
        Assert.Null(o.ClosedAt);
        Assert.Equal(80, o.Probability);
    }

    [Fact]
    public void Lost_requires_reason_and_clears_when_reopened()
    {
        var o = Create();

        Assert.Equal("opportunity.lost_reason_required", o.MoveTo(Lost, null, null, 3, Now).Error!.Code);
        Assert.Equal(OpportunityStatuses.Open, o.Status);

        o.MoveTo(Lost, 2, "Đối thủ rẻ hơn 15%", 3, Now);
        Assert.Equal(OpportunityStatuses.Lost, o.Status);
        Assert.Equal(2, o.LostReasonId);

        o.MoveTo(New, null, null, 3, Now);
        Assert.Null(o.LostReasonId);
        Assert.Null(o.LostNote);
    }

    [Fact]
    public void Same_stage_is_noop_and_other_pipeline_rejected()
    {
        var o = Create();
        Assert.Null(o.MoveTo(New, null, null, 3, Now).Value);
        Assert.True(o.MoveTo(Opportunity.TestStage(99, "open", 50, pipelineId: 2), null, null, 3, Now).IsFailure);
    }
}

public class LeadConversionTests
{
    private static Lead NewLead() => Lead.Create(1, "LD", 3, new LeadInfo("An", "Cty A", null, "0912345678", null, null, null, null, null));

    [Fact]
    public void Converted_lead_is_locked()
    {
        var lead = NewLead();
        Assert.True(lead.CanConvert().IsSuccess);

        lead.MarkConverted(10, 20, DateTime.UtcNow);

        Assert.Equal(LeadStatuses.Converted, lead.Status);
        Assert.Equal(10, lead.ConvertedPartnerId);
        Assert.Equal(20, lead.ConvertedOpportunityId);
        Assert.True(lead.CanConvert().IsFailure);
        Assert.True(lead.Update(new LeadInfo("B", null, null, "0912345678", null, null, null, null, null)).IsFailure);
    }

    [Fact]
    public void Unqualified_lead_cannot_be_converted()
    {
        var lead = NewLead();
        lead.ChangeStatus(LeadStatuses.Unqualified, "Không có ngân sách");
        Assert.Equal("lead.unqualified", lead.CanConvert().Error!.Code);
    }
}
