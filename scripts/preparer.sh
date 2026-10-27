#!/usr/bin/env bash
# Prépare le poste AVANT la séance (connexion Internet nécessaire) :
#   - crée le fichier .env ;
#   - télécharge les images Caddy, PostgreSQL et k6 ;
#   - construit les images de l'application en versions 1.0.0 et 1.1.0.
set -euo pipefail
cd "$(dirname "$0")/.."

if [ ! -f .env ]; then
    cp .env.example .env
    echo "Fichier .env créé à partir de .env.example"
fi

echo "Téléchargement des images Caddy, PostgreSQL et k6..."
docker compose --profile outils pull caddy db k6

for version in 1.0.0 1.1.0; do
    echo "Construction de l'image optilandes-app:${version}..."
    # Le code de chaque version est extrait de l'étiquette Git correspondante.
    # --network host : la construction utilise le DNS du poste (indispensable sous WSL2).
    git archive "v${version}:app" | docker build --network host --tag "optilandes-app:${version}" -
done

echo
echo "Préparation terminée. Vérifier le poste avec : ./scripts/verifier-poste.sh"
