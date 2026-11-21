# Website bán hàng mẫu (Next.js) - đọc dữ liệu từ MyERP

Website **không có database riêng**: mọi trang lấy dữ liệu từ ERP qua `/api/public/...`.
Sửa sản phẩm, giá, tồn kho, mô tả, bài viết, trang, menu, hotline... ở ERP là website đổi theo.

```
Trình duyệt khách ──► Next.js (máy chủ, giữ khóa bí mật) ──X-Site-Key──► MyERP /api/public/*
                                  ▲
        ERP sửa dữ liệu ──webhook POST /api/revalidate──┘  (làm mới đúng nhóm trang ngay lập tức)
```

## Chạy thử

1. Chạy backend ERP (cổng 5121).
2. Vào ERP → **Website → Kết nối website**:
   - bấm **Tạo khóa API** (chỉ hiện 1 lần, chép ngay),
   - nhập webhook `http://localhost:3000/api/revalidate` → **Lưu** để có mật khẩu webhook,
   - bấm **Chép cả 3 dòng** ở mục 3.
3. Tạo file `storefront/.env.local`, dán 3 dòng vừa chép (mẫu: `.env.example`).
4. Chạy:
   ```powershell
   cd storefront
   npm install
   npm run dev
   ```
   Mở http://localhost:3000. Thử đổi giá 1 sản phẩm trong app Kho rồi tải lại trang sản phẩm.

Mỗi website (VD MyStyle Fashion, MyStyle Sneaker) dùng **chung mã nguồn này**, chỉ khác `.env.local` (khóa của website đó)
và giao diện bạn tự sửa. Website nào bán mẫu nào, giá riêng, nổi bật: chọn ở ERP → Website → Sản phẩm trên web.

## Các trang

| Đường dẫn | Nội dung | Lấy từ ERP |
|---|---|---|
| `/` | Trang chủ: khẩu hiệu, danh mục, sản phẩm nổi bật, bài viết mới | `site`, `products?featured=true`, `posts` |
| `/san-pham?category=&sort=&q=` | Danh sách, lọc danh mục, tìm, sắp xếp | `products` |
| `/san-pham/[slug]` | Chi tiết: chọn màu / size (hết hàng làm mờ), thêm giỏ, sản phẩm liên quan | `products/{slug}` |
| `/gio-hang` | Giỏ hàng (lưu ở trình duyệt), mã giảm giá, form đặt hàng | `promotions/check`, `orders` |
| `/blog`, `/blog/[slug]` | Bài viết | `posts` |
| `/pages/[slug]` | Trang tĩnh (Giới thiệu, Chính sách đổi trả...) | `pages/{slug}` |
| `/lien-he` | Form liên hệ → ERP > Website > Liên hệ từ web | `contact` |

## Quy tắc quan trọng

- `lib/erp.js` chỉ dùng ở **phía máy chủ** (Server Component, Route Handler). Không import vào file có `'use client'` -
  khóa `ERP_SITE_KEY` sẽ lộ ra trình duyệt.
- Form trong trình duyệt gửi về route của Next.js (`app/api/order`, `app/api/contact`, `app/api/promo`), route này mới gọi ERP.
- Giá trong giỏ chỉ để hiển thị: **ERP tính lại giá, tồn kho, phí ship, mã giảm giá** khi đặt hàng.
- Đơn từ website vào app Đơn hàng ở trạng thái **Nháp**, kênh *Website* - shop gọi xác nhận rồi bấm Xác nhận như đơn thường.
- Mỗi fetch gắn tag `site` / `products` / `posts` / `pages`. ERP báo thay đổi → `app/api/revalidate` gọi `revalidateTag`.
  Webhook lỗi thì trang vẫn tự làm mới sau 5 phút (`REVALIDATE_SECONDS` trong `lib/erp.js`).
- Màu chủ đạo, tên, logo, hotline, phí ship lấy từ ERP → Website → Tổng quan → Thông tin website.

## Đưa lên mạng

Deploy như mọi app Next.js (Vercel, VPS với `npm run build && npm start`...). Đặt 3 biến môi trường như `.env.local`,
`ERP_API_URL` là địa chỉ public của backend ERP (nên dùng https). Ở ERP sửa webhook thành `https://ten-mien-that/api/revalidate`.
