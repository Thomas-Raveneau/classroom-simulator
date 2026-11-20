# classroom-simulator

Le début d'un jeu multijoueur Godot 4.7 : un lobby Steam complet, les briques réseau du gameplay, et une première manche jouable à plusieurs (ramasser des pièces), à remplacer au fur et à mesure par le vrai jeu.

## Organisation

| Dossier | Contenu |
|---|---|
| `network/` | Le code réseau : le lobby (`lobby/`) et les briques réseau de la partie (`gameplay/`). Voir [network/README.md](network/README.md). |
| `scenes/` | Les scènes du jeu et leurs scripts : menus (`UI/`), personnage, apparition des joueurs, manche de collecte et HUD (`gameplay/`), maps (`maps/`), chargement des scènes (`managers/`). |
| `config/` | Les réglages, dont `lobby_config.tres`. |
| `assets/` | Textures et icônes. |
| `tests/` | Tests automatiques. |
| `addons/` | Addons tiers : GodotSteam et GUT (tests). |

## Lancer le projet

Avec Steam ouvert, lancer le projet normalement.

Sans Steam, lancer plusieurs instances avec les arguments `--lobby-backend=enet --lobby-name=<nom>` (dans l'éditeur : Débogage > Personnaliser les instances d'exécution).

## Lancer les tests

```
godot --headless --path . -s addons/gut/gut_cmdln.gd -gexit
tests/e2e/run.sh
```

## Démarrer un nouveau jeu à partir de ce repo

1. Copier le repo, sauf `export_presets.cfg` (chemins propres à ce projet) et `license.txt` (la licence de GodotSteam, déjà présente dans `addons/godotsteam/`).
2. Dans `project.godot`, changer le nom du projet (`config/name`).
3. Dans `config/lobby_config.tres`, changer `game_key` et `steam_app_id`.

Le backend Steam n'a pas encore été testé en conditions réelles : dérouler la liste « À vérifier sur Steam » de [network/README.md](network/README.md) avec deux comptes.
