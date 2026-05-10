extends Node

# Autoload singleton. Owns global game state and registers the InputMap
# at startup. Also drives the run-level state machine (explore / regroup / defend /
# boss / won), per-session compass bias, dynamic weather, hidden trait,
# and adaptive-AI usage tracking.

signal kills_changed(new_count: int)
signal player_died
signal game_won
signal scrap_changed(new_total: int)
signal toast(text: String)
signal quest_changed(quest: Dictionary)
signal world_state_changed
signal phase_changed(phase: String)
signal weather_changed(weather: String)
signal trait_changed(trait_def: Dictionary)
signal boss_health_changed(current: float, maximum: float)
signal boss_spawned
signal boss_defeated
signal inventory_changed(resources: Dictionary, unlocked_weapons: Dictionary)
signal weapon_unlocked(weapon_name: String)

const KILLS_TO_REGROUP: int = 16
const KILLS_TO_BOSS: int = 36
const REGROUP_DURATION: float = 30.0  # seconds to hold sanctuary before defense

# Costs surfaced here so NPCs and HUD pull from one place.
const COST_HEAL: int = 30
const COST_REPAIR_WORKSHOP: int = 100
const COST_BUY_CAR: int = 250

const SCRAP_REWARDS: Dictionary = {
	"Walker": 5,
	"Runner": 4,
	"Crawler": 3,
	"Stalker": 12,
	"Brute": 30,
	"Shrieker": 8,
	"Bloater": 20,
	"Husk": 18,
	"Wolf": 10,
	"Tiger": 26,
	"Giant Spider": 14,
	"Frost Beetle": 16,
	"Frost Matriarch": 90,
	"Dune Warden": 120,
	"River Broodmother": 105,
	"Plain Alpha": 90,
	"Ashfang": 110,
	"Coast Shellback": 130,
	"Frost Titan": 0,  # boss reward handled separately
}

const QUEST_TEMPLATES: Array = [
	{"target_type": "Walker",  "count": 5, "reward": 60},
	{"target_type": "Runner",  "count": 4, "reward": 70},
	{"target_type": "Brute",   "count": 2, "reward": 120},
	{"target_type": "Stalker", "count": 3, "reward": 90},
	{"target_type": "Husk",    "count": 3, "reward": 80},
	{"target_type": "Wolf",    "count": 4, "reward": 85},
	{"target_type": "Giant Spider", "count": 3, "reward": 95},
]

# One trait is rolled per run. Modifiers are applied by the player's
# _apply_trait — the dictionary just describes them.
const TRAITS: Array = [
	{"id": "cold_blooded", "name": "Cold-Blooded",
	 "desc": "Warmth drains 40% slower; stamina regen -20%",
	 "warmth_drain": 0.6, "stamina_regen": 0.8},
	{"id": "tough",        "name": "Tough",
	 "desc": "Max HP +30; sanctuary heal +50%",
	 "max_health_add": 30.0, "heal_mult": 1.5},
	{"id": "iron_lungs",   "name": "Iron Lungs",
	 "desc": "Stamina drain -40%",
	 "stamina_drain": 0.6},
	{"id": "frostbitten",  "name": "Frostbitten",
	 "desc": "Frost cooldown -30%; warmth drains 25% faster",
	 "skill_frost_cd": 0.7, "warmth_drain": 1.25},
	{"id": "scavenger",    "name": "Scavenger",
	 "desc": "Scrap from kills/loot +50%",
	 "scrap_mult": 1.5},
	{"id": "berserker",    "name": "Berserker",
	 "desc": "All damage +25%; max HP -15",
	 "damage_mult": 1.25, "max_health_add": -15.0},
	{"id": "marksman",     "name": "Marksman",
	 "desc": "Pistol/ranged damage +50%",
	 "ranged_dmg_mult": 1.5},
	{"id": "stormcaller",  "name": "Stormcaller",
	 "desc": "Lightning chains hit +1 target; lightning CD -20%",
	 "skill_shock_cd": 0.8, "shock_chain_bonus": 1},
]

# Weather state machine: each phase carries multipliers used elsewhere.
const WEATHER_DEFS: Dictionary = {
	"clear":     {"warmth_drain_mult": 1.0, "spawn_mult": 1.0,  "fog_density": 0.008, "fog_color": Color(0.78, 0.83, 0.9), "compass_wobble": 0.0},
	"fog":       {"warmth_drain_mult": 1.1, "spawn_mult": 1.05, "fog_density": 0.025, "fog_color": Color(0.7, 0.74, 0.78), "compass_wobble": 4.0},
	"snowstorm": {"warmth_drain_mult": 1.6, "spawn_mult": 1.2,  "fog_density": 0.045, "fog_color": Color(0.82, 0.88, 0.95), "compass_wobble": 12.0},
	"blizzard":  {"warmth_drain_mult": 2.2, "spawn_mult": 1.4,  "fog_density": 0.075, "fog_color": Color(0.88, 0.94, 1.0),  "compass_wobble": 22.0},
}

const WEATHER_ORDER: Array = ["clear", "fog", "snowstorm", "blizzard", "fog", "clear"]

var kills: int = 0
var game_over: bool = false

# Economy / progression
var scrap: int = 0
var workshop_repaired: bool = false
var car_owned: bool = false
var active_quest: Dictionary = {}
var resources: Dictionary = {"wood": 0, "stone": 0, "ore": 0, "fish": 0}
var unlocked_weapons: Dictionary = {}

# Run state
var phase: String = "explore"  # explore / regroup / defend / boss / won
var regroup_time_left: float = 0.0
var regroup_counting_down: bool = false
var active_trait: Dictionary = {}
var weather: String = "clear"
var weather_index: int = 0
var compass_bias_deg: float = 0.0
var boss: Node = null
var boss_max_hp: float = 1.0

# Adaptive-AI usage tracker. Keys: fire / frost / shock / melee / ranged.
var damage_type_uses: Dictionary = {
	"fire": 0, "frost": 0, "shock": 0, "melee": 0, "ranged": 0
}


func _ready() -> void:
	_register_inputs()


func _register_inputs() -> void:
	_add_key("move_forward", KEY_W)
	_add_key("move_back", KEY_S)
	_add_key("move_left", KEY_A)
	_add_key("move_right", KEY_D)
	_add_key("sprint", KEY_SHIFT)
	_add_key("jump", KEY_SPACE)
	_add_key("restart", KEY_R)
	_add_mouse("attack", MOUSE_BUTTON_LEFT)
	_add_key("weapon_1", KEY_1)
	_add_key("weapon_2", KEY_2)
	_add_key("weapon_3", KEY_3)
	_add_key("weapon_4", KEY_4)
	_add_key("weapon_5", KEY_5)
	_add_key("weapon_6", KEY_6)
	_add_key("weapon_7", KEY_7)
	_add_key("weapon_8", KEY_8)
	_add_key("skill_fire", KEY_Q)
	_add_key("skill_frost", KEY_E)
	_add_key("skill_lightning", KEY_F)
	_add_key("interact", KEY_G)
	_add_key("build_shelter", KEY_B)
	_add_key("toggle_map", KEY_M)


func _add_key(action: String, keycode: Key) -> void:
	if InputMap.has_action(action):
		return
	InputMap.add_action(action)
	var ev := InputEventKey.new()
	ev.physical_keycode = keycode
	InputMap.action_add_event(action, ev)


func _add_mouse(action: String, button: MouseButton) -> void:
	if InputMap.has_action(action):
		return
	InputMap.add_action(action)
	var ev := InputEventMouseButton.new()
	ev.button_index = button
	InputMap.action_add_event(action, ev)


# -- Economy --------------------------------------------------------------

func add_scrap(amount: int) -> void:
	if amount == 0:
		return
	if active_trait.has("scrap_mult") and amount > 0:
		amount = int(round(amount * float(active_trait["scrap_mult"])))
	scrap = max(0, scrap + amount)
	scrap_changed.emit(scrap)


func spend_scrap(amount: int) -> bool:
	if scrap < amount:
		return false
	scrap -= amount
	scrap_changed.emit(scrap)
	return true


func show_toast(text: String) -> void:
	toast.emit(text)


# -- Inventory / crafting -------------------------------------------------

func add_item(item_id: String, amount: int) -> void:
	if amount <= 0:
		return
	if not resources.has(item_id):
		resources[item_id] = 0
	resources[item_id] = int(resources[item_id]) + amount
	inventory_changed.emit(resources.duplicate(), unlocked_weapons.duplicate())


func item_count(item_id: String) -> int:
	return int(resources.get(item_id, 0))


func has_items(cost: Dictionary) -> bool:
	for k in cost.keys():
		if item_count(String(k)) < int(cost[k]):
			return false
	return true


func spend_items(cost: Dictionary) -> bool:
	if not has_items(cost):
		return false
	for k in cost.keys():
		var key := String(k)
		resources[key] = item_count(key) - int(cost[k])
	inventory_changed.emit(resources.duplicate(), unlocked_weapons.duplicate())
	return true


func unlock_weapon(weapon_name: String) -> void:
	if weapon_name == "" or unlocked_weapons.has(weapon_name):
		return
	unlocked_weapons[weapon_name] = true
	weapon_unlocked.emit(weapon_name)
	inventory_changed.emit(resources.duplicate(), unlocked_weapons.duplicate())
	show_toast("Unlocked: %s" % weapon_name)


func has_weapon(weapon_name: String) -> bool:
	return unlocked_weapons.has(weapon_name)


# -- Kills, phases, quests ------------------------------------------------

func register_kill(type_name: String) -> void:
	if game_over:
		return
	var reward: int = int(SCRAP_REWARDS.get(type_name, 5))
	if reward > 0:
		add_scrap(reward)
	if active_quest.has("target_type") and String(active_quest["target_type"]) == type_name:
		active_quest["progress"] = int(active_quest.get("progress", 0)) + 1
		quest_changed.emit(active_quest)
	kills += 1
	kills_changed.emit(kills)
	_advance_phase()


func _advance_phase() -> void:
	# Exploration → Regroup → Defense → Boss at fixed kill thresholds.
	if phase == "explore" and kills >= KILLS_TO_REGROUP:
		_set_phase("regroup")
	elif phase == "defend" and kills >= KILLS_TO_BOSS:
		_set_phase("boss")


func _set_phase(new_phase: String) -> void:
	if phase == new_phase:
		return
	phase = new_phase
	phase_changed.emit(phase)
	match new_phase:
		"regroup":
			regroup_time_left = REGROUP_DURATION
			regroup_counting_down = false
			show_toast("Regroup at the sanctuary. The horde is coming.")
		"defend":
			regroup_time_left = 0.0
			regroup_counting_down = false
			show_toast("The horde is closing in. Hold the sanctuary.")
		"boss":
			regroup_time_left = 0.0
			regroup_counting_down = false
			show_toast("Something massive is moving through the storm…")
		"won":
			regroup_time_left = 0.0
			regroup_counting_down = false
			show_toast("It's over. The Titan is down.")


func tick_regroup(in_sanctuary: bool, delta: float) -> void:
	if phase != "regroup" or game_over:
		return
	regroup_counting_down = in_sanctuary
	if not in_sanctuary:
		return
	regroup_time_left = max(0.0, regroup_time_left - delta)
	if regroup_time_left <= 0.0:
		_set_phase("defend")


func notify_boss_spawned(b: Node, max_hp: float) -> void:
	boss = b
	boss_max_hp = max_hp
	boss_spawned.emit()
	boss_health_changed.emit(max_hp, max_hp)


func notify_boss_health(current: float, maximum: float) -> void:
	boss_health_changed.emit(current, maximum)


func notify_boss_defeated() -> void:
	if game_over:
		return
	game_over = true
	boss = null
	_set_phase("won")
	boss_defeated.emit()
	game_won.emit()


# Backwards-compat for old callers.
func add_kill() -> void:
	register_kill("")


func start_random_quest() -> void:
	if active_quest.size() > 0:
		return
	var pick: Dictionary = (QUEST_TEMPLATES[randi() % QUEST_TEMPLATES.size()] as Dictionary).duplicate()
	pick["progress"] = 0
	active_quest = pick
	quest_changed.emit(active_quest)


func is_quest_complete() -> bool:
	if active_quest.size() == 0:
		return false
	return int(active_quest.get("progress", 0)) >= int(active_quest.get("count", 1))


func complete_quest() -> int:
	if not is_quest_complete():
		return 0
	var reward: int = int(active_quest.get("reward", 0))
	active_quest = {}
	add_scrap(reward)
	quest_changed.emit(active_quest)
	return reward


func quest_text() -> String:
	if active_quest.size() == 0:
		return ""
	return "Kill %d %s (%d/%d) — %d scrap" % [
		int(active_quest["count"]),
		String(active_quest["target_type"]),
		int(active_quest.get("progress", 0)),
		int(active_quest["count"]),
		int(active_quest["reward"]),
	]


# -- Adaptive AI ---------------------------------------------------------

func record_damage_use(dmg_type: String) -> void:
	if not damage_type_uses.has(dmg_type):
		return
	damage_type_uses[dmg_type] = int(damage_type_uses[dmg_type]) + 1


func dominant_damage_type() -> String:
	# Returns the key with the highest use count, or "" if no uses yet.
	var best: String = ""
	var best_n: int = 0
	for k in damage_type_uses.keys():
		var v: int = int(damage_type_uses[k])
		if v > best_n:
			best_n = v
			best = String(k)
	return best


# -- Weather --------------------------------------------------------------

func set_weather(weather_name: String) -> void:
	if not WEATHER_DEFS.has(weather_name) or weather == weather_name:
		return
	weather = weather_name
	weather_changed.emit(weather)
	show_toast("Weather: %s" % weather_name.capitalize())


func current_weather_def() -> Dictionary:
	return WEATHER_DEFS.get(weather, WEATHER_DEFS["clear"])


# -- Lifecycle ------------------------------------------------------------

func notify_player_died() -> void:
	if game_over:
		return
	game_over = true
	player_died.emit()


func reset_game() -> void:
	kills = 0
	game_over = false
	scrap = 0
	workshop_repaired = false
	car_owned = false
	active_quest = {}
	resources = {"wood": 0, "stone": 0, "ore": 0, "fish": 0}
	unlocked_weapons = {}
	phase = "explore"
	regroup_time_left = 0.0
	regroup_counting_down = false
	weather = "clear"
	weather_index = 0
	compass_bias_deg = randf_range(-12.0, 12.0)
	boss = null
	boss_max_hp = 1.0
	for k in damage_type_uses.keys():
		damage_type_uses[k] = 0

	# Roll a fresh trait for this run.
	active_trait = (TRAITS[randi() % TRAITS.size()] as Dictionary).duplicate()

	kills_changed.emit(kills)
	scrap_changed.emit(scrap)
	inventory_changed.emit(resources.duplicate(), unlocked_weapons.duplicate())
	quest_changed.emit(active_quest)
	world_state_changed.emit()
	phase_changed.emit(phase)
	weather_changed.emit(weather)
	trait_changed.emit(active_trait)
