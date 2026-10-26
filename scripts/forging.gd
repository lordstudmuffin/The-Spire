class_name Forging
extends RefCounted
## The forging minigame: a craft at the anvil is a few hammer strikes, each
## timed against a heat bar. A glowing mark sweeps the bar; striking while it
## is over the hot zone is a Good strike, dead centre a Perfect one. The
## strikes' average is the piece's quality (0..1), which shifts the rank roll
## (Crafting.roll_rank) and the stat roll (Crafting.make_item).
##
## Server-validated online. "forge_start" makes the server roll the strike
## specs and stamp its clock; the client draws them and sends each strike as
## it happens ("forge_strike" {i, at}, `at` = ms since the client got the
## specs). The server grades `at` itself, and only accepts it when it fits
## the strike's arrival time: no later than the server's own elapsed time,
## no earlier than that minus the peer's round trip (plus a little). A client
## cannot plan strikes ahead or hold them back to pick a better moment, beyond
## its own ping. The worst a cheat buys is about QUALITY_LEVELS smithing
## levels on the roll. Tools skip the minigame; a plain "craft" (bots, the
## old quick path) forges at QUICK_QUALITY.
##
## The mark's position is a deterministic triangle wave of the time since the
## strike opened, so client and server agree on every frame.

const STRIKES := 3
## Recipes at or above this base stat take a fourth strike.
const FOURTH_STRIKE_BASE := 12
## Seconds a strike stays open before it counts as a miss.
const STRIKE_WINDOW := 5.0
## A strike cannot follow the last one faster than this (ms).
const MIN_GAP_MS := 180
## Server clock slack: how far before its own elapsed time a strike may claim
## to have happened, as round trip * RTT_MULT + RTT_PAD, clamped.
const RTT_MULT := 1.25
const RTT_PAD_MS := 90
const SLACK_MIN_MS := 140
const SLACK_MAX_MS := 520
## Whole session lifetime (ms); an older one is refused.
const SESSION_MS := 40000
## Effective smithing levels between quality 0.5 and 1.0 (and 0.5 and 0).
const QUALITY_LEVELS := 3.0
const QUICK_QUALITY := 0.3
const SCORE := {"perfect": 1.0, "good": 0.65, "glance": 0.3, "miss": 0.0}
const GRADE_NAMES := {"perfect": "PERFECT", "good": "GOOD", "glance": "GLANCE", "miss": "MISS"}


static func strike_count(recipe_name: String) -> int:
	var r: Dictionary = Crafting.RECIPES.get(recipe_name, {})
	return STRIKES + (1 if int(r.get("base", 0)) >= FOURTH_STRIKE_BASE else 0)


static func uses_minigame(recipe_name: String) -> bool:
	return Crafting.RECIPES.has(recipe_name) and str(Crafting.RECIPES[recipe_name]["kind"]) != "tool"


## Rolls the strike specs. The hot zone narrows on harder recipes and widens
## with smithing skill; Forgeborn smiths read the metal better still.
## Each spec: {center, width, period (ms per sweep), phase (0..1)}.
static func roll_specs(recipe_name: String, smithing_level: int, forgeborn := false, seed := -1) -> Array:
	var rng := RandomNumberGenerator.new()
	if seed >= 0:
		rng.seed = seed
	else:
		rng.randomize()
	var r: Dictionary = Crafting.RECIPES.get(recipe_name, {"base": 6})
	var hard := clampf(float(r.get("base", 6)) / 18.0, 0.0, 1.0)
	var width := 0.24 - 0.08 * hard + 0.008 * float(clampi(smithing_level, 1, 10))
	if forgeborn:
		width += 0.04
	var specs := []
	for i in strike_count(recipe_name):
		# Later strikes sweep a little faster: the metal is cooling.
		var period := int(rng.randf_range(1300.0, 1700.0) - 120.0 * i - 260.0 * hard)
		specs.append({"center": snappedf(rng.randf_range(0.22, 0.78), 0.001), "width": snappedf(width * rng.randf_range(0.9, 1.1), 0.001),
			"period": maxi(period, 760), "phase": snappedf(rng.randf(), 0.001)})
	return specs


## The mark's position (0..1) `ms` after its strike opened.
static func mark(spec: Dictionary, ms: float) -> float:
	var p := fposmod(ms / maxf(float(spec.get("period", 1400)), 1.0) + float(spec.get("phase", 0.0)), 1.0)
	return 1.0 - absf(2.0 * p - 1.0)


static func grade(spec: Dictionary, ms: float) -> String:
	if ms > STRIKE_WINDOW * 1000.0:
		return "miss"
	var d := absf(mark(spec, ms) - float(spec["center"]))
	var w := float(spec["width"])
	if d <= w * 0.18:
		return "perfect"
	if d <= w * 0.5:
		return "good"
	if d <= w * 0.85:
		return "glance"
	return "miss"


static func quality(grades: Array) -> float:
	if grades.is_empty():
		return 0.0
	var s := 0.0
	for g in grades:
		s += float(SCORE.get(str(g), 0.0))
	return s / float(grades.size())


## Quality as a word for the toast and the item card.
static func quality_word(q: float) -> String:
	if q >= 0.99:
		return "Flawless"
	if q >= 0.8:
		return "Fine"
	if q >= 0.5:
		return "Sound"
	if q >= 0.25:
		return "Rough"
	return "Crude"


## The smithing level the rank roll uses for a piece of quality `q`.
static func effective_level(smithing_level: int, q: float) -> int:
	return maxi(1, int(round(float(smithing_level) + (q - 0.5) * 2.0 * QUALITY_LEVELS)))


# --- Server sessions (kept on the record as "_forge", never saved) ----------

## Server: open a session for `rs` (a RecordState) after Crafting.check passed.
## Returns what the client needs to draw it.
static func srv_open(rs, recipe_name: String) -> Dictionary:
	var specs := roll_specs(recipe_name, int(rs.smithing_level), str(rs.hidden_class) == "Forgeborn")
	rs.rec["_forge"] = {"recipe": recipe_name, "specs": specs, "t0": Time.get_ticks_msec(), "grades": [], "last": 0}
	return {"recipe": recipe_name, "specs": specs}


## Server: grade strike `i` at client time `at` (ms since the client got the
## specs). `rtt_ms` is the peer's round trip. Returns {"grade"} for a middle
## strike, {"done": true, "quality", "grades"} for the last, or {"error"}.
static func srv_strike(rs, i: int, at: int, rtt_ms: int, now_ms := -1) -> Dictionary:
	var s = rs.rec.get("_forge")
	if not (s is Dictionary):
		return {"error": "The anvil is cold (no forging in progress)."}
	var now := Time.get_ticks_msec() if now_ms < 0 else now_ms
	var elapsed := now - int(s["t0"])
	if elapsed > SESSION_MS:
		rs.rec.erase("_forge")
		return {"error": "The metal cooled. Start again."}
	var grades: Array = s["grades"]
	var specs: Array = s["specs"]
	if i != grades.size() or i >= specs.size():
		return {"error": "Out-of-order strike."}
	var slack := clampi(int(rtt_ms * RTT_MULT) + RTT_PAD_MS, SLACK_MIN_MS, SLACK_MAX_MS)
	if at > elapsed + 30 or at < elapsed - slack or at < int(s["last"]) + MIN_GAP_MS:
		rs.rec.erase("_forge")
		return {"error": "That strike's timing does not add up. The piece is spoiled; start again."}
	var g := grade(specs[i], float(at - int(s["last"])))
	grades.append(g)
	s["last"] = at
	if grades.size() < specs.size():
		return {"grade": g, "i": i}
	rs.rec.erase("_forge")
	return {"done": true, "recipe": str(s["recipe"]), "quality": quality(grades), "grades": grades.duplicate()}
