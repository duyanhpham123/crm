using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Diagnostics;
using MyERP.Api.Models.Entities;
using MyERP.Api.Services.Common;

namespace MyERP.Api.Data;

/// <summary>
/// Chạy trước mỗi lần SaveChanges: tự điền CreatedAt/By, UpdatedAt/By
/// và đổi lệnh xóa thành xóa mềm (IsDeleted = 1).
/// </summary>
public sealed class AuditInterceptor(ICurrentUser currentUser, TimeProvider clock) : SaveChangesInterceptor
{
    public override ValueTask<InterceptionResult<int>> SavingChangesAsync(
        DbContextEventData eventData, InterceptionResult<int> result, CancellationToken cancellationToken = default)
    {
        if (eventData.Context is not null) Apply(eventData.Context);
        return base.SavingChangesAsync(eventData, result, cancellationToken);
    }

    public override InterceptionResult<int> SavingChanges(DbContextEventData eventData, InterceptionResult<int> result)
    {
        if (eventData.Context is not null) Apply(eventData.Context);
        return base.SavingChanges(eventData, result);
    }

    private void Apply(DbContext context)
    {
        var now = clock.GetUtcNow().UtcDateTime;
        var userId = currentUser.UserId;

        foreach (var entry in context.ChangeTracker.Entries())
        {
            if (entry is { State: EntityState.Deleted, Entity: ISoftDelete soft })
            {
                entry.State = EntityState.Modified;
                soft.IsDeleted = true;
            }

            if (entry.Entity is not IAuditable audit) continue;

            switch (entry.State)
            {
                case EntityState.Added:
                    audit.CreatedAt = now;
                    audit.CreatedBy = userId;
                    break;
                case EntityState.Modified:
                    audit.UpdatedAt = now;
                    audit.UpdatedBy = userId;
                    entry.Property(nameof(IAuditable.CreatedAt)).IsModified = false;
                    entry.Property(nameof(IAuditable.CreatedBy)).IsModified = false;
                    break;
            }
        }
    }
}
