class_name RouteData
extends RefCounted
## The line the train runs on: stations in order with their position along the route (metres from
## the start), whether the train calls there, the timetable time, which side the platform is on
## (+1 = +Z side of the train, -1 = -Z side) and the size of the town or village around it.
## Between the stations the scenery places villages of its own (see VILLAGES).
## Halved on 2026-11-03 for the 20-minute shift (Journey: 30 m/s, 25 s at each stop): the timetable
## times are the run's arrivals at 6.4 game minutes per real minute.

const STATIONS: Array[Dictionary] = [
	{"name": "KRÁLOVEC", "s": 0.0, "stop": true, "time": "19.10", "side": 1, "town": 3},
	{"name": "LHOTA", "s": 1300.0, "stop": false, "time": "", "side": -1, "town": 1},
	{"name": "DOBŘANY", "s": 3100.0, "stop": true, "time": "19.26", "side": 1, "town": 2},
	{"name": "ZLATNÍKY", "s": 4550.0, "stop": false, "time": "", "side": 1, "town": 1},
	{"name": "VRCHOVINA", "s": 6500.0, "stop": true, "time": "19.46", "side": -1, "town": 2},
	{"name": "LESNÁ", "s": 8200.0, "stop": false, "time": "", "side": -1, "town": 0},
	{"name": "HORNÍ VES", "s": 9650.0, "stop": false, "time": "", "side": 1, "town": 1},
	{"name": "SNĚŽNÁ", "s": 11750.0, "stop": true, "time": "20.13", "side": 1, "town": 2},
	{"name": "KAMENICE", "s": 13600.0, "stop": false, "time": "", "side": -1, "town": 1},
	{"name": "VYSOKÉ POLE", "s": 15500.0, "stop": true, "time": "20.35", "side": -1, "town": 2},
	{"name": "OSTRUŽNÁ", "s": 17300.0, "stop": false, "time": "", "side": 1, "town": 0},
	{"name": "STŘÍBRNÁ HORA", "s": 19500.0, "stop": true, "time": "20.57", "side": 1, "town": 3},
	{"name": "KAMENNÝ MOST", "s": 22250.0, "stop": true, "time": "21.15", "side": -1, "town": 3},
]

## Villages away from any station: route position, side, distance off the line (m), size.
const VILLAGES: Array[Dictionary] = [
	{"s": 2150.0, "side": -1, "off": 140.0, "size": 9},
	{"s": 5600.0, "side": 1, "off": 260.0, "size": 12},
	{"s": 7500.0, "side": 1, "off": 90.0, "size": 6},
	{"s": 10650.0, "side": -1, "off": 180.0, "size": 10},
	{"s": 12800.0, "side": 1, "off": 320.0, "size": 14},
	{"s": 14650.0, "side": -1, "off": 120.0, "size": 7},
	{"s": 16500.0, "side": 1, "off": 220.0, "size": 11},
	{"s": 18400.0, "side": -1, "off": 150.0, "size": 8},
	{"s": 20850.0, "side": 1, "off": 200.0, "size": 12},
]

const PLATFORM_LEN := 130.0
const HALT_PLATFORM_LEN := 45.0

static func stops() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for st in STATIONS:
		if st.stop:
			out.append(st)
	return out

static func end_s() -> float:
	return STATIONS[STATIONS.size() - 1].s

## The station (stopping or not) whose platform covers route position `s`, or {}.
static func station_at(s: float) -> Dictionary:
	for st in STATIONS:
		var half := (PLATFORM_LEN if st.stop else HALT_PLATFORM_LEN) * 0.5
		if absf(s - st.s) < half + 60.0:
			return st
	return {}

## "NAME|HH.MM" lines for the route boards in the saloons.
static func board_lines() -> PackedStringArray:
	var out := PackedStringArray()
	for st in stops():
		out.append("%s|%s" % [st.name, st.time])
	return out
