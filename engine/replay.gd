class_name Replay
extends RefCounted
## A battle as data: seed, loadouts and actions, plus the state hash after every action, so a
## replay can say exactly where it first went differently (technical_design.md, Replay tests).
## Plain dictionaries in and out; reading and writing files is the caller's job.

## Characters of each per-action hash kept in "checks". Enough to spot a change, short enough to diff.
const CHECK_CHARS := 12
const CHANGED := "rules or content changed since it was recorded (if that's intended, re-record with tools/replay.gd --write)"


class Result:
	var state: BattleState
	## Empty if the replay matched the recording.
	var error := ""


## Plays actions from a fresh battle and returns the recording (null if an action is illegal).
static func record(battle_seed: int, loadouts: Array, actions: Array[Action], content: ContentLoader) -> Dictionary:
	var s := Rules.new_battle(battle_seed, content, loadouts)
	var out := {"seed": battle_seed, "loadouts": loadouts.duplicate(true), "actions": [], "checks": []}
	for a in actions:
		var o := Rules.apply(s, a)
		if o == null:
			return {}
		s = o.state
		out.actions.append(to_dict(a))
		out.checks.append(s.state_hash().hex_encode().left(CHECK_CHARS))
	out["hash"] = s.state_hash().hex_encode()
	return out


## Replays a recording and compares it with the hashes it holds.
static func play(rec: Dictionary, content: ContentLoader) -> Result:
	var r := Result.new()
	for key in ["seed", "loadouts", "actions"]:
		if not rec.has(key):
			r.error = "not a replay: missing \"%s\"" % key
			return r
	r.state = Rules.new_battle(int(rec.seed), content, rec.loadouts)
	var checks: Array = rec.get("checks", [])
	for i in rec.actions.size():
		var a := from_dict(rec.actions[i])
		var o := Rules.apply(r.state, a) if a else null
		if o == null:
			r.error = "action %d (%s) is not legal any more: %s" % [i, describe(a), CHANGED]
			return r
		r.state = o.state
		if i < checks.size() and r.state.state_hash().hex_encode().left(CHECK_CHARS) != checks[i]:
			r.error = "state differs from the recording after action %d (%s): %s" % [i, describe(a), CHANGED]
			return r
	if rec.has("hash") and r.state.state_hash().hex_encode() != rec.hash:
		r.error = "final state differs from the recording: " + CHANGED
	return r


static func to_dict(a: Action) -> Dictionary:
	match a.kind:
		Action.Kind.SWAP:
			return {"kind": "swap", "a": a.a, "b": a.b}
		Action.Kind.CAST:
			return {"kind": "cast", "spell": str(a.spell)}
		Action.Kind.ATTACK:
			return {"kind": "attack"}
	return {"kind": "pass"}


## The action a dictionary describes, or null if it isn't one.
static func from_dict(d: Variant) -> Action:
	if d is not Dictionary:
		return null
	match d.get("kind"):
		"swap":
			return Action.swap(int(d.get("a", -1)), int(d.get("b", -1)))
		"cast":
			return Action.cast(StringName(str(d.get("spell", ""))))
		"attack":
			return Action.attack()
		"pass":
			return Action.pass_turn()
	return null


static func describe(a: Action) -> String:
	if a == null:
		return "unreadable"
	match a.kind:
		Action.Kind.SWAP:
			return "swap %d-%d" % [a.a, a.b]
		Action.Kind.CAST:
			return "cast %s" % a.spell
		Action.Kind.ATTACK:
			return "attack"
	return "pass"


## JSON text for a recording, one action per line so fixture diffs stay readable.
static func to_json(rec: Dictionary) -> String:
	var lines := PackedStringArray()
	for key in rec:
		if key == "actions" or key == "checks":
			var items := PackedStringArray()
			for item in rec[key]:
				items.append("    " + JSON.stringify(item))
			lines.append("  %s: [\n%s\n  ]" % [JSON.stringify(key), ",\n".join(items)] if items else "  %s: []" % JSON.stringify(key))
		else:
			lines.append("  %s: %s" % [JSON.stringify(key), JSON.stringify(rec[key])])
	return "{\n%s\n}\n" % ",\n".join(lines)
