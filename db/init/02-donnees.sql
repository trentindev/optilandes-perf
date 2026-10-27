-- Optilandes : données de démonstration
-- 3 dépôts, 24 zones, 50 000 clients, 500 000 rendez-vous
-- répartis sur 120 jours, du 2 novembre 2026 au 1er mars 2027.
-- Les données sont fictives. La graine fixe rend le jeu de données identique sur tous les postes.

SELECT setseed(0.42);

INSERT INTO depots (id, nom, ville, lat, lon) VALUES
    (1, 'Dépôt Côte sud',   'Bénesse-Maremne', 43.6378, -1.3656),
    (2, 'Dépôt Marsan',     'Mont-de-Marsan',  43.8902, -0.4997),
    (3, 'Dépôt Agenais',    'Astaffort',       44.0650,  0.6517);

INSERT INTO zones (id, nom, depot_id)
SELECT z.id, 'Zone ' || z.ville, (z.id - 1) / 8 + 1
FROM unnest(ARRAY[
    'Bénesse-Maremne', 'Capbreton', 'Hossegor', 'Labenne', 'Seignosse', 'Saint-Vincent-de-Tyrosse', 'Angresse', 'Saubion',
    'Mont-de-Marsan', 'Saint-Pierre-du-Mont', 'Saint-Perdon', 'Bretagne-de-Marsan', 'Mazerolles', 'Benquet', 'Campet-et-Lamolère', 'Uchacq-et-Parentis',
    'Astaffort', 'Layrac', 'Agen', 'Cuq', 'Caudecoste', 'Fals', 'Sauveterre-Saint-Denis', 'Saint-Nicolas-de-la-Balerme'
]) WITH ORDINALITY AS z(ville, id);

INSERT INTO clients (id, nom, adresse, ville, lat, lon, zone_id)
SELECT
    g,
    'Client ' || g,
    (1 + floor(random() * 120))::int || ' rue des ' ||
        (ARRAY['Pins', 'Chênes', 'Arènes', 'Écoles', 'Forges', 'Vignes', 'Landes', 'Moulins'])[1 + floor(random() * 8)::int],
    substr(z.nom, 6),
    d.lat + (random() - 0.5) * 0.4,
    d.lon + (random() - 0.5) * 0.4,
    z.id
FROM generate_series(1, 50000) AS g
JOIN zones z ON z.id = 1 + (g - 1) % 24
JOIN depots d ON d.id = z.depot_id;

INSERT INTO rendez_vous (client_id, zone_id, date_livraison, creneau, statut, cree_le)
SELECT
    c.id,
    c.zone_id,
    DATE '2026-11-02' + floor(random() * 120)::int,
    1 + floor(random() * 8)::int,
    CASE WHEN random() < 0.05 THEN 'annule' ELSE 'confirme' END,
    TIMESTAMPTZ '2026-10-01 00:00:00+01' + random() * INTERVAL '30 days'
FROM (SELECT 1 + floor(random() * 50000)::int AS client_id FROM generate_series(1, 500000)) AS tirage
JOIN clients c ON c.id = tirage.client_id;

ANALYZE;
