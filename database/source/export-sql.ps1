<#
  Tạo lại file database\MyERP.sql = cấu trúc (các script 00..20 trong thư mục này)
  + toàn bộ dữ liệu đang có trong database thật.

  Thường chạy qua database\cap-nhat-file-sql.cmd. Chạy tay:
    .\export-sql.ps1                          # localhost, database MyERP
    .\export-sql.ps1 -Server ".\SQLEXPRESS" -Database MyERP
#>
param(
    [string]$Server   = "localhost",
    [string]$Database = "MyERP",
    [string]$Output   = ""
)

$ErrorActionPreference = "Stop"
$dir = Split-Path -Parent $MyInvocation.MyCommand.Path
if (-not $Output) { $Output = Join-Path (Split-Path -Parent $dir) "$Database.sql" }
$Output = [IO.Path]::GetFullPath($Output)

# Bảng chỉ chứa phiên đăng nhập - không mang sang máy khác
$skipTables = @('core.RefreshTokens')

$inv = [Globalization.CultureInfo]::InvariantCulture
$cn = New-Object System.Data.SqlClient.SqlConnection "Server=$Server;Database=$Database;Integrated Security=true;TrustServerCertificate=true;Application Name=MyERP export"
$cn.Open()

function Get-Rows([string]$sql) {
    $cmd = $cn.CreateCommand(); $cmd.CommandText = $sql; $cmd.CommandTimeout = 300
    $da = New-Object System.Data.SqlClient.SqlDataAdapter $cmd
    $t = New-Object System.Data.DataTable; [void]$da.Fill($t); return ,$t
}

function Format-Value($v, [string]$type) {
    if ($v -is [DBNull]) { return 'NULL' }
    switch ($type) {
        { $_ -in 'nvarchar','nchar','ntext','xml' } { return "N'" + ([string]$v).Replace("'", "''") + "'" }
        { $_ -in 'varchar','char','text' }          { return "'" + ([string]$v).Replace("'", "''") + "'" }
        'bit'              { return $(if ($v) { '1' } else { '0' }) }
        'uniqueidentifier' { return "'" + $v.ToString() + "'" }
        'date'             { return "'" + $v.ToString('yyyy-MM-dd', $inv) + "'" }
        { $_ -in 'datetime2','datetime','smalldatetime' } { return "'" + $v.ToString('yyyy-MM-ddTHH:mm:ss.fffffff', $inv) + "'" }
        'datetimeoffset'   { return "'" + $v.ToString('yyyy-MM-ddTHH:mm:ss.fffffffzzz', $inv) + "'" }
        'time'             { return "'" + $v.ToString('hh\:mm\:ss\.fffffff', $inv) + "'" }
        { $_ -in 'varbinary','binary','image' } { return '0x' + [BitConverter]::ToString([byte[]]$v).Replace('-', '') }
        { $_ -in 'float','real' } { return ([double]$v).ToString('R', $inv) }
        default            { return [Convert]::ToString($v, $inv) }
    }
}

$sb = New-Object System.Text.StringBuilder
function Out([string]$s) { [void]$sb.AppendLine($s) }

# ---------- Đầu file ----------
$now = Get-Date -Format 'yyyy-MM-dd HH:mm'
Out @"
/* =====================================================================
   Database $Database – MyERP (cấu trúc + toàn bộ dữ liệu)
   Tạo lúc: $now

   CÁCH DÙNG TRÊN MÁY MỚI:
     1. Mở file này trong SQL Server Management Studio (SSMS), kết nối tới SQL Server.
     2. Bấm Execute (F5). Xong.
     (hoặc dòng lệnh: sqlcmd -S localhost -E -C -f 65001 -i $Database.sql)

   Nếu máy đó đã có database $Database, script sẽ dừng lại, không ghi đè gì.
   Muốn thay hẳn: xóa database $Database cũ trong SSMS rồi chạy lại file này.

   File này được sinh tự động bởi database\cap-nhat-file-sql.cmd – đừng sửa tay.
   Muốn đổi cấu trúc: sửa script trong database\source rồi chạy lại cmd.
   ===================================================================== */
SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
SET ANSI_PADDING ON;
SET ANSI_WARNINGS ON;
SET CONCAT_NULL_YIELDS_NULL ON;
SET ARITHABORT ON;
SET NUMERIC_ROUNDABORT OFF;
GO
IF DB_ID(N'$Database') IS NOT NULL
BEGIN
    RAISERROR(N'Database $Database đã tồn tại trên máy này. Không chạy tiếp để tránh ghi đè dữ liệu.', 16, 1) WITH NOWAIT;
    SET NOEXEC ON;
END
GO
CREATE DATABASE [$Database] COLLATE Latin1_General_100_CI_AI;
GO
ALTER DATABASE [$Database] SET READ_COMMITTED_SNAPSHOT ON WITH ROLLBACK IMMEDIATE;
ALTER DATABASE [$Database] SET ALLOW_SNAPSHOT_ISOLATION ON;
GO
USE [$Database];
GO
"@

# ---------- Cấu trúc: script 01..20 ----------
$schemaFiles = Get-ChildItem $dir -Filter '*.sql' |
    Where-Object { $_.Name -match '^(\d{2})_' -and [int]$Matches[1] -ge 1 -and [int]$Matches[1] -lt 30 } |
    Sort-Object Name
foreach ($f in $schemaFiles) {
    Out ""
    Out "-- ===================== $($f.Name) ====================="
    $text = [IO.File]::ReadAllText($f.FullName, [Text.Encoding]::UTF8)
    if ($text -match '\$\(') { throw "$($f.Name) có biến sqlcmd `$(...) - không gộp được." }
    Out $text.TrimEnd()
    Out "GO"
}

# ---------- Dữ liệu ----------
Out ""
Out "-- ===================== DỮ LIỆU ====================="
Out "EXEC sp_MSforeachtable N'ALTER TABLE ? NOCHECK CONSTRAINT ALL; ALTER TABLE ? DISABLE TRIGGER ALL;';"
Out "GO"

$tables = Get-Rows @"
SELECT s.name AS sch, t.name AS tbl, t.object_id AS id,
       CAST(OBJECTPROPERTY(t.object_id, 'TableHasIdentity') AS bit) AS hasIdentity
FROM sys.tables t JOIN sys.schemas s ON s.schema_id = t.schema_id
WHERE t.is_ms_shipped = 0
ORDER BY s.name, t.name
"@

$total = 0
foreach ($t in $tables) {
    $full = "$($t.sch).$($t.tbl)"
    if ($skipTables -contains $full) { continue }
    $cols = Get-Rows @"
SELECT c.name, TYPE_NAME(c.system_type_id) AS type
FROM sys.columns c
WHERE c.object_id = $($t.id) AND c.is_computed = 0 AND c.system_type_id <> 189
ORDER BY c.column_id
"@
    $colList = ($cols | ForEach-Object { "[$($_.name)]" }) -join ', '
    $rows = Get-Rows "SELECT $colList FROM [$($t.sch)].[$($t.tbl)]"
    if ($rows.Rows.Count -eq 0) { continue }

    $types = @($cols | ForEach-Object { $_.type })
    $target = "[$($t.sch)].[$($t.tbl)]"
    Out ""
    Out "-- $full ($($rows.Rows.Count) dòng)"
    if ($t.hasIdentity) { Out "SET IDENTITY_INSERT $target ON;" }
    $i = 0
    foreach ($r in $rows.Rows) {
        if ($i % 500 -eq 0) {
            if ($i -gt 0) { [void]$sb.Remove($sb.Length - [Environment]::NewLine.Length - 1, 1); Out ";" }
            Out "INSERT INTO $target ($colList) VALUES"
        }
        $vals = for ($k = 0; $k -lt $types.Count; $k++) { Format-Value $r[$k] $types[$k] }
        Out ("(" + ($vals -join ', ') + "),")
        $i++
    }
    [void]$sb.Remove($sb.Length - [Environment]::NewLine.Length - 1, 1); Out ";"
    if ($t.hasIdentity) { Out "SET IDENTITY_INSERT $target OFF;" }
    Out "GO"
    $total += $rows.Rows.Count
}
$cn.Close()

Out ""
Out "EXEC sp_MSforeachtable N'ALTER TABLE ? WITH CHECK CHECK CONSTRAINT ALL; ALTER TABLE ? ENABLE TRIGGER ALL;';"
Out "GO"
Out "PRINT N'Xong: database $Database đã sẵn sàng.';"
Out "GO"

[IO.File]::WriteAllText($Output, $sb.ToString(), (New-Object Text.UTF8Encoding $true))
Write-Host ("Xong: {0} ({1} script cấu trúc, {2} dòng dữ liệu, {3:N0} KB)" -f $Output, $schemaFiles.Count, $total, ((Get-Item $Output).Length / 1KB)) -ForegroundColor Green
