# classroom-simulator

Projet Godot 4.7 qui sert de base à un template de lobby Steam.

- [`addons/steam_lobby/`](addons/steam_lobby/) : le kit de lobby, autonome. Sa [documentation](addons/steam_lobby/README.md) explique comment l'utiliser dans un nouveau jeu.
- [`example/`](example/) : un jeu minimal qui s'en sert (une map, un personnage par joueur, un retour au lobby).
- [`tests/`](tests/) : tests automatiques du kit.
- `lobby_config.tres` : les réglages du lobby pour ce projet.

## Lancer le projet

Avec Steam ouvert, lancer le projet normalement.

Sans Steam, lancer plusieurs instances avec les arguments `--lobby-backend=enet --lobby-name=<nom>` (dans l'éditeur : Débogage > Personnaliser les instances d'exécution).

## Lancer les tests

```
godot --headless --path . -s addons/gut/gut_cmdln.gd -gexit
tests/e2e/run.sh
```

## Créer le repo template

À copier tel quel :

- `addons/steam_lobby/`, `addons/godotsteam/`, `addons/gut/`
- `example/`, `tests/`, `.gutconfig.json`
- `lobby_config.tres`, `project.godot`, `icon.svg`
- `.gitignore`, `.gitattributes`, `.editorconfig`

À adapter après la copie :

- `project.godot` : le nom du projet (`config/name`) ;
- `lobby_config.tres` : `game_key` et `steam_app_id` ;
- ce `README.md`.

À ne pas copier : `export_presets.cfg` (chemins propres à ce projet) et `license.txt` (la licence de GodotSteam, déjà présente dans `addons/godotsteam/`).

Avant de déclarer le template validé, dérouler la liste « À vérifier sur Steam » de la documentation du kit : le backend Steam n'a pas encore été testé en conditions réelles.
