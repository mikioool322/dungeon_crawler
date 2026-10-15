class_name LootGrant
extends RefCounted

## Transfer object of one loot award (ADR-009).
##
## Invariants:
## - A grant is *what* is awarded plus *the stable key* that makes it idempotent;
##   it carries no Node and no `RewardDefinition` reference, so it can be rebuilt
##   from persisted data (the key) without the content resources.
## - `grant_key` is the only identity of a grant. It is built by `key_for()` from the
##   stable world id and the per-placement `loot_source_id`, never from a node name,
##   display name or asset path.
## - A usable grant awards at least one item or gold: a grant that awards neither is
##   rejected by `is_valid()` instead of silently consuming its key.
## - `LootService.grant()` treats the codes it returns as the only result channel;
##   a grant never mutates the session by itself.
## - `scope` decides the ledger the key is checked against (ADR-012, ADR-013):
##   `SCOPE_RUN` is repeatable and idempotent per dungeon run (a transient ledger, so
##   ordinary rewards never accumulate in the save), `SCOPE_STORY` is one-time and
##   idempotent per save (the persistent ledger).

## Repeatable reward: claimable once per dungeon run, never persisted.
const SCOPE_RUN: StringName = &"run"

## One-time story reward: claimable once per save, persisted in the session.
const SCOPE_STORY: StringName = &"story"

## Stable idempotency key, `<world_id>/<loot_source_id>`.
var grant_key: StringName = &""

## Ledger this key is checked against: `SCOPE_RUN` (default) or `SCOPE_STORY`.
var scope: StringName = SCOPE_RUN

## Run that produced the grant; 0 means "do not check the run identity". When set, the
## service refuses a grant from a run that is no longer current.
var run_id: int = 0

## Content id of the `RewardDefinition` this grant came from; informational.
var reward_id: StringName = &""

## Content id of the item to award; empty for a gold-only grant.
var item_id: StringName = &""

## Copies of `item_id` to award; 0 when no item is granted.
var item_count: int = 0

## Gold to award; >= 0.
var gold: int = 0


## Builds the documented `<world_id>/<loot_source_id>` key.
##
## Returns an empty key when either part is empty: a half-built key would collide
## across worlds or loot sources (`"/enemy.a"`), and an empty key is rejected by
## `is_valid()`, so the caller learns about the authoring mistake.
static func key_for(world_id: StringName, loot_source_id: StringName) -> StringName:
	if world_id == &"" or loot_source_id == &"":
		return &""
	return StringName("%s/%s" % [world_id, loot_source_id])


## Copies a reward's numbers into a grant. Returns null when `reward` is null.
##
## The item is carried as its stable id, not as the resource reference: the service
## resolves it through the content registry, so a hand-authored reward and a loaded
## .tres go through exactly the same path.
##
## `scope` defaults to `SCOPE_RUN`: scene rewards (drops, chests) are repeatable per
## dungeon run. Story rewards must pass `SCOPE_STORY` explicitly.
static func from_reward(
	grant_key: StringName,
	reward: RewardDefinition,
	scope: StringName = SCOPE_RUN
) -> LootGrant:
	if reward == null:
		return null
	var grant := LootGrant.new()
	grant.grant_key = grant_key
	grant.scope = scope
	grant.reward_id = reward.id
	if reward.item != null:
		grant.item_id = reward.item.id
		grant.item_count = reward.item_count
	grant.gold = reward.gold
	return grant


## True when the grant can be applied as a single atomic award.
func is_valid() -> bool:
	if grant_key == &"":
		return false
	if scope != SCOPE_RUN and scope != SCOPE_STORY:
		return false
	if run_id < 0:
		return false
	if gold < 0:
		return false
	if item_id == &"":
		return item_count == 0 and gold > 0
	return item_count >= 1


func is_story_scope() -> bool:
	return scope == SCOPE_STORY


func _to_string() -> String:
	return "LootGrant(%s, scope=%s, reward=%s, item=%s x%d, gold=%d)" % [
		grant_key, scope, reward_id, item_id, item_count, gold
	]
