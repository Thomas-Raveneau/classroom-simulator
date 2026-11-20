# Réseau

Le code réseau du jeu. `lobby/` gère le lobby : créer, rejoindre, inviter, se déclarer prêt, exclure, lancer la partie et revenir au lobby. Il fonctionne avec Steam (via GodotSteam) et, pour tester sans Steam, en local sur une seule machine (ENet). `gameplay/` contient les briques réseau utilisées pendant la partie.

Le jeu ne parle au lobby que par un seul objet, l'autoload `Lobby`.

## Régler le lobby

Les réglages sont dans `config/lobby_config.tres` (une ressource `LobbyConfig`). À renseigner pour un nouveau jeu :

- `game_scene` : la scène de jeu à charger au lancement ;
- `game_key` : un identifiant propre au jeu ;
- `steam_app_id` : l'identifiant Steam du jeu (480 est l'app de test de Valve).

## Tester en local, sans Steam

Lancer plusieurs instances avec le backend ENet, créer un lobby dans l'une et le rejoindre depuis les autres (« Join lobby » puis « Local game »).

Dans l'éditeur : Débogage > Personnaliser les instances d'exécution, activer plusieurs instances et donner à chacune les arguments :

```
--lobby-backend=enet --lobby-name=Alice
```

En ligne de commande :

```
godot --path . -- --lobby-backend=enet --lobby-name=Alice
```

Le backend ENet n'a ni amis, ni invitations, ni vraie liste de lobbies : les boutons correspondants sont masqués. Tout le reste (joueurs, données, prêt, exclusion, chargement, arrivée en cours de partie) se comporte comme sur Steam, parce que c'est synchronisé par RPC et non par Steam.

## Utiliser le lobby depuis le jeu

### Créer, rejoindre, quitter

```gdscript
Lobby.create()                # répond par `created` ou `create_failed(reason)`
Lobby.join(lobby_id)          # répond par `joined` ou `join_failed(reason)`
Lobby.leave()                 # répond par `left(reason)`
```

`left(reason)` est émis quelle que soit la cause du départ : volontaire, hôte parti, exclusion, connexion perdue. `LobbyTypes.reason_text(reason)` donne un message par défaut.

L'état courant est dans `Lobby.state` : `NONE`, `CREATING`, `JOINING`, `IN_LOBBY`, `LOADING`, `IN_GAME`. `Lobby.is_host()` indique si le joueur local est l'hôte.

### Les joueurs et leurs données

```gdscript
for member: LobbyMember in Lobby.get_members():
	print(member.name, member.is_host, member.is_ready)

Lobby.set_member_data("team", 2)       # sur soi-même
Lobby.set_ready(true)
Lobby.kick(member)                     # hôte uniquement
```

- Signaux : `member_joined(member)`, `member_left(member)`, `member_updated(member, key)`.
- Les données d'un joueur (`member.data`) sont libres : personnage, équipe, couleur. Un joueur n'écrit que les siennes, l'hôte peut écrire celles de tous.
- L'hôte valide chaque changement. Pour ajouter vos règles : `Lobby.member_data_validator = func(member, key, value) -> bool`.
- `Lobby.set_lobby_data("map", "forest")` partage une donnée du lobby entier (hôte uniquement), lue avec `Lobby.get_lobby_data("map")`.

### Lancer la partie

```gdscript
Lobby.start_game()                     # hôte : charge `game_scene` chez tout le monde
Lobby.change_game_scene(path)          # hôte, en partie : niveau suivant
Lobby.return_to_lobby()                # hôte, en partie : retour au lobby pour tous
```

L'hôte attend que tous les joueurs aient chargé la scène. `game_started` est alors émis chez chacun.

### Faire apparaître les joueurs

Deux règles suffisent.

**1. Faire apparaître un joueur quand `member_scene_ready` est émis.** Ce signal est émis pour chaque joueur au lancement, puis pour chaque joueur arrivant en cours de partie. Côté hôte :

```gdscript
extends MultiplayerSpawner

func _ready() -> void:
	spawn_function = _create_player
	if multiplayer.is_server():
		Lobby.member_scene_ready.connect(func(member: LobbyMember) -> void: spawn(member.peer_id))

func _create_player(peer_id: int) -> Node:
	var player: Node = player_scene.instantiate()
	player.name = str(peer_id)
	player.set_multiplayer_authority(peer_id)
	return player
```

**2. Ajouter un nœud `ReplicationGate` comme enfant direct de chaque objet répliqué** de la scène de jeu (joueur, projectile, plateforme mobile). C'est un `MultiplayerSynchronizer` avec le script `network/gameplay/replication_gate.gd`, sans rien à configurer.

Sans lui, Godot réplique un objet vers un joueur dès qu'il est connecté, même s'il n'a pas encore chargé la scène. L'objet est alors perdu, et ses mises à jour n'arrivent plus jamais chez ce joueur.

## Configuration (`LobbyConfig`)

| Réglage | Rôle |
|---|---|
| `max_players` | Nombre maximum de joueurs, hôte compris. |
| `default_visibility` | Privé (sur invitation), amis, ou public. |
| `game_key` | Distingue vos lobbies de ceux des autres jeux de la même app Steam. Indispensable avec l'app de test 480. |
| `protocol_version` | À augmenter quand deux versions du jeu ne sont plus compatibles en réseau. |
| `allow_join_in_progress` | Autorise à rejoindre une partie lancée. Sinon le lobby est verrouillé pendant la partie. |
| `require_all_ready` | L'hôte ne peut lancer que si tous les joueurs sont prêts. |
| `main_menu_scene`, `lobby_list_scene`, `lobby_scene`, `game_scene` | Les scènes du parcours. |
| `auto_navigation` | Le lobby enchaîne lui-même menu, lobby et jeu. À désactiver pour piloter les scènes depuis le code du jeu. |
| `join_timeout`, `load_timeout`, `dismiss_grace` | Délais maximum, en secondes. |
| `default_backend` | `steam` ou `enet`. L'argument `--lobby-backend=` a priorité. |
| `steam_app_id`, `enet_port` | Réglages des backends. |

`allow_join_in_progress` ne fait que charger la scène et faire apparaître le nouveau joueur. Lui transmettre l'état de la partie en cours (scores, objets déjà ramassés) reste à la charge du jeu.

## L'interface

Les écrans du lobby sont dans `scenes/UI/menus/` (menu principal, liste des lobbies, lobby, invitations). Ils n'utilisent que l'API publique de `Lobby` : on peut les modifier ou les remplacer librement. Leurs chemins sont dans `LobbyConfig`.

`Lobby.supports_friends`, `supports_invites` et `supports_invite_overlay` indiquent ce que le backend sait faire, pour masquer le reste.

## Architecture

```
interface, jeu  →  Lobby (LobbyService)  →  LobbyBackend (Steam ou ENet)
                       ├─ MemberSync : joueurs, données, exclusion (RPC)
                       └─ SceneSync  : chargement synchronisé (RPC)
```

| Dossier | Contenu |
|---|---|
| `network/lobby/core/` | La façade, le registre des joueurs, le chargement synchronisé, la config, la classe de base des backends. |
| `network/lobby/backends/` | Steam et ENet. Seul `backends/steam/` connaît Steam. |
| `network/gameplay/` | Les briques réseau de la partie (`ReplicationGate`). |
| `scenes/managers/` | Le chargeur de scènes (`SceneLoader`, utilisable seul) et l'enchaînement des écrans. |
| `scenes/UI/menus/` | Les écrans du lobby. |

Principes :
- Les dépendances vont dans un seul sens. Un backend ne connaît ni la façade ni l'interface.
- L'hôte fait autorité : il admet les joueurs, établit leur identité et valide leurs données.
- Le code de `scenes/` utilise l'autoload `Lobby`. Le code de `network/` ne le cite jamais par son nom et passe par `LobbyService.for_node(self)`, ce qui permet de faire tourner plusieurs joueurs dans un même test.

### Écrire un autre backend

Hériter de `LobbyBackend`, implémenter `create`, `join`, `leave`, `get_peer`, `get_local_identity` et `resolve_identity`, puis l'ajouter à `BACKEND_SCRIPTS` dans `lobby_autoload.gd`. `backends/enet/enet_lobby_backend.gd` est l'exemple le plus court. Un backend répond toujours par signal, jamais dans l'appel lui-même.

## Tests

```
godot --headless --path . -s addons/gut/gut_cmdln.gd -gexit    # tests unitaires (GUT), dans tests/unit/
tests/e2e/run.sh                                               # le vrai jeu, à 3 instances
```

Les tests unitaires font tourner plusieurs joueurs dans le même processus, sur une vraie connexion ENet. Le script `run.sh` lance trois instances du jeu : un hôte, un client et un joueur qui arrive en cours de partie.

Pour ne pas embarquer les tests dans le jeu exporté, ajouter `tests/*, addons/gut/*` aux filtres d'exclusion des préréglages d'export.

## À vérifier sur Steam

Le backend Steam a été écrit sans pouvoir être exécuté : il compile avec GodotSteam 4.24, mais **aucun parcours Steam n'a encore été testé**. À faire avec deux comptes, sur deux machines ou une machine et une VM :

- [ ] Créer un lobby, le voir chez un ami dans « Join lobby », le rejoindre.
- [ ] Les noms des joueurs s'affichent chez tout le monde.
- [ ] Inviter depuis la liste d'amis du lobby et depuis le bouton « Invite... ».
- [ ] Accepter une invitation depuis le jeu, puis depuis l'overlay Steam.
- [ ] Jeu fermé, accepter une invitation : le jeu se lance et arrive dans le lobby.
- [ ] Lobby public : visible par un compte qui n'est pas ami. Lobby privé : invisible.
- [ ] Lobby plein, lobby d'une autre `protocol_version` : refus avec le bon message.
- [ ] Lancer la partie, jouer, revenir au lobby.
- [ ] Exclure un joueur : il revient au menu avec le message, et ne peut pas revenir.
- [ ] L'hôte quitte : les clients reviennent au menu avec « The host left the lobby ».
- [ ] Rejoindre une partie en cours, avec `allow_join_in_progress` activé puis désactivé.

## Limites connues

- Pas de migration d'hôte : quand l'hôte part, le lobby se ferme pour tous.
- L'exclusion demande au joueur de partir, puis coupe sa connexion à l'hôte. Steam ne permet pas de retirer quelqu'un d'un lobby : un client modifié peut y rester inscrit, mais il n'est plus dans la partie.
- Les textes de l'interface sont en anglais.
