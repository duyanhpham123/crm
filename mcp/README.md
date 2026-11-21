# Trợ lý AI cho MyERP (MCP server)

Cho **Claude Desktop** (hoặc Claude Code / app khác hỗ trợ MCP) xem và làm việc trong ERP bằng lời:

> "Doanh thu tháng này so với tháng trước?" · "Size nào sắp hết hàng?" · "Giảm 10% nhóm Giày sneaker" ·
> "Bật mẫu Mũ lưỡi trai lên web Sneaker giá 99k" · "Tạo mã TET2027 giảm 15%" · "Viết bài blog phối đồ Tết, lưu nháp" ·
> "Giao việc cho Châu gọi lại khách VIP, hạn thứ 6"

```
Bạn ──lời nói──► Claude Desktop ──MCP (stdio)──► mcp/server.js ──REST + khóa erp_...──► ERP backend
```

- AI dùng **khóa truy cập cá nhân** của bạn → chỉ làm được những gì tài khoản bạn được phép. Mọi thay đổi đi qua API ERP:
  kiểm tra quyền, kiểm tra dữ liệu, ghi nhật ký, website tự cập nhật như thao tác bằng tay.
- Khóa **không** dùng được cho: quản lý người dùng, vai trò & quyền, khóa khác, đổi mật khẩu.
- Claude Desktop hỏi bạn đồng ý trước mỗi lần AI dùng công cụ. Đổi giá hàng loạt luôn **xem trước** rồi mới áp dụng.
- Không cần API key trả tiền: dùng tài khoản Claude của bạn (gói Free giới hạn lượt chat thấp, dùng nhiều nên lên Pro).

## Cài đặt (mỗi máy làm 1 lần)

Cần: Node.js 20+, Claude Desktop (claude.ai/download, đăng nhập tài khoản Claude), backend ERP đang chạy.

1. Vào ERP → biểu tượng **robot** trên thanh trên cùng → **Tạo khóa** (máy lab / dùng thử chọn 7 ngày). Khóa chỉ hiện 1 lần.
2. Bấm **Chép** lệnh ở bước 2 trên trang đó, dán vào PowerShell. Lệnh tự `npm install`, kiểm tra khóa và thêm ERP vào
   `%APPDATA%\Claude\claude_desktop_config.json` (sao lưu file cũ). Hoặc chạy tay:
   ```powershell
   powershell -ExecutionPolicy Bypass -File C:\.Net\CRM\mcp\cai-claude-desktop.ps1 -Token erp_xxxx -ApiUrl http://localhost:5121
   ```
3. **Thoát hẳn** Claude Desktop (khay hệ thống → Quit) rồi mở lại → ô chat có công cụ **myerp**.

Gỡ: `cai-claude-desktop.ps1 -Remove`, rồi thu hồi khóa trong ERP.

Kiểm tra không cần Claude Desktop:
```powershell
cd C:\.Net\CRM\mcp; $env:ERP_TOKEN="erp_xxxx"; npm run check
```

## Công cụ

| Công cụ | Việc | Ghi dữ liệu |
|---|---|---|
| `whoami` | Tài khoản, công ty, quyền của khóa | |
| `get_sales_report` | Doanh thu, lãi gộp, đơn, kênh, nhóm hàng, top sản phẩm, hàng sắp hết theo khoảng ngày | |
| `search_products`, `get_product` | Tìm mẫu; chi tiết từng SKU màu - size (giá, giá vốn, tồn) | |
| `low_stock` | SKU dưới mức tồn tối thiểu | |
| `list_orders`, `get_order` | Đơn hàng theo trạng thái / kênh / ngày; chi tiết đơn | |
| `search_customers` | Tìm khách theo tên, SĐT, MST | |
| `list_websites`, `website_products` | Website và sản phẩm đang bày trên từng web | |
| `list_promotions`, `list_tasks` | Mã giảm giá; công việc (của tôi / quá hạn) | |
| `update_prices` | Đổi giá theo mẫu / SKU / nhóm hàng: đặt giá, % hoặc ± tiền, làm tròn 1.000đ. **Xem trước, `apply=true` mới đổi** | ✔ |
| `set_website_product` | Bày / ẩn mẫu trên 1 website, giá riêng, nổi bật | ✔ |
| `create_promotion` | Tạo mã giảm giá | ✔ |
| `create_blog_post` | Viết bài lên website (mặc định lưu nháp) | ✔ |
| `create_task` | Giao việc theo tên nhân viên / dự án | ✔ |

Thêm công cụ: viết thêm 1 `server.registerTool(...)` trong `server.js`, gọi API ERP qua hàm `erp(...)` (đừng truy cập thẳng database).

## Đổi máy (VD máy lab)

Clone dự án → tạo database (`database/MyERP.sql`) → chạy backend → làm lại 3 bước cài ở trên với **khóa mới**.
Rời máy lab: chạy `cai-claude-desktop.ps1 -Remove` và **thu hồi khóa** trong ERP.

## Khi ERP đưa lên mạng (https)

Đổi `-ApiUrl https://erp.ten-mien.vn` khi chạy lệnh cài. Muốn dùng trên claude.ai (không cài Node) thì cần thêm bản MCP chạy
từ xa (remote MCP, HTTPS cổng 443) - chưa có trong dự án.
