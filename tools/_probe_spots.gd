extends SceneTree
# Prints where the shift's working places are (train space) and whether the walking grid reaches them.

func _initialize() -> void:
	var world: Node3D = load("res://scenes/game/journey.tscn").instantiate()
	root.add_child(world)
	var nav: TrainNav = null
	while nav == null or not nav.ready_:
		await process_frame
		nav = get_first_node_in_group("train_nav")
	var train := world.find_child("Train", true, false) as Node3D
	var player: Node3D = world.get_node("Player")
	print("PLAYER ", player.global_position)
	for c: Node in train.get_children():
		if c is Node3D:
			print("CAR ", c.name, " x ", (c as Node3D).global_position.x)
	for p: Node in train.find_children("*", "StaffPanel", true, false):
		var n := p as Node3D
		print("PANEL ", _car(n), " at ", n.global_position.snapped(Vector3.ONE * 0.01), " fwd ", (-n.global_basis.z).snapped(Vector3.ONE * 0.01), " free ", _free(nav, n.global_position))
	for t: Node in train.find_children("*", "ComputerTerminal", true, false):
		var ct := t as ComputerTerminal
		print("TERM ", _car(ct), " eye ", ct.view_transform().origin.snapped(Vector3.ONE * 0.01), " free ", _free(nav, ct.view_transform().origin))
	for b: Node in train.find_children("ToiletBowl*", "Node3D", true, false):
		print("BOWL ", _car(b), " ", (b as Node3D).global_position.snapped(Vector3.ONE * 0.01), " free ", _free(nav, (b as Node3D).global_position))
	for nm in ["InspectorRoom", "GuardRoom", "ServiceRoom"]:
		var g := train.find_child(nm, true, false) as Node3D
		if g:
			for ch: Node in g.get_children():
				if ch is Node3D and String(ch.name) in ["Desk", "Bed", "Chair", "Nightstand", "Safe", "Drawers", "LinenShelves", "Hamper", "Door"]:
					print(nm, "/", ch.name, " ", (ch as Node3D).global_position.snapped(Vector3.ONE * 0.01), " free ", _free(nav, (ch as Node3D).global_position))
	var sl := train.get_node("SleeperCar1") as Node3D
	for d: Node in sl.find_children("Door_Compartment_*", "Node3D", true, false):
		print("COMP ", d.name, " ", (d as Node3D).global_position.snapped(Vector3.ONE * 0.01))
	for m: Node in sl.find_children("Bed_*", "Marker3D", true, false):
		print("BED ", m.name, " berth ", m.get_meta("berth", "?"), " ", (m as Node3D).global_position.snapped(Vector3.ONE * 0.01))
	var cage: HoldingCage = get_first_node_in_group("holding_cage")
	print("CAGE approach ", cage.approach_point())
	var mike := train.find_child("Mike", true, false) as Node3D
	print("MIKE ", mike.global_position if mike else "?")
	quit()

func _car(n: Node) -> String:
	while n and not (n.get_parent() and n.get_parent().name == "Train"):
		n = n.get_parent()
	return String(n.name) if n else "?"

func _free(nav: TrainNav, p: Vector3) -> String:
	var c := nav.nearest_free(p, false, 1.2)
	return str(nav.cell_pos(c).snapped(Vector3.ONE * 0.01)) if c.x >= 0 else "none"
