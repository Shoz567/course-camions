# METRICS.md — Les métriques de gameplay sont mesurées, pas décrétées

---

## 1. Le problème que ce fichier résout

Le `level-designer` a besoin de chiffres pour concevoir une arène : à quelle
hauteur un joueur peut-il sauter, jusqu'où peut-il attraper, à quelle vitesse
se déplace-t-il.

La tentation est d'écrire ces chiffres dans la spec du niveau et de commencer à
construire. C'est une erreur, parce que **ce sont des résultats, pas des
entrées** : la hauteur de saut n'est pas un paramètre qu'on choisit, c'est ce qui
sort du tuning des phases 1 et 2, du rapport masse/impulsion, de la friction des
pieds et de la raideur des jambes.

Concevoir une arène sur un saut supposé de 0,80 m alors qu'il fait 0,55 m, c'est
refaire l'arène en entier — et le découvrir tard, quand les plateformes sont
déjà placées.

**Donc : ces valeurs sont produites par un test qui les mesure, et le
`level-designer` les lit. Personne ne les invente.**

## 2. Comment elles sont produites

La tâche **2.11** crée `game/tests/scenes/metrics_test.tscn`. Ce test pilote un
personnage réel avec une `ScriptedInputSource`, mesure chaque grandeur, et écrit
les résultats dans `game/tests/baseline.json`.

Il tourne à la fin de la phase 2, puis à chaque fin de phase ultérieure. Toute
dérive de plus de 10 % est signalée : si la hauteur de saut change de 15 % entre
la phase 2 et la phase 5, une arène est peut-être devenue infranchissable.

## 3. Le tableau

Valeurs `null` tant que la tâche 2.11 n'a pas tourné. **Un `null` dans ce
tableau signifie « ne conçois pas d'arène qui en dépend »**, pas « prends la
valeur d'à côté ».

| Métrique | Clé dans `baseline.json` | Valeur mesurée | Protocole de mesure |
|---|---|---|---|
| Hauteur du personnage | `head_y_rest_m` | _null_ | position de `head` au repos, tick 0 |
| Centre de masse | `com_y_rest_m` | _null_ | barycentre pondéré des 13 corps, au repos |
| Hauteur de saut utile | `jump_height_m` | _null_ | plus haute plateforme atteinte et **tenue** 30 ticks, par dichotomie |
| Portée du grab | `grab_reach_m` | _null_ | distance torse↔cible maximale donnant une prise en < 12 ticks |
| Vitesse de marche | `walk_speed_ms` | _null_ | déplacement du bassin sur 120 ticks, stick à fond, en ligne droite |
| Largeur d'épaules | `shoulder_width_m` | _null_ | distance entre les deux `upperarm`, pose idle |
| Distance de rupture du grab | `grab_break_dist_m` | _null_ | séparation main↔ancre au-delà de laquelle la prise casse |
| Temps de relevé | `recovery_ticks` | _null_ | ticks entre la chute et le retour du critère d'équilibre |

### Deux pièges de mesure

**La hauteur de saut se mesure en atteignant *et tenant* une plateforme**, pas en
relevant le pic du bassin. Un ragdoll peut voir son bassin passer 0,9 m tout en
étant incapable de finir sur une plateforme à 0,7 m : c'est la seconde valeur qui
intéresse le level design.

**La portée du grab se mesure depuis le torse**, pas depuis la main, parce que
c'est depuis le torse que le joueur juge la distance à l'écran.

## 4. Dimensions d'arène

Ces valeurs-là sont des **choix de design**, pas des mesures. Elles restent ici
pour être au même endroit que le reste, mais elles ne sortent d'aucun test.

| Grandeur | Valeur | Justification |
|---|---|---|
| Arène jouable à 4 | ~12 × 12 m | assez petit pour que les joueurs se croisent en permanence |
| Distance minimale entre spawns | 4 m | pas de coup gratuit au démarrage |
| Marge entre spawn et bord | 2 m | pas d'élimination avant le premier input |

Principe : si tu hésites sur la taille d'une arène, **réduis de 20 %**. Une arène
trop grande est l'erreur la plus fréquente du genre, et la plus difficile à
diagnostiquer — le jeu n'est pas « cassé », il est juste mou.

## 5. Règle d'usage

- Le `level-designer` **lit** ce fichier et `baseline.json`. Il ne les écrit pas.
- Le `godot-qa` **écrit** `baseline.json` via `metrics_test`. Il ne conçoit pas
  de niveau.
- Personne ne modifie une valeur mesurée à la main pour faire passer un design.
  Si une arène a besoin d'un saut de 0,9 m et que le jeu en fait 0,6 m, c'est
  soit l'arène qui change, soit le tuning — et le tuning se change en phase 1,
  avec ses tests, pas en douce depuis un fichier de niveau.
