# workflow-claude

Ensemble de scripts et de config mis au point avec Claude pour automatiser le
workflow "Claude clone un repo, travaille dessus, push, et le pull se fait
automatiquement en local pour que je puisse tester et reviewer".

Pense a bien lire les commentaires/placeholders dans chaque fichier avant de
les utiliser : aucun token, secret ou chemin personnel n'a ete laisse dans ce
dossier volontairement.

## Vue d'ensemble du workflow

1. Claude clone un repo GitHub et travaille sur une branche `dev` dediee
   (jamais directement sur `main`).
2. Claude push ses changements sur `dev`.
3. Un webhook GitHub notifie un petit serveur local (via un relais smee.io,
   pratique quand on n'a pas d'IP publique/port ouvert) a chaque push.
4. Ce serveur local (`webhook_listener.py`) declenche automatiquement un
   `git pull` sur le repo concerne, donc le code arrive en local sans action
   manuelle.
5. Un CI GitHub Actions (a mettre en place separement, pas fourni ici de
   facon generique car specifique a chaque stack) peut aussi tourner a
   chaque push et ecrire un rapport de statut committe dans le repo, pour
   que Claude puisse lire les resultats directement en local plutot que
   d'interroger l'API GitHub a chaque fois.
6. Un watchdog reseau rattrape les evenements webhook manques en cas de
   coupure de connexion.
7. On merge `dev` dans `main` seulement quand le travail est valide.

## Contenu

### scripts/

- **webhook_listener.py** : petit serveur HTTP qui recoit les webhooks push
  de GitHub (relayes via smee.io) et declenche un `git pull` sur le repo
  local correspondant. Voir `REPO_MAP` en haut du fichier pour la config.
  Necessite un secret partage avec la config du webhook GitHub (a generer
  toi-meme, jamais le meme que celui d'un autre usage).

- **network_watchdog.sh** : surveille la connectivite reseau en continu.
  Des qu'il detecte un retour de connexion apres une coupure, il fait un
  `fetch` + compare + `pull` sur tous les repos listes dans `REPOS`, pour
  rattraper les webhooks potentiellement manques pendant la coupure.

- **watch_repos.sh** : alternative/complement au webhook, verifie par
  polling (toutes les N secondes) si un repo a des changements distants et
  pull automatiquement. Utile en secours si le webhook tombe en panne, ou
  si tu ne veux pas mettre en place toute l'infra webhook/smee.

- **create_dev_branches.sh** : cree une branche `dev` a partir de la branche
  courante sur tous les repos git trouves recursivement sous un dossier
  donne, et la pousse sur le remote si possible.

- **convert_to_ssh_recursive.sh** : convertit les remotes `origin` de HTTPS
  vers SSH sur tous les repos git trouves recursivement sous un dossier
  donne (utile si tu es fatigue de rentrer tes identifiants a chaque push).

- **before_work.sh** : a lancer avant de reprendre un travail sur un repo
  deja clone. Verifie qu'il n'y a pas de modifications locales non
  commitees, puis fetch/pull si le distant a avance, en affichant ce qui a
  change.

### systemd/

Trois services utilisateur systemd (`~/.config/systemd/user/`) pour faire
tourner le webhook et le watchdog en continu, sans terminal ouvert :

- **smee-client.service** : relais smee.io -> localhost. Remplace
  `TON_CANAL_ICI` par ton propre canal smee (cree un sur https://smee.io).
- **webhook-listener.service** : lance `webhook_listener.py`.
  `PYTHONUNBUFFERED=1` est important, sinon les logs Python restent
  bufferises et n'apparaissent pas dans `journalctl` en temps reel.
- **network-watchdog.service** : lance `network_watchdog.sh`.

Apres avoir copie ces fichiers dans `~/.config/systemd/user/` et ajuste les
chemins/placeholders :

```bash
systemctl --user daemon-reload
systemctl --user enable --now smee-client.service
systemctl --user enable --now webhook-listener.service
systemctl --user enable --now network-watchdog.service
```

Pour que les services tournent meme apres deconnexion de la session :

```bash
loginctl enable-linger $USER
```

### prompt-generique.md

Modele de prompt a copier/adapter en debut de conversation avec Claude pour
lui donner le contexte du workflow attendu sur un repo donne (branches,
authentification, quand fetch/pull, comment vaerifier le CI, etc.). Remplace
les placeholders entre crochets par les vraies valeurs a chaque usage - ne
jamais laisser un token en clair dans un prompt que tu pourrais partager ou
committer par erreur.

## Mise en place resumee pour un nouveau repo

1. Cree une branche `dev` sur le repo (`create_dev_branches.sh` ou
   manuellement).
2. Ajoute un webhook GitHub (Settings > Webhooks) pointant vers ton URL
   smee.io, content-type `application/json` (important : GitHub met
   `application/x-www-form-urlencoded` par defaut, ce qui casse tout),
   avec le meme secret que dans `webhook_listener.py`.
3. Ajoute une entree dans `REPO_MAP` du script avec le nom exact du repo
   GitHub (`compte/nom-repo`), le chemin local, et la branche a surveiller.
4. Redemarre `webhook-listener.service`.
5. Teste avec un petit push et verifie `journalctl --user -u
   webhook-listener.service -f`.

## Pieges deja rencontres (pour gagner du temps)

- **Content-type du webhook** : doit etre `application/json`, pas la valeur
  par defaut de GitHub.
- **Nom du repo dans REPO_MAP** : doit correspondre exactement au nom GitHub
  (`compte/repo`), pas a un nom de dossier local abrege.
- **Buffering Python** : sans `PYTHONUNBUFFERED=1`, les `print()` du script
  n'apparaissent pas dans les logs systemd avant un moment (buffer plein ou
  fin de process), rendant le debug tres confus.
- **`pipefail` en bash** : si un `run:` de CI utilise `commande | tee
  fichier.log`, le code de sortie du step devient celui de `tee` (toujours
  0), pas celui de `commande` - un step peut donc apparaitre "success" alors
  que la commande a echoue. Ajouter `set -o pipefail` (ou eviter le pipe et
  utiliser une redirection simple `> fichier.log 2>&1`).
- **Coupures reseau locales** : smee.io utilise un flux SSE sans mecanisme
  de rattrapage - un evenement recu pendant une coupure reseau est perdu
  definitivement. D'ou le watchdog reseau en complement.
