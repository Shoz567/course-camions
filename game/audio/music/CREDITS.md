# Musiques

Toutes les musiques sont de **MintoDog**, publiées sur OpenGameArt sous licence
**CC0 1.0** (domaine public : usage libre, commercial compris, sans crédit
obligatoire). Elles ont été choisies par l'utilisateur le 2026-10-22, qui les
a téléchargées lui-même, sauf la dernière du tableau.

| Fichier | Morceau | Source |
|---|---|---|
| `menu.mp3` | Racing Game Title (140 BPM) | https://opengameart.org/content/racing-game-title |
| `cyber_city.ogg` | Neon sign Circuit (145 BPM) | https://opengameart.org/content/neon-sign-circuit |
| `cyber_city_last_lap.ogg` | Neon sign Circuit (Climax, 160 BPM) | https://opengameart.org/content/neon-sign-circuit |
| `playa_del_sol.mp3` | Sunny City (120 BPM) | https://opengameart.org/content/sunny-city |
| `playa_del_sol_last_lap.mp3` | Sunny City (Climax, 135 BPM) | https://opengameart.org/content/sunny-city |
| `sakura.mp3` | Blossom Mountain [Remake] (140 BPM) | https://opengameart.org/content/blossom-mountainremake |
| `sakura_last_lap.ogg` | Blossom Mountain (Climax) [Remake] (155 BPM) | https://opengameart.org/content/blossom-mountainremake |

Le dernier fichier a été téléchargé par Claude, avec l'accord de l'utilisateur,
à la place de la version FLAC (Godot ne lit pas le FLAC).

Les fichiers sont suivis par Git LFS (`.gitattributes`) et importés en
boucle (`loop=true` dans leurs `.import`). Le jeu les joue avec `RaceMusic`
(un morceau par habillage, version Climax au dernier tour) et `MenuMusic`.
