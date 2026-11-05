class_name Economy
extends Node
## Kevin's money: the wallet he carries from day to day, and today's account. Every line in the
## account has a stable id and is booked once, however often the thing behind it is noticed. When he
## turns in (EndOfDay, his bed) the base wage goes in and the day closes; the next day starts from the
## wallet he ended with (handed across the scene reload in `carry`, and saved to user://campaign.json).
## Amounts are dollars: base wage 120, a task done on time +15, a task missed -10, Jim's fee 10 on a
## day he was asked; anomalies and ghosts as set below. An anomaly that attacked him and leapt from
## the train costs nothing (it was a jumpscare, not his fault).

signal changed

const SAVE := "user://campaign.json"

@export_group("Wages")
@export var base_wage := 120
@export var task_bonus := 15
@export var task_fine := -10
@export var medium_fee := -10
@export_group("Anomalies and ghosts")
@export var anomaly_held := 15
@export var anomaly_left_free := -15       # questioned (or out of a cage left open) and still free at the end
@export var anomaly_not_checked := -10
@export var wrongly_held := -20
@export var ghost_rested := 15             # laid to rest before it broke anything
@export var ghost_breakdown := -10         # each breakdown it caused (the repair is a task of its own)
@export var ghost_left := -20              # still riding at the end of the day

## Handed from one day to the next across the scene reload (plain data only).
static var carry := {}

var day := 1
var wallet := 0                            # what he had when the day began
var lines: Array = []                      # today: [{id, amount, text, kind}]
var history: Array = []                    # the days before: [{day, net, wallet}]
var closed := false
var _ids := {}

static func of(n: Node) -> Economy:
	return n.get_tree().get_first_node_in_group("economy") as Economy

func _ready() -> void:
	add_to_group("economy")
	var from := carry
	if from.is_empty() and "--continue" in OS.get_cmdline_user_args():
		from = _read_save()
	if not from.is_empty():
		day = int(from.get("day", 1))
		wallet = int(from.get("wallet", 0))
		history = from.get("history", [])
		TerminalData.log_line("Day %d. Wallet %s." % [day, money(wallet)])
	carry = {}

## Books a line once (false if `id` was booked already today).
func book(id: String, amount: int, text: String, kind := "") -> bool:
	if _ids.has(id) or closed:
		return false
	_ids[id] = true
	lines.append({"id": id, "amount": amount, "text": text, "kind": kind})
	changed.emit()
	return true

func booked(id: String) -> bool:
	return _ids.has(id)

## Today's money so far.
func today() -> int:
	var t := 0
	for l: Dictionary in lines:
		t += int(l.amount)
	return t

## The wallet as it stands (what he began with and today's account).
func balance() -> int:
	return wallet + today()

## Jim charges for a day he was asked anything.
func medium_used() -> void:
	book("medium", medium_fee, "Jim's fee (private line)", "medium")

## The day is over: the base wage goes in and nothing more is booked.
func close_day() -> void:
	if closed:
		return
	book("wage", base_wage, "Base pay for the shift", "wage")
	closed = true
	changed.emit()

## Hands the wallet to tomorrow, saves, and starts the next day (reloads the journey).
func start_next_day() -> void:
	close_day()
	var h := history.duplicate()
	h.append({"day": day, "net": today(), "wallet": balance()})
	carry = {"day": day + 1, "wallet": balance(), "history": h}
	var f := FileAccess.open(SAVE, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(carry))
	# A new night: yesterday's manifest, log and messages go, and the passengers' names are free again.
	TerminalData.passengers.clear()
	PassengerTalk._names_used.clear()
	get_tree().reload_current_scene.call_deferred()

static func _read_save() -> Dictionary:
	if not FileAccess.file_exists(SAVE):
		return {}
	var d = JSON.parse_string(FileAccess.get_file_as_string(SAVE))
	return d if d is Dictionary else {}

static func money(v: int) -> String:
	return ("-$%d" % -v) if v < 0 else ("$%d" % v)
