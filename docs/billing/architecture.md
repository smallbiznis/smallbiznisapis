
# 🧾 SmallBiznis Core Billing Engine — Architecture

Dokumen ini menjelaskan arsitektur **Core Billing Engine** SmallBiznis berbasis gRPC/protobuf yang dirancang **enterprise-ready**, compatible dengan:

- **Multi-meter pricing** (mirip Stripe / AWS Billing),
- **Usage-based billing**,
- **Subscription lifecycle**,
- **Tax, credit dan payment orchestration**.

Fokus dokumen ini:

- Menjelaskan **peran masing-masing service/proto**
- Menjelaskan **data flow end-to-end**
- Menjadi **satu sumber referensi** untuk semua engineer (BE, FE, DevOps, QA) dan product.

Repo target:
`smallbiznisapis/docs/billing/architecture.md`

---

## Daftar Isi

1. [Prinsip Desain Utama](#1-prinsip-desain-utama)
2. [Daftar Proto &amp; Layanan](#2-daftar-proto--layanan)
   - [Pricing Service (`pricing.proto`)](#21-pricing-service-pricingproto--locked)
   - [Subscription Service (`subscription.proto`)](#22-subscription-service-subscriptionproto)
   - [Usage Service (`usage.proto`)](#23-usage-service-usageproto)
   - [Billing Service (`billingproto`)](#24-billing-service-billingproto)
   - [Rating Service (`ratingproto`)](#25-rating-service-ratingproto)
   - [Invoice Model &amp; Service (`invoiceproto`)](#26-invoice-model--service-invoiceproto)
   - [Invoice Engine (`invoice_engineproto`)](#27-invoice-engine-invoice_engineproto)
   - [Tax Service (`taxproto`)](#28-tax-service-taxproto)
   - [Credit Service (`creditproto`)](#29-credit-service-creditproto)
   - [Payment Service (`paymentproto`)](#210-payment-service-paymentproto)
3. [Alur Data Utama](#3-alur-data-utama)
   - [Subscription &amp; Trial Initialization](#31-subscription--trial-initialization)
   - [Usage Ingestion](#32-usage-ingestion)
   - [Rating (Usage → Charge)](#33-rating-usage--charge)
   - [Invoice Build &amp; Finalization](#34-invoice-build--finalization)
   - [Payment &amp; Settlement](#35-payment--settlement)
4. [Diagram Arsitektur](#4-diagram-arsitektur)
   - [Context Diagram](#41-context-diagram)
   - [Sequence Diagram Billing Cycle](#42-sequence-diagram-billing-cycle)
5. [Catatan Implementasi &amp; Konvensi](#5-catatan-implementasi--konvensi)

---

## 1. Prinsip Desain Utama

1. **Single source of truth untuk pricing**Semua aturan harga disimpan di **`pricing.proto`**:

   - `Plan` + `Plan.meters[]`
   - `PlanMeter.metric_code`, `pricing_model`, `tiers`, `included_units`, `overage_unit_price_cents`
   - **Tidak ada service lain** yang mendefinisikan pricing kedua.
2. **Subscription sebagai pusat lifecycle billing**

   - Subscription menghubungkan **tenant ↔ plan**,
   - Menyimpan status (TRIALING/ACTIVE/PAST_DUE/dll),
   - Menjadi key utama untuk seluruh billing (usage, rating, invoice, payment).
3. **Usage-first billing**

   - Semua konsumsi (API calls, workflows, dsb) dicatat di **UsageService**,
   - Per **`subscription_id` + `metric_code`** dengan precision double.
4. **Rating terpisah dari invoicing**

   - **RatingService** menghitung charge per metric berdasarkan usage + pricing,
   - **InvoiceEngine** membangun line item, tax, discount, credit dan invoice final.
5. **`Money` sebagai tipe uang standar**

   - Semua nilai uang menggunakan **`smallbiznis.common.Money`**,
   - Menghindari `int64_cents` tersebar di mana-mana dan bug konversi.
6. **Event/BUS oriented**

   - Proto tidak mendefinisikan outbox,
   - Diasumsikan integrasi antar service via BUS (Kafka/NATS dsb),
   - Contoh event: `SubscriptionCreated`, `BillingCycleDue`, `InvoiceFinalized`, `PaymentSucceeded`.

---

## 2. Daftar Proto & Layanan

### 2.1 Pricing Service (`pricing.proto` — LOCKED)

> **Source of Truth Harga & Meter**

**Model utama:**

- `Plan`

  - `id`, `code`, `name`, `description`
  - `pricing_model` (FLAT, METERED, TIERED, PACKAGE)
  - `base_price_cents`
  - `currency_code`
  - `tiers[]` (jika ada level global per plan)
  - `metadata`, `active`, timestamps
- `PlanMeter` (melekat pada Plan)

  - `metric_code` — *e.g.* `"api_calls"`, `"workflow_runs"`
  - `pricing_model`
  - `unit_price_cents`
  - `included_units`
  - `overage_unit_price_cents`
  - `tiers[]` (tier pricing per meter)

**Service:**

- `GetPlan`
- `GetPlanByCode`
- `ListPlans`
- `CreatePlan`

> Semua service lain (Subscription, Rating, InvoiceEngine) **mengonsumsi** definisi ini, bukan menduplikasinya.

---

### 2.2 Subscription Service (`subscription.proto`)

> **Mengelola lifecycle subscription per tenant.**

**Model: `Subscription`**

- `id`
- `tenant_id`
- **Referensi pricing:**
  - `plan_code`
  - `plan_id`
- `status` (`SubscriptionStatus`: ACTIVE, TRIALING, PAST_DUE, CANCELED, TRIAL_EXPIRED, etc)
- `auto_renew`
- `allow_overage_billing`
- Timestamps:
  - `start_at`
  - `current_period_start`, `current_period_end`
  - `trial_start_at`, `trial_end_at`
  - `cancel_at`, `canceled_at`
- `metadata` (Struct)

**Event:**

- `SubscriptionCreatedEvent`
  - `subscription_id`
  - `tenant_id`
  - `plan_code`
  - `trial_days`
  - `occurred_at`

**Service:**

- `CreateSubscription`
- `GetSubscription`
- `ListSubscriptions`
- `CancelSubscription`
- `ChangeSubscriptionPlan`

> Subscription **tidak menyimpan rincian pricing**, hanya referensi ke Plan.

---

### 2.3 Usage Service (`usage.proto`)

> **Menangkap dan mengagregasi usage per subscription & metric.**

**Model:**

- `UsageMetricDefinition`

  - `code`, `name`, `description`
  - `type` (COUNTER / GAUGE)
  - `unit` (e.g. `"calls"`, `"GB"`)
- `UsageRecord` (raw)

  - `id`
  - `tenant_id`
  - `subscription_id`
  - `metric_code` *(selaras dengan `PlanMeter.metric_code`)*
  - `value` (double)
  - `recorded_at`
  - `idempotency_key`
  - `metadata`
- `UsageAggregation`

  - `tenant_id`
  - `subscription_id`
  - `metric_code`
  - `total_value`
  - `window_start`, `window_end`
  - `window_granularity` (`"hour"`, `"day"`, `"month"`)

**Service:**

- `IngestUsage(IngestUsageRequest{record: UsageRecord})`
- `ListUsage`
- `GetUsageSummary` → `UsageAggregation[]`
- `ListUsageMetrics`

> RatingService akan mengambil agregasi usage dari sini untuk dihitung.

---

### 2.4 Billing Service (`billing.proto`)

> **Trial, fast-path balance, & billing period per subscription.**
> Setelah refactor, **tidak lagi mendefinisikan Meter/Pricing sendiri**.

**Model:**

- `TrialStatus`

  - `enabled`, `expired`
  - `trial_balance_cents`
  - `trial_start_at`, `trial_end_at`
- `Balance`

  - `subscription_id`
  - `trial_balance_cents`
  - `updated_at`
- `BillingPeriod`

  - `id`
  - `subscription_id`
  - `period_start`, `period_end`
  - `status` (`OPEN`, `CLOSED`, `INVOICED`)
  - `created_at`, `updated_at`
- `UsageRecord` (di sisi Billing, hasil rating/trial)

  - `id`
  - `subscription_id`
  - `metric_code`
  - `period_id` (kosong = masih trial)
  - `amount` (double, kuantitas usage)
  - `cost_cents` (hasil rating)
  - `trial_balance_left`
  - `metadata`
  - `created_at`

**RPC:**

- `OnSubscriptionCreated`

  - Input: `subscription_id`, `trial_days`
  - Output: `TrialStatus`
  - Dipanggil setelah subscription dibuat untuk inisialisasi trial.
- `RecordUsage`

  - Input: `subscription_id`, `metric_code`, `amount`, `metadata`
  - Output: info `cost_cents`, `trial_balance_left`
  - Mengurangi trial jika masih berlaku, atau menandai usage sebagai billable.
- Query:

  - `GetTrialStatus(subscription_id)`
  - `GetBalance(subscription_id)`
  - `GetCurrentBillingPeriod(subscription_id)`
  - `ListBillingPeriods(subscription_id)`

> BillingService menjadi **pengelola state trial & period**, bukan pricing engine.

---

### 2.5 Rating Service (`rating.proto`)

> **Mengubah usage menjadi charge (per metric).**

**Model:**

- `RatingResultItem`

  - `metric_code`
  - `quantity` (double)
  - `amount_cents` (int64)
  - `currency_code`
  - `metadata` (misalnya detail tier, breakdown paket, dsb.)
- `RatingResult`

  - `subscription_id`
  - `items[]` (`RatingResultItem`)
  - `rated_at`

**Service:**

- `RateSubscription(RateSubscriptionRequest)`
  - Input: `subscription_id`, `period_start`, `period_end`
  - Engine:
    - Ambil agregat usage dari `UsageService`
    - Ambil Plan + PlanMeter dari `PricingService`
    - Apply pricing model per metric
  - Output: `RatingResult`

> Output ini dikonsumsi `InvoiceEngineService.BuildChargesFromRating` atau pipeline invoice lainnya.

---

### 2.6 Invoice Model & Service (`invoice.proto`)

> **Representasi invoice final yang akan dikirim ke customer.**

**Model:**

- `InvoiceLineItem`

  - `id`
  - `invoice_id`
  - `type` (`InvoiceLineItemType`: RECURRING, USAGE, OVERAGE, DISCOUNT, TAX, ADJUSTMENT)
  - `description`
  - `quantity` (double)
  - `unit_price` (`Money`)
  - `amount` (`Money`)
  - `metric_code` (optional, untuk usage-based line)
  - `metadata`
- `TaxBreakdown`

  - `id`, `invoice_id`
  - `name` (*e.g.* `"PPN"`)
  - `rate_percent`
  - `amount` (`Money`)
- `Invoice`

  - `id`
  - `tenant_id`
  - `subscription_id`
  - `invoice_number`
  - `status` (`InvoiceStatus`: DRAFT, PENDING, PAID, OVERDUE, VOID, REFUNDED)
  - `billing_period_start`, `billing_period_end`
  - `issued_at`, `due_at`, `paid_at`, `void_at`
  - `line_items[]`
  - `subtotal`, `discount_total`, `tax_total`, `total`, `amount_paid`, `amount_due` (`Money`)
  - `taxes[]` (TaxBreakdown)
  - `currency_code`
  - `customer_reference`
  - `metadata`
  - `created_at`, `updated_at`

**Service:**

- `GetInvoice`
- `ListInvoices`
- `GenerateInvoiceForSubscription`
  - Untuk scheduler/renewal: generate invoice dari subscription & period (bisa dry-run).
- `GetInvoicePdf`
  - Mengembalikan `pdf_url` (signed URL / internal path).

---

### 2.7 Invoice Engine (`invoice_engine.proto`)

> **Otak komputasi billing: rating → charge → tax/discount/credit → invoice.**

**Snapshot Pricing:**

- `PlanSnapshot`

  - `plan_id`, `plan_code`, `plan_name`
  - `pricing_model`
  - `currency_code`
  - `meters[]` → `MeterPriceSnapshot`
- `MeterPriceSnapshot`

  - `metric_code`
  - `pricing_model`
  - `unit_price_cents`
  - `included_units`
  - `overage_unit_price_cents`
  - `tiers[]` → `TierPriceSnapshot`
  - `metadata`
- `TierPriceSnapshot`

  - `up_to`
  - `unit_price_cents`

**Charge Model:**

- `ChargeComponent`
  - `id`
  - `description`
  - `quantity` (double)
  - `unit_price` (`Money`)
  - `amount` (`Money`)
  - `type` (`InvoiceLineItemType`)
  - `metric_code`
  - `metadata`

**Result Helper:**

- `TaxResult`, `DiscountResult`, `CreditResult`

**RPC Utama:**

- `BuildChargesFromRating`

  - Input:
    - `tenant_id`
    - `subscription_id`
    - `RatingResult`
    - `PlanSnapshot`
  - Output:
    - `line_items[]` (ChargeComponent)
    - `subtotal`
- `BuildInvoice`

  - Input:
    - `tenant_id`
    - `subscription_id`
    - `billing_period_start`, `billing_period_end`
  - Output:
    - `line_items[]`
    - `subtotal`, `discount_total`, `tax_total`, `total`
    - `billing_period_start`, `billing_period_end`
- `RunProration`
- `ApplyTax` (bisa panggil `TaxService` di dalamnya)
- `ApplyDiscount`
- `ApplyCredit`
- `FinalizeInvoice`

  - Input: line_items, taxes, discounts, totals, period
  - Output: `invoice_id`, `invoice_number`, `total`, `amount_due`, `issued_at`
- Period management (opsional):

  - `OpenBillingPeriod`
  - `CloseBillingPeriod`
- `GenerateInvoiceNumber`

> Ini adalah layer yang menyatukan semua: rating, tax, discount, credit → invoice final.

---

### 2.8 Tax Service (`tax.proto`)

> **Maintain katalog dan perhitungan pajak.**

**Model:**

- `TaxRule`
  - `id`
  - `region_code` (`"ID"`, `"SG"`, `"EU-DE"`)
  - `name` (`"PPN"`, `"VAT"`)
  - `rate_percent`
  - `is_default`, `is_active`
  - `created_at`, `updated_at`

**RPC:**

- `ListTaxRules(region_code)`
- `CalculateTax(TaxCalculationRequest{subtotal: Money, country, region})`
  - Output: `TaxCalculationResponse{tax: Money}`

---

### 2.9 Credit Service (`credit.proto`)

> **Merepresentasikan kredit/penyesuaian atas invoice.**

**Model:**

- `CreditNote`
  - `id`
  - `tenant_id`
  - `invoice_id`
  - `type` (`ADJUSTMENT`, `REFUND`, `BALANCE`)
  - `amount` (`Money`)
  - `reason`
  - `metadata`
  - `created_at`

**RPC:**

- `CreateCreditNote(invoice_id, type, amount, reason)`
- `ListCreditNotes(tenant_id, invoice_id)`

> Bekerja berdampingan dengan `InvoiceEngine.ApplyCredit` untuk mengurangi amount due.

---

### 2.10 Payment Service (`payment.proto`)

> **Pengelolaan payment method & charge invoice.**

**Model:**

- `PaymentMethod`

  - `id`
  - `tenant_id`
  - `provider` (STRIPE / XENDIT / MIDTRANS / DUMMY)
  - `type` (CARD / VA / EWALLET)
  - `display_name`, `last4`, `exp_month`, `exp_year`
  - `is_default`
  - `provider_data` (token, VA info, payload provider)
  - `created_at`, `updated_at`
- `PaymentAttempt`

  - `id`
  - `tenant_id`
  - `invoice_id`
  - `payment_method_id`
  - `status` (PENDING, PROCESSING, SUCCEEDED, FAILED, REFUNDED)
  - `provider_transaction_id`
  - `attempted_at`
  - `metadata`

**Service:**

- `ListPaymentMethods(tenant_id)`
- `AttachPaymentMethod(tenant_id, provider, type, provider_payload, set_as_default)`
- `ChargeInvoice(invoice_id, payment_method_id?)`
- `GetPaymentAttempts(invoice_id)`

> Dipanggil setelah invoice final dengan `amount_due` yang jelas.

---

## 3. Alur Data Utama

### 3.1 Subscription & Trial Initialization

1. Tenant memilih Plan (`PricingService.GetPlanByCode`).
2. `SubscriptionService.CreateSubscription`:
   - Menyimpan `Subscription`.
   - Meng-emmit `SubscriptionCreatedEvent`.
3. `BillingService.OnSubscriptionCreated(subscription_id, trial_days?)`:
   - Menginisialisasi `TrialStatus` + `Balance`.
   - Membuka `BillingPeriod` pertama untuk subscription tersebut.

---

### 3.2 Usage Ingestion

1. Aplikasi (workflow, voucher, dsb) memanggil `UsageService.IngestUsage` dengan:
   - `subscription_id`
   - `metric_code`
   - `value`
   - `metadata`
2. Usage disimpan sebagai `UsageRecord` dan diaggregate menjadi `UsageAggregation` untuk periode tertentu.
3. `BillingService.RecordUsage` bisa dipanggil untuk sinkron trial/balance jika ingin fast-path trial deduction.

---

### 3.3 Rating (Usage → Charge)

1. Di akhir billing period (atau by schedule), sistem memanggil:
   - `RatingService.RateSubscription(subscription_id, period_start, period_end)`
2. Rating engine:
   - Query `UsageService.GetUsageSummary` per metric.
   - Query `PricingService.GetPlan` untuk Plan + PlanMeter.
   - Apply pricing model (flat, metered, tiered, package).
   - Hasil: `RatingResult` dengan `RatingResultItem[]`.

---

### 3.4 Invoice Build & Finalization

1. `InvoiceEngineService.BuildChargesFromRating`:

   - Input: `RatingResult` + `PlanSnapshot`.
   - Output: `ChargeComponent[]` dan `subtotal`.
2. Jalur komposisi invoice:

   - `ApplyDiscount` → generate discount components + `total_discount`.
   - `ApplyTax` → hitung pajak via `TaxService.CalculateTax` + tax components + `total_tax`.
   - `ApplyCredit` → mengurangi `amount_due` berdasarkan kredit/balance.
3. `FinalizeInvoice`:

   - Mengambil semua komponen:
     - `line_items` (usage/recurring/overage)
     - `taxes`
     - `discounts`
     - `subtotal`, `discount_total`, `tax_total`, `total`
     - `billing_period_start`, `billing_period_end`
   - Menghasilkan:
     - `invoice_id`
     - `invoice_number`
     - `total`
     - `amount_due`
     - `issued_at`
   - Menyimpan `Invoice` melalui layer persistence (adapter ke `InvoiceService` / DB).
4. `InvoiceService.GenerateInvoiceForSubscription` bisa menjadi façade HTTP/gRPC di atas pipeline ini.

---

### 3.5 Payment & Settlement

1. UI memanggil `PaymentService.ListPaymentMethods(tenant_id)`.
2. Tenant memilih atau membuat metode pembayaran baru via:
   - `AttachPaymentMethod(tenant_id, provider, type, provider_payload)`.
3. Setelah invoice final, UI/backend memanggil:
   - `PaymentService.ChargeInvoice(invoice_id, payment_method_id?)`.
4. PaymentService:
   - Berkomunikasi dengan gateway (Stripe / Xendit / Midtrans).
   - Menyimpan `PaymentAttempt`.
   - Meng-emmit event `PaymentSucceeded` / `PaymentFailed`.
5. Event `PaymentSucceeded` digunakan untuk:
   - Update `Invoice.amount_paid`, `Invoice.status = PAID`.
   - Potensial update ke modul lain (Loyalty, entitlements, dsb).

---

## 4. Diagram Arsitektur

### 4.1 Context Diagram

```mermaid
flowchart LR
    subgraph Tenant
      UI[Console / Tenant Admin]
    end

    subgraph CoreBilling
      PRICING[Pricing Service\n(pricing.proto)]
      SUBS[Subscription Service\n(subscription.proto)]
      BILL[Billing Service\n(billing.proto)]
      USAGE[Usage Service\n(usage.proto)]
      RATING[Rating Service\n(rating.proto)]
      INVENG[Invoice Engine\n(invoice_engine.proto)]
      INV[Invoice Service\n(invoice.proto)]
      TAX[Tax Service\n(tax.proto)]
      CREDIT[Credit Service\n(credit.proto)]
      PAY[Payment Service\n(payment.proto)]
    end

    UI --> SUBS
    UI --> INV
    UI --> PAY

    SUBS --> PRICING
    SUBS --> BILL

    USAGE --> RATING
    RATING --> INVENG
    PRICING --> RATING
    PRICING --> INVENG

    INVENG --> INV
    INVENG --> TAX
    INVENG --> CREDIT

    INV --> PAY
```
