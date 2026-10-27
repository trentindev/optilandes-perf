-- Optilandes : structure de la base
-- Ce script s'exécute une seule fois, à la première création du volume de données.

CREATE EXTENSION IF NOT EXISTS pg_stat_statements;

CREATE TABLE depots (
    id      smallint PRIMARY KEY,
    nom     text NOT NULL,
    ville   text NOT NULL,
    lat     double precision NOT NULL,
    lon     double precision NOT NULL
);

CREATE TABLE zones (
    id                smallint PRIMARY KEY,
    nom               text NOT NULL,
    depot_id          smallint NOT NULL REFERENCES depots (id),
    capacite_creneau  smallint NOT NULL DEFAULT 45
);

CREATE TABLE clients (
    id       integer PRIMARY KEY,
    nom      text NOT NULL,
    adresse  text NOT NULL,
    ville    text NOT NULL,
    lat      double precision NOT NULL,
    lon      double precision NOT NULL,
    zone_id  smallint NOT NULL REFERENCES zones (id)
);

CREATE TABLE rendez_vous (
    id              bigserial PRIMARY KEY,
    client_id       integer NOT NULL REFERENCES clients (id),
    zone_id         smallint NOT NULL REFERENCES zones (id),
    date_livraison  date NOT NULL,
    creneau         smallint NOT NULL CHECK (creneau BETWEEN 1 AND 8),
    statut          text NOT NULL DEFAULT 'confirme' CHECK (statut IN ('confirme', 'annule')),
    cree_le         timestamptz NOT NULL DEFAULT now()
);
