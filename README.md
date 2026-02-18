FREE SCRIPT https://siik-scripts-store.tebex.io/package/7290110

# SiiK-H-portable-crafting (FULL + Anti-Dupe)

This build includes:
- Blueprint NUI (X/Y ingredient counts, glow rows, ruler progress, ink-line draw animation)
- Items + Weapons benches (separate props, qb-target)
- Weapon serial preview (reserved token used for craft)
- XP/Levels (max 100) saved to SQL
- Persistent placed tables across restarts
- Busy crafting lock + cancel (move away / damage)
- Anti-dupe: server-authoritative placement, rate limits, output-fail refund, stacking prevention, table limit per player

## Install
1) Import `sql.sql`
2) Add items in qb-core/shared/items.lua:
```lua
['portable_crafting_table'] = { ['name'] = 'portable_crafting_table', ['label'] = 'Portable Crafting Table', ['weight'] = 5000, ['type'] = 'item', ['image'] = 'portable_crafting_table.png', ['unique'] = false, ['useable'] = true, ['shouldClose'] = true, ['combinable'] = nil, ['description'] = 'Placeable crafting table' },
['portable_weapon_bench']   = { ['name'] = 'portable_weapon_bench', ['label'] = 'Portable Weapons Bench', ['weight'] = 7000, ['type'] = 'item', ['image'] = 'portable_weapon_bench.png', ['unique'] = false, ['useable'] = true, ['shouldClose'] = true, ['combinable'] = nil, ['description'] = 'Placeable weapon bench' },
```
3) Put images into qb-inventory/html/images/
4) ensure the resource

## Notes
- Placement item is only removed on confirmed placement (anti-dupe).
- Cancel placement calls server CancelPlacement (no refunds needed).


SiiK Scripts – Terms & Conditions 2026

By purchasing or downloading any product from SiiK Scripts, you agree to the following:
You are purchasing a license to use, not ownership of the script.
Scripts are licensed for one (1) FiveM server per purchase unless stated otherwise.
Reselling, sharing, redistributing, or leaking any SiiK Scripts product is strictly prohibited.
Editing, modifying, decompiling, or removing credits is not allowed without written permission from SiiK Scripts.
Scripts may not be used in paid bundles or commercial redistribution.
Unauthorized use, redistribution, or modification will result in immediate license termination with no refund.
All products are provided as-is. Support is only provided to verified purchasers.
By completing your purchase or download of free asset, you confirm that you agree to these Terms & Conditions. 
