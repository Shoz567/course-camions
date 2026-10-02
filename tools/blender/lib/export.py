"""Reglages glTF standardises.

C'est le SEUL endroit du projet ou bpy.ops.export_scene.gltf est appele.
Tous les scripts de build passent par ici (cf. .claude/agents/blender-modeler.md).

Le contrat d'export est dans docs/ART_PIPELINE.md §3. Il est verifie par le
spike S6 : une echelle non appliquee est la cause n1 de camions geants ou
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
    """Applique rotation et echelle. A faire TOUJOURS avant l'export.

    La location n'est PAS appliquee : c'est elle qui porte le pivot. L'appliquer
    ramene l'origine de chaque objet au centre du monde ; mesure au spike V4, le
    pivot des roues arrivait a 2,24 m du moyeu dans Godot (0,0000 m sans).
    """
    bpy.ops.object.select_all(action="DESELECT")
    for obj in objects:
        obj.select_set(True)
    if objects:
        bpy.context.view_layer.objects.active = objects[0]
        bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)


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


def to_blend(out_path, objects, name):
    """Sauvegarde un .blend d'UN modele, pour l'ouvrir et le regarder dans
    Blender (docs/ART_PIPELINE.md §4 ter).

    Copie de consultation : la source de verite reste le script ; `make
    assets` reecrit ce fichier. Les objets sont ranges dans une collection
    au nom du modele, pres d'un sol, d'une lumiere et d'une camera cadree.
    """
    import math
    from mathutils import Vector

    out = Path(out_path)
    out.parent.mkdir(parents=True, exist_ok=True)
    scene = bpy.context.scene
    scene.name = name
    coll = bpy.data.collections.new(name)
    scene.collection.children.link(coll)
    for obj in objects:
        for c in list(obj.users_collection):
            c.objects.unlink(obj)
        coll.objects.link(obj)

    # Cadrage : boite englobante du modele.
    pts = [o.matrix_world @ Vector(c) for o in objects if o.type == "MESH" for c in o.bound_box]
    lo = Vector((min(p.x for p in pts), min(p.y for p in pts), min(p.z for p in pts)))
    hi = Vector((max(p.x for p in pts), max(p.y for p in pts), max(p.z for p in pts)))
    centre = (lo + hi) / 2
    taille = max((hi - lo).length, 1.0)

    stage = bpy.data.collections.new("Studio")
    scene.collection.children.link(stage)
    sol = bpy.data.meshes.new("Sol")
    r = taille * 1.5
    z = min(lo.z, 0.0)      # sous le point le plus bas (projectiles centres)
    sol.from_pydata([(centre.x - r, centre.y - r, z), (centre.x + r, centre.y - r, z),
                     (centre.x + r, centre.y + r, z), (centre.x - r, centre.y + r, z)],
                    [], [(0, 1, 2, 3)])
    mat_sol = bpy.data.materials.new("Sol_Studio")
    mat_sol.use_nodes = True
    bsdf = next(n for n in mat_sol.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
    bsdf.inputs["Base Color"].default_value = (0.30, 0.31, 0.33, 1.0)
    bsdf.inputs["Roughness"].default_value = 0.9
    sol.materials.append(mat_sol)
    stage.objects.link(bpy.data.objects.new("Sol", sol))

    soleil = bpy.data.lights.new("Soleil", "SUN")
    soleil.energy = 3.0
    lum = bpy.data.objects.new("Soleil", soleil)
    lum.rotation_euler = (math.radians(50), 0, math.radians(30))
    stage.objects.link(lum)

    cam_data = bpy.data.cameras.new("Camera")
    cam = bpy.data.objects.new("Camera", cam_data)
    direction = Vector((1.0, 1.1, 0.75)).normalized()   # trois-quarts avant droit
    cam.location = centre + direction * taille * 1.75
    cam.rotation_euler = (-direction).to_track_quat("-Z", "Y").to_euler()
    stage.objects.link(cam)
    scene.camera = cam

    world = bpy.data.worlds.new("Monde")
    world.use_nodes = True
    bg = next(n for n in world.node_tree.nodes if n.type == "BACKGROUND")
    bg.inputs["Color"].default_value = (0.45, 0.50, 0.58, 1.0)
    scene.world = world

    bpy.context.preferences.filepaths.save_version = 0     # pas de .blend1
    bpy.ops.wm.save_as_mainfile(filepath=str(out), check_existing=False, compress=True)
    return out
