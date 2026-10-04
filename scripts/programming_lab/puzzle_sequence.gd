class_name PuzzleSequence
extends Resource

## The exact order of puzzles for a lab. Create one .tres file per lab in
## res://data/sequences/ and reference it from ProgrammingLab.
@export var puzzle_order: Array[FlowchartPuzzleData] = []
