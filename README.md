# Smallbiznis APIs

## Variant stock event streaming

Realtime inventory updates are now exposed through the
`VariantStockEventService.SubscribeVariantStock` server-side stream. The gRPC
stream is bridged to HTTP via the gateway so that admin clients can establish
an SSE connection using the following endpoint:

```
GET /api/v1/orgs/{org_id}/variant-stock:subscribe
```

Query parameters can be used to filter specific variant or location IDs
(`variant_ids` and `location_ids`) and to resume from a cursor. When the
`include_snapshot` flag is provided, the first message includes the current
`VariantStock` state before live deltas are pushed.

Every successful stock mutation (`UpdateVariantStock`, `AdjustInventory`, and
`TransferInventory`) publishes a `VariantStockEvent`. Event payloads contain
the delta quantities, the latest stock snapshot, and metadata such as
`event_type`, `occurred_at`, and `correlation_id` so consumers can reconcile
state changes.
