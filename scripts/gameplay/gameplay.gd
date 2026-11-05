class_name Gameplay
extends Node3D
## The shift's gameplay, under one node in the journey scene: the walkable grid of the train
## (TrainNav), the record of the shift (ShiftRecord), reports and the holding cage (Detention),
## Mike's day (MikeDuty), the ghost pilot (GhostStory), the scares (HorrorDirector), the hauntings
## (HauntDirector) and the anomalies that turn violent (AnomalyFrenzy); the money (Economy), what
## Kevin carries (Inventory), the work orders (TaskBoard, Chores), the berth that is not what it seems
## (WakeScare), his bed that ends the day (EndOfDay), the clocks on the car walls (WallClocks), his
## clipboard and wristwatch (Clipboard, Wristwatch) and the screen over it all (ShiftHUD). Each part
## finds the others through groups, so any of them can be left out.

@export var with_mike := true
@export var with_detention := true
@export var with_horror := true
@export var with_ghost := true
@export var with_haunts := true
@export var with_passing_train := true
@export var with_frenzy := true
@export var with_chores := true
@export var with_wake_scare := true
@export var with_hud := true

func _ready() -> void:
	# The cage's gate first: the walkable grid is scanned with it in place.
	if with_detention:
		_add(HoldingCage.new(), "HoldingCage")
	_add(TrainNav.new(), "TrainNav")
	_add(Economy.new(), "Economy")
	_add(Inventory.new(), "Inventory")
	_add(TaskBoard.new(), "TaskBoard")
	_add(ShiftRecord.new(), "ShiftRecord")
	if with_detention:
		_add(Detention.new(), "Detention")
	if with_mike:
		_add(MikeDuty.new(), "MikeDuty")
	if with_horror:
		_add(HorrorDirector.new(), "HorrorDirector")
	if with_ghost:
		_add(GhostStory.new(), "GhostStory")
	if with_haunts:
		_add(HauntDirector.new(), "HauntDirector")
	if with_passing_train:
		_add(PassingTrain.new(), "PassingTrain")
	if with_frenzy:
		_add(AnomalyFrenzy.new(), "AnomalyFrenzy")
	if with_chores:
		_add(Chores.new(), "Chores")
	if with_wake_scare:
		_add(WakeScare.new(), "WakeScare")
	_add(EndOfDay.new(), "EndOfDay")
	_add(WallClocks.new(), "WallClocks")
	if DisplayServer.get_name() != "headless":
		_add(Clipboard.new(), "Clipboard")
		_add(Wristwatch.new(), "Wristwatch")
	if with_hud and DisplayServer.get_name() != "headless":
		_add(ShiftHUD.new(), "ShiftHUD")

func _add(n: Node, n_name: String) -> Node:
	n.name = n_name
	add_child(n)
	return n
