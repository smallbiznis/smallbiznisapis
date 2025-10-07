# Smallbiznis APIs

## Variant stock fields

`VariantStock` responses now include two additional real-time metrics:

* `on_hand_quantity` – the total physical stock stored at a location.
* `incoming_quantity` – quantities that are already inbound from purchase orders or transfers.

Make sure client applications refresh their stock projections using these attributes alongside
`available_quantity` and `reserved_quantity` whenever an `UpdateVariantStock` response is received
or when synchronizing from the Inventory domain service.
