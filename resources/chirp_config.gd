@tool
class_name ChirpConfig
extends Resource
## Global parameters and VCAs. Point the "chirp/config" project setting at a saved copy.
## Sound directories and background pausing are project settings under "chirp/".

@export var global_parameters: Array[ChirpParameter] = []
@export var vcas: Array[ChirpVCA] = []
