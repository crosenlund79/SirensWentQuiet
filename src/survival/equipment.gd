class_name Equipment
extends RefCounted
## Equipment slots and their effects (SPEC-003 §2). Owner: K. Pure rules and
## numbers; the state (slot -> item id) lives in GameState.equipment and the
## calls are GameState.equip / unequip / equipped / has_equipped / slot_of.
## Rules and numbers: docs/experiment-003/equipment.md.

const SLOTS := ["primary", "secondary", "body", "back", "utility", "tool"]
const WEAPON_SLOTS := ["primary", "secondary"]
const SLOT_NAMES := {
	"primary": "Primary weapon", "secondary": "Secondary weapon", "body": "Body",
	"back": "Back", "utility": "Utility", "tool": "Tool",
}
## Item slot kind (Items.slot) -> the equipment slots it fits.
const KIND_SLOTS := {
	"weapon": ["primary", "secondary"], "body": ["body"], "back": ["back"],
	"utility": ["utility"], "tool": ["tool"],
}

## Vest: incoming damage x0.65 (-35 %) for every cause except these (bodily
## needs are not blows).
const VEST_FACTOR := 0.65
const UNARMORED_CAUSES := ["starvation", "dehydration"]
## Backpack: expedition carrying capacity (loot) x1.5. Household material caps
## are storage, not carrying: crates raise them, the backpack doesn't.
const BACKPACK_CARRY := 1.5
## Newly acquired gear goes into a free slot, except these (the hammer has no
## equipped effect: building needs it owned, so it shouldn't take the crowbar's
## tool slot by itself).
const NO_AUTO_EQUIP := ["hammer"]


static func is_slot(slot) -> bool:
	return typeof(slot) == TYPE_STRING and slot in SLOTS


## The slots `id` fits ([] if it can't be equipped).
static func slots_for(id) -> Array:
	return KIND_SLOTS.get(Items.slot(id), [])


static func is_equippable(id) -> bool:
	return not slots_for(id).is_empty()


static func fits(id, slot: String) -> bool:
	return slot in slots_for(id)
