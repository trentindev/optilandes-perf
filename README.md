# Optilandes : TP d'optimisation des performances en production

Ce dépôt contient une mini-application de prise de rendez-vous de livraison, inspirée du scénario Optilandes, et tout ce qu'il faut pour la mettre en production sur un poste de travail.

Le TP consiste à :

- mesurer ses performances sous charge ;
- trouver ses goulots d'étranglement ;
- les corriger un par un en mesurant chaque gain ;
- faire tout cela sans interrompre le service.

## Prérequis

- Une distribution Ubuntu, installée nativement ou sous WSL2.
- Docker et Docker Compose, utilisables sans `sudo`.
- Git.

Sous WSL2, le dépôt doit être cloné dans le dossier personnel Linux (`~`), jamais dans un dossier Windows (`/mnt/c/...`). Les accès disque à travers Windows sont très lents et fausseraient toutes les mesures.

## Avant la séance (connexion Internet nécessaire)

Chaque bloc de commandes se lance seul, après la fin du précédent.

1. Cloner le dépôt :

```bash
cd ~
git clone <adresse-du-depot> optilandes-perf
cd optilandes-perf
```

2. Télécharger les images et construire l'application en versions 1.0.0 et 1.1.0. L'opération dure plusieurs minutes :

```bash
./scripts/preparer.sh
```

3. Une fois la préparation terminée, vérifier le poste. Le script doit se terminer sans erreur :

```bash
./scripts/verifier-poste.sh
```

## Démarrer l'application

1. Démarrer les services :

```bash
docker compose up -d
```

2. Suivre leur état. Au premier démarrage, PostgreSQL charge 500 000 rendez-vous de démonstration : on relance cette commande jusqu'à ce que `db` puis `app-bleu` soient `healthy`.

```bash
docker compose ps
```

3. Vérifier que l'application répond :

```bash
curl http://localhost:8080/health
```

## L'architecture

| Service | Rôle | Processeur maximum | Mémoire maximum |
| --- | --- | --- | --- |
| `caddy` | Reverse proxy, seul point d'entrée, sur le port 8080 du poste | 0,5 | 128 Mo |
| `app-bleu` | Application, environnement bleu, actif au démarrage | 1 par instance | 512 Mo par instance |
| `app-vert` | Application, environnement vert, démarré à la demande | 1 par instance | 512 Mo par instance |
| `db` | Base PostgreSQL 16 | 1 | 512 Mo |
| `k6` | Générateur de charge, lancé à la demande | 1 | 512 Mo |

Les limites de processeur et de mémoire définissent le « serveur » étudié. Elles sont identiques sur tous les postes : toute modification doit être notée et justifiée dans le rapport.

## Les points d'accès

| Méthode | Chemin | Rôle | Exemple |
| --- | --- | --- | --- |
| GET | `/health` | L'application répond-elle ? | `curl http://localhost:8080/health` |
| GET | `/creneaux` | Créneaux libres d'une zone pour une date | `curl "http://localhost:8080/creneaux?zone=3&date=2026-11-05"` |
| POST | `/rendez-vous` | Prise d'un rendez-vous | voir ci-dessous |
| GET | `/livraisons` | Livraisons d'une zone pour une date | `curl "http://localhost:8080/livraisons?zone=3&date=2026-11-02"` |
| GET | `/tournees` | Tournée optimisée d'une zone pour une date | `curl "http://localhost:8080/tournees?zone=3&date=2026-11-02"` |

```bash
curl -X POST http://localhost:8080/rendez-vous \
  -H "Content-Type: application/json" \
  -d '{"client_id": 3, "zone_id": 3, "date_livraison": "2026-11-05", "creneau": 2}'
```

Les données couvrent les dates du 2 novembre 2026 au 1er mars 2027, sur 24 zones. Les clients de la zone z portent les numéros z, z + 24, z + 48, etc.

Chaque réponse contient trois en-têtes utiles :

- `X-Temps-Traitement-ms` : durée du traitement dans l'application ;
- `X-Version` : version de l'application qui a répondu ;
- `X-Instance` : instance qui a répondu.

## Les réglages de l'application

Les réglages se trouvent dans `config/bleu.env` et `config/vert.env`, un fichier par environnement.

| Variable | Rôle |
| --- | --- |
| `WORKERS` | Nombre de processus de l'application par instance |
| `DB_POOL_MAX` | Nombre maximal de connexions à la base, par processus |
| `DB_POOL_TIMEOUT` | Délai d'attente d'une connexion libre, en secondes. Au-delà, l'application répond 503 |
| `CACHE_TTL` | Durée de vie du cache des créneaux et des tournées, en secondes. 0 désactive le cache |
| `LOG_REQUETES` | Journalisation de chaque requête : 1 pour oui, 0 pour non |

Le fichier `.env` fixe le port publié et la version de l'application de chaque environnement.

## Mesurer

Lancer une charge nominale, à 10 requêtes par seconde pendant 3 minutes :

```bash
docker compose run --rm k6 run /scripts/nominal.js
```

Changer le débit et la durée, et garder le résultat :

```bash
docker compose run --rm -e DEBIT=20 -e DUREE=1m k6 run /scripts/nominal.js | tee resultats/nominal-20.txt
```

Mesurer plusieurs débits à la suite :

```bash
for debit in 10 20 40; do
  docker compose run --rm -e DEBIT=$debit -e DUREE=1m k6 run /scripts/nominal.js | tee resultats/palier-$debit.txt
done
```

Les autres scénarios :

```bash
docker compose run --rm k6 run /scripts/montee.js
docker compose run --rm k6 run /scripts/pic.js
```

Les seuils du SLA sont vérifiés à la fin de chaque test : 95 % des requêtes en moins de 2 secondes, moins de 0,5 % d'erreurs. Pour les adapter à un autre SLA :

```bash
docker compose run --rm -e SLA_MS=1500 -e ERREURS_MAX=0.01 k6 run /scripts/nominal.js
```

## Observer

Consommation des conteneurs, en continu :

```bash
docker stats
```

Processus d'un conteneur :

```bash
docker top optilandes-app-bleu-1
```

Avec Docker Desktop, les processus des conteneurs ne sont pas visibles depuis Ubuntu avec `top` : on utilise `docker stats` et `docker top`.

Journaux de l'application et du reverse proxy :

```bash
docker compose logs -f app-bleu
docker compose logs -f caddy
```

Console PostgreSQL :

```bash
docker compose exec db psql -U optilandes -d optilandes
```

Requêtes les plus coûteuses, depuis la console PostgreSQL :

```sql
SELECT calls, round(total_exec_time) AS total_ms, round(mean_exec_time::numeric, 2) AS moyenne_ms, left(query, 80) AS requete
FROM pg_stat_statements
ORDER BY total_exec_time DESC
LIMIT 10;
```

Remise à zéro de ces statistiques :

```sql
SELECT pg_stat_statements_reset();
```

Connexions ouvertes et leur état :

```sql
SELECT state, count(*) FROM pg_stat_activity WHERE datname = 'optilandes' GROUP BY state;
```

Plan d'exécution d'une requête :

```sql
EXPLAIN ANALYZE SELECT count(*) FROM rendez_vous WHERE zone_id = 3 AND date_livraison = '2026-11-05';
```

## Faire évoluer la production sans interruption

### Ajouter des instances

Ajouter des instances à l'environnement bleu, jusqu'à 3 :

```bash
docker compose up -d --scale app-bleu=3
```

Caddy répartit les requêtes entre les instances en bonne santé. Il vérifie chacune d'elles toutes les secondes sur `/health`. Tant que les instances 2 et 3 n'existent pas, les journaux de Caddy le signalent chaque seconde par un message « HTTP request failed » : c'est normal.

### Changer de réglages ou de version : bascule bleu vers vert

1. Préparer `config/vert.env`, et si besoin la version dans `.env` (`VERSION_VERT`).
2. Démarrer l'environnement vert :

```bash
docker compose --profile vert up -d app-vert
```

3. Suivre son état, jusqu'à ce que l'instance verte soit `healthy` :

```bash
docker compose ps
```

4. Basculer le trafic :

```bash
./scripts/basculer.sh vert
```

5. Laisser les requêtes en cours se terminer pendant 30 secondes au minimum, puis arrêter l'ancien environnement :

```bash
docker compose stop app-bleu
```

Pour revenir au bleu, on suit la même démarche en sens inverse avec `./scripts/basculer.sh bleu`.

Un test de charge lancé pendant toute la bascule permet de vérifier qu'aucune requête n'a échoué.

## Repartir de zéro

1. Arrêter tous les services et supprimer le volume de la base. Toutes les données, ainsi que les index ajoutés, seront rechargées depuis `db/init` :

```bash
docker compose --profile vert --profile outils down -v
```

2. Redémarrer, puis suivre l'état des services comme au premier démarrage :

```bash
docker compose up -d
```

## Contenu du dépôt

| Chemin | Contenu |
| --- | --- |
| `app/` | Code de l'application (Python, FastAPI, Gunicorn) |
| `caddy/` | Configuration du reverse proxy |
| `config/` | Réglages des environnements bleu et vert |
| `db/init/` | Structure et données de la base, chargées au premier démarrage |
| `k6/` | Scénarios de charge |
| `scripts/` | Préparation et vérification du poste, bascule bleu vers vert |
| `resultats/` | Dossier pour conserver les résultats des tests |

Les versions de l'application sont repérées par les étiquettes Git `v1.0.0` et `v1.1.0`.
