class_name TaskBoard
extends Node
## The shift's work orders: each with an id, a title, a deadline on the train's clock and a check
## that says when the job is done (polled), or done from outside with complete(). Paid once: done by
## the deadline +15 (Economy.task_bonus); not done by then -10 (task_fine), and finishing it late after
## that earns nothing more. Routine orders come every day (Chores), special ones now and then
## (Chores), repairs from the ghosts' breakdowns. ShiftHUD lists the open ones.

signal changed

class Task:
	var id := ""
	var title := ""
	var where := ""                # the car, for the list ("coach two")
	var kind := "routine"          # routine | special | repair
	var due := -1.0                # train clock, hours (-1: no deadline)
	var state := "open"            # open | done | late | missed | void
	var check: Callable            # true once the job is done (polled)
	var bonus := true              # paid on time (repairs of a ghost's breakdown are not)
	var closed_t := 0.0            # real seconds since it closed (the HUD lets it fade)

var tasks: Array = []
var _poll := 0.0
var _ts: Node

static func of(n: Node) -> TaskBoard:
	return n.get_tree().get_first_node_in_group("task_board") as TaskBoard

## Game hours per real second (the Journey's clock_scale / 3600).
static func hours_per_second(n: Node) -> float:
	var j := n.get_tree().root.find_child("Journey", true, false)
	var k = j.get("clock_scale") if j else null
	return (float(k) if k != null else 3.0) / 3600.0

## A clock time ("20.13" or hours) as HH:MM.
static func hhmm(h: float) -> String:
	var m := int(round(fposmod(h, 24.0) * 60.0))
	return "%02d:%02d" % [(m / 60) % 24, m % 60]

func _ready() -> void:
	add_to_group("task_board")
	_ts = get_node_or_null("/root/TrainState")

func clock() -> float:
	return float(_ts.get("clock")) if _ts else 19.0

## A new order. `check` (optional) is polled; without it the order closes through complete().
func add(id: String, title: String, due: float, check := Callable(), kind := "routine", where := "", bonus := true) -> Task:
	var t := get_task(id)
	if t:
		return t
	t = Task.new()
	t.id = id
	t.title = title
	t.due = due
	t.check = check
	t.kind = kind
	t.where = where
	t.bonus = bonus
	tasks.append(t)
	TerminalData.log_line("Work order: %s%s." % [title, (" by " + hhmm(due)) if due >= 0.0 else ""])
	_mark("order: " + title)
	changed.emit()
	return t

## A deadline `seconds` of real time from now, on the train's clock.
func due_in(seconds: float) -> float:
	return clock() + seconds * hours_per_second(self)

func get_task(id: String) -> Task:
	for t: Task in tasks:
		if t.id == id:
			return t
	return null

## Real seconds left to the deadline (INF without one).
func time_left(t: Task) -> float:
	if t.due < 0.0:
		return INF
	return (t.due - clock()) / hours_per_second(self)

func open_tasks() -> Array:
	return tasks.filter(func(t: Task): return t.state == "open")

## The job is done (from outside); paid if on time.
func complete(id: String) -> void:
	var t := get_task(id)
	if t and t.state in ["open", "missed"]:
		_done(t)

## No longer wanted (the passenger got off, the car is gone...): no pay, no fine.
func cancel(id: String) -> void:
	var t := get_task(id)
	if t and t.state == "open":
		t.state = "void"
		changed.emit()

## The day is over: what is still open is called off (a missed order was charged when it was missed).
func close_all() -> void:
	for t: Task in tasks:
		if t.state == "open":
			t.state = "void"
	changed.emit()

# On the night's timeline (HorrorDirector.mark), for tests and the log.
func _mark(what: String) -> void:
	var hd := HorrorDirector.of(self)
	if hd:
		hd.mark(what, "work")

func _process(delta: float) -> void:
	for t: Task in tasks:
		if t.state != "open":
			t.closed_t += delta
	_poll -= delta
	if _poll > 0.0:
		return
	_poll = 0.25
	var now := clock()
	for t: Task in tasks.duplicate():
		if not (t.state in ["open", "missed"]):
			continue
		if t.check.is_valid() and bool(t.check.call()):
			_done(t)
		elif t.state == "open" and t.due >= 0.0 and now > t.due:
			_miss(t)

func _done(t: Task) -> void:
	var on_time := t.state == "open"
	t.state = "done" if on_time else "late"
	t.closed_t = 0.0
	var eco := Economy.of(self)
	if eco and on_time and t.bonus:
		eco.book("task:" + t.id, eco.task_bonus, t.title, t.kind)
	TerminalData.log_line("Done: %s%s." % [t.title, "" if on_time else " (late)"])
	_mark(("done: " if on_time else "late: ") + t.title)
	changed.emit()

func _miss(t: Task) -> void:
	t.state = "missed"
	t.closed_t = 0.0
	var eco := Economy.of(self)
	if eco:
		eco.book("task:" + t.id, eco.task_fine, "Missed: " + t.title, t.kind)
	TerminalData.log_line("Missed: %s." % t.title)
	_mark("missed: " + t.title)
	var p := get_tree().root.find_child("Player", true, false)
	if p and p.has_method("show_message"):
		p.call("show_message", "Missed: %s  (%s)" % [t.title, Economy.money(eco.task_fine if eco else -10)], 4.0)
	changed.emit()
