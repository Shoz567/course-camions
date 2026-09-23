"""Reglages glTF standardises.

C'est le SEUL endroit du projet ou bpy.ops.export_scene.gltf est appele.
Tous les scripts de build passent par ici (cf. .claude/agents/blender-modeler.md).

Le contrat d'export est dans docs/ART_PIPELINE.md §3. Il est verifie par le
spike S6 : une echelle non appliquee est la cause n1 de personnages geants ou
minuscules dans Godot, et ca ne se voit qu'une fois tout le pipeline ecrit.
"""

from pathlib import Path

import bpy

# Contrat d'export — ne pas devier sans mettre a jour docs/ART_PIPELINE.md §3.
GLTF_SETTINGS = {
    "export_format": "GLB",
    "export_yup": True,            # Y up / -Z forward : convention Godot
    "export_apply": True,          # applique les modificateurs
    "export_skins": True,
    "export_all_influences": False,  # 4 poids max par sommet (limite Godot)
    "export_animations": True,     # seulement la pose idle de reference
    "export_morph": False,
    "export_cameras": False,
    "export_lights": False,
    "use_selection": True,
}


def apply_transforms(objects):
    """Applique location/rotation/scale. A faire TOUJOURS avant l'export."""
    bpy.ops.object.select_all(action="DESELECT")
    for obj in objects:
        obj.select_set(True)
    if objects:
        bpy.context.view_layer.objects.active = objects[0]
        bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)


def to_glb(out_path, objects):
    """Exporte `objects` vers `out_path` avec les reglages du contrat."""
    out = Path(out_path)
    out.parent.mkdir(parents=True, exist_ok=True)

    bpy.ops.object.select_all(action="DESELECT")
    for obj in objects:
        obj.select_set(True)
    if objects:
        bpy.context.view_layer.objects.active = objects[0]

    bpy.ops.export_scene.gltf(filepath=str(out), **GLTF_SETTINGS)
    return out
