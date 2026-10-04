class_name ScoringManager
extends RefCounted

const GRADE_S: float = 95.0
const GRADE_A: float = 90.0
const GRADE_B: float = 80.0
const GRADE_C: float = 70.0

func grade_from_percent(pct: float) -> String:
	if pct >= GRADE_S: return "S"
	elif pct >= GRADE_A: return "A"
	elif pct >= GRADE_B: return "B"
	elif pct >= GRADE_C: return "C"
	else: return "Retry"

func grade_label(pct: float) -> String:
	if pct >= GRADE_S: return "Outstanding!"
	elif pct >= GRADE_A: return "Excellent!"
	elif pct >= GRADE_B: return "Good!"
	elif pct >= GRADE_C: return "Passable"
	else: return "Try Again"

func grade_color(pct: float) -> Color:
	if pct >= GRADE_S: return Color(1.0, 0.84, 0.0)
	elif pct >= GRADE_A: return Color(0.25, 1.0, 0.45)
	elif pct >= GRADE_B: return Color(0.29, 0.62, 1.0)
	elif pct >= GRADE_C: return Color(1.0, 0.65, 0.0)
	else: return Color(1.0, 0.25, 0.25)

func calculate_final(primitive_scores: Array[float]) -> float:
	if primitive_scores.is_empty():
		return 0.0
	var total := 0.0
	for s in primitive_scores:
		total += s
	return total / float(primitive_scores.size())
