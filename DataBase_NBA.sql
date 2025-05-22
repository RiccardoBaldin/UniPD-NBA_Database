DROP TABLE IF EXISTS Membro_Squadra CASCADE;
DROP TABLE IF EXISTS Contratto CASCADE;
DROP TABLE IF EXISTS Squadra CASCADE;
DROP TABLE IF EXISTS Stadio CASCADE;
DROP TABLE IF EXISTS Partita CASCADE;
DROP TABLE IF EXISTS Stagione CASCADE;
DROP TABLE IF EXISTS Analisi_Partita CASCADE;
DROP TABLE IF EXISTS Premio CASCADE;

DROP TYPE IF EXISTS ruolo_enum CASCADE;
DROP TYPE IF EXISTS conferenza_enum CASCADE;
DROP TYPE IF EXISTS premio_enum CASCADE;
DROP TYPE IF EXISTS qualifica_enum CASCADE;


CREATE TYPE ruolo_enum AS ENUM ('Playmaker', 'Guardia', 'Ala Piccola', 'Ala Grande', 'Centro');
CREATE TYPE conferenza_enum AS ENUM ('Conferenza Est', 'Conferenza Ovest');
CREATE TYPE premio_enum AS ENUM ('MVP','All-NBA Team', 'NBA All-Defensive Team');
CREATE TYPE qualifica_enum AS ENUM ('Giocatore','Allenatore', 'Preparatore Fisico', 'Medico', 'Fisioterapista', 'Mascotte');



--insert fatto
CREATE TABLE IF NOT EXISTS Membro_Squadra (
    ID_Membro INT NOT NULL,
    Nome VARCHAR(32) NOT NULL,
    Cognome VARCHAR(32) NOT NULL,
    Data_Nascita DATE NOT NULL,
    Nazionalità VARCHAR(32) NOT NULL,
    Peso INT,
    Altezza INT,
    Qualifica qualifica_enum NOT NULL,
    Ruolo ruolo_enum,

    PRIMARY KEY (ID_Membro)
);

--insert fatto
CREATE TABLE IF NOT EXISTS Stadio (
    Nome_Stadio VARCHAR(32) NOT NULL,
    Città VARCHAR(32) NOT NULL,
    Capacità INT,

    PRIMARY KEY (Nome_Stadio)
);

--insert fatto
CREATE TABLE IF NOT EXISTS Squadra (
    Nome_Squadra VARCHAR(32) NOT NULL,
    Conferenza conferenza_enum NOT NULL,
    Nome_Stadio VARCHAR(32) NOT NULL,

    FOREIGN KEY (Nome_Stadio) REFERENCES Stadio(Nome_Stadio),

    PRIMARY KEY (Nome_Squadra)
);


CREATE TABLE IF NOT EXISTS Contratto(
    ID_Membro INT NOT NULL,
    Nome_Squadra VARCHAR(32) NOT NULL,
    Inizio_Contratto DATE NOT NULL,
    Fine_Contratto DATE NOT NULL,
    Stipendio INT NOT NULL,
    
    CHECK (Fine_Contratto > Inizio_Contratto),

    FOREIGN KEY (ID_Membro) REFERENCES Membro_Squadra(ID_Membro),
    FOREIGN KEY (Nome_Squadra) REFERENCES Squadra(Nome_Squadra),

    PRIMARY KEY (ID_Membro, Nome_Squadra, Inizio_Contratto)
);

--insert fatto
CREATE TABLE IF NOT EXISTS Stagione (
    Numero_Stagione INT NOT NULL,
    Data_Inizio DATE NOT NULL,
    Data_Fine DATE NOT NULL,

    PRIMARY KEY (Numero_Stagione)
);


CREATE TABLE IF NOT EXISTS Partita (
    Data_Partita DATE NOT NULL,
    Squadra_Casa VARCHAR(32) NOT NULL,
    Squadra_Ospiti VARCHAR(32) NOT NULL,
    Punteggio_Casa INT NOT NULL,
    Punteggio_Ospiti INT NOT NULL,
    Numero_Stagione INT NOT NULL,
    Vincitore BOOLEAN,

    FOREIGN KEY (Squadra_Casa) REFERENCES Squadra(Nome_Squadra),
    FOREIGN KEY (Squadra_Ospiti) REFERENCES Squadra(Nome_Squadra),
    FOREIGN KEY (Numero_Stagione) REFERENCES Stagione(Numero_Stagione),

    PRIMARY KEY (Data_Partita, Squadra_Casa)
);


CREATE TABLE IF NOT EXISTS Analisi_Partita (
    ID_Membro INT NOT NULL,
    Data_Partita DATE NOT NULL,
    Squadra_Casa VARCHAR(32) NOT NULL,
    Punti INT ,
    Rimbalzi INT,
    Assist INT,

    FOREIGN KEY (ID_Membro) REFERENCES Membro_Squadra(ID_Membro),
    FOREIGN KEY (Data_Partita, Squadra_Casa) REFERENCES Partita(Data_Partita, Squadra_Casa),

    PRIMARY KEY (ID_Membro, Data_Partita)
);


CREATE TABLE IF NOT EXISTS Premio (
    Nome_Premio premio_enum NOT NULL,
    ID_Membro INT NOT NULL,
    Numero_Stagione INT NOT NULL,

    FOREIGN KEY (ID_Membro) REFERENCES Membro_Squadra(ID_Membro),
    FOREIGN KEY (Numero_Stagione) REFERENCES Stagione(Numero_Stagione),

    PRIMARY KEY (Nome_Premio, ID_Membro, Numero_Stagione)
);










--------------------------------------------------------------------------------------------------------------------------------------

DROP FUNCTION IF EXISTS check_mvp_unico();
-- CONTROLLO UNICITÀ MVP PER STAGIONE
CREATE OR REPLACE FUNCTION check_mvp_unico()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.Nome_Premio = 'MVP' THEN
        IF EXISTS (
            SELECT 1 FROM Premio
            WHERE Nome_Premio = 'MVP'
            AND Numero_Stagione = NEW.Numero_Stagione
        ) THEN
            RAISE EXCEPTION 'Esiste già un MVP per la stagione %', NEW.Numero_Stagione;
        END IF;
    END IF;                                             
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS MVP_Stagione_Unico ON Premio CASCADE;
-- TRIGGER PREMIO SINGOLO
CREATE TRIGGER MVP_Stagione_Unico
BEFORE INSERT OR UPDATE ON Premio
FOR EACH ROW
EXECUTE FUNCTION check_mvp_unico();

--------------------------------------------------------------------------------------------------------------------------------------

DROP FUNCTION IF EXISTS check_quintetto_premiato();
-- CONTROLLO CINQUE GIOCATORI PER PREMI MULTIPLI
CREATE OR REPLACE FUNCTION check_quintetto_premiato()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.Nome_Premio != 'MVP' THEN
        IF (SELECT COUNT(*) FROM Premio
            WHERE Numero_Stagione = NEW.Numero_Stagione
            AND Nome_Premio = NEW.Nome_Premio) >= 5
        THEN 
            RAISE EXCEPTION 'Il premio % è gia stato assegnato a 5 persone (numero massimo)', NEW.Nome_Premio;
        END IF;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;


DROP TRIGGER IF EXISTS Massimo_Cinque_Premiati ON Premio CASCADE;
-- TRIGGER PREMIO MULTIPLO
CREATE TRIGGER Massimo_Cinque_Premiati
BEFORE INSERT OR UPDATE ON Premio
FOR EACH ROW
EXECUTE FUNCTION check_quintetto_premiato();

--------------------------------------------------------------------------------------------------------------------------------------

DROP FUNCTION IF EXISTS check_vincitore();
-- CONTROLLO VINCITORE DELLA PARTITA
CREATE OR REPLACE FUNCTION check_vincitore()
RETURNS TRIGGER AS $$
BEGIN
    NEW.Vincitore := (NEW.Punteggio_Casa > NEW.Punteggio_Ospiti);
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS Set_Vincitore ON Partita CASCADE;
-- TRIGGER VINCITORE AUTOMATICO
CREATE TRIGGER Set_Vincitore
BEFORE INSERT OR UPDATE ON Partita
FOR EACH ROW
EXECUTE FUNCTION check_vincitore();

--------------------------------------------------------------------------------------------------------------------------------------

DROP FUNCTION IF EXISTS check_coerenza_membro();
--CONTROLLO COERENZA DI QUALIFICA E ATTRIBUTI
CREATE OR REPLACE FUNCTION check_coerenza_membro()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.Qualifica = 'Giocatore' THEN
        IF NEW.Altezza IS NULL OR NEW.Peso IS NULL OR NEW.Ruolo IS NULL THEN
            RAISE EXCEPTION 'Un giocatore non può avere Peso, Altezza o Ruolo nulli';
        END IF;
    ELSE
        IF NEW.Altezza IS NOT NULL OR NEW.Peso IS NOT NULL OR NEW.Ruolo IS NOT NULL THEN
            RAISE EXCEPTION 'Solo i giocatori possono avere Peso, Altezza e Ruolo valorizzati';
        END IF;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS Coerenza_Membro ON Membro_Squadra;
-- TRIGGER COERENZA MEMBRO
CREATE TRIGGER Coerenza_Membro
BEFORE INSERT OR UPDATE ON Membro_Squadra
FOR EACH ROW
EXECUTE FUNCTION check_coerenza_membro();

--------------------------------------------------------------------------------------------------------------------------------------

DROP FUNCTION IF EXISTS check_contratto_attivo();
-- CONTROLLO SE IL MEMBRO È GIÀ VINCOLATO TRAMITE CONTRATTO ATTIVO
CREATE OR REPLACE FUNCTION check_contratto_attivo()
RETURNS TRIGGER AS $$
DECLARE
    v_nome_membro VARCHAR;
    v_nome_squadra VARCHAR;
    v_inizio DATE;
    v_fine DATE;
BEGIN
    SELECT c.Nome_Squadra, c.Inizio_Contratto, c.Fine_Contratto
    INTO v_nome_squadra, v_inizio, v_fine
    FROM Contratto c
    WHERE c.ID_Membro = NEW.ID_Membro
      AND NEW.Inizio_Contratto <= c.Fine_Contratto
      AND NEW.Fine_Contratto >= c.Inizio_Contratto
    LIMIT 1;

    IF FOUND THEN
        SELECT Nome INTO v_nome_membro
        FROM Membro_Squadra
        WHERE ID_Membro = NEW.ID_Membro;

        RAISE EXCEPTION 'Il membro % ha già un contratto attivo con la squadra % dal % al %',
            v_nome_membro, v_nome_squadra, v_inizio, v_fine;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS Contratto_Attivo ON Contratto;
-- TRIGGER CONTRATTO ATTIVO
CREATE TRIGGER Contratto_Attivo
BEFORE INSERT OR UPDATE ON Contratto
FOR EACH ROW
EXECUTE FUNCTION check_contratto_attivo();


CREATE INDEX indice_Analisi_Partita ON Analisi_Partita (Data_partita, ID_Membro);


INSERT INTO Stadio (Nome_Stadio, Città, Capacità) VALUES
                    ('State Farm Arena', 'Atlanta', 16600),
                    ('TD Garden', 'Boston', 19580),
                    ('Barclays Center', 'Brooklyn', 17732),
                    ('Spectrum Center', 'Charlotte', 19077),
                    ('United Center', 'Chicago', 20917),
                    ('Rocket Mortgage FieldHouse', 'Cleveland', 19432),
                    ('Little Caesars Arena', 'Detroit', 20491),
                    ('Gainbridge Fieldhouse', 'Indianapolis', 17923),
                    ('Kaseya Center', 'Miami', 19600),
                    ('Fiserv Forum', 'Milwaukee', 17500),
                    ('Madison Square Garden', 'New York', 19812),
                    ('Amway Center', 'Orlando', 18846),
                    ('Wells Fargo Center', 'Philadelphia', 20478),
                    ('Scotiabank Arena', 'Toronto', 19800),
                    ('Capital One Arena', 'Washington', 20356),

                    ('American Airlines Center', 'Dallas', 19200),
                    ('Ball Arena', 'Denver', 19520),
                    ('Chase Center', 'San Francisco', 18064),
                    ('Toyota Center', 'Houston', 18055),
                    ('Crypto.com Arena', 'Los Angeles', 19060),
                    ('Inuit Dome', 'Los Angeles', 18000),
                    ('FedExForum', 'Memphis', 18119),
                    ('Target Center', 'Minneapolis', 19156),
                    ('Smoothie King Center', 'New Orleans', 16867),
                    ('Paycom Center', 'Oklahoma City', 18203),
                    ('Footprint Center', 'Phoenix', 18055),
                    ('Moda Center', 'Portland', 19393),
                    ('Golden 1 Center', 'Sacramento', 17383),
                    ('Frost Bank Center', 'San Antonio', 18381),
                    ('Delta Center', 'Salt Lake City', 18306);



INSERT INTO Squadra (Nome_Squadra, Conferenza, Nome_Stadio) VALUES
                    ('Atlanta Hawks', 'Conferenza Est', 'State Farm Arena'),
                    ('Boston Celtics', 'Conferenza Est', 'TD Garden'),
                    ('Brooklyn Nets', 'Conferenza Est', 'Barclays Center'),
                    ('Charlotte Hornets', 'Conferenza Est', 'Spectrum Center'),
                    ('Chicago Bulls', 'Conferenza Est', 'United Center'),
                    ('Cleveland Cavaliers', 'Conferenza Est', 'Rocket Mortgage FieldHouse'),
                    ('Detroit Pistons', 'Conferenza Est', 'Little Caesars Arena'),
                    ('Indiana Pacers', 'Conferenza Est', 'Gainbridge Fieldhouse'),
                    ('Miami Heat', 'Conferenza Est', 'Kaseya Center'),
                    ('Milwaukee Bucks', 'Conferenza Est', 'Fiserv Forum'),
                    ('New York Knicks', 'Conferenza Est', 'Madison Square Garden'),
                    ('Orlando Magic', 'Conferenza Est', 'Amway Center'),
                    ('Philadelphia 76ers', 'Conferenza Est', 'Wells Fargo Center'),
                    ('Toronto Raptors', 'Conferenza Est', 'Scotiabank Arena'),
                    ('Washington Wizards', 'Conferenza Est', 'Capital One Arena'),

                    ('Dallas Mavericks', 'Conferenza Ovest', 'American Airlines Center'),
                    ('Denver Nuggets', 'Conferenza Ovest', 'Ball Arena'),
                    ('Golden State Warriors', 'Conferenza Ovest', 'Chase Center'),
                    ('Houston Rockets', 'Conferenza Ovest', 'Toyota Center'),
                    ('LA Clippers', 'Conferenza Ovest', 'Inuit Dome'),
                    ('Los Angeles Lakers', 'Conferenza Ovest', 'Crypto.com Arena'),
                    ('Memphis Grizzlies', 'Conferenza Ovest', 'FedExForum'),
                    ('Minnesota Timberwolves', 'Conferenza Ovest', 'Target Center'),
                    ('New Orleans Pelicans', 'Conferenza Ovest', 'Smoothie King Center'),
                    ('Oklahoma City Thunder', 'Conferenza Ovest', 'Paycom Center'),
                    ('Phoenix Suns', 'Conferenza Ovest', 'Footprint Center'),
                    ('Portland Trail Blazers', 'Conferenza Ovest', 'Moda Center'),
                    ('Sacramento Kings', 'Conferenza Ovest', 'Golden 1 Center'),
                    ('San Antonio Spurs', 'Conferenza Ovest', 'Frost Bank Center'),
                    ('Utah Jazz', 'Conferenza Ovest', 'Delta Center');



INSERT INTO Stagione (Numero_Stagione, Data_Inizio, Data_Fine) VALUES
                    (2005, '2004-10-26', '2005-06-23'),
                    (2006, '2005-11-01', '2006-06-20'),
                    (2007, '2006-10-31', '2007-06-14'),
                    (2008, '2007-10-30', '2008-06-17'),
                    (2009, '2008-10-28', '2009-06-14'),
                    (2010, '2009-10-27', '2010-06-17'),
                    (2011, '2010-10-26', '2011-06-12'),
                    (2012, '2011-12-25', '2012-06-21'),
                    (2013, '2012-10-30', '2013-06-20'),
                    (2014, '2013-10-29', '2014-06-15'),
                    (2015, '2014-10-28', '2015-06-16'),
                    (2016, '2015-10-27', '2016-06-19'),
                    (2017, '2016-10-25', '2017-06-12'),
                    (2018, '2017-10-17', '2018-06-08'),
                    (2019, '2018-10-16', '2019-06-13'),
                    (2020, '2019-10-22', '2020-10-11'),
                    (2021, '2020-12-22', '2021-07-20'),
                    (2022, '2021-10-19', '2022-06-16'),
                    (2023, '2022-10-18', '2023-06-12'),
                    (2024, '2023-10-24', '2024-06-14');



INSERT INTO Membro_Squadra (ID_Membro, Nome, Cognome, Data_Nascita, Nazionalità, Peso, Altezza, Qualifica, Ruolo) VALUES
                    (1, 'LeBron', 'James', '1984-12-30', 'USA', 113, 206, 'Giocatore', 'Ala Grande'),
                    (2, 'Stephen', 'Curry', '1988-03-14', 'USA', 86, 191, 'Giocatore', 'Playmaker'),
                    (3, 'Kevin', 'Durant', '1988-09-29', 'USA', 108, 208, 'Giocatore', 'Ala Piccola'),
                    (4, 'Giannis', 'Antetokounmpo', '1994-12-06', 'Grecia', 110, 211, 'Giocatore', 'Ala Grande'),
                    (5, 'Nikola', 'Jokic', '1995-02-19', 'Serbia', 129, 211, 'Giocatore', 'Centro'),
                    (6, 'Joel', 'Embiid', '1994-03-16', 'Camerun', 127, 213, 'Giocatore', 'Centro'),
                    (7, 'Luka', 'Doncic', '1999-02-28', 'Slovenia', 104, 201, 'Giocatore', 'Guardia'),
                    (8, 'Jayson', 'Tatum', '1998-03-03', 'USA', 95, 203, 'Giocatore', 'Ala Piccola'),
                    (9, 'Jimmy', 'Butler', '1989-09-14', 'USA', 104, 201, 'Giocatore', 'Ala Piccola'),
                    (10, 'Devin', 'Booker', '1996-10-30', 'USA', 93, 196, 'Giocatore', 'Guardia'),
                    (11, 'Chris', 'Paul', '1985-05-06', 'USA', 79, 183, 'Giocatore', 'Playmaker'),
                    (12, 'Draymond', 'Green', '1990-03-04', 'USA', 104, 198, 'Giocatore', 'Ala Grande'),
                    (13, 'Bam', 'Adebayo', '1997-07-18', 'USA', 115, 206, 'Giocatore', 'Centro'),
                    (14, 'Rudy', 'Gobert', '1992-06-26', 'Francia', 117, 216, 'Giocatore', 'Centro'),
                    (15, 'Damian', 'Lillard', '1990-07-15', 'USA', 88, 188, 'Giocatore', 'Playmaker'),
                    (16, 'Zach', 'LaVine', '1995-03-10', 'USA', 91, 196, 'Giocatore', 'Guardia'),
                    (17, 'Karl-Anthony', 'Towns', '1995-11-15', 'USA', 112, 211, 'Giocatore', 'Centro'),
                    (18, 'Anthony', 'Davis', '1993-03-11', 'USA', 115, 208, 'Giocatore', 'Ala Grande'),
                    (19, 'Trae', 'Young', '1998-09-19', 'USA', 74, 185, 'Giocatore', 'Playmaker'),
                    (20, 'Donovan', 'Mitchell', '1996-09-07', 'USA', 98, 185, 'Giocatore', 'Guardia'),
                    (21, 'Steve', 'Nash', '1974-02-07', 'Canada', NULL, NULL, 'Allenatore', NULL),
                    (22, 'Erik', 'Spoelstra', '1970-11-01', 'USA', NULL, NULL, 'Allenatore', NULL),
                    (23, 'Gary', 'Vitti', '1959-04-01', 'USA', NULL, NULL, 'Preparatore Fisico', NULL),
                    (24, 'Rachel', 'Nichols', '1983-10-18', 'USA', NULL, NULL, 'Fisioterapista', NULL),
                    (25, 'Rocky', 'Mascotte', '1995-01-01', 'USA', NULL, NULL, 'Mascotte', NULL);




-- QUERY 1 : Classifica della stagione, in base all' anno inserito dall'utente

WITH Statistiche AS (
	SELECT
		s.Nome_Squadra,
		SUM(CASE
			WHEN (p.Vincitore = TRUE AND p.Squadra_Casa = s.Nome_Squadra) OR
			(p.Vincitore = FALSE AND p.Squadra_Ospiti = s.Nome_Squadra)
			THEN 1 ELSE 0
		END) AS Vittorie,
		SUM(CASE
			WHEN (p.Vincitore = FALSE AND p.Squadra_Casa = s.Nome_Squadra) OR
			(p.Vincitore = TRUE AND p.Squadra_Ospiti = s.Nome_Squadra)
			THEN 1 ELSE 0
		END) AS Sconfitte
	FROM Partita p
	JOIN Squadra s ON s.Nome_Squadra = p.Squadra_Casa OR
	s.Nome_Squadra = p. Squadra_Ospiti
	WHERE p.Numero_Stagione = 2024
	GROUP BY s.Nome_Squadra
)
SELECT
	Nome_Squadra,
	CASE
		WHEN (Vittorie + Sconfitte) = 0 THEN NULL
		ELSE ROUND(CAST(Vittorie AS numeric) / (Vittorie + Sconfitte), 3)
	END AS Rapporto_Vittorie_Partite,
	Vittorie,
	Sconfitte
FROM Statistiche
ORDER BY Rapporto_Vittorie_Partite DESC
LIMIT 5;

-- QUERY 2 : Giocatore (o giocatori in caso di parità) che ha collezionato più premi in tutta sua la carriera

SELECT ms.Nome, ms.Cognome, COUNT(*) AS Numero_Premi
FROM Premio pr
JOIN Membro_Squadra ms ON pr.ID_Membro = ms.ID_Membro
WHERE ms.Qualifica = 'Giocatore'
GROUP BY ms.ID_Membro, ms.Nome, ms.Cognome
HAVING COUNT(*) = (
    SELECT MAX(Numero_Premi) FROM (
        SELECT COUNT(*) AS Numero_Premi
        FROM Premio pr
        JOIN Membro_Squadra ms ON pr.ID_Membro = ms.ID_Membro
        WHERE ms.Qualifica = 'Giocatore'
        GROUP BY ms.ID_Membro
    ) AS Premi_Giocatori
);

-- QUERY 3 : Giocatore (o giocatori in caso di parità) che ha collezionato più premi dello stesso tipo (scelto da utente tra i disponibili)

SELECT ms.Nome, ms.Cognome, COUNT(*) AS Premio_individuale
FROM Premio pr
JOIN Membro_Squadra ms ON pr.ID_Membro = ms.ID_Membro
WHERE ms.Qualifica = 'Giocatore'
AND pr.Nome_Premio = 'MVP'
GROUP BY ms.ID_Membro, ms.Nome, ms.Cognome
HAVING COUNT(*) = (
    SELECT MAX(Premio_individuale) FROM (
        SELECT COUNT(*) AS Premio_individuale
        FROM Premio pr
        JOIN Membro_Squadra ms ON pr.ID_Membro = ms.ID_Membro
        WHERE ms.Qualifica = 'Giocatore'
        AND pr.Nome_Premio = 'MVP'
        GROUP BY ms.ID_Membro
    ) AS Premio_individuale
);

-- QUERY 4 : Squadre che hanno più giocatori con x premi (numero scelto da utente)

WITH Giocatori_Con_X_Premi AS (
    SELECT ID_Membro
    FROM Premio
    GROUP BY ID_Membro
    HAVING COUNT(*) >= 0 
),

Giocatori_Squadre AS (
    SELECT DISTINCT c.Nome_Squadra, c.ID_Membro
    FROM Contratto c
    JOIN Giocatori_Con_X_Premi g ON g.ID_Membro = c.ID_Membro
),

Squadre_Con_Conteggio AS (
    SELECT gs.Nome_Squadra, COUNT(*) AS Giocatori_Con_Premi
    FROM Giocatori_Squadre gs
    GROUP BY gs.Nome_Squadra
),

Max_Valore AS (
    SELECT MAX(Giocatori_Con_Premi) AS Max_Premi
    FROM Squadre_Con_Conteggio
)

SELECT s.Nome_Squadra, s.Giocatori_Con_Premi
FROM Squadre_Con_Conteggio s
JOIN Max_Valore m ON s.Giocatori_Con_Premi = m.Max_Premi;

-- QUERY 5 : Giocatore che ha firmato il maggior numero di contratti negli ultimi vent'anni, e numero di squadre con le quali ha firmato

SELECT ms.Nome, ms.Cognome, COUNT(*) AS Numero_Contratti, COUNT(DISTINCT c.Nome_Squadra) AS Squadre_Diverse
FROM Contratto c
JOIN Membro_Squadra ms ON c.ID_Membro = ms.ID_Membro
WHERE ms.Qualifica = 'Giocatore'
GROUP BY ms.ID_Membro, ms.Nome, ms.Cognome
HAVING COUNT(*) = (
    SELECT MAX(Numero_Contratti) FROM (
        SELECT COUNT(*) AS Numero_Contratti
        FROM Contratto c JOIN Membro_Squadra ms ON c.ID_Membro = ms.ID_Membro
        WHERE ms.Qualifica = 'Giocatore'
		GROUP BY ms.ID_Membro
    ) AS Numero_Contratti
);

-- QUERY 6 : Tra due squadre, scelte dall'utente, restituire la data della partita degli ultimi venti anni 
    --con più grande distacco di punti tra le due squadre e lo stadio in cui è stata giocata

SELECT 
    p.Data_Partita,
    ABS(p.Punteggio_Casa - p.Punteggio_Ospiti) AS Distacco,
    CASE 
        WHEN p.Punteggio_Casa > p.Punteggio_Ospiti THEN p.Squadra_Casa
        ELSE p.Squadra_Ospiti
    END AS Squadra_Vincente,
	sq.Nome_Stadio
FROM Partita p
JOIN Squadra sq ON p.Squadra_Casa = sq.Nome_Squadra
WHERE (
    (p.Squadra_Casa = 'Los Angeles Lakers' AND p.Squadra_Ospiti = 'Boston Celtics') OR
    (p.Squadra_Casa = 'Boston Celtics' AND p.Squadra_Ospiti = 'Los Angeles Lakers')
)
AND p.Data_Partita >= CURRENT_DATE - INTERVAL '20 years'
AND ABS(p.Punteggio_Casa - p.Punteggio_Ospiti) = (
    SELECT MAX(ABS(p2.Punteggio_Casa - p2.Punteggio_Ospiti))
    FROM Partita p2
    WHERE (
        (p2.Squadra_Casa = 'Los Angeles Lakers' AND p2.Squadra_Ospiti = 'Boston Celtics') OR
        (p2.Squadra_Casa = 'Boston Celtics' AND p2.Squadra_Ospiti = 'Los Angeles Lakers')
    )
    AND p2.Data_Partita >= CURRENT_DATE - INTERVAL '20 years'
);

-- QUERY 7 : Squadre con giocatori che nell'anno selezionato dall'utente hanno collezionato più triple-doppie
    --(= punti >= 10, rimbalzi >= 10 e assist >= 10). Stampa anche il numero di triple-doppie e il giocatore 
    --che ne ha collezionate di più per ogni squadra

WITH TripleDoppie AS (
    SELECT 
        ap.ID_Membro,
        p.Numero_Stagione,
        c.Nome_Squadra,
        COUNT(*) AS Num_Triple_Doppie
    FROM Analisi_Partita ap
    JOIN Partita p 
        ON ap.Data_Partita = p.Data_Partita AND ap.Squadra_Casa = p.Squadra_Casa
    JOIN Contratto c 
        ON ap.ID_Membro = c.ID_Membro 
        AND p.Data_Partita BETWEEN c.Inizio_Contratto AND c.Fine_Contratto
    WHERE 
        ((ap.Punti >= 10)::int +
         (ap.Rimbalzi >= 10)::int +
         (ap.Assist >= 10)::int) >= 3
        AND p.Numero_Stagione = 2023 
    GROUP BY ap.ID_Membro, p.Numero_Stagione, c.Nome_Squadra
),

SquadraTriple AS (
    SELECT 
        Nome_Squadra,
        SUM(Num_Triple_Doppie) AS Totale_Triple_Doppie
    FROM TripleDoppie
    GROUP BY Nome_Squadra
),

TopGiocatori AS (
    SELECT 
        td.Nome_Squadra,
        ms.Nome || ' ' || ms.Cognome AS Giocatore,
        td.Num_Triple_Doppie,
        ROW_NUMBER() OVER (PARTITION BY td.Nome_Squadra ORDER BY td.Num_Triple_Doppie DESC) AS rn
    FROM TripleDoppie td
    JOIN Membro_Squadra ms ON td.ID_Membro = ms.ID_Membro
)

SELECT 
    st.Nome_Squadra,
    st.Totale_Triple_Doppie,
    tg.Giocatore,
    tg.Num_Triple_Doppie AS Triple_Doppie_Giocatore
FROM SquadraTriple st
JOIN TopGiocatori tg 
    ON st.Nome_Squadra = tg.Nome_Squadra AND tg.rn = 1
ORDER BY st.Totale_Triple_Doppie DESC

-- QUERY 8 : Classifica degli N giocatori (numero scelto dall'utente) che hanno accumulato più punti in carriera
    -- specificando in quante partite hanno giocato

SELECT ms.Nome, ms.Cognome, COUNT(DISTINCT ap.Data_Partita) AS Partite_Giocate, SUM(ap.Punti) AS Totale_Punti
FROM Analisi_Partita ap
JOIN Membro_Squadra ms ON ap.ID_Membro = ms.ID_Membro
WHERE ms.Qualifica = 'Giocatore'
GROUP BY ms.ID_Membro, ms.Nome, ms.Cognome
ORDER BY Totale_Punti DESC, Partite_Giocate ASC
LIMIT 2;