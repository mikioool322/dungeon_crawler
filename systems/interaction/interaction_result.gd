class_name InteractionResult
extends RefCounted

## Outcome of one interaction attempt (ADR-008). This is the only channel between
## an `Interactable` and its caller, and the only thing `InteractionController`
## shows to the rest of the game.
##
## Invariants:
## - `code` is a stable, machine-readable id; `message` is display text only and
##   must never be parsed for logic (no i18n, no contract).
## - `succeeded()` is defined as `code == OK`. Every other code is a refusal, so
##   domain detail travels in `code` on the refusal path and in `message` on the
##   success path; a success is never "ok with a failure code".
## - A refusal code is never empty: `rejected(&"")` degrades to `unavailable`,
##   because an empty code tells the caller and the HUD nothing.
## - Results are immutable in practice: subclasses and the caller read them, the
##   factories are the only writers.
##
## Code vocabulary (Sprint 02; keep this list closed):
## - `ok`                  `ok()`: the action completed.
## - `unavailable`         `unavailable()`: no focus, a disabled or used
##                         interactable, a dead interactor, or a re-entrant call.
## - `invalid_destination` `PortalInteractable` without destination ids or without
##                         a travel provider.
## - `not_configured`      `PickupInteractable`/`ChestInteractable` without a loot
##                         binding. (The sprint freeze also offered `unconfigured`;
##                         it is deliberately unused - one word for one case.)
## - `invalid`             the reward/definition cannot be granted. Emitted by the
##                         loot layer and passed through verbatim.
## - router codes          `PortalInteractable` passes the travel provider's code
##                         through verbatim: `busy`, `unknown_world`,
##                         `invalid_world`, `invalid_spawn`, ...
## - loot codes            `PickupInteractable`/`ChestInteractable` pass the
##                         `LootService` codes through verbatim (`invalid`,
##                         `unknown_item`). The two *success* loot codes do not
##                         travel in `code`: see below.
##
## Success messages (code stays `ok`, the domain word rides in `message`):
## - `"granted"` / `"already_collected"` - a pickup or chest grant. The second one
##   means the grant key was already claimed: a harmless re-open, never a second
##   award (ADR-009).
## - `"travel_started"` - the portal handed the request to the router.
## The frozen contract spells these as `ok(<code>)`, which can only mean "a success
## whose display text is the domain code": `ok()` takes a message, and a success
## code other than `OK` would make `succeeded()` report a false failure.

## The only success code. `succeeded()` is exactly this comparison.
const OK: StringName = &"ok"

## Convenience constant for `unavailable()`; the code every refusal defaults to.
const UNAVAILABLE: StringName = &"unavailable"

## Machine-readable outcome.
var code: StringName = &""

## Player-facing text; never parsed.
var message: String = ""


## A successful action. `message` may carry a domain word (see the class docs).
static func ok(message: String = "") -> InteractionResult:
	var result := InteractionResult.new()
	result.code = OK
	result.message = message
	return result


## A refused action. An empty code degrades to `UNAVAILABLE`.
static func rejected(code: StringName, message: String = "") -> InteractionResult:
	var result := InteractionResult.new()
	result.code = code if code != &"" else UNAVAILABLE
	result.message = message
	return result


## Nothing to do: no focus, a guard, or an unbound service.
static func unavailable() -> InteractionResult:
	return rejected(UNAVAILABLE)


## True only for `OK`.
func succeeded() -> bool:
	return code == OK


func _to_string() -> String:
	if message == "":
		return "InteractionResult(%s)" % code
	return "InteractionResult(%s, '%s')" % [code, message]
