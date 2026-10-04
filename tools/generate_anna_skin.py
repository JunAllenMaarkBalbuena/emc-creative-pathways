import os, glob, math

BASE = r"D:\BSEMC_SEM_Git_repo\Emc-semulator-prototype\progress-3-bs-emc-sem\assets\Anna_sprite"
OUTPUT = r"D:\BSEMC_SEM_Git_repo\Emc-semulator-prototype\progress-3-bs-emc-sem\data\skins\anna_skin.tres"
TARGET = 12

ANIMS = [
    ("Back_up_Walk", "Back_up_Walk", True),
    ("Back_up_Idle", "Back_up_Idle", False),
    ("2_3Back_Left_up_Walk", "2_3Back_Left_up_Walk", True),
    ("2_3Back_Left_up_Idle", "2_3Back_Left_up_Idle", False),
    ("2_3Back_Right_up_Walk", "2_3Back_Right_up_Walk", True),
    ("2_3Back_Right_up_Idle", "2_3Back_Right_up_Idle", False),
    ("Front_down_Walk", "Front_down_Walk", True),
    ("Front_down_idle", "Front_down_idle", False),
    ("2_3Front_Left_down_walk", "2_3Front_Left_down_walk", True),
    ("2_3Front_Left_down_Idle", "2_3Front_Left_down_Idle", False),
    ("2_3Front_Right_down_walk", "2_3Front_Right_down_walk", True),
    ("2_3Front_Right_down_Idle", "2_3Front_Right_down_Idle", False),
    ("Left_walk", "Left_walk", True),
    ("Left_idle", "Left_idle", False),
    ("Right_walk", "Right_walk", True),
    ("Right_idle", "Right_idle", False),
]

lines = []
lines.append('[gd_resource type="Resource" script_class="CharacterSkin" format=3]')
lines.append('')
lines.append('[ext_resource type="Script" path="res://scripts/character_skin.gd" id="1_script"]')

ext_resources = []
anim_blocks = []
global_idx = 0

for anim_name, folder, is_walk in ANIMS:
    folder_path = os.path.join(BASE, folder)
    pngs = sorted(glob.glob(os.path.join(folder_path, "*.png")))
    count = len(pngs)
    
    if count <= TARGET:
        indices = list(range(count))
    else:
        step = max(1, count / TARGET)
        indices = [min(int(i * step), count - 1) for i in range(TARGET)]
    
    speed = 10.0 if is_walk else 5.0
    frame_entries = []
    
    for idx in indices:
        png_path = pngs[idx]
        png_name = os.path.basename(png_path).replace("\\", "/")
        res_id = f"anna_{global_idx}"
        rel_path = f"res://assets/Anna_sprite/{folder}/{png_name}"
        ext_resources.append(f'[ext_resource type="Texture2D" path="{rel_path}" id="{res_id}"]')
        frame_entries.append(f'{{"duration": 1.0, "texture": ExtResource("{res_id}")}}')
        global_idx += 1
    
    frames_str = ", ".join(frame_entries)
    anim_blocks.append(f'{{"frames": [{frames_str}], "loop": 1, "name": &"{anim_name}", "speed": {speed}}}')

for er in ext_resources:
    lines.append(er)

lines.append('')
lines.append('[sub_resource type="SpriteFrames" id="SpriteFrames_anna"]')
lines.append('animations = [')

for i, block in enumerate(anim_blocks):
    sep = "," if i < len(anim_blocks) - 1 else ""
    lines.append(block + sep)

lines.append(']')
lines.append('')
lines.append('[resource]')
lines.append('script = ExtResource("1_script")')
lines.append('skin_name = "Anna"')
lines.append('sprite_frames = SubResource("SpriteFrames_anna")')
lines.append('walk_animations = {')
lines.append('"up": "Back_up_Walk",')
lines.append('"up_left": "2_3Back_Left_up_Walk",')
lines.append('"up_right": "2_3Back_Right_up_Walk",')
lines.append('"down": "Front_down_Walk",')
lines.append('"down_left": "2_3Front_Left_down_walk",')
lines.append('"down_right": "2_3Front_Right_down_walk",')
lines.append('"left": "Left_walk",')
lines.append('"right": "Right_walk"')
lines.append('}')
lines.append('idle_animations = {')
lines.append('"up": "Back_up_Idle",')
lines.append('"up_left": "2_3Back_Left_up_Idle",')
lines.append('"up_right": "2_3Back_Right_up_Idle",')
lines.append('"down": "Front_down_idle",')
lines.append('"down_left": "2_3Front_Left_down_Idle",')
lines.append('"down_right": "2_3Front_Right_down_Idle",')
lines.append('"left": "Left_idle",')
lines.append('"right": "Right_idle"')
lines.append('}')
lines.append('has_diagonals = true')
lines.append('walk_speed = 10.0')
lines.append('idle_speed = 5.0')

with open(OUTPUT, "w", encoding="utf-8") as f:
    f.write("\n".join(lines))

print(f"Generated {OUTPUT}")
print(f"  Total ext_resources: {global_idx}")
print(f"  Total animations: {len(ANIMS)}")
for anim_name, folder, is_walk in ANIMS:
    folder_path = os.path.join(BASE, folder)
    count = len(glob.glob(os.path.join(folder_path, "*.png")))
    sampled = min(count, TARGET)
    print(f"  {anim_name}: {count} frames -> {sampled} sampled")
