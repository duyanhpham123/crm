/* =====================================================================
   MyERP - 20. VIEW / FUNCTION báo cáo dùng chung
   ===================================================================== */

/* Tồn kho khả dụng + cảnh báo dưới định mức */
CREATE OR ALTER VIEW inv.vw_StockAvailability
AS
SELECT  b.CompanyId,
        w.Id   AS WarehouseId, w.Code AS WarehouseCode, w.Name AS WarehouseName,
        p.Id   AS ProductId,   p.Code AS ProductCode,   p.Name AS ProductName,
        SUM(b.QtyOnHand)    AS QtyOnHand,
        SUM(b.QtyReserved)  AS QtyReserved,
        SUM(b.QtyAvailable) AS QtyAvailable,
        SUM(b.QtyIncoming)  AS QtyIncoming,
        p.MinStock,
        CAST(CASE WHEN SUM(b.QtyAvailable) < p.MinStock THEN 1 ELSE 0 END AS BIT) AS IsBelowMin,
        SUM(b.QtyOnHand * b.AvgCost) AS StockValue
FROM inv.StockBalances b
JOIN inv.Warehouses w ON w.Id = b.WarehouseId
JOIN md.Products   p ON p.Id = b.ProductId
GROUP BY b.CompanyId, w.Id, w.Code, w.Name, p.Id, p.Code, p.Name, p.MinStock;
GO

/* Bảng cân đối số phát sinh: đầu kỳ - phát sinh - cuối kỳ */
CREATE OR ALTER FUNCTION acc.fn_TrialBalance (@CompanyId BIGINT, @FromDate DATE, @ToDate DATE)
RETURNS TABLE
AS
RETURN
    SELECT  a.Id AS AccountId, a.Code, a.Name, a.AccountType,
            SUM(CASE WHEN e.PostingDate <  @FromDate THEN l.Debit - l.Credit ELSE 0 END) AS OpeningBalance,
            SUM(CASE WHEN e.PostingDate BETWEEN @FromDate AND @ToDate THEN l.Debit  ELSE 0 END) AS PeriodDebit,
            SUM(CASE WHEN e.PostingDate BETWEEN @FromDate AND @ToDate THEN l.Credit ELSE 0 END) AS PeriodCredit,
            SUM(CASE WHEN e.PostingDate <= @ToDate THEN l.Debit - l.Credit ELSE 0 END) AS ClosingBalance
    FROM acc.JournalEntryLines l
    JOIN acc.JournalEntries e ON e.Id = l.EntryId AND e.Status = 'posted'
    JOIN acc.Accounts a       ON a.Id = l.AccountId
    WHERE e.CompanyId = @CompanyId AND e.PostingDate <= @ToDate
    GROUP BY a.Id, a.Code, a.Name, a.AccountType;
GO

/* Tuổi nợ phải thu theo khách hàng */
CREATE OR ALTER VIEW acc.vw_ReceivableAging
AS
SELECT  i.CompanyId, i.PartnerId, p.Code AS PartnerCode, p.Name AS PartnerName,
        SUM(i.AmountDue) AS TotalDue,
        SUM(CASE WHEN i.DueDate IS NULL OR i.DueDate >= CAST(SYSDATETIME() AS DATE) THEN i.AmountDue ELSE 0 END) AS NotDue,
        SUM(CASE WHEN DATEDIFF(DAY, i.DueDate, SYSDATETIME()) BETWEEN 1  AND 30 THEN i.AmountDue ELSE 0 END) AS Overdue1_30,
        SUM(CASE WHEN DATEDIFF(DAY, i.DueDate, SYSDATETIME()) BETWEEN 31 AND 60 THEN i.AmountDue ELSE 0 END) AS Overdue31_60,
        SUM(CASE WHEN DATEDIFF(DAY, i.DueDate, SYSDATETIME()) BETWEEN 61 AND 90 THEN i.AmountDue ELSE 0 END) AS Overdue61_90,
        SUM(CASE WHEN DATEDIFF(DAY, i.DueDate, SYSDATETIME()) > 90 THEN i.AmountDue ELSE 0 END) AS OverdueOver90
FROM acc.Invoices i
JOIN md.Partners p ON p.Id = i.PartnerId
WHERE i.InvoiceType = 'out_invoice' AND i.Status = 'posted' AND i.PaymentStatus <> 'paid' AND i.IsDeleted = 0
GROUP BY i.CompanyId, i.PartnerId, p.Code, p.Name;
GO

/* Pipeline bán hàng theo giai đoạn */
CREATE OR ALTER VIEW crm.vw_PipelineSummary
AS
SELECT  o.CompanyId, o.PipelineId, s.Id AS StageId, s.Name AS StageName, s.SortOrder,
        o.OwnerUserId,
        COUNT(*)               AS OpportunityCount,
        SUM(o.ExpectedRevenue) AS ExpectedRevenue,
        SUM(o.WeightedRevenue) AS WeightedRevenue
FROM crm.Opportunities o
JOIN crm.Stages s ON s.Id = o.StageId
WHERE o.IsDeleted = 0 AND o.Status = 'open'
GROUP BY o.CompanyId, o.PipelineId, s.Id, s.Name, s.SortOrder, o.OwnerUserId;
GO

/* Doanh thu & lãi gộp theo tháng, nhân viên */
CREATE OR ALTER VIEW sales.vw_MonthlySales
AS
SELECT  so.CompanyId,
        YEAR(so.OrderDate)  AS SalesYear,
        MONTH(so.OrderDate) AS SalesMonth,
        so.SalespersonUserId,
        so.Channel,
        COUNT(DISTINCT so.Id)                       AS OrderCount,
        SUM(l.LineSubTotal)                         AS Revenue,
        SUM(l.UnitCost * l.Quantity)                AS Cogs,
        SUM(l.LineSubTotal - l.UnitCost * l.Quantity) AS GrossProfit
FROM sales.SalesOrders so
JOIN sales.SalesOrderLines l ON l.SalesOrderId = so.Id
WHERE so.Status IN ('confirmed','processing','completed') AND so.IsDeleted = 0
GROUP BY so.CompanyId, YEAR(so.OrderDate), MONTH(so.OrderDate), so.SalespersonUserId, so.Channel;
GO
