# Réseau

Le code réseau du jeu, en deux parties :

- `lobby/` gère le lobby : créer, rejoindre, inviter, se déclarer prêt, exclure, lancer la partie, revenir au lobby, se reconnecter. Il fonctionne avec Steam (via GodotSteam) et, pour tester sans Steam, en local sur une seule machine (ENet).
- `gameplay/` contient les briques réseau utilisées pendant la partie : état partagé, apparition d'objets, actions validées par l'hôte, déplacement fluide des autres joueurs.

Le jeu ne parle au lobby que par un seul objet, l'autoload `Lobby`.

**Qui décide de quoi.** Chaque joueur fait autorité sur le déplacement de son propre personnage. Tout le reste (qui est dans le lobby, les scores, qui ramasse quoi, où on réapparaît) est décidé par l'hôte.

## Régler le lobby

Les réglages sont dans `config/lobby_config.tres` (une ressource `LobbyConfig`). À renseigner pour un nouveau jeu :

- `game_scene` : la scène de jeu à charger au lancement ;
- `game_key` : un identifiant propre au jeu ;
- `steam_app_id` : l'identifiant Steam du jeu (480 est l'app de test de Valve).

| Réglage | Rôle |
|---|---|
| `max_players` | Nombre maximum de joueurs, hôte compris. |
| `default_visibility` | Privé (sur invitation), amis, ou public. |
| `game_key` | Distingue vos lobbies de ceux des autres jeux de la même app Steam. Indispensable avec l'app de test 480. |
| `protocol_version` | À augmenter quand deux versions du jeu ne sont plus compatibles en réseau. |
| `allow_join_in_progress` | Autorise un nouveau joueur à rejoindre une partie lancée. |
| `require_all_ready` | L'hôte ne peut lancer que si tous les joueurs sont prêts. |
| `reconnect_grace` | Durée pendant laquelle la place d'un joueur déconnecté en pleine partie est gardée. 0 pour désactiver. |
| `main_menu_scene`, `lobby_list_scene`, `lobby_scene`, `game_scene` | Les scènes du parcours. |
| `auto_navigation` | Le lobby enchaîne lui-même menu, lobby et jeu. À désactiver pour piloter les scènes depuis le code du jeu. |
| `join_timeout`, `load_timeout`, `dismiss_grace` | Délais maximum, en secondes. |
| `connection_timeout` | Délai sans réponse au-delà duquel un joueur (ou l'hôte) est considéré comme déconnecté. |
| `default_backend` | `steam` ou `enet`. L'argument `--lobby-backend=` a priorité. |
| `steam_app_id`, `enet_port` | Réglages des backends. |

`allow_join_in_progress` ne fait que charger la scène et faire apparaître le nouveau joueur. `MatchState` lui transmet la phase, le chrono et les scores ; tout autre état propre au jeu reste à lui transmettre.

Une instance mise en pause dans le débogueur plus longtemps que `connection_timeout` est retirée du lobby. Augmenter ce délai pendant une session de débogage, ou le mettre à 0.

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

Le backend ENet n'a ni amis, ni invitations, ni vraie liste de lobbies : les boutons correspondants sont masqués. Tout le reste se comporte comme sur Steam, parce que c'est synchronisé par RPC et non par Steam.

### Simuler une mauvaise connexion

Sur une seule machine, la connexion est parfaite : aucun délai, aucune perte. Trois arguments donnent à une instance la connexion d'un joueur mal connecté :

```
--lobby-backend=enet --lobby-name=Alice --net-latency=150 --net-jitter=30 --net-loss=5
```

| Argument | Effet |
|---|---|
| `--net-latency=150` | Ajoute 150 ms à la latence de cette instance : la moitié sur ce qu'elle envoie, la moitié sur ce qu'elle reçoit. |
| `--net-jitter=30` | Retarde chaque paquet d'une durée aléatoire, jusqu'à 30 ms. Les paquets non ordonnés se doublent. |
| `--net-loss=5` | Perd 5 % des paquets dans chaque sens. Ce qui est envoyé en non fiable (positions, mesures de latence) disparaît ; ce qui est envoyé en fiable arrive en retard, comme après un renvoi. |

La latence affichée dans le lobby et dans le tableau des scores reflète ce qui est simulé. Ces arguments ne sont lus que dans une version de débogage, et fonctionnent avec n'importe quel backend, Steam compris : la simulation enveloppe la connexion, elle ne dépend pas du transport.

Depuis le code, `Lobby.network_conditions = NetworkConditions.new()` fait la même chose avant de créer ou de rejoindre un lobby. Ses valeurs (`latency_ms`, `jitter_ms`, `loss_percent`) peuvent être modifiées en cours de partie.

La simulation mélange les paquets plus qu'un vrai réseau, où deux paquets envoyés à la suite prennent presque toujours le même chemin. Elle sert à trouver ce qui casse, pas à mesurer une qualité de jeu.

## Le lobby

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
	print(member.name, member.is_host, member.is_ready, member.ping)

Lobby.set_member_data("color", "red")  # sur soi-même
Lobby.set_ready(true)
Lobby.kick(member)                     # hôte uniquement
```

- Signaux : `member_joined(member)`, `member_left(member)`, `member_updated(member, key)`.
- Les données d'un joueur (`member.data`) sont libres : personnage, équipe, couleur. Un joueur n'écrit que les siennes, l'hôte peut écrire celles de tous.
- `member.user_id` identifie l'utilisateur (son identifiant Steam) et ne change pas s'il se reconnecte. `member.peer_id` identifie sa connexion.
- `member.ping` est la latence entre l'hôte et le joueur, en millisecondes, mesurée toutes les 2 secondes.
- L'hôte valide chaque changement. Pour ajouter vos règles : `Lobby.member_data_validator = func(member, key, value) -> bool`.
- Pour réserver une donnée à l'hôte (une équipe attribuée par le jeu) : `Lobby.host_only_member_keys.append("team")`.
- `Lobby.set_lobby_data("map", "forest")` partage une donnée du lobby entier (hôte uniquement), lue avec `Lobby.get_lobby_data("map")`. Elle survit aux changements de scène.

### Lancer la partie

```gdscript
Lobby.start_game()                     # hôte : charge `game_scene` chez tout le monde
Lobby.change_game_scene(path)          # hôte, en partie : niveau suivant
Lobby.return_to_lobby()                # hôte, en partie : retour au lobby pour tous
```

L'hôte attend que tous les joueurs aient chargé la scène. `game_started` est alors émis chez chacun, puis `member_scene_ready(member)` pour chaque joueur. Ce dernier signal est émis de nouveau pour chaque joueur qui arrive ou revient en cours de partie : c'est le moment de faire apparaître ce qui lui appartient.

### Reconnexion

Quand la connexion d'un joueur tombe en pleine partie, l'hôte garde sa place pendant `reconnect_grace` (60 secondes par défaut) : son nom, ses données, et son score puisque `MatchState` le range par utilisateur.

- Le joueur reçoit `left(CONNECTION_LOST)`. `Lobby.can_rejoin()` devient vrai, et le menu principal affiche « Rejoin game » (`Lobby.rejoin()`).
- À son retour, il retrouve ses données, charge la scène de jeu et `member_scene_ready` est émis pour lui : son personnage réapparaît.
- Une place réservée compte dans `max_players`. Elle est libérée à la fin du délai ou au retour au lobby.
- Un joueur qui quitte volontairement ou qui est exclu ne garde pas de place.
- Côté hôte, `Lobby.get_absent_members()` liste les joueurs dont la place est gardée.

Pendant une partie verrouillée (`allow_join_in_progress` désactivé), seuls les joueurs qui ont une place réservée sont admis.

## Les briques de gameplay

Elles se posent dans la scène de jeu. `scenes/maps/prototype/` et `scenes/gameplay/game/round/collect_round.gd` montrent comment elles s'assemblent.

### `NetworkSpawner` : faire apparaître des objets

Un `MultiplayerSpawner` pour les personnages, les objets à ramasser, les projectiles. Lister les scènes possibles dans `scenes`, régler `spawn_path`, puis côté hôte :

```gdscript
var coin: Node = spawner.spawn_scene(coin_scene, { "position": Vector3(2, 1, 0) })
coin.queue_free()                                  # disparaît chez tout le monde

spawner.spawn_scene(player_scene, {}, member.peer_id, str(member.peer_id))  # donné à un joueur
```

Ce qu'un joueur possédait est libéré quand il quitte la partie.

### `ReplicationGate` : ne rien envoyer trop tôt

Godot réplique un objet vers un joueur dès qu'il est connecté, même s'il n'a pas encore chargé la scène. L'objet est alors perdu, et ses mises à jour n'arrivent plus jamais chez ce joueur.

- Les objets créés par `NetworkSpawner` sont protégés automatiquement.
- Pour un objet répliqué **posé dans la scène** (une plateforme mobile avec son `MultiplayerSynchronizer`), ajouter un nœud `MultiplayerSynchronizer` avec le script `replication_gate.gd` comme enfant direct de l'objet, sans rien configurer.

### `MatchState` : l'état de la partie

Un nœud tenu par l'hôte et connu de tous : la phase et son chrono, les scores, et toute autre valeur commune.

```gdscript
# Hôte
match_state.start_phase(MatchState.PHASE_PLAYING, 60.0)
match_state.add_score(member.user_id)
match_state.set_value("target", 10)

# Tout le monde
match_state.phase_changed.connect(_on_phase_changed)
print(match_state.time_left, match_state.get_score(user_id), match_state.get_ranking())
```

- `phase_time_elapsed(phase)` est émis à la fin du chrono : l'hôte décide de la suite.
- Un joueur qui arrive en cours reçoit l'état complet.
- Les scores et les noms sont rangés par `user_id` : un joueur parti reste dans le classement, et retrouve son score s'il revient.
- L'état vit et meurt avec la scène de jeu. Ce qui doit survivre à un changement de scène va dans `Lobby.set_lobby_data()`.

### `HostActions` : le joueur demande, l'hôte décide

Pour tout ce qui compte dans la partie : ramasser, frapper, interagir, réapparaître.

```gdscript
# Sur chaque joueur, dans _ready()
actions.register(&"collect", _can_collect, _collect)

# Le joueur qui agit
actions.request(&"collect", [coin.name])

# Chez l'hôte uniquement
func _can_collect(member: LobbyMember, arguments: Array) -> bool:
	...  # vérifier le nombre et le type des arguments, la distance, la phase

func _collect(member: LobbyMember, arguments: Array) -> void:
	coin.queue_free()                        # répliqué par NetworkSpawner
	match_state.add_score(member.user_id)    # répliqué par MatchState
```

- L'hôte sait qui demande grâce à la connexion, jamais grâce au message.
- Les arguments viennent d'une autre machine : toujours les vérifier dans la fonction de validation. Envoyer un nom de nœud, pas un nœud.
- `register()` accepte un délai minimum entre deux actions d'un même joueur, et une option pour rejouer l'action chez tous (un son, un effet).
- `HostActions.find_for(self)` retrouve le nœud depuis n'importe quel objet de la scène.

### `NetworkSmoother` : déplacement fluide des autres joueurs

Un nœud enfant de l'objet. Le `MultiplayerSynchronizer` réplique `sync_position`, `sync_rotation` et `sync_teleport_count` de ce nœud au lieu de la position de l'objet. Chez les autres joueurs, l'objet glisse vers la dernière valeur reçue, ce qui permet de n'envoyer que 20 mises à jour par seconde (`replication_interval`).

Après un déplacement instantané (réapparition, téléporteur), appeler `smoother.teleport()` chez le propriétaire : les autres placent l'objet d'un coup au lieu de le faire glisser.

### Réapparition

`PlayerSpawner` fait apparaître un personnage par joueur et gère la réapparition. Un personnage qui tombe sous `fall_limit` demande l'action `respawn` ; l'hôte choisit un point d'apparition et demande au propriétaire de s'y téléporter. Côté hôte, `player_spawner.respawn(peer_id)` fait la même chose à la demande du jeu.

## L'interface

Les écrans du lobby sont dans `scenes/UI/menus/` (menu principal, liste des lobbies, lobby, invitations). Ils n'utilisent que l'API publique de `Lobby` : on peut les modifier ou les remplacer librement. Leurs chemins sont dans `LobbyConfig`.

`Lobby.supports_friends`, `supports_invites` et `supports_invite_overlay` indiquent ce que le backend sait faire, pour masquer le reste.

## Architecture

```
interface, jeu  →  Lobby (LobbyService)  →  LobbyBackend (Steam ou ENet)
                       ├─ MemberSync : joueurs, données, exclusion, places réservées
                       ├─ SceneSync  : chargement synchronisé
                       └─ Ping       : latence, détection des joueurs injoignables
```

| Dossier | Contenu |
|---|---|
| `network/lobby/core/` | La façade, le registre des joueurs, le chargement synchronisé, la latence, la config, la classe de base des backends. |
| `network/lobby/backends/` | Steam et ENet. Seul `backends/steam/` connaît Steam. |
| `network/gameplay/` | Les briques de la partie. |
| `network/debug/` | La simulation de mauvaise connexion. |
| `scenes/managers/` | Le chargeur de scènes (`SceneLoader`, utilisable seul) et l'enchaînement des écrans. |
| `scenes/UI/menus/` | Les écrans du lobby. |
| `scenes/gameplay/` | Le personnage, l'apparition des joueurs, la manche de collecte, le HUD. |

Principes :
- Les dépendances vont dans un seul sens. Un backend ne connaît ni la façade ni l'interface.
- L'hôte fait autorité : il admet les joueurs, établit leur identité et valide leurs données.
- Tout nœud qui reçoit des RPC a le même nom et le même chemin chez tous les joueurs.
- On n'envoie rien sur la scène de jeu à un joueur qui ne l'a pas chargée. `Lobby.scene_ready_peers` donne ceux qui l'ont.
- Le code de `scenes/` utilise l'autoload `Lobby`. Le code de `network/` ne le cite jamais par son nom et passe par `LobbyService.for_node(self)`, ce qui permet de faire tourner plusieurs joueurs dans un même test.

### Écrire un autre backend

Hériter de `LobbyBackend`, implémenter `create`, `join`, `leave`, `get_peer`, `get_local_identity` et `resolve_identity`, puis l'ajouter à `BACKEND_SCRIPTS` dans `lobby_autoload.gd`. `backends/enet/enet_lobby_backend.gd` est l'exemple le plus court. Un backend répond toujours par signal, jamais dans l'appel lui-même.

## Tests

```
godot --headless --path . -s addons/gut/gut_cmdln.gd -gexit    # tests unitaires (GUT), dans tests/unit/
tests/e2e/run.sh                                               # le vrai jeu, à 3 instances
```

Les tests unitaires font tourner plusieurs joueurs dans le même processus, sur une vraie connexion ENet. `tests/support/game_test.gd` sert de base à un test qui a besoin d'une partie en cours.

Le script `run.sh` lance trois instances du jeu : un hôte, un client et un joueur qui arrive en cours de partie. Ils vérifient les positions, la réapparition, le ramassage des pièces, les scores, une coupure de connexion suivie d'un retour, la fin de manche, l'exclusion et le départ de l'hôte.

Les deux se rejouent sur une mauvaise connexion simulée, avec des variables d'environnement :

```
NET_LATENCY=100 NET_JITTER=30 NET_LOSS=5 godot --headless --path . -s addons/gut/gut_cmdln.gd -gexit
NET_LATENCY=150 NET_JITTER=30 NET_LOSS=5 tests/e2e/run.sh
```

Chaque joueur des tests reçoit alors cette connexion, et les tests attendent trois fois plus longtemps. Un test peut aussi donner une mauvaise connexion à certains joueurs seulement (`conditions` dans `game_test.gd`).

Dans ce mode, un test qui exige « aucune erreur moteur » peut échouer de temps en temps : une mise à jour arrivée après un changement de scène est signalée par le moteur (voir les limites connues). Un échec qui porte sur autre chose mérite d'être regardé.

Pour ne pas embarquer les tests dans le jeu exporté, ajouter `tests/*, addons/gut/*` aux filtres d'exclusion des préréglages d'export.

## À vérifier sur Steam

Le backend Steam a été écrit sans pouvoir être exécuté : il compile avec GodotSteam 4.24, mais **aucun parcours Steam n'a encore été testé**. À faire avec deux comptes, sur deux machines ou une machine et une VM :

- [ ] Créer un lobby, le voir chez un ami dans « Join lobby », le rejoindre.
- [ ] Les noms des joueurs et leur latence s'affichent chez tout le monde.
- [ ] Inviter depuis la liste d'amis du lobby et depuis le bouton « Invite... ».
- [ ] Accepter une invitation depuis le jeu, puis depuis l'overlay Steam.
- [ ] Jeu fermé, accepter une invitation : le jeu se lance et arrive dans le lobby.
- [ ] Lobby public : visible par un compte qui n'est pas ami. Lobby privé : invisible.
- [ ] Lobby plein, lobby d'une autre `protocol_version` : refus avec le bon message.
- [ ] Lancer la partie : personnages visibles et fluides, pièces, scores, résultats, retour au lobby.
- [ ] Exclure un joueur : il revient au menu avec le message, et ne peut pas revenir.
- [ ] L'hôte quitte : les clients reviennent au menu avec « The host left the lobby ».
- [ ] Rejoindre une partie en cours, avec `allow_join_in_progress` activé puis désactivé.
- [ ] Couper le réseau d'un client en pleine partie, puis « Rejoin game » : il retrouve son score.
- [ ] Un client quitte volontairement en pleine partie : sa place n'est pas gardée chez l'hôte.

Deux points propres à Steam à surveiller pendant ces essais :
- Le message d'un départ volontaire part juste avant la fermeture de la connexion. S'il n'arrive pas, la place du joueur est gardée pendant `reconnect_grace` : sans gravité, mais à constater.
- Un lobby en partie reste joignable au niveau de Steam tant que `reconnect_grace` est positif, pour permettre le retour d'un joueur déconnecté. C'est l'hôte qui refuse les autres, avec le message « The game has already started ».

## Limites connues

- Pas de migration d'hôte : quand l'hôte part, le lobby se ferme pour tous.
- L'exclusion demande au joueur de partir, puis coupe sa connexion à l'hôte. Steam ne permet pas de retirer quelqu'un d'un lobby : un client modifié peut y rester inscrit, mais il n'est plus dans la partie.
- Le déplacement d'un personnage n'est pas vérifié par l'hôte : un client modifié peut se déplacer comme il veut. Les actions de jeu, elles, sont validées.
- Les textes de l'interface sont en anglais.
- Avec beaucoup de latence et de pertes (essayé à 300 ms et 15 %), le moteur écrit des erreurs « Node not found » dans le journal : une mise à jour d'un personnage est arrivée chez un joueur avant le personnage lui-même, ou après sa disparition. Elle est ignorée et la suivante passe ; le jeu n'est pas affecté.
