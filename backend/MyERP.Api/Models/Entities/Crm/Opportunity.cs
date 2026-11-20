using MyERP.Api.Common;

namespace MyERP.Api.Models.Entities.Crm;

public static class OpportunityStatuses
{
    public const string Open = "open";
    public const string Won = "won";
    public const string Lost = "lost";
}

public sealed record OpportunityInfo(
    string Name,
    long? ContactId,
    decimal ExpectedRevenue,
    decimal? Probability,
    DateOnly? ExpectedCloseDate,
    byte Priority,
    long? OwnerUserId,
    string? Description);

/// <summary>
/// Bảng crm.Opportunities - cơ hội bán hàng, đi qua các giai đoạn của pipeline.
/// Quy tắc: chuyển sang giai đoạn "Thành công"/"Thất bại" là đóng cơ hội;
/// đánh dấu thất bại bắt buộc có lý do; kéo về giai đoạn mở là mở lại.
/// </summary>
public sealed class Opportunity : AuditableEntity, ICompanyOwned
{
    private Opportunity() { }

    public long CompanyId { get; private set; }
    public string Code { get; private set; } = "";
    public string Name { get; private set; } = "";
    public long PartnerId { get; private set; }
    public long? ContactId { get; private set; }
    public long? LeadId { get; private set; }
    public long PipelineId { get; private set; }
    public long StageId { get; private set; }
    public decimal ExpectedRevenue { get; private set; }
    public decimal Probability { get; private set; }
    public DateOnly? ExpectedCloseDate { get; private set; }
    public byte Priority { get; private set; }
    public long? OwnerUserId { get; private set; }
    public string Status { get; private set; } = OpportunityStatuses.Open;
    public long? LostReasonId { get; private set; }
    public string? LostNote { get; private set; }
    public DateTime? ClosedAt { get; private set; }
    public DateTime? StageChangedAt { get; private set; }
    public string? Description { get; private set; }

    public Stage? Stage { get; private set; }

    /// <summary>Doanh thu kỳ vọng = giá trị × xác suất.</summary>
    public decimal WeightedRevenue => Math.Round(ExpectedRevenue * Probability / 100, 0);

    public static Result<Opportunity> Create(long companyId, string code, long partnerId, long? leadId, Stage stage, OpportunityInfo info, DateTime now)
    {
        if (stage.StageType != OpportunityStatuses.Open)
            return Error.Validation("opportunity.stage_closed", "Cơ hội mới phải bắt đầu ở giai đoạn đang mở.");

        var o = new Opportunity
        {
            CompanyId = companyId,
            Code = code,
            PartnerId = partnerId,
            LeadId = leadId,
            PipelineId = stage.PipelineId,
            StageId = stage.Id,
            Probability = stage.Probability,
            StageChangedAt = now
        };
        o.Update(info);
        return o;
    }

    public void Update(OpportunityInfo d)
    {
        Name = d.Name.Trim();
        ContactId = d.ContactId;
        ExpectedRevenue = d.ExpectedRevenue;
        if (d.Probability is { } p) Probability = p;
        ExpectedCloseDate = d.ExpectedCloseDate;
        Priority = Math.Min(d.Priority, (byte)3);
        OwnerUserId = d.OwnerUserId;
        Description = string.IsNullOrWhiteSpace(d.Description) ? null : d.Description.Trim();
    }

    /// <summary>Chuyển giai đoạn (kéo thả trên Kanban). Trả về lịch sử chuyển để lưu lại.</summary>
    public Result<OpportunityStageHistory?> MoveTo(Stage target, long? lostReasonId, string? lostNote, long? userId, DateTime now)
    {
        if (target.PipelineId != PipelineId)
            return Error.Validation("opportunity.stage_invalid", "Giai đoạn không thuộc quy trình bán hàng của cơ hội.");
        if (target.Id == StageId)
            return (OpportunityStageHistory?)null;
        if (target.StageType == OpportunityStatuses.Lost && lostReasonId is null)
            return Error.Validation("opportunity.lost_reason_required", "Chọn lý do thất bại.");

        var history = OpportunityStageHistory.Create(Id, StageId, target.Id, userId, now);
        StageId = target.Id;
        Probability = target.Probability;
        StageChangedAt = now;
        Status = target.StageType;
        ClosedAt = target.StageType == OpportunityStatuses.Open ? null : now;
        LostReasonId = target.StageType == OpportunityStatuses.Lost ? lostReasonId : null;
        LostNote = target.StageType == OpportunityStatuses.Lost && !string.IsNullOrWhiteSpace(lostNote) ? lostNote.Trim() : null;
        return history;
    }

    /// <summary>Chỉ dùng cho unit test.</summary>
    internal static Stage TestStage(long id, string type, decimal probability, long pipelineId = 1) => Stage.CreateForTest(id, type, probability, pipelineId);
}

/// <summary>Bảng crm.Pipelines - quy trình bán hàng.</summary>
public sealed class Pipeline : ICompanyOwned
{
    public long Id { get; private set; }
    public long CompanyId { get; private set; }
    public string Name { get; private set; } = "";
    public bool IsDefault { get; private set; }
    public bool IsActive { get; private set; }
    public List<Stage> Stages { get; private set; } = [];
}

/// <summary>Bảng crm.Stages - giai đoạn (cột trên Kanban). StageType: open | won | lost.</summary>
public sealed class Stage
{
    public long Id { get; private set; }
    public long PipelineId { get; private set; }
    public string Name { get; private set; } = "";
    public int SortOrder { get; private set; }
    public decimal Probability { get; private set; }
    public string StageType { get; private set; } = OpportunityStatuses.Open;
    public string? Color { get; private set; }

    internal static Stage CreateForTest(long id, string type, decimal probability, long pipelineId)
        => new() { Id = id, StageType = type, Probability = probability, PipelineId = pipelineId, Name = type };
}

/// <summary>Bảng crm.LostReasons - lý do thất bại.</summary>
public sealed class LostReason : ICompanyOwned
{
    public long Id { get; private set; }
    public long CompanyId { get; private set; }
    public string Name { get; private set; } = "";
    public bool IsActive { get; private set; }
}

/// <summary>Bảng crm.OpportunityStageHistory - để đo thời gian ở mỗi giai đoạn, tỷ lệ chuyển đổi.</summary>
public sealed class OpportunityStageHistory
{
    private OpportunityStageHistory() { }

    public long Id { get; private set; }
    public long OpportunityId { get; private set; }
    public long? FromStageId { get; private set; }
    public long ToStageId { get; private set; }
    public DateTime ChangedAt { get; private set; }
    public long? ChangedBy { get; private set; }

    internal static OpportunityStageHistory Create(long opportunityId, long? fromStageId, long toStageId, long? userId, DateTime now)
        => new() { OpportunityId = opportunityId, FromStageId = fromStageId, ToStageId = toStageId, ChangedBy = userId, ChangedAt = now };
}
