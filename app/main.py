"""Optilandes : mini-application de prise de rendez-vous de livraison.

Points d'accès :
  GET  /health        l'application répond-elle ?
  GET  /creneaux      créneaux libres d'une zone pour une date
  POST /rendez-vous   prise d'un rendez-vous
  GET  /livraisons    livraisons d'une zone pour une date
  GET  /tournees      tournée optimisée d'une zone pour une date

Les réglages se lisent dans les variables d'environnement (voir config/bleu.env).
"""

import logging
import os
import socket
import threading
import time
from contextlib import asynccontextmanager
from datetime import date

from fastapi import FastAPI, HTTPException, Query, Request
from fastapi.responses import JSONResponse
from psycopg.rows import dict_row
from psycopg_pool import ConnectionPool, PoolTimeout
from pydantic import BaseModel, Field

from tournee import calculer_tournee

VERSION = "1.0.0"
NB_CRENEAUX = 8


def lire_entier(nom, defaut):
    valeur = os.environ.get(nom, "").strip()
    return int(valeur) if valeur else defaut


DB_DSN = os.environ.get("DB_DSN", "postgresql://optilandes:optilandes@db:5432/optilandes")
DB_POOL_MAX = lire_entier("DB_POOL_MAX", 2)
DB_POOL_TIMEOUT = lire_entier("DB_POOL_TIMEOUT", 10)
CACHE_TTL = lire_entier("CACHE_TTL", 0)
LOG_REQUETES = lire_entier("LOG_REQUETES", 1)
INSTANCE = socket.gethostname()

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
journal = logging.getLogger("optilandes")


class Cache:
    """Cache en mémoire, propre à chaque processus. Une durée de 0 le désactive."""

    def __init__(self, duree_s):
        self.duree_s = duree_s
        self.donnees = {}
        self.verrou = threading.Lock()

    def lire(self, cle):
        if self.duree_s <= 0:
            return None
        with self.verrou:
            entree = self.donnees.get(cle)
            if entree and entree[0] > time.monotonic():
                return entree[1]
        return None

    def ecrire(self, cle, valeur):
        if self.duree_s <= 0:
            return
        with self.verrou:
            self.donnees[cle] = (time.monotonic() + self.duree_s, valeur)

    def oublier(self, cle):
        with self.verrou:
            self.donnees.pop(cle, None)


cache = Cache(CACHE_TTL)
pool = ConnectionPool(
    DB_DSN,
    min_size=1,
    max_size=DB_POOL_MAX,
    timeout=DB_POOL_TIMEOUT,
    kwargs={"row_factory": dict_row},
    open=False,
)


@asynccontextmanager
async def cycle_de_vie(_app):
    pool.open()
    journal.info(
        "Démarrage version=%s pool_max=%s cache_ttl=%s pid=%s",
        VERSION, DB_POOL_MAX, CACHE_TTL, os.getpid(),
    )
    yield
    pool.close()


app = FastAPI(title="Optilandes", version=VERSION, lifespan=cycle_de_vie)


@app.middleware("http")
async def mesurer(request: Request, call_next):
    debut = time.perf_counter()
    reponse = await call_next(request)
    duree_ms = (time.perf_counter() - debut) * 1000
    reponse.headers["X-Temps-Traitement-ms"] = f"{duree_ms:.1f}"
    reponse.headers["X-Version"] = VERSION
    reponse.headers["X-Instance"] = INSTANCE
    if LOG_REQUETES:
        journal.info("%s %s %s %.1f ms", request.method, request.url.path, reponse.status_code, duree_ms)
    return reponse


@app.exception_handler(PoolTimeout)
def base_saturee(_request, _exc):
    return JSONResponse(status_code=503, content={"erreur": "base de données saturée, réessayer plus tard"})


class DemandeRendezVous(BaseModel):
    client_id: int = Field(ge=1)
    zone_id: int = Field(ge=1)
    date_livraison: date
    creneau: int = Field(ge=1, le=NB_CRENEAUX)


@app.get("/health")
async def sante():
    # Fonction asynchrone : le contrôle de santé ne fait pas la queue derrière les autres requêtes.
    return {"statut": "ok", "version": VERSION, "instance": INSTANCE}


@app.get("/creneaux")
def creneaux(zone: int = Query(ge=1), date_livraison: date = Query(alias="date")):
    cle = ("creneaux", zone, date_livraison)
    resultat = cache.lire(cle)
    if resultat is not None:
        return resultat
    with pool.connection() as conn:
        ligne = conn.execute("SELECT capacite_creneau FROM zones WHERE id = %s", (zone,)).fetchone()
        if ligne is None:
            raise HTTPException(status_code=404, detail="zone inconnue")
        capacite = ligne["capacite_creneau"]
        pris = {
            r["creneau"]: r["pris"]
            for r in conn.execute(
                "SELECT creneau, count(*) AS pris FROM rendez_vous "
                "WHERE zone_id = %s AND date_livraison = %s AND statut = 'confirme' "
                "GROUP BY creneau",
                (zone, date_livraison),
            )
        }
    resultat = {
        "zone": zone,
        "date": date_livraison.isoformat(),
        "creneaux": [
            {"creneau": c, "capacite": capacite, "pris": pris.get(c, 0), "libres": max(capacite - pris.get(c, 0), 0)}
            for c in range(1, NB_CRENEAUX + 1)
        ],
    }
    cache.ecrire(cle, resultat)
    return resultat


@app.post("/rendez-vous", status_code=201)
def prendre_rendez_vous(demande: DemandeRendezVous):
    with pool.connection() as conn:
        with conn.transaction():
            client = conn.execute("SELECT zone_id FROM clients WHERE id = %s", (demande.client_id,)).fetchone()
            if client is None:
                raise HTTPException(status_code=404, detail="client inconnu")
            if client["zone_id"] != demande.zone_id:
                raise HTTPException(status_code=422, detail="le client n'appartient pas à cette zone")
            zone = conn.execute(
                "SELECT capacite_creneau FROM zones WHERE id = %s FOR UPDATE", (demande.zone_id,)
            ).fetchone()
            deja_pris = conn.execute(
                "SELECT count(*) AS n FROM rendez_vous "
                "WHERE zone_id = %s AND date_livraison = %s AND creneau = %s AND statut = 'confirme'",
                (demande.zone_id, demande.date_livraison, demande.creneau),
            ).fetchone()["n"]
            if deja_pris >= zone["capacite_creneau"]:
                raise HTTPException(status_code=409, detail="créneau complet")
            nouveau = conn.execute(
                "INSERT INTO rendez_vous (client_id, zone_id, date_livraison, creneau) "
                "VALUES (%s, %s, %s, %s) RETURNING id",
                (demande.client_id, demande.zone_id, demande.date_livraison, demande.creneau),
            ).fetchone()
    cache.oublier(("creneaux", demande.zone_id, demande.date_livraison))
    return {"id": nouveau["id"], "statut": "confirme"}


@app.get("/livraisons")
def livraisons(zone: int = Query(ge=1), date_livraison: date = Query(alias="date")):
    with pool.connection() as conn:
        rendez_vous = conn.execute(
            "SELECT id, client_id, creneau FROM rendez_vous "
            "WHERE zone_id = %s AND date_livraison = %s AND statut = 'confirme' "
            "ORDER BY creneau, id",
            (zone, date_livraison),
        ).fetchall()
        resultat = []
        for rdv in rendez_vous:
            client = conn.execute(
                "SELECT nom, adresse, ville FROM clients WHERE id = %s", (rdv["client_id"],)
            ).fetchone()
            resultat.append({
                "id": rdv["id"],
                "creneau": rdv["creneau"],
                "client": client["nom"],
                "adresse": client["adresse"],
                "ville": client["ville"],
            })
    return {"zone": zone, "date": date_livraison.isoformat(), "nombre": len(resultat), "livraisons": resultat}


@app.get("/tournees")
def tournees(zone: int = Query(ge=1), date_livraison: date = Query(alias="date")):
    cle = ("tournees", zone, date_livraison)
    resultat = cache.lire(cle)
    if resultat is not None:
        return resultat
    with pool.connection() as conn:
        depot = conn.execute(
            "SELECT d.lat, d.lon FROM zones z JOIN depots d ON d.id = z.depot_id WHERE z.id = %s", (zone,)
        ).fetchone()
        if depot is None:
            raise HTTPException(status_code=404, detail="zone inconnue")
        points = conn.execute(
            "SELECT r.id, c.lat, c.lon FROM rendez_vous r JOIN clients c ON c.id = r.client_id "
            "WHERE r.zone_id = %s AND r.date_livraison = %s AND r.statut = 'confirme' ORDER BY r.id",
            (zone, date_livraison),
        ).fetchall()
        ordre, distance = calculer_tournee(
            (depot["lat"], depot["lon"]), [(p["lat"], p["lon"], p["id"]) for p in points]
        )
    resultat = {
        "zone": zone,
        "date": date_livraison.isoformat(),
        "nombre_points": len(ordre),
        "distance_km": distance,
        "ordre": ordre,
    }
    cache.ecrire(cle, resultat)
    return resultat
