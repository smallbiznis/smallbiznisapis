# SmallBiznis SaaS Roadmap

Dokumen ini merangkum gap fitur dan rencana pekerjaan yang direkomendasikan untuk
mendukung visi proyek SaaS multi-tenant: Online Store, Point of Sale, Loyalty,
Voucher, serta Rule Engine.

## 1. Pondasi Multi-Tenant
- **Konsistensi metadata tenant.** `InventoryItem` belum membawa `org_id`
  sehingga identitas tenant hanya ada di request (`CreateInventoryItemRequest`,
  `GetVariantInventoryRequest`, dll). Tambahkan `org_id` pada resource inti dan
  event seperti `InventoryItem` agar data denormalized ini aman direplikasi ke
  search/cache layer.【F:smallbiznis/inventory/inventory.proto†L13-L49】
- **Lifecycle organisasi.** `OrganizationService` sudah mencakup API onboarding,
  lokasi, dan anggota, tetapi belum ada mekanisme provisioning default (misal
  channel, pricebook, workflow). Tambahkan workflow provisioning asynchronous
  setelah `CreateOrganization` atau `CreateLocation` dipanggil.【F:smallbiznis/organization/v1/organization.proto†L32-L188】
- **Channel multi-lokasi.** `SalesChannel` belum menyimpan `org_id`, sehingga
  channel antar tenant bisa saling bertabrakan. Sertakan `org_id` dan tambah API
  create/update supaya channel per tenant bisa dikustomisasi.【F:smallbiznis/channel/channel.proto†L16-L112】

## 2. Online Store
- **Katalog & kategori.** `ProductService` sudah memiliki CRUD dasar produk dan
  varian namun belum ada model kategori/collection, pricebook, serta publis
  status per channel. Tambahkan entity `Collection`, relasi produk-channel, dan
  pengaturan harga khusus channel.【F:smallbiznis/product/product.proto†L213-L510】
- **Inventori realtime.** Pertahankan SSE `VariantStockEventService` tetapi
  tambahkan cursor checkpoint & retry guideline di dokumentasi klien. Pertimbangkan
  history endpoint untuk audit per varian di channel web.【F:smallbiznis/product/product_events.proto†L12-L66】
- **Checkout & order.** Repositori belum memiliki proto Order/Checkout. Tambahkan
  domain Order (cart, payment, shipment) dan integrasi ke InventoryService untuk
  reserve stock pada saat checkout, plus posting ke Ledger untuk pencatatan
  finansial.【F:smallbiznis/inventory/inventory.proto†L62-L210】【F:smallbiznis/ledger/v1/ledger.proto†L26-L150】

## 3. Point of Sale (POS)
- **Registrasi device & shift.** Tambahkan service POS untuk mencatat register,
  shift, kasir, dan penutupan kas. Gunakan `ChannelService` agar POS lokasi
  tertentu dapat diaktifkan/ditonaktifkan.【F:smallbiznis/channel/channel.proto†L16-L112】
- **Transaksi offline-first.** Definisikan proto `PosOrder` dengan status sinkron,
  payment breakdown, dan fallback untuk offline. Integrasikan ke `LedgerService`
  guna menutup kas dan mem-posting penjualan kasir.【F:smallbiznis/ledger/v1/ledger.proto†L26-L150】

## 4. Loyalty
- **Pra-perhitungan dan simulasi.** `PointService` menyediakan earning dan
  redemption, tetapi belum ada endpoint preview/riwayat. Implementasikan
  `EarningPreview`, `ListTransactions`, dan `ListBalances` per tenant agar member
  dapat melihat riwayat akrual. Gunakan `TransactionAttributes` sebagai sumber
  filter (channel, brand, outlet).【F:smallbiznis/loyalty/v1/loyalty.proto†L33-L245】
- **Tier & expiry.** Tambahkan model tier membership, aturan expiry poin, serta
  background job untuk melakukan expirations dan mengirim notifikasi (melalui
  WorkflowService).【F:smallbiznis/workflow/v1/workflow.proto†L247-L393】

## 5. Voucher & Kampanye
- Belum ada proto voucher. Buat `VoucherService` dengan tipe single-use,
  multi-use, dan bulk, termasuk API generate code, assign ke member, redeem,
  serta integrasi dengan Loyalty & Workflow untuk kampanye gabungan.
- Tambahkan entity `Promotion` yang dapat mengikat voucher, rule engine, dan
  channel (misal voucher hanya berlaku di ONLINE atau POS). Hubungkan dengan
  `SalesChannel` dan `NodeAction.REWARD_VOUCHER`.【F:smallbiznis/channel/channel.proto†L16-L112】【F:smallbiznis/workflow/v1/workflow.proto†L290-L343】

## 6. Rule Engine & Workflow
- `WorkflowService` sudah memiliki node trigger/condition/action namun belum ada
  tipe data terstruktur untuk action parameters. Definisikan message spesifik
  (misal `RewardPointAction`, `VoucherAction`, `NotificationAction`) lalu gunakan
  `oneof` di `NodeAction` agar validasi schema lebih ketat.【F:smallbiznis/workflow/v1/workflow.proto†L247-L343】
- Tambahkan evaluasi real-time untuk event transaksi (sinkron) dan scheduled job
  (async). Integrasikan ke Loyalty `Earning` dan Voucher redeem untuk memastikan
  rule dapat memblok atau mengubah reward sebelum disimpan.【F:smallbiznis/loyalty/v1/loyalty.proto†L40-L115】

## 7. Observabilitas & Compliance
- Standarisasi penggunaan `google.protobuf.Timestamp` untuk `created_at` dan
  `updated_at` di semua message (beberapa request masih menerima timestamp dari
  klien). Dorong server-side timestamps untuk audit trail.【F:smallbiznis/product/product.proto†L76-L118】【F:smallbiznis/inventory/inventory.proto†L22-L32】
- Tambahkan metadata audit (misal `actor_id`, `source_channel`) pada event besar
  seperti `VariantStockEvent` agar debugging multi-channel lebih mudah.【F:smallbiznis/product/product_events.proto†L21-L66】

## 8. Dokumentasi & DX
- Lengkapi komentar OpenAPI (summary/description) yang masih kosong dan
  definisikan security scheme Bearer agar dokumentasi siap digunakan di portal
  developer.【F:smallbiznis/loyalty/v1/loyalty.proto†L14-L115】
- Tambahkan contoh payload JSON dan sequence diagram di README untuk alur
  penting (checkout online, penjualan POS, earning poin, redeem voucher).
