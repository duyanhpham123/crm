# MyERP

Hệ thống quản trị doanh nghiệp (ERP/CRM) cho tất cả phòng ban.

| Phần | Công nghệ | Thư mục |
|---|---|---|
| Backend | ASP.NET Core 10 Web API, mô hình **MVC**, trả **JSON** | `backend/` |
| Frontend | **React 19** + Vite + React Router + Axios | `frontend/` |
| Website bán hàng mẫu | **Next.js 15** đọc dữ liệu từ ERP (nhiều website dùng chung 1 ERP) | `storefront/` |
| Trợ lý AI | **MCP server** (Node.js) cho Claude Desktop: hỏi / ra lệnh ERP bằng lời, dùng quyền của người dùng | `mcp/` |
| Database | SQL Server, 157 bảng, 15 schema | `database/MyERP.sql` |

```
Trình duyệt ──► React (frontend/) ──HTTP JSON──► Controller ──► Service ──► AppDbContext ──► SQL Server
                 pages, components               (backend/MyERP.Api)
```

## Chạy dự án

Cần: .NET SDK 10+, Node.js 20+, SQL Server (localhost, Windows Authentication).

```powershell
# 1. Tạo database (chỉ làm 1 lần): mở database/MyERP.sql trong SSMS rồi bấm Execute (F5)
#    hoặc:
sqlcmd -S localhost -E -C -f 65001 -i database/MyERP.sql

# 2. Chạy backend - cửa sổ terminal 1
dotnet run --project backend/MyERP.Api --launch-profile http

# 3. Chạy frontend - cửa sổ terminal 2
cd frontend
npm install        # lần đầu
npm run dev
```

Mở **http://localhost:5173**. Lần đầu sẽ hiện màn hình thiết lập mật khẩu cho tài khoản `admin`.

- Tài liệu API, thử API trực tiếp: http://localhost:5121/docs
- **Thư mục `database/`** gọn như sau:
  - `MyERP.sql` – một file duy nhất: cấu trúc + toàn bộ dữ liệu hiện tại. Mang sang máy khác chỉ cần chạy file này.
  - `cap-nhat-file-sql.cmd` – bấm đúp để tạo lại `MyERP.sql` từ database MyERP đang chạy (làm trước khi mang project đi / commit).
  - `source/` – script gốc để sửa cấu trúc (`00..20`), dữ liệu khởi tạo (`30`), dữ liệu mẫu (`40..43`), `migrations/` và `run_all.ps1`.
    Đổi cấu trúc: sửa script trong `source/` + viết migration cho DB đang chạy, rồi chạy lại `cap-nhat-file-sql.cmd`.
  - Tạo DB sạch không có dữ liệu bán hàng: `.\database\source\run_all.ps1` (thêm `-Demo` để có dữ liệu mẫu).
- **Database tạo từ trước** cần chạy các bản nâng cấp trong `database/source/migrations/` theo thứ tự ngày (chạy lại nhiều lần không sao), ví dụ:
  `sqlcmd -S localhost -E -d MyERP -I -f 65001 -i database/source/migrations/2026-11-24_phase4.sql` (bản mới nhất - quyền Chat / Tài liệu / Dự án cho mọi vai trò; dữ liệu mẫu đợt 4: `database/source/44_demo_phase4.sql`)
- Dữ liệu mẫu đợt 4 tạo 6 tài khoản nhân viên (nhung, chau, ducanh, thaovy, tung, mai) **chưa có mật khẩu** - vào app Người dùng đặt mật khẩu nếu muốn đăng nhập bằng các tài khoản này.
- Trợ lý AI: migration `.../migrations/2026-11-26_api_tokens.sql` (khóa truy cập cá nhân). Hướng dẫn cài Claude Desktop: `mcp/README.md` hoặc trang ERP → biểu tượng robot.
- Nâng cấp nhiều website: `.../migrations/2026-11-25_multisite.sql`; dữ liệu mẫu 2 website: `database/source/45_demo_multisite.sql`. Hướng dẫn nối website Next.js: `storefront/README.md`.
- File tải lên ở app Tài liệu lưu trong `backend/MyERP.Api/App_Data/uploads` (không commit; đổi chỗ bằng cấu hình `Storage:Root`, giới hạn `Storage:MaxUploadMb`, mặc định 20 MB). Mang sang máy khác thì chép cả thư mục này.
- Quy tắc tính lương (giảm trừ gia cảnh, biểu thuế TNCN, tỷ lệ bảo hiểm) nằm ở `backend/MyERP.Api/Models/Entities/Hr/Payroll.cs` (`PayrollRules`) - kiểm tra lại theo quy định hiện hành trước khi trả lương thật.
- Vite tự chuyển `/api/*` sang backend nên không cần cấu hình CORS khi dev.
- Sửa file React thì trình duyệt tự cập nhật ngay. Sửa C# thì dừng và chạy lại backend (hoặc dùng `dotnet watch`).

```powershell
dotnet test --project backend/MyERP.Tests     # chạy test backend
```

## Cấu trúc backend (MVC)

```
backend/
├── MyERP.slnx                     Mở bằng Visual Studio / Rider
├── MyERP.Api/
│   ├── Program.cs                 Khởi động: đăng ký service + pipeline
│   ├── appsettings.json           Chuỗi kết nối DB, JWT, CORS
│   │
│   ├── Controllers/               [C] Nhận request, gọi Service, trả JSON. KHÔNG viết nghiệp vụ ở đây
│   │   ├── ApiControllerBase.cs       Lớp cha: [ApiController], [Authorize], đổi Result thành HTTP
│   │   ├── AuthController.cs          /api/auth/login, refresh, logout, setup
│   │   ├── AccountController.cs       /api/me, /api/apps, /api/me/change-password
│   │   ├── UsersController.cs         /api/users (quản lý người dùng)
│   │   ├── RolesController.cs         /api/roles (vai trò & ma trận quyền)
│   │   └── Crm/LeadsController.cs     /api/crm/leads
│   │
│   ├── Models/                    [M] Dữ liệu
│   │   ├── Entities/                  Ánh xạ bảng DB (Core/User.cs, Crm/Lead.cs...) + quy tắc nghiệp vụ của bảng
│   │   ├── DTOs/                      Dữ liệu JSON gửi lên / trả về (không trả Entity ra ngoài)
│   │   └── Constants.cs               Mã quyền, trạng thái
│   │
│   ├── Services/                  Nghiệp vụ: mỗi service có interface (ILeadService) + lớp cài đặt
│   │   ├── Auth/                      Đăng nhập, JWT, phân quyền
│   │   ├── Crm/LeadService.cs
│   │   └── Common/                    Người dùng hiện tại, sinh số chứng từ
│   │
│   ├── Data/                      Truy cập DB
│   │   ├── AppDbContext.cs            DbSet các bảng + lọc tự động (xóa mềm, theo công ty)
│   │   ├── Configurations/            Map Entity sang bảng (tên bảng, độ dài cột...)
│   │   └── AuditInterceptor.cs        Tự điền CreatedAt/By, UpdatedAt/By
│   │
│   ├── Validators/                Kiểm tra dữ liệu đầu vào (FluentValidation) - tự chạy trước Controller
│   ├── Infrastructure/            Cấu hình chung: phân quyền [HasPermission], xử lý lỗi, đăng ký DI
│   └── Common/                    Result/Error, chuẩn hóa số điện thoại
└── MyERP.Tests/                   Unit test + test quy ước (controller phải có phân quyền...)
```

**Luồng một request** - ví dụ tạo lead `POST /api/crm/leads`:

1. `LeadsController.Create` nhận JSON vào `SaveLeadRequest` (DTO).
2. `ValidationFilter` chạy `SaveLeadRequestValidator`; dữ liệu sai thì trả 400 kèm danh sách lỗi.
3. `[HasPermission("crm.create")]` kiểm tra quyền; không có quyền thì trả 403.
4. `LeadService.CreateAsync` xử lý nghiệp vụ: chống trùng, sinh mã, tạo `Lead`, lưu qua `AppDbContext`.
5. Controller trả `201 Created` + JSON `LeadDto`. Lỗi nghiệp vụ thành JSON `{ status, title, code }`.

## Cấu trúc frontend (React)

```
frontend/src/
├── main.jsx               Điểm khởi động
├── App.jsx                Bảng định tuyến: URL nào hiện trang nào
├── api/                   Gọi backend - mỗi file một nhóm API
│   ├── client.js              Axios: tự gắn token, tự refresh khi hết hạn, đọc thông báo lỗi
│   ├── authApi.js             đăng nhập, /api/me, /api/apps
│   └── leadApi.js             /api/crm/leads
├── context/AuthContext.jsx    Trạng thái đăng nhập: useAuth() → { me, apps, can, login, logout }
├── layouts/               Khung trang: MainLayout (thanh trên), ModuleLayout (menu trái)
├── components/            Thành phần dùng lại: Modal, Pagination, AppIcon, ProtectedRoute
├── pages/                 Mỗi màn hình một file
│   ├── LoginPage.jsx, HomePage.jsx (lưới ứng dụng)
│   └── crm/LeadsPage.jsx, LeadFormModal.jsx, CrmLayout.jsx
├── constants/             Mã quyền, trạng thái (khớp backend)
├── utils/format.js        Định dạng tiền, ngày
└── styles/app.css         Giao diện (tự đổi sáng / tối theo hệ điều hành)
```

## Thêm một chức năng mới (ví dụ: Đơn hàng)

**Backend**
1. `Models/Entities/Sales/SalesOrder.cs`: entity ánh xạ bảng `sales.SalesOrders`.
2. `Data/Configurations/SalesConfigurations.cs`: `ToTable("SalesOrders", "sales")`. Thêm `DbSet<SalesOrder>` vào `AppDbContext`.
3. `Models/DTOs/SalesDtos.cs`: `OrderDto`, `SaveOrderRequest`...
4. `Validators/SalesValidators.cs`: quy tắc nhập liệu.
5. `Services/Sales/OrderService.cs`: `IOrderService` + `OrderService`. Đăng ký trong `Infrastructure/ServiceRegistration.cs`.
6. `Controllers/Sales/OrdersController.cs`: `[Route("api/sales/orders")]`, `[HasPermission("order.view")]`, action ghi gắn `[HasPermission("order.create")]`...
7. `dotnet test`: test quy ước sẽ báo nếu quên phân quyền.

**Frontend**
1. `src/api/orderApi.js`: các hàm gọi `/api/sales/orders`.
2. `src/pages/sales/OrdersPage.jsx` (+ `SalesLayout.jsx` cho menu trái).
3. Khai báo `<Route path="orders" element={<OrdersPage />} />` trong `App.jsx`.
4. Mã quyền mới thêm vào `src/constants/index.js`.

## Triển khai (deploy)

```powershell
cd frontend
npm run build                         # xuất React vào backend/MyERP.Api/wwwroot
cd ..
dotnet publish backend/MyERP.Api -c Release -o publish
```

Chỉ cần chạy một ứng dụng .NET: nó phục vụ cả API lẫn giao diện React. Nếu muốn host React riêng (Nginx, Vercel...), đặt `VITE_API_URL` (xem `frontend/.env.example`) và thêm địa chỉ frontend vào `Cors:AllowedOrigins`.

**Trước khi chạy production**
- Đặt `Jwt:SigningKey` ngẫu nhiên ≥ 32 byte qua biến môi trường `Jwt__SigningKey`. Khóa trong `appsettings.Development.json` chỉ để dev.
- `Setup:Enabled` mặc định `false` ở production; chỉ bật tạm khi cài lần đầu.
- Chuỗi kết nối dùng tài khoản SQL riêng có quyền tối thiểu.
- Chạy sau HTTPS (Nginx/IIS); HSTS và chuyển hướng HTTPS đã bật sẵn ngoài môi trường Development.

## Đã có

| Hạng mục | Chi tiết |
|---|---|
| Đăng nhập | JWT 30 phút + refresh token 14 ngày xoay vòng; dùng lại token cũ thì thu hồi cả phiên; khóa 15 phút sau 5 lần sai; giới hạn 10 request/phút/IP |
| Phân quyền | Theo mã quyền + phạm vi dữ liệu (của tôi / phòng ban / chi nhánh / công ty). Frontend ẩn nút theo `can('crm.create')` |
| Lưới ứng dụng | Chỉ hiện ứng dụng công ty đã bật và người dùng có quyền |
| CRM - Lead | Danh sách, tìm không dấu, lọc, phân trang, tạo / sửa / xóa mềm, đổi trạng thái, chống trùng SĐT/email, **chuyển đổi thành khách hàng + cơ hội** |
| CRM - Khách hàng | Doanh nghiệp / cá nhân, mã số thuế, nhóm, người phụ trách, nhiều người liên hệ (1 liên hệ chính); tìm theo tên, MST, SĐT, tên người liên hệ; hồ sơ khách hàng kèm cơ hội; chống trùng MST / SĐT |
| CRM - Cơ hội | Bảng Kanban kéo thả theo giai đoạn (đổi được cả trong form - dùng trên điện thoại); tổng giá trị + doanh thu kỳ vọng mỗi cột; thất bại bắt buộc có lý do; quá hạn chốt tô đỏ; lưu lịch sử chuyển giai đoạn |
| Kho - Sản phẩm | Mẫu sản phẩm + biến thể màu × size: chọn màu, bộ size (áo S–XL, quần 28–34, giày 35–43...) là sinh sẵn SKU (VD `ATB01-DEN-M`); thêm màu / size sau vẫn được; giá, mã vạch, tồn tối thiểu riêng từng SKU; bảng tồn theo màu × size tô màu hàng sắp hết |
| Kho - Tồn & phiếu kho | Tồn từng SKU, giá vốn bình quân gia quyền, giá trị tồn, lọc hàng sắp hết. Phiếu nhập / xuất / kiểm kê thủ công; phiếu từ đơn bán, đơn nhập tự sinh và link về chứng từ gốc; không cho xuất quá tồn |
| Đơn hàng | Bán tại quầy (để trống khách = Khách lẻ) và online (Facebook, Shopee, TikTok, Lazada, Website, Zalo...): tìm SKU kiểu "thun đen M", chiết khấu dòng, giảm giá đơn, phí ship. Nháp → Xác nhận (trừ kho, chốt giá vốn) → Hoàn thành; thu tiền nhiều lần; hủy đơn đã xuất thì hàng tự về kho; xem lãi gộp từng đơn |
| Mua hàng | Nhà cung cấp (mã NCC tự sinh); đơn nhập Nháp → Gửi đặt hàng → Nhận hàng (tự tạo phiếu nhập, cập nhật tồn và giá vốn; chi phí vận chuyển phân bổ vào giá vốn theo giá trị dòng) |
| Báo cáo | Doanh thu, lãi gộp, số đơn, giá trị TB/đơn so với kỳ trước (7 / 30 / 90 ngày); biểu đồ doanh thu theo ngày (xem dạng bảng được); theo kênh bán, nhóm hàng; top sản phẩm; hàng sắp hết; công nợ khách; giá trị tồn kho |
| Trả hàng | Từ đơn đã xác nhận / hoàn thành: chọn sản phẩm, số lượng, tình trạng (còn bán được thì nhập lại kho đúng giá vốn, hỏng thì không); hoàn tiền mặt / chuyển khoản (tự tạo phiếu chi) hoặc trừ công nợ; giảm giá đơn chia đều khi trả |
| Báo giá | Lập báo giá cho khách sỉ / doanh nghiệp, điều khoản, hạn hiệu lực (tự báo hết hạn), in / lưu PDF; sửa sau khi gửi thì tăng số lần sửa; khách đồng ý thì tự tạo đơn hàng nháp đúng giá; tỷ lệ chốt |
| Vận chuyển | Danh sách đơn chờ giao; tạo vận đơn (GHN, GHTK, Viettel Post, J&T, SPX, shop tự giao) kèm COD, phí ship; hành trình Chờ lấy → Đã lấy → Đang giao → Đã giao (đơn tự hoàn thành) / Thất bại → Giao lại / Hoàn hàng (đơn tự hủy, hàng về kho); đối soát COD: chọn vận đơn hãng đã giao → 1 phiếu báo có + 1 phiếu chi phí ship, đơn ghi đã thu |
| Kế toán | Phiếu thu / chi tiền mặt (PT / PC) và ngân hàng (BC / BN); thu tiền khách / trả NCC tự trừ vào đơn nợ cũ nhất; hủy phiếu thì trả lại công nợ; sổ quỹ có tồn đầu / cuối kỳ; công nợ khách hàng, nhà cung cấp; báo cáo lãi lỗ (doanh thu thuần, giá vốn, chi phí theo loại); tài khoản ngân hàng. Thu tiền ở Đơn hàng, COD, hoàn tiền trả hàng đều tự ghi sổ |
| CSKH | Phiếu hỗ trợ / khiếu nại / bảo hành / đổi trả từ mọi kênh, gắn khách + đơn hàng; hạn phản hồi và hạn xử lý theo mức ưu tiên (SLA), báo quá hạn; trao đổi với khách + ghi chú nội bộ; giao người xử lý; đánh giá hài lòng 1-5 sao; tạo phiếu ngay từ đơn hàng |
| Nhân sự | Hồ sơ nhân viên, hợp đồng & lương (đổi lương tự lập hợp đồng mới), gắn tài khoản đăng nhập; chấm công tháng dạng bảng (bấm ô để sửa, chấm đủ công, check-in / check-out, đi trễ, tăng ca); đơn nghỉ phép có duyệt, quỹ phép năm (duyệt thì tự chấm công "nghỉ phép"); bảng lương tháng: công thực tế, phép có lương, tăng ca 150%, BH 10,5%, thuế TNCN lũy tiến, thưởng / tạm ứng; duyệt rồi chi lương tạo phiếu chi bên Kế toán |
| Marketing | Chiến dịch quảng cáo (Facebook, TikTok, Google...): ngân sách, chi phí / hiển thị / click / lead theo ngày, CTR, chi phí mỗi lead, doanh thu và ROAS qua mã giảm giá của chiến dịch; mã giảm giá (% có trần, số tiền, miễn phí ship; đơn tối thiểu, kênh, thời gian, số lượt) áp dụng ngay ở màn hình tạo đơn; phân nhóm khách VIP / thân thiết / mới / lâu không mua |
| Dự án & công việc | Bảng Kanban công việc dùng chung (Cần làm / Đang làm / Chờ duyệt / Hoàn thành) kéo thả; giao việc cho người hoặc phòng ban, ưu tiên, hạn chót (quá hạn tô đỏ); checklist tự tính tiến độ; ghi giờ làm; dự án có thành viên, ngân sách, tiến độ = trung bình tiến độ công việc. Nhân viên chỉ thấy việc của mình và dự án mình tham gia |
| Tài liệu | Thư mục chung / riêng phòng ban; hợp đồng có số hiệu, đối tác, giá trị, ngày hiệu lực - hết hạn (báo trước 30 ngày, tự coi là hết hạn); tải file nhiều phiên bản (PDF, Word, Excel, ảnh, ZIP), tải về; chặn file lạ |
| Chat nội bộ | Kênh toàn công ty, nhóm tự tạo, nhắn riêng 1-1; trả lời trích dẫn, sửa / thu hồi tin, thả biểu tượng; số tin chưa đọc; tự cập nhật tin mới vài giây một lần; dùng tốt trên điện thoại |
| Website | Thông tin website, bật / tắt mẫu sản phẩm hiện trên web (giá, tồn lấy từ Kho); bài viết blog + trang tĩnh (đường dẫn tự tạo, SEO, xem trước, nháp / đăng); menu đầu / chân trang; liên hệ khách gửi từ web → tạo Lead CRM (trùng SĐT thì gắn lead cũ). API công khai cho web bán hàng: `/api/public/site`, `products`, `posts`, `pages/{slug}`, `contact` (chống spam bằng ô ẩn + giới hạn theo IP) |
| Nhiều website tự code | Mỗi website (Next.js...) có khóa API riêng, chọn mẫu bày bán, giá riêng, nổi bật, menu, bài viết, phí ship riêng; website không có database - đọc thẳng ERP qua `/api/public` (khóa gửi trong header `X-Site-Key`, chỉ dùng ở máy chủ website). Đơn đặt từ web vào app Đơn hàng (Nháp, kênh Website), giá / tồn / mã giảm giá tính lại ở ERP, khách tìm theo SĐT. Sửa sản phẩm, giá, tồn kho, bài viết, menu ở ERP → webhook báo website làm mới ngay |
| Trợ lý AI (Claude) | Mỗi người tự tạo **khóa truy cập cá nhân** (7/30/90/365 ngày, thu hồi được); Claude Desktop cắm vào ERP qua MCP server `mcp/` với 17 công cụ: báo cáo, tìm sản phẩm / đơn / khách, hàng sắp hết, đổi giá hàng loạt (luôn xem trước), bày sản phẩm lên website, tạo mã giảm giá, viết bài, giao việc. AI có đúng quyền của chủ khóa; khóa không quản lý được người dùng / vai trò / khóa / mật khẩu |
| Cài đặt | Thông tin cửa hàng + chính sách đổi trả (in trên báo giá), phòng ban, kho hàng, bật / tắt ứng dụng trên màn hình chính, quy tắc đánh số chứng từ |
| Đánh số chứng từ | Bộ đếm riêng từng kỳ - nhập chứng từ lùi ngày không bị trùng số |
| Người dùng | Danh sách, lọc theo phòng ban / vai trò / trạng thái; tạo tài khoản (mật khẩu ban đầu có nút sinh ngẫu nhiên); sửa thông tin, phòng ban, vai trò (quyền mới có hiệu lực ngay); khóa / mở khóa (đăng xuất khỏi mọi thiết bị); đặt lại mật khẩu |
| Đổi mật khẩu | Nút chìa khóa trên thanh trên cùng; các thiết bị khác bị đăng xuất, thiết bị hiện tại vẫn dùng tiếp |
| Quy tắc an toàn | Không tự khóa / tự đổi vai trò của mình; chỉ quản trị hệ thống mới sửa được tài khoản quản trị hệ thống và gán vai trò hệ thống |
| Vai trò & quyền | Ma trận: hàng = ứng dụng, cột = Xem / Tạo / Sửa / Xóa / Duyệt / Xuất + quyền đặc thù + phạm vi dữ liệu. Tạo, sửa, nhân bản, xóa (chỉ khi không ai giữ). Sửa xong người giữ vai trò nhận quyền mới ngay |
| Chống leo thang đặc quyền | Người không phải quản trị hệ thống: không sửa được vai trò mình đang giữ, chỉ cấp được quyền mình có với phạm vi không rộng hơn; phạm vi "Mọi công ty" chỉ quản trị hệ thống cấp |
| Dữ liệu | Tự lọc theo công ty, tự ghi audit, chống ghi đè khi 2 người cùng sửa (409) |
