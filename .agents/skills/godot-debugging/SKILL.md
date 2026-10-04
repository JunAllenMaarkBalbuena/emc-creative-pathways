---
name: godot-debugging
description: "Use this skill when the user reports an engine crash, broken signal, null instance error, physics issue, or unexpected logic behavior in a Godot game."
---

# Godot 4 Systematic Game Debugging Skill

You are an expert Godot 4 systems troubleshooter. When tasked with fixing bugs, you must strictly follow a 4-phase root-cause analysis process before altering any script.

## Phase 1: Context Isolation

- Check the error log channel. Differentiate between `push_error()` (red engine halts) and custom console `print()` lines.
- Map out the exact node hierarchy involved in the failure. Check for `@onready` path mismatches or missing `unique_name_in_owner` (%) shortcuts.

## Phase 2: Hypothesis Generation

- State 2-3 potential technical reasons for the bug *out loud* in chat before typing code changes.
- Look out for common Godot pitfalls:
  - Accessing properties on a node that hasn't entered the tree yet (Null Instance error).
  - Race conditions caused by utilizing physical calculations in `_process` instead of `_physics_process`.
  - Signal execution disconnects or stale references after a `queue_free()`.

## Phase 3: Runtime Verification Draft

- Instruct the user on how to verify via Godot's runtime tools:
  - Advise inspecting the **Remote Tab** in the Scene Dock while the game is running to check changing variables.
  - Suggest toggling **"Visible Collision Shapes"** under the Godot Editor's *Debug* menu for collision/physics issues.

## Phase 4: Atomic Fix & Test

- Implement the minimal fix. Use `call_deferred()` for thread-safe scene changes or `is_instance_valid()` guards for volatile objects.
- Run a verification check. Never claim a game system is fixed until the exact replication path proves stable.

## Common Godot 4 Bug Patterns

### Null Instance Errors
```gdscript
# BAD: Node may not be in tree yet
var node = get_node("Path")

# GOOD: Guard with is_instance_valid + is_inside_tree
var node = get_node_or_null("Path")
if node and is_instance_valid(node) and node.is_inside_tree():
    node.do_something()
```

### Signal Stale References
```gdscript
# BAD: Signal connected to freed object
some_signal.connect(freed_node.method)

# GOOD: Use CONNECT_ONE_SHOT or guard
some_signal.connect(func(): if is_instance_valid(freed_node): freed_node.method())

# GOOD: Or disconnect on _exit_tree
func _exit_tree():
    some_signal.disconnect(method)
```

### Thread-Safe Scene Changes
```gdscript
# BAD: Changing scene from _process
func _process(delta):
    get_tree().change_scene_to_file("res://scene.tscn")  # UNSAFE

# GOOD: Use call_deferred
func _process(delta):
    get_tree().call_deferred("change_scene_to_file", "res://scene.tscn")
```

### Physics vs Process
```gdscript
# BAD: Physics in _process (inconsistent across frame rates)
func _process(delta):
    velocity.y += gravity * delta  # NOT PHYSICS

# GOOD: Use _physics_process for physics
func _physics_process(delta):
    velocity.y += gravity * delta  # CONSISTENT
```

### Type Safety
```gdscript
# BAD: Unchecked cast
var mesh = node as MeshInstance3D
mesh.material = mat  # CRASH if node is not MeshInstance3D

# GOOD: Check before using
if node is MeshInstance3D:
    var mesh = node as MeshInstance3D
    mesh.material = mat
```

## Debugging Checklist

- [ ] Read the full error message (not just the first line)
- [ ] Check the Remote tab in the editor while running
- [ ] Verify node paths match the scene tree
- [ ] Confirm signals are connected to valid objects
- [ ] Check for race conditions between _process and _physics_process
- [ ] Verify type casts before using
- [ ] Test with `is_instance_valid()` guards
- [ ] Run minimal reproduction case
