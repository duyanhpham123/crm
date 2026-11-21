<#
  Cắm MyERP vào Claude Desktop: thêm máy chủ MCP "myerp" vào %APPDATA%\Claude\claude_desktop_config.json
  (giữ nguyên các máy chủ khác, sao lưu file cũ trước khi sửa).

  Cách dùng (khóa tạo ở ERP > biểu tượng robot > Tạo khóa):
    powershell -ExecutionPolicy Bypass -File cai-claude-desktop.ps1 -Token erp_xxxxx
    powershell -ExecutionPolicy Bypass -File cai-claude-desktop.ps1 -Token erp_xxxxx -ApiUrl http://localhost:5121
    powershell -ExecutionPolicy Bypass -File cai-claude-desktop.ps1 -Remove        # gỡ ra khỏi Claude Desktop

  Xong thì THOÁT HẲN Claude Desktop (khay hệ thống > Quit) rồi mở lại.
#>
param(
    [string]$Token,
    [string]$ApiUrl = "http://localhost:5121",
    [string]$Name = "myerp",
    [switch]$Remove
)
$ErrorActionPreference = "Stop"
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$configDir = Join-Path $env:APPDATA "Claude"
$configFile = Join-Path $configDir "claude_desktop_config.json"

if (-not $Remove) {
    if (-not $Token -or -not $Token.StartsWith("erp_")) { throw "Thiếu -Token erp_... (tạo ở ERP > biểu tượng robot > Tạo khóa)." }
    $node = Get-Command node -ErrorAction SilentlyContinue
    if (-not $node) { throw "Chưa cài Node.js (https://nodejs.org) - cần Node 20 trở lên." }
    if (-not (Test-Path (Join-Path $here "node_modules\@modelcontextprotocol\sdk"))) {
        Write-Host "Cài thư viện cho MCP server (npm install)..." -ForegroundColor Cyan
        Push-Location $here
        try { & npm install --no-audit --no-fund | Out-Host } finally { Pop-Location }
        if ($LASTEXITCODE -ne 0) { throw "npm install thất bại." }
    }
    # Thử gọi ERP bằng khóa để báo lỗi sớm
    try {
        $me = Invoke-RestMethod -Uri "$($ApiUrl.TrimEnd('/'))/api/me" -Headers @{ Authorization = "Bearer $Token" } -TimeoutSec 10
        Write-Host "Khóa hợp lệ: $($me.fullName) - $($me.companyName)" -ForegroundColor Green
    } catch {
        Write-Warning "Chưa gọi được ERP bằng khóa này ($($_.Exception.Message)). Vẫn ghi cấu hình - kiểm tra backend đang chạy và khóa còn hiệu lực."
    }
}

# Đọc cấu hình cũ (nếu có)
$config = [pscustomobject]@{}
if (Test-Path $configFile) {
    $raw = [IO.File]::ReadAllText($configFile)
    if ($raw.Trim()) { $config = $raw | ConvertFrom-Json }
    $backup = "$configFile.bak-$(Get-Date -Format yyyyMMdd-HHmmss)"
    Copy-Item $configFile $backup
    Write-Host "Đã sao lưu cấu hình cũ: $backup"
} else {
    New-Item -ItemType Directory -Force $configDir | Out-Null
}
if (-not ($config.PSObject.Properties.Name -contains "mcpServers")) {
    $config | Add-Member -NotePropertyName mcpServers -NotePropertyValue ([pscustomobject]@{})
}
$servers = $config.mcpServers
if ($servers.PSObject.Properties.Name -contains $Name) { $servers.PSObject.Properties.Remove($Name) }

if ($Remove) {
    Write-Host "Đã gỡ '$Name' khỏi Claude Desktop." -ForegroundColor Yellow
} else {
    $entry = [pscustomobject]@{
        command = "node"
        args    = @((Join-Path $here "server.js"))
        env     = [pscustomobject]@{ ERP_API_URL = $ApiUrl; ERP_TOKEN = $Token }
    }
    $servers | Add-Member -NotePropertyName $Name -NotePropertyValue $entry
    Write-Host "Đã thêm '$Name' vào Claude Desktop." -ForegroundColor Green
}

# Ghi UTF-8 không BOM (Claude Desktop đọc JSON chuẩn)
$json = $config | ConvertTo-Json -Depth 20
[IO.File]::WriteAllText($configFile, $json, (New-Object Text.UTF8Encoding $false))
Write-Host "File cấu hình: $configFile"
Write-Host "Bây giờ THOÁT HẲN Claude Desktop (khay hệ thống > Quit) rồi mở lại." -ForegroundColor Cyan
