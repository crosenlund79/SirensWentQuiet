class_name ArchitectIdentity
extends RefCounted
## Experiment 011: the minimal internal identity of "the Architect", kept for
## future use. "Architect" is an INTERNAL development name only: it must
## never appear in player-facing text (HUD, toasts, encounters, map,
## settings, enemy lists, save summaries). He is not an EnemyDefs kind, so
## no roster, invasion director, POI encounter, straggler or menu siege can
## pick him; only the developer tools make his figure (the character
## showroom and F10 > Character). He is silent: no sounds are wired (the
## voice and follower recordings in the audio inbox stay untouched).
## No AI, encounter, siege or voice exists yet (tests/character/test_architect.gd
## guards all of this).

const ID := "architect"                 ## the archetype file: src/character/archetypes/architect.gd
const DEV_LABEL := "Architect (internal)"   ## the only label, in developer tools
const HIDDEN := true                    ## never named or listed to the player
const SPAWNABLE := false                ## not in EnemyDefs; no spawner may choose him
const SILENT := true                    ## no voice, footsteps or other sounds
const HOSTILE := false                  ## no AI and no combat yet
## The animation states his rig (ArchitectRig) supports.
const ANIMATIONS := ["still", "walk", "turn", "observe", "attack", "hit", "collapse"]


static func flags() -> Dictionary:
	return {"id": ID, "hidden": HIDDEN, "spawnable": SPAWNABLE, "silent": SILENT, "hostile": HOSTILE,
		"animations": ANIMATIONS}
