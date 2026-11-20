# MyERP

Hệ thống quản trị doanh nghiệp (ERP/CRM) cho tất cả phòng ban.

| Phần | Công nghệ | Thư mục |
|---|---|---|
| Backend | ASP.NET Core 10 Web API, mô hình **MVC**, trả **JSON** | `backend/` |
| Frontend | **React 19** + Vite + React Router + Axios | `frontend/` |
| Database | SQL Server, 157 bảng, 15 schema | `database/` |

```
Trình duyệt ──► React (frontend/) ──HTTP JSON──► Controller ──► Service ──► AppDbContext ──► SQL Server
                 pages, components               (backend/MyERP.Api)
```

## Chạy dự án

Cần: .NET SDK 10+, Node.js 20+, SQL Server (localhost, Windows Authentication).

```powershell
# 1. Tạo database (chỉ làm 1 lần). Thêm -Demo để có sẵn 15 lead mẫu cho dùng thử
.\database\run_all.ps1 -Demo

# 2. Chạy backend - cửa sổ terminal 1
dotnet run --project backend/MyERP.Api --launch-profile http

# 3. Chạy frontend - cửa sổ terminal 2
cd frontend
npm install        # lần đầu
npm run dev
```

Mở **http://localhost:5173**. Lần đầu sẽ hiện màn hình thiết lập mật khẩu cho tài khoản `admin`.

- Tài liệu API, thử API trực tiếp: http://localhost:5121/docs
- **Database tạo trước ngày 20/11/2026** cần chạy bản nâng cấp: `sqlcmd -S localhost -E -d MyERP -I -f 65001 -i database/migrations/2026-11-20_sequence_counters.sql`
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
| Đánh số chứng từ | Bộ đếm riêng từng kỳ - nhập chứng từ lùi ngày không bị trùng số |
| Người dùng | Danh sách, lọc theo phòng ban / vai trò / trạng thái; tạo tài khoản (mật khẩu ban đầu có nút sinh ngẫu nhiên); sửa thông tin, phòng ban, vai trò (quyền mới có hiệu lực ngay); khóa / mở khóa (đăng xuất khỏi mọi thiết bị); đặt lại mật khẩu |
| Đổi mật khẩu | Nút chìa khóa trên thanh trên cùng; các thiết bị khác bị đăng xuất, thiết bị hiện tại vẫn dùng tiếp |
| Quy tắc an toàn | Không tự khóa / tự đổi vai trò của mình; chỉ quản trị hệ thống mới sửa được tài khoản quản trị hệ thống và gán vai trò hệ thống |
| Vai trò & quyền | Ma trận: hàng = ứng dụng, cột = Xem / Tạo / Sửa / Xóa / Duyệt / Xuất + quyền đặc thù + phạm vi dữ liệu. Tạo, sửa, nhân bản, xóa (chỉ khi không ai giữ). Sửa xong người giữ vai trò nhận quyền mới ngay |
| Chống leo thang đặc quyền | Người không phải quản trị hệ thống: không sửa được vai trò mình đang giữ, chỉ cấp được quyền mình có với phạm vi không rộng hơn; phạm vi "Mọi công ty" chỉ quản trị hệ thống cấp |
| Dữ liệu | Tự lọc theo công ty, tự ghi audit, chống ghi đè khi 2 người cùng sửa (409) |
