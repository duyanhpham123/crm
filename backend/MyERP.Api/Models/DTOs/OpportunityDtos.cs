namespace MyERP.Api.Models.DTOs;

/// <summary>Thẻ cơ hội trên Kanban / trong trang khách hàng.</summary>
public sealed record OpportunityCard(
    long Id,
    string Code,
    string Name,
    long CustomerId,
    string CustomerName,
    long StageId,
    string Status,
    decimal ExpectedRevenue,
    decimal Probability,
    DateOnly? ExpectedCloseDate,
    byte Priority,
    long? OwnerUserId,
    string? OwnerName,
    bool IsOverdue);

public sealed record BoardColumn(StageDto Stage, int Count, decimal TotalValue, decimal WeightedValue, IReadOnlyList<OpportunityCard> Items);

/// <summary>GET /api/crm/opportunities/board - dữ liệu cho Kanban.</summary>
public sealed record OpportunityBoard(long PipelineId, string PipelineName, IReadOnlyList<BoardColumn> Columns);

public sealed record OpportunityDetail(
    long Id,
    string Code,
    string Name,
    long CustomerId,
    string CustomerName,
    long? ContactId,
    long? LeadId,
    long PipelineId,
    long StageId,
    string Status,
    decimal ExpectedRevenue,
    decimal Probability,
    DateOnly? ExpectedCloseDate,
    byte Priority,
    long? OwnerUserId,
    long? LostReasonId,
    string? LostNote,
    DateTime? ClosedAt,
    string? Description,
    DateTime CreatedAt,
    string RowVersion);

public sealed record SaveOpportunityRequest(
    string Name,
    long CustomerId,           // chỉ dùng khi tạo mới
    long? ContactId,
    long? StageId,             // chỉ dùng khi tạo mới; null = giai đoạn đầu tiên
    decimal ExpectedRevenue,
    decimal? Probability,
    DateOnly? ExpectedCloseDate,
    byte Priority,
    long? OwnerUserId,
    string? Description,
    string? RowVersion = null);

/// <summary>POST /api/crm/opportunities/{id}/stage - kéo thả sang cột khác.</summary>
public sealed record MoveStageRequest(long StageId, long? LostReasonId, string? LostNote);
