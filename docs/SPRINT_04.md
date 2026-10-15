# Sprint 04 — RPG foundations: stats, equipment, NPC, trading (plan of record)

Status: approved after the architecture audit; executed with `architect`, `gameplay-engineer`,
`godot-specialist`, `qa-engineer` and `reviewer` roles. ADR-015/016/017 plus the ADR-005 Sprint 04
addendum record the decisions. Baseline: `master` at `6f5b627`, 440 tests / 3510 assertions PASS.

## Goal

Hub → open the inventory screen → see base stats → visit the merchant NPC → dialogue → shop → buy a
sword (gold down, sword in the bag) → equip it (attack damage rises) → enter dungeon 01 → fight with
the equipped weapon's damage → kill → loot → return → sell the loot → equip armour (defense rises) →
save at the shrine → relaunch → equipment, gold and dungeon progress are restored. Dungeon 01 → 02
progression, repeatable runs and first-clear rewards keep working.

Out of scope: procedural generation, magic, skill trees, crafting, random affixes, durability,
multi-currency, reputation, dialogue trees, quest framework, final art/animation/UI, multiplayer,
backend, autosave, persistent dungeon world state.

## Three lifetimes (unchanged rule)

| Kind | Type | Owner | Persisted |
|------|------|-------|-----------|
| Static content | `PlayerDefinition`, `ItemDefinition` (extended), `MerchantDefinition`, `NpcDefinition` | `ContentManifest` buckets | as content |
| Durable runtime | `PlayerSessionState.equipment` (`EquipmentState`) | `GameSession` | yes, save v3 `equipment` |
| Derived runtime | `CharacterStats` (base + modifier buckets) | `GameSession.stats` | **never** — recomputed from the definition + equipment |

## Contracts (frozen)

```gdscript
class_name PlayerDefinition extends Resource       # core/stats/player_definition.gd
@export id, display_name, max_health=100.0, attack_damage=34.0, defense=0.0, movement_speed=4.0
@export attack_definition: AttackDefinition        # profile used when no weapon overrides it
func validation_errors()/is_valid()

class_name CharacterStats extends RefCounted       # core/stats/character_stats.gd
signal changed()
const MAX_HEALTH/ATTACK_DAMAGE/DEFENSE/MOVEMENT_SPEED; const STATS; const MINIMUM
func setup(definition) -> bool                     # false => is_ready() == false, consumers must not overwrite rig values
func is_ready() -> bool; func base(stat)/effective(stat)/modifier_total(stat) -> float
func set_modifiers(source_id, modifiers) -> bool   # REPLACE per source, never accumulate
func clear_modifiers(source_id) -> bool; func has_source(source_id) -> bool; func sources()

class_name EquipmentSlot extends RefCounted        # core/equipment/equipment_slot.gd
enum Id { NONE, MAIN_HAND, CHEST_ARMOR }; const SUPPORTED; const NAMES
static func name_of(slot)/from_name(name)/is_supported(slot)/supported_names()

class_name EquipmentState extends RefCounted       # core/equipment/equipment_state.gd  (ownership A)
signal changed()
const CODE_OK/CODE_UNKNOWN_ITEM/CODE_NOT_EQUIPPABLE/CODE_WRONG_SLOT/CODE_NOT_OWNED/CODE_SLOT_EMPTY/CODE_NOT_READY
func setup(registry, inventory) -> void; func is_ready() -> bool
func can_equip(item_id, slot)/equip(item_id, slot)/unequip(slot) -> StringName
func get_equipped(slot)/is_equipped(item_id)/equipped_slots()/equipped_entries()
func modifiers_by_source() -> Dictionary           # slot name -> additive modifiers (bucket per slot)
func weapon_attack_definition() -> AttackDefinition
func to_save_dict()/static from_save_dict(data, registry, inventory)

class_name MerchantDefinition extends Resource     # core/content/merchant_definition.gd
@export id, display_name, greeting, stock: Array[ItemDefinition]
func validation_errors()/is_valid()

class_name NpcDefinition extends Resource          # core/content/npc_definition.gd
@export id, display_name, greeting, merchant: MerchantDefinition (nullable)

class_name NpcInteractable extends Interactable    # systems/interaction/npc_interactable.gd
signal dialogue_requested(npc: NpcDefinition)
@export npc: NpcDefinition
# knows nothing about gold, the bag, the save or the player controller; the HUD opens the dialogue

class_name TradingService extends RefCounted       # systems/trade/trading_service.gd
signal trade_completed(kind, item_id, price, gold_total)
const CODE_OK/CODE_UNKNOWN_ITEM/CODE_NOT_TRADABLE/CODE_NO_STOCK/CODE_NOT_ENOUGH_GOLD/CODE_NOT_IN_BAG/CODE_EQUIPPED/CODE_INVALID
const SELL_RATE := 0.5                             # the only price rule
func setup(state, registry, equipment) -> void
func bind_merchant(merchant) -> void               # fresh TRANSIENT stock
func buy_price(item_id)/sell_price(item_id)/stock_of(item_id) -> int
func can_buy(item_id)/buy(item_id)/can_sell(item_id)/sell(item_id) -> StringName

# ItemDefinition (extended): slot, attack_bonus, defense_bonus, max_health_bonus, movement_bonus,
# attack_definition (weapons: reach/timings only), base_value (merchant price); equipment_modifiers()
# HealthComponent: set_max_health(value) (clamps current, never heals), defense_provider
# AttackController: set_stats(stats), set_attack_profile(profile) -> pins profile AND damage at swing start
```

## Decisions (ADR-015/016/017 + ADR-005 addendum)

| Area | Decision |
|------|----------|
| Stats model | `effective = max(MINIMUM[stat], base + Σ buckets)`, additive only; one bucket per equipment slot (replacing a bucket is how a swap removes the old bonus); non-finite/unknown values ignored with a warning; `changed` only on a real difference |
| Ownership | **A**: an equipped item leaves the bag (`equip` removes one copy, `unequip` returns it, a swap returns the old one); `is_equipped(id) ⇒ count_of(id) == 0` is the local invariant; selling an equipped item is impossible by construction |
| Combat damage | The stats owner's damage = `effective(ATTACK_DAMAGE)`; an actor without stats (every enemy) keeps `profile.damage`; a weapon profile owns reach/arc/timings only and validates `damage == 0` |
| Swing snapshot | `request_attack()` pins the profile **and** the damage value, so a mid-swing weapon change cannot alter reach, timing or damage; the cooldown of the finished swing comes from the same pin |
| Defense | Receiver-side mitigation in `HealthComponent`: `amount * (100 / (100 + defense))`, defense >= 0, never zero damage for a positive hit; `defense == 0` is byte-identical to today |
| Max HP | `set_max_health()` raises the ceiling without healing and clamps current HP down without emitting `died`; the spawn path applies stats **after** `add_child` (the component resets to the scene max in `_ready`) |
| Movement | `PlayerController.move_speed` is overwritten from `effective(MOVEMENT_SPEED)` when stats are ready; the scene value (4.0) is the shipped default |
| Trading | One price rule (`buy = base_value`, `sell = max(1, floor(base_value * 0.5))`); transient per-merchant stock (never saved); every operation re-validates internally and is atomic (validation → bag → gold → stock → signal) |
| NPC | `NpcDefinition` + `NpcInteractable` emit `dialogue_requested`; the HUD opens a dialogue panel with the greeting and an optional shop button; the NPC never touches gold, the bag, the save or the player |
| Save | v3 adds an optional `equipment` map (stable slot names → item ids); `MIGRATIONS[2]` adds an empty section (no invented items); the equipment record is authoritative on load and a bagged duplicate is removed; unknown ids/slots are dropped with warnings |
| Input | ADR-005 addendum: the `inventory` action (TAB) opens/closes the inventory panel; `ui_cancel` closes any open panel; the lock tests are updated |

## Ownership and writers

| State | Writer |
|-------|--------|
| `CharacterStats` | `GameSession` (build from the definition, apply `EquipmentState.modifiers_by_source()` per slot) |
| `EquipmentState` | `GameSession.equip_item()/unequip_slot()` only (the panel calls those operations) |
| gold | `LootService` (rewards) and `TradingService` (trade) — both emit, `GameSession` re-emits `gold_changed` |
| inventory | `LootService` (rewards), `EquipmentState` (equip/unequip), `TradingService` (trade) |
| rig values (max HP, speed, profile) | `WorldRouter`/`GameSession` at spawn and on `stats.changed` |
| UI panels | read models, call explicit session operations, own no state |

## Work items

| ID | Deliverable | Owner | State |
|----|-------------|-------|-------|
| W0 | Contracts: ADR-015..017 + ADR-005 addendum, this plan, the `inventory` action + lock tests | coordinator | in progress |
| W1 | Domain: `PlayerDefinition`, `CharacterStats`, `EquipmentSlot`, `EquipmentState`, `ItemDefinition` extensions | coordinator | in progress |
| W2 | Combat integration: swing snapshot, damage/defense providers, `set_max_health`, viewmodel weapon swap | coordinator | planned |
| W3 | Session integration: equipment in the session, equip/unequip operations, stats application on spawn, save v3 | coordinator | planned |
| W4 | Content: `player.default`, two swords, armour, junk item, merchant, NPC, manifest buckets | coordinator | planned |
| W5 | NPC interactable + `TradingService` + world host binding + hub placement | coordinator | planned |
| W6 | UI: inventory/equipment/stats panel + dialogue/shop panel + HUD wiring | `godot-specialist` | planned |
| W7 | Tests: domain suites, E2E loop, Sprint 01-03 regression | coordinator + `qa-engineer` | planned |
| W8 | Independent review + fixes + re-validation | `reviewer` | planned |

## Acceptance criteria

Stats: base + per-slot buckets; repeated equip never stacks; non-finite values ignored; clamps keep
HP/attack/defense >= 0 and speed > 0; `changed` only on a real difference; an invalid definition
leaves `is_ready() == false` and the spawn path then does not touch the rig.
Equipment: equip a bagged item, reject an unowned one, reject a wrong slot, reject a non-equippable
item, swap returns the old item, unequip returns the item, the local invariant holds, save round trip
is stable, a damaged record is handled (unknown id/slot dropped, slot mismatch returned to the bag).
Combat: damage depends on the weapon, defense changes the received damage, a swing uses one pinned
snapshot, a weapon change cannot bypass the cooldown, evasion by leaving reach still works, the
dungeon objective still completes, every Sprint 01-03 combat test passes unchanged.
NPC: interaction opens the dialogue, out of reach and through a wall are refused, closing restores
control, the shop opens from the dialogue.
Trading: buy/sell gold and items, insufficient gold refused, unowned item refused, equipped item
refused, duplicate UI events cannot duplicate anything, invalid ids and invalid prices refused, a
failed transaction leaves no partial change, gold never goes negative.
Save: v3 stores/restores equipment, effective stats are recomputed deterministically, v1 and v2
migrate, DungeonProgress and first-clear claims survive, a corrupt save is handled, backup recovery
still works, unknown item ids cannot crash the load.
Integration: buy → equip → fight; loot → sell; equip → save → relaunch → load; dungeon 01 → 02;
repeatable runs still reset ordinary loot; the first-clear reward stays one-time; exactly one world
and one player rig everywhere; no ObjectDB leaks; every Sprint 01-03 test passes.
Manual/graphical (report NOT RUN when not performed): panel readability, cursor capture/release, no
attacks while a panel is open, buy/sell feel, visible weapon swap.

## Known constraints (Sprint 04)

- No per-instance items: equipment works on item ids (ownership A), so two copies of the same id are
  interchangeable.
- Merchant stock is transient: reloading resets stock and gold together, so no buy/sell loop exists.
- Effective stats are never saved; they are recomputed from the definition plus the equipment.
- The merchant sells from the hub only; dungeons have no vendors in Sprint 04.
- `NpcDefinition` ships with one greeting line and an optional shop; dialogue trees are out of scope.
