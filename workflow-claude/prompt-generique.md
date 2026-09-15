# Workflow git - prompt generique

Repo : [URL_DU_REPO]
[Description rapide du projet et de son stack]. Compte GitHub : [TON_COMPTE_GITHUB]

## Authentification

Utilise ce PAT pour toutes les operations git (clone, fetch, push) et pour l'API GitHub :
[COLLER_LE_TOKEN_ICI]

## Branches

- `main` : branche stable, je merge dedans seulement apres validation de mon cote.
- `dev` : branche de travail ou tu ecris librement. Ne push jamais directement sur `main`.

## Demarrage d'une session

1. Si le repo n'est pas deja clone en local, clone-le et checkout `dev`.
2. Si deja clone, fais `git fetch origin dev` avant toute modification et compare avec ta version locale. S'il y a des commits distants que tu n'as pas, pull-les d'abord et dis-moi ce qui a change.

## Avant chaque modification

Dis-moi ce que tu comptes faire (fichier, changement, raison) avant de modifier quoi que ce soit de significatif. Pour des changements mineurs deja discutes, tu peux proceder et resumer apres coup.

## Fin d'une modification

1. Commit avec un message clair et descriptif (pas de message generique type "update").
2. Push sur `dev` (jamais sur `main`).
3. Dis-moi precisement quel commit a ete pousse et ce qu'il contient.

## CI automatique (si mis en place)

Si le repo a un workflow GitHub Actions (`.github/workflows/ci.yml`), verifie toi-meme le resultat apres chaque push, sans attendre qu'on te le demande :

```bash
curl -s -H "Authorization: token [TOKEN]" \
  -H "Accept: application/vnd.github+json" \
  "https://api.github.com/repos/[COMPTE]/[REPO]/actions/runs?branch=dev&per_page=1"

curl -s -H "Authorization: token [TOKEN]" \
  -H "Accept: application/vnd.github+json" \
  "https://api.github.com/repos/[COMPTE]/[REPO]/actions/runs/RUN_ID/jobs"
```

Si le CI ecrit un fichier de log (ex: `ci-status.md`) commite automatiquement apres chaque run, tu peux le lire directement apres un `git pull` plutot que d'appeler l'API.

Si le workflow echoue, dis-moi precisement quelle etape a echoue et pourquoi, sans corriger le code toi-meme sauf si je te le demande explicitement.

## Reprise apres ma review

Avant de continuer un travail apres un delai ou apres ma review, refais `git fetch origin dev` au cas ou quelque chose ait change entre-temps (par moi ou par une autre session de travail sur ce repo).
