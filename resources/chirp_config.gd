@tool
@icon("res://addons/chirp/icons/config.svg")
class_name ChirpConfig
extends Resource
## Global parameters, VCAs, snapshots, bus automation and ducking.
## Point the "chirp/config" project setting at a saved copy.
## Sound directories and background pausing are project settings under "chirp/".

@export var global_parameters: Array[ChirpParameter] = []
@export var vcas: Array[ChirpVCA] = []
## Started by name with Chirp.mixer.start_snapshot().
@export var snapshots: Array[ChirpSnapshot] = []
## Global parameters driving bus volumes and effect properties.
@export var bus_automations: Array[ChirpBusAutomation] = []
## Buses turned down while others are busy (music under dialogue).
@export var duckings: Array[ChirpDucking] = []
