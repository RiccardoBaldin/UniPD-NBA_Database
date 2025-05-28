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


CREATE TABLE IF NOT EXISTS Stadio (
    Nome_Stadio VARCHAR(32) NOT NULL,
    Città VARCHAR(32) NOT NULL,
    Capacità INT,

    PRIMARY KEY (Nome_Stadio)
);


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
-- FUNZIONI E CONTROLLI
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


--------------------------------------------------------------------------------------------------------------------------------------
-- INDICE
--------------------------------------------------------------------------------------------------------------------------------------

CREATE INDEX indice_Analisi_Partita ON Analisi_Partita (Data_partita, ID_Membro);


--------------------------------------------------------------------------------------------------------------------------------------
-- INSERIMENTI
--------------------------------------------------------------------------------------------------------------------------------------

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
                    (25, 'Rocky', 'Mascotte', '1995-01-01', 'USA', NULL, NULL, 'Mascotte', NULL),
                    (26, 'Kawhi', 'Leonard', '1991-06-29', 'USA', 104, 201, 'Giocatore', 'Ala Piccola'),
                    (27, 'Russell', 'Westbrook', '1988-11-12', 'USA', 91, 191, 'Giocatore', 'Playmaker'),
                    (28, 'Klay', 'Thompson', '1990-02-08', 'USA', 98, 198, 'Giocatore', 'Guardia'),
                    (29, 'Paul', 'George', '1990-05-02', 'USA', 100, 203, 'Giocatore', 'Ala Grande'),
                    (30, 'Bradley', 'Beal', '1993-06-28', 'USA', 91, 196, 'Giocatore', 'Guardia'),
                    (31, 'DeMar', 'DeRozan', '1989-08-07', 'USA', 102, 201, 'Giocatore', 'Ala Piccola'),
                    (32, 'John', 'Wall', '1990-09-06', 'USA', 91, 191, 'Giocatore', 'Playmaker'),
                    (33, 'Al', 'Horford', '1986-06-03', 'Repubblica Dominicana', 104, 208, 'Giocatore', 'Centro'),
                    (34, 'Nikola', 'Vucevic', '1990-10-24', 'Montenegro', 109, 211, 'Giocatore', 'Centro'),
                    (35, 'Jrue', 'Holiday', '1990-06-12', 'USA', 93, 193, 'Giocatore', 'Guardia'),
                    (36, 'Kristaps', 'Porzingis', '1995-08-02', 'Lettonia', 109, 221, 'Giocatore', 'Ala Grande'),
                    (37, 'Darius', 'Bazley', '1999-06-12', 'USA', 102, 203, 'Giocatore', 'Ala Grande'),
                    (38, 'Julius', 'Randle', '1994-11-29', 'USA', 109, 203, 'Giocatore', 'Ala Grande'),
                    (39, 'Mikal', 'Bridges', '1996-08-30', 'USA', 93, 201, 'Giocatore', 'Ala Piccola'),
                    (40, 'Fred', 'VanVleet', '1994-02-25', 'USA', 79, 183, 'Giocatore', 'Playmaker'),
                    (41, 'Tyler', 'Herro', '2000-01-20', 'USA', 86, 196, 'Giocatore', 'Guardia'),
                    (42, 'Buddy', 'Hield', '1993-12-17', 'Bahamas', 95, 193, 'Giocatore', 'Guardia'),
                    (43, 'Jarrett', 'Allen', '1998-04-21', 'USA', 109, 213, 'Giocatore', 'Centro'),
                    (44, 'Richaun', 'Holmes', '1993-06-15', 'USA', 109, 208, 'Giocatore', 'Centro'),
                    (45, 'Malcolm', 'Brogdon', '1992-12-11', 'USA', 91, 198, 'Giocatore', 'Playmaker'),
                    (46, 'Duncan', 'Robinson', '1994-04-22', 'USA', 86, 201, 'Giocatore', 'Ala Piccola'),
                    (47, 'Joe', 'Harris', '1991-09-06', 'USA', 98, 203, 'Giocatore', 'Ala Piccola'),
                    (48, 'Eric', 'Bledsoe', '1989-12-09', 'USA', 91, 188, 'Giocatore', 'Playmaker'),
                    (49, 'Jonas', 'Valanciunas', '1992-05-06', 'Lituania', 109, 213, 'Giocatore', 'Centro'),
                    (50, 'Clint', 'Capela', '1994-05-18', 'Svizzera', 109, 208, 'Giocatore', 'Centro'),
                    (51, 'Jaren', 'Jackson Jr.', '1999-09-15', 'USA', 104, 211, 'Giocatore', 'Ala Grande'),
                    (52, 'Bojan', 'Bogdanovic', '1989-04-18', 'Croazia', 102, 203, 'Giocatore', 'Ala Piccola'),
                    (53, 'Dennis', 'Schroder', '1993-09-15', 'Germania', 86, 188, 'Giocatore', 'Playmaker'),
                    (54, 'Gary', 'Harris', '1994-09-14', 'USA', 93, 196, 'Giocatore', 'Guardia'),
                    (55, 'Kevin', 'Huerter', '1998-08-27', 'USA', 86, 198, 'Giocatore', 'Guardia'),
                    (56, 'Jamal', 'Murray', '1997-02-23', 'Canada', 91, 191, 'Giocatore', 'Playmaker'),
                    (57, 'Collin', 'Sexton', '1999-01-04', 'USA', 86, 185, 'Giocatore', 'Guardia'),
                    (58, 'Jarrett', 'Culver', '1999-02-20', 'USA', 86, 198, 'Giocatore', 'Ala Piccola'),
                    (59, 'Terry', 'Rozier', '1994-03-17', 'USA', 84, 188, 'Giocatore', 'Guardia'),
                    (60, 'Monte', 'Morris', '1995-06-27', 'USA', 79, 183, 'Giocatore', 'Playmaker'),
                    (61, 'Malik', 'Beasley', '1996-11-26', 'USA', 91, 196, 'Giocatore', 'Guardia'),
                    (62, 'Wendell', 'Carter Jr.', '1999-04-16', 'USA', 102, 208, 'Giocatore', 'Centro');



INSERT INTO Contratto (ID_Membro, Nome_Squadra, Inizio_Contratto, Fine_Contratto, Stipendio) VALUES
                    (1, 'Miami Heat', '2018-05-27', '2020-05-27', 14000100),
                    (1, 'Miami Heat', '2020-05-28', '2022-05-27', 15000100),
                    (1, 'Miami Heat', '2022-05-28', '2023-05-27', 16000100),
                    (2, 'Atlanta Hawks', '2020-04-10', '2022-04-10', 4423085),
                    (2, 'Atlanta Hawks', '2022-04-11', '2023-04-10', 10000000),
                    (3, 'Sacramento Kings', '2018-06-10', '2025-06-10', 10198895),
                    (4, 'Utah Jazz', '2018-07-15', '2025-07-15', 21350564),
                    (5, 'Miami Heat', '2018-07-15', '2025-07-15', 10780890),
                    (6, 'Sacramento Kings', '2018-06-02', '2025-06-02', 23437791),
                    (7, 'Brooklyn Nets', '2018-02-25', '2025-02-25', 18942749),
                    (8, 'Atlanta Hawks', '2018-09-02', '2025-09-02', 5938422),
                    (9, 'Golden State Warriors', '2018-11-12', '2025-11-12', 23294959),
                    (10, 'Los Angeles Lakers', '2018-05-27', '2025-05-27', 23099314),
                    (11, 'Cleveland Cavaliers', '2018-07-17', '2025-07-17', 11286774),
                    (12, 'Golden State Warriors', '2018-07-25', '2025-07-25', 13813503),
                    (13, 'Phoenix Suns', '2018-04-23', '2025-04-23', 23484976),
                    (14, 'Golden State Warriors', '2018-12-09', '2025-12-09', 18774439),
                    (15, 'Dallas Mavericks', '2018-06-05', '2025-06-05', 8198668),
                    (16, 'Los Angeles Lakers', '2018-06-09', '2025-06-09', 9114934),
                    (17, 'Milwaukee Bucks', '2018-07-22', '2025-12-31', 22156189),
                    (18, 'Brooklyn Nets', '2018-09-04', '2025-12-31', 29084018),
                    (19, 'Washington Wizards', '2018-08-12', '2025-08-12', 28242819),
                    (20, 'Milwaukee Bucks', '2018-02-01', '2025-02-01', 16086834),
                    (26, 'Philadelphia 76ers', '2018-08-29', '2025-08-29', 9476631),
                    (27, 'Indiana Pacers', '2018-01-04', '2025-01-04', 22714372),
                    (28, 'Oklahoma City Thunder', '2018-03-08', '2025-12-31', 5906883),
                    (29, 'Indiana Pacers', '2018-11-29', '2025-11-29', 24552550),
                    (30, 'San Antonio Spurs', '2018-06-16', '2025-06-16', 20621800),
                    (31, 'Portland Trail Blazers', '2018-05-02', '2025-05-02', 20341492),
                    (32, 'Brooklyn Nets', '2018-06-10', '2025-06-10', 10139652),
                    (33, 'Chicago Bulls', '2018-12-02', '2025-12-02', 9996779),
                    (34, 'Chicago Bulls', '2018-08-03', '2025-08-03', 13000068),
                    (35, 'Detroit Pistons', '2018-12-06', '2025-12-06', 28442805),
                    (36, 'New Orleans Pelicans', '2018-07-31', '2025-07-31', 25241308),
                    (37, 'Miami Heat', '2018-02-24', '2025-12-31', 10375076),
                    (38, 'Miami Heat', '2018-02-22', '2025-02-22', 16817716),
                    (39, 'Utah Jazz', '2018-11-24', '2025-11-24', 15429607),
                    (40, 'Philadelphia 76ers', '2018-05-31', '2025-05-31', 5450173),
                    (41, 'Oklahoma City Thunder', '2018-10-09', '2025-10-09', 17445266),
                    (42, 'Memphis Grizzlies', '2018-01-01', '2025-01-01', 7889990),
                    (43, 'Oklahoma City Thunder', '2018-08-02', '2025-08-02', 4824519),
                    (44, 'Orlando Magic', '2018-01-12', '2025-01-12', 4292980),
                    (45, 'Miami Heat', '2018-11-08', '2025-11-08', 10496899),
                    (46, 'Dallas Mavericks', '2018-08-27', '2025-08-27', 20423484),
                    (47, 'Toronto Raptors', '2018-11-29', '2025-11-29', 10063717),
                    (48, 'Houston Rockets', '2018-08-23', '2025-08-23', 6079039),
                    (49, 'Minnesota Timberwolves', '2018-12-09', '2025-12-09', 25446785),
                    (50, 'Oklahoma City Thunder', '2018-03-29', '2025-03-29', 2613261),
                    (51, 'Orlando Magic', '2018-05-18', '2025-05-18', 20345057),
                    (52, 'New Orleans Pelicans', '2018-07-26', '2025-07-26', 6008559),
                    (53, 'Sacramento Kings', '2018-04-29', '2025-04-29', 27275611),
                    (54, 'Memphis Grizzlies', '2018-03-13', '2025-03-13', 4756801),
                    (55, 'Boston Celtics', '2018-08-01', '2025-08-01', 18222326),
                    (56, 'Philadelphia 76ers', '2018-05-31', '2025-05-31', 3340669),
                    (57, 'Dallas Mavericks', '2018-09-01', '2025-09-01', 25305495),
                    (58, 'Boston Celtics', '2018-04-08', '2025-04-08', 29528212),
                    (59, 'Detroit Pistons', '2018-08-17', '2025-08-17', 16872024),
                    (60, 'Washington Wizards', '2018-08-26', '2025-08-26', 10148290),
                    (61, 'Philadelphia 76ers', '2018-07-11', '2025-07-11', 1961375),
                    (62, 'Charlotte Hornets', '2018-12-07', '2025-12-07', 15660657);



INSERT INTO Premio (Nome_premio, Numero_Stagione, ID_Membro) VALUES
                    ('MVP', 2020, 4),
                    ('All-NBA Team', 2020, 1),
                    ('All-NBA Team', 2020, 2),
                    ('All-NBA Team', 2020, 3),
                    ('All-NBA Team', 2020, 5),
                    ('All-NBA Team', 2020, 7),
                    ('NBA All-Defensive Team', 2020, 13),
                    ('NBA All-Defensive Team', 2020, 14),
                    ('NBA All-Defensive Team', 2020, 18),
                    ('NBA All-Defensive Team', 2020, 29),
                    ('NBA All-Defensive Team', 2020, 47),
                    ('MVP', 2021, 5),
                    ('All-NBA Team', 2021, 6),
                    ('All-NBA Team', 2021, 10),
                    ('All-NBA Team', 2021, 15),
                    ('All-NBA Team', 2021, 19),
                    ('All-NBA Team', 2021, 26),
                    ('NBA All-Defensive Team', 2021, 13),
                    ('NBA All-Defensive Team', 2021, 14),
                    ('NBA All-Defensive Team', 2021, 18),
                    ('NBA All-Defensive Team', 2021, 39),
                    ('NBA All-Defensive Team', 2021, 43),
                    ('MVP', 2022, 6),
                    ('All-NBA Team', 2022, 9),
                    ('All-NBA Team', 2022, 8),
                    ('All-NBA Team', 2022, 10),
                    ('All-NBA Team', 2022, 15),
                    ('All-NBA Team', 2022, 20),
                    ('NBA All-Defensive Team', 2022, 13),
                    ('NBA All-Defensive Team', 2022, 14),
                    ('NBA All-Defensive Team', 2022, 29),
                    ('NBA All-Defensive Team', 2022, 43),
                    ('NBA All-Defensive Team', 2022, 51),
                    ('MVP', 2023, 5),
                    ('All-NBA Team', 2023, 7),
                    ('All-NBA Team', 2023, 11),
                    ('All-NBA Team', 2023, 10),
                    ('All-NBA Team', 2023, 1),
                    ('All-NBA Team', 2023, 15),
                    ('NBA All-Defensive Team', 2023, 14),
                    ('NBA All-Defensive Team', 2023, 13),
                    ('NBA All-Defensive Team', 2023, 18),
                    ('NBA All-Defensive Team', 2023, 39),
                    ('NBA All-Defensive Team', 2023, 43),
                    ('All-NBA Team', 2024, 17),
                    ('All-NBA Team', 2024, 34),
                    ('All-NBA Team', 2024, 8),
                    ('All-NBA Team', 2024, 10),
                    ('All-NBA Team', 2024, 19),
                    ('NBA All-Defensive Team', 2024, 14),
                    ('NBA All-Defensive Team', 2024, 13),
                    ('NBA All-Defensive Team', 2024, 29),
                    ('NBA All-Defensive Team', 2024, 43),
                    ('NBA All-Defensive Team', 2024, 51);


INSERT INTO Partita (data_partita, squadra_casa, squadra_ospiti, punteggio_casa, punteggio_ospiti, numero_stagione)
VALUES
                    ('2018-10-17', 'Boston Celtics', 'Philadelphia 76ers', 105, 87, 2019),
                    ('2018-10-17', 'Charlotte Hornets', 'Milwaukee Bucks', 112, 113, 2019),
                    ('2018-10-17', 'Indiana Pacers', 'Memphis Grizzlies', 100, 107, 2019),
                    ('2018-10-18', 'Houston Rockets', 'New Orleans Pelicans', 112, 131, 2019),
                    ('2018-10-18', 'LA Clippers', 'Denver Nuggets', 98, 107, 2019),
                    ('2018-10-18', 'Sacramento Kings', 'Utah Jazz', 117, 103, 2019),
                    ('2018-10-18', 'San Antonio Spurs', 'Minnesota Timberwolves', 112, 108, 2019),
                    ('2018-10-19', 'Orlando Magic', 'Charlotte Hornets', 88, 112, 2019),
                    ('2018-10-19', 'Philadelphia 76ers', 'Milwaukee Bucks', 132, 126, 2019),
                    ('2018-10-19', 'Portland Trail Blazers', 'Los Angeles Lakers', 128, 119, 2019),
                    ('2018-10-19', 'Washington Wizards', 'Miami Heat', 112, 113, 2019),
                    ('2018-10-20', 'Minnesota Timberwolves', 'Cleveland Cavaliers', 131, 123, 2019),
                    ('2018-10-20', 'New Orleans Pelicans', 'Sacramento Kings', 149, 129, 2019),
                    ('2018-10-20', 'New York Knicks', 'Boston Celtics', 126, 137, 2019),
                    ('2018-10-20', 'Toronto Raptors', 'Boston Celtics', 113, 101, 2019),
                    ('2018-10-21', 'Denver Nuggets', 'Golden State Warriors', 100, 98, 2019),
                    ('2018-10-21', 'Los Angeles Lakers', 'Houston Rockets', 115, 124, 2019),
                    ('2018-10-21', 'Miami Heat', 'Charlotte Hornets', 112, 113, 2019),
                    ('2018-10-21', 'Oklahoma City Thunder', 'LA Clippers', 92, 108, 2019),
                    ('2018-10-22', 'Boston Celtics', 'Milwaukee Bucks', 103, 118, 2019),
                    ('2018-10-22', 'LA Clippers', 'San Antonio Spurs', 92, 107, 2019),
                    ('2018-10-23', 'Milwaukee Bucks', 'New York Knicks', 124, 113, 2019),
                    ('2018-10-23', 'Minnesota Timberwolves', 'Indiana Pacers', 101, 91, 2019),
                    ('2018-10-23', 'Portland Trail Blazers', 'Washington Wizards', 113, 124, 2019),
                    ('2018-10-23', 'Utah Jazz', 'Houston Rockets', 100, 89, 2019),
                    ('2018-10-24', 'Atlanta Hawks', 'Dallas Mavericks', 111, 104, 2019),
                    ('2018-10-24', 'Miami Heat', 'New York Knicks', 110, 87, 2019),
                    ('2018-10-24', 'New Orleans Pelicans', 'Los Angeles Lakers', 131, 112, 2019),
                    ('2018-10-25', 'Chicago Bulls', 'Charlotte Hornets', 112, 110, 2019),
                    ('2018-10-25', 'Houston Rockets', 'Utah Jazz', 89, 100, 2019),
                    ('2018-10-25', 'Milwaukee Bucks', 'Philadelphia 76ers', 123, 108, 2019),
                    ('2018-10-25', 'Orlando Magic', 'Boston Celtics', 93, 90, 2019),
                    ('2018-10-25', 'Phoenix Suns', 'Memphis Grizzlies', 97, 117, 2019),
                    ('2018-10-26', 'Charlotte Hornets', 'Chicago Bulls', 106, 112, 2019),
                    ('2018-10-26', 'New Orleans Pelicans', 'Brooklyn Nets', 116, 115, 2019),
                    ('2018-10-27', 'Detroit Pistons', 'Boston Celtics', 89, 87, 2019),
                    ('2018-10-27', 'Houston Rockets', 'LA Clippers', 116, 133, 2019),
                    ('2018-10-27', 'Memphis Grizzlies', 'Phoenix Suns', 117, 96, 2019),
                    ('2018-10-27', 'Sacramento Kings', 'Washington Wizards', 116, 112, 2019),
                    ('2018-10-28', 'Memphis Grizzlies', 'Phoenix Suns', 117, 96, 2019),
                    ('2018-10-28', 'San Antonio Spurs', 'Los Angeles Lakers', 110, 106, 2019),
                    ('2018-10-29', 'LA Clippers', 'Oklahoma City Thunder', 128, 138, 2019),
                    ('2018-10-29', 'New York Knicks', 'Indiana Pacers', 101, 107, 2019),
                    ('2018-10-30', 'Milwaukee Bucks', 'Toronto Raptors', 124, 109, 2019),
                    ('2018-10-31', 'Memphis Grizzlies', 'Utah Jazz', 88, 96, 2019),
                    ('2018-11-01', 'Atlanta Hawks', 'Sacramento Kings', 123, 115, 2019),
                    ('2018-11-01', 'Houston Rockets', 'Portland Trail Blazers', 105, 113, 2019),
                    ('2018-11-01', 'Los Angeles Lakers', 'Minnesota Timberwolves', 114, 110, 2019),
                    ('2018-11-06', 'Detroit Pistons', 'Miami Heat', 115, 120, 2019),
                    ('2018-11-06', 'Orlando Magic', 'Cleveland Cavaliers', 107, 100, 2019),
                    ('2018-11-08', 'Utah Jazz', 'Dallas Mavericks', 117, 102, 2019),
                    ('2018-11-09', 'Phoenix Suns', 'Boston Celtics', 109, 116, 2019),
                    ('2018-11-10', 'Philadelphia 76ers', 'Charlotte Hornets', 109, 99, 2019),
                    ('2018-11-11', 'Memphis Grizzlies', 'Philadelphia 76ers', 112, 106, 2019),
                    ('2018-11-12', 'Denver Nuggets', 'Houston Rockets', 109, 104, 2019),
                    ('2018-11-13', 'Miami Heat', 'San Antonio Spurs', 110, 113, 2019),
                    ('2018-11-14', 'Cleveland Cavaliers', 'Charlotte Hornets', 113, 89, 2019),
                    ('2018-11-15', 'Indiana Pacers', 'Miami Heat', 99, 91, 2019),
                    ('2018-11-15', 'Milwaukee Bucks', 'Memphis Grizzlies', 110, 107, 2019),
                    ('2018-11-15', 'Orlando Magic', 'New York Knicks', 115, 89, 2019),
                    ('2018-11-17', 'Washington Wizards', 'Brooklyn Nets', 120, 122, 2019),
                    ('2018-11-18', 'Chicago Bulls', 'Orlando Magic', 104, 109, 2019),
                    ('2018-11-20', 'Detroit Pistons', 'Houston Rockets', 116, 111, 2019),
                    ('2018-11-20', 'Indiana Pacers', 'Utah Jazz', 121, 94, 2019),
                    ('2018-11-20', 'Philadelphia 76ers', 'Phoenix Suns', 119, 114, 2019),
                    ('2018-11-22', 'Cleveland Cavaliers', 'Milwaukee Bucks', 92, 119, 2019),
                    ('2018-11-24', 'Atlanta Hawks', 'Boston Celtics', 106, 114, 2019),
                    ('2018-11-24', 'Detroit Pistons', 'Houston Rockets', 116, 111, 2019),
                    ('2018-11-24', 'Los Angeles Lakers', 'Utah Jazz', 90, 83, 2019),
                    ('2018-11-24', 'Washington Wizards', 'New Orleans Pelicans', 124, 114, 2019),
                    ('2018-11-25', 'Cleveland Cavaliers', 'Los Angeles Lakers', 105, 109, 2019),
                    ('2018-11-25', 'Dallas Mavericks', 'Sacramento Kings', 117, 116, 2019),
                    ('2018-11-25', 'Minnesota Timberwolves', 'Chicago Bulls', 101, 100, 2019),
                    ('2018-11-25', 'Oklahoma City Thunder', 'Denver Nuggets', 119, 124, 2019),
                    ('2018-11-26', 'Portland Trail Blazers', 'Orlando Magic', 115, 112, 2019),
                    ('2018-11-26', 'Sacramento Kings', 'Golden State Warriors', 106, 127, 2019),
                    ('2023-12-25', 'Los Angeles Lakers', 'Boston Celtics', 115, 126, 2023),
                    ('2022-12-14', 'Los Angeles Lakers', 'Boston Celtics', 118, 122, 2022),
                    ('2021-12-08', 'Los Angeles Lakers', 'Boston Celtics', 117, 102, 2021),
                    ('2021-04-16', 'Los Angeles Lakers', 'Boston Celtics', 113, 121, 2020),
                    ('2020-02-23', 'Los Angeles Lakers', 'Boston Celtics', 114, 112, 2019),
                    ('2019-03-10', 'Los Angeles Lakers', 'Boston Celtics', 107, 120, 2018),
                    ('2024-10-22', 'Boston Celtics', 'New York Knicks', 132, 109, 2024),
                    ('2024-10-23', 'Los Angeles Lakers', 'Minnesota Timberwolves', 110, 103, 2024),
                    ('2024-10-23', 'Detroit Pistons', 'Indiana Pacers', 109, 115, 2024),
                    ('2024-10-23', 'Atlanta Hawks', 'Brooklyn Nets', 120, 116, 2024),
                    ('2024-10-23', 'Miami Heat', 'Orlando Magic', 97, 116, 2024),
                    ('2024-10-23', 'Philadelphia 76ers', 'Milwaukee Bucks', 109, 124, 2024),
                    ('2024-10-23', 'Toronto Raptors', 'Cleveland Cavaliers', 106, 136, 2024),
                    ('2024-10-24', 'Houston Rockets', 'Charlotte Hornets', 105, 110, 2024),
                    ('2024-10-24', 'New Orleans Pelicans', 'Chicago Bulls', 123, 111, 2024),
                    ('2024-10-24', 'Utah Jazz', 'Memphis Grizzlies', 124, 126, 2024),
                    ('2024-10-24', 'LA Clippers', 'Phoenix Suns', 113, 116, 2024),
                    ('2024-10-24', 'Portland Trail Blazers', 'Golden State Warriors', 104, 140, 2024),
                    ('2024-10-24', 'Washington Wizards', 'Boston Celtics', 102, 122, 2024),
                    ('2024-10-24', 'Dallas Mavericks', 'San Antonio Spurs', 120, 109, 2024),
                    ('2024-10-25', 'Denver Nuggets', 'Oklahoma City Thunder', 87, 102, 2024),
                    ('2024-10-25', 'Sacramento Kings', 'Minnesota Timberwolves', 115, 117, 2024),
                    ('2024-10-25', 'Orlando Magic', 'Brooklyn Nets', 116, 101, 2024),
                    ('2024-10-25', 'Toronto Raptors', 'Philadelphia 76ers', 115, 107, 2024),
                    ('2024-10-25', 'Atlanta Hawks', 'Charlotte Hornets', 125, 120, 2024),
                    ('2024-10-25', 'Cleveland Cavaliers', 'Detroit Pistons', 113, 101, 2024),
                    ('2024-10-25', 'New York Knicks', 'Indiana Pacers', 123, 98, 2024),
                    ('2024-10-26', 'Houston Rockets', 'Memphis Grizzlies', 128, 108, 2024),
                    ('2024-10-26', 'Milwaukee Bucks', 'Chicago Bulls', 122, 133, 2024),
                    ('2024-10-26', 'Utah Jazz', 'Golden State Warriors', 86, 127, 2024),
                    ('2024-10-26', 'Los Angeles Lakers', 'Phoenix Suns', 123, 116, 2024),
                    ('2024-10-26', 'Portland Trail Blazers', 'New Orleans Pelicans', 103, 105, 2024),
                    ('2024-10-26', 'Denver Nuggets', 'LA Clippers', 104, 109, 2024),
                    ('2024-10-26', 'Charlotte Hornets', 'Miami Heat', 106, 114, 2024),
                    ('2024-10-26', 'Detroit Pistons', 'Boston Celtics', 118, 124, 2024),
                    ('2024-10-26', 'Washington Wizards', 'Cleveland Cavaliers', 116, 135, 2024),
                    ('2024-10-27', 'Chicago Bulls', 'Oklahoma City Thunder', 95, 114, 2024),
                    ('2024-10-27', 'Memphis Grizzlies', 'Orlando Magic', 124, 111, 2024),
                    ('2024-10-27', 'Minnesota Timberwolves', 'Toronto Raptors', 112, 101, 2024),
                    ('2024-10-27', 'San Antonio Spurs', 'Houston Rockets', 109, 106, 2024),
                    ('2024-10-27', 'Phoenix Suns', 'Dallas Mavericks', 114, 102, 2024),
                    ('2024-10-27', 'Los Angeles Lakers', 'Sacramento Kings', 131, 127, 2024),
                    ('2024-10-27', 'Indiana Pacers', 'Philadelphia 76ers', 114, 118, 2024),
                    ('2024-10-27', 'Brooklyn Nets', 'Milwaukee Bucks', 115, 102, 2024),
                    ('2024-10-27', 'Portland Trail Blazers', 'New Orleans Pelicans', 125, 103, 2024),
                    ('2024-10-27', 'Oklahoma City Thunder', 'Atlanta Hawks', 128, 104, 2024),
                    ('2024-10-28', 'Golden State Warriors', 'LA Clippers', 104, 112, 2024),
                    ('2024-10-28', 'Orlando Magic', 'Indiana Pacers', 119, 115, 2024),
                    ('2024-10-28', 'Atlanta Hawks', 'Washington Wizards', 119, 121, 2024),
                    ('2024-10-28', 'Boston Celtics', 'Milwaukee Bucks', 119, 108, 2024),
                    ('2024-10-28', 'Miami Heat', 'Detroit Pistons', 106, 98, 2024),
                    ('2024-10-28', 'New York Knicks', 'Cleveland Cavaliers', 104, 110, 2024),
                    ('2024-10-28', 'Toronto Raptors', 'Denver Nuggets', 125, 127, 2024),
                    ('2024-10-29', 'Memphis Grizzlies', 'Chicago Bulls', 123, 126, 2024),
                    ('2024-10-29', 'San Antonio Spurs', 'Houston Rockets', 101, 106, 2024),
                    ('2024-10-29', 'Dallas Mavericks', 'Utah Jazz', 110, 102, 2024),
                    ('2024-10-29', 'Phoenix Suns', 'Los Angeles Lakers', 109, 105, 2024),
                    ('2024-10-29', 'Sacramento Kings', 'Portland Trail Blazers', 111, 98, 2024),
                    ('2024-10-29', 'Brooklyn Nets', 'Denver Nuggets', 139, 144, 2024),
                    ('2024-10-29', 'Minnesota Timberwolves', 'Dallas Mavericks', 114, 120, 2024),
                    ('2024-10-30', 'Utah Jazz', 'Sacramento Kings', 96, 113, 2024),
                    ('2024-10-30', 'Golden State Warriors', 'New Orleans Pelicans', 124, 106, 2024),
                    ('2024-10-30', 'Charlotte Hornets', 'Toronto Raptors', 138, 133, 2024),
                    ('2024-10-30', 'Cleveland Cavaliers', 'Los Angeles Lakers', 134, 110, 2024),
                    ('2024-10-30', 'Indiana Pacers', 'Boston Celtics', 135, 132, 2024),
                    ('2024-10-30', 'Philadelphia 76ers', 'Detroit Pistons', 95, 105, 2024),
                    ('2024-10-30', 'Washington Wizards', 'Atlanta Hawks', 133, 120, 2024),
                    ('2024-10-30', 'Miami Heat', 'New York Knicks', 107, 116, 2024),
                    ('2024-10-31', 'Chicago Bulls', 'Orlando Magic', 102, 99, 2024),
                    ('2024-10-31', 'Memphis Grizzlies', 'Brooklyn Nets', 106, 119, 2024),
                    ('2024-10-31', 'Oklahoma City Thunder', 'San Antonio Spurs', 105, 93, 2024),
                    ('2024-10-31', 'Golden State Warriors', 'New Orleans Pelicans', 104, 89, 2024),
                    ('2024-10-31', 'LA Clippers', 'Portland Trail Blazers', 105, 106, 2024),
                    ('2024-11-01', 'Memphis Grizzlies', 'Milwaukee Bucks', 122, 99, 2024),
                    ('2024-11-01', 'Dallas Mavericks', 'Houston Rockets', 102, 108, 2024),
                    ('2024-11-01', 'Utah Jazz', 'San Antonio Spurs', 88, 106, 2024),
                    ('2024-11-01', 'LA Clippers', 'Phoenix Suns', 119, 125, 2024),
                    ('2024-11-01', 'Charlotte Hornets', 'Boston Celtics', 109, 124, 2024),
                    ('2024-11-01', 'Cleveland Cavaliers', 'Orlando Magic', 120, 109, 2024),
                    ('2024-11-01', 'Detroit Pistons', 'New York Knicks', 98, 128, 2024),
                    ('2024-11-01', 'Atlanta Hawks', 'Sacramento Kings', 115, 123, 2024),
                    ('2024-11-01', 'Brooklyn Nets', 'Chicago Bulls', 120, 112, 2024),
                    ('2024-11-01', 'Toronto Raptors', 'Los Angeles Lakers', 125, 131, 2024),
                    ('2024-11-02', 'New Orleans Pelicans', 'Indiana Pacers', 125, 118, 2024),
                    ('2024-11-02', 'Minnesota Timberwolves', 'Denver Nuggets', 119, 116, 2024),
                    ('2024-11-02', 'Portland Trail Blazers', 'Oklahoma City Thunder', 114, 137, 2024),
                    ('2024-11-02', 'Charlotte Hornets', 'Boston Celtics', 103, 113, 2024),
                    ('2024-11-02', 'Philadelphia 76ers', 'Memphis Grizzlies', 104, 124, 2024),
                    ('2024-11-02', 'Toronto Raptors', 'Sacramento Kings', 131, 128, 2024),
                    ('2024-11-03', 'Houston Rockets', 'Golden State Warriors', 121, 127, 2024),
                    ('2024-11-03', 'Milwaukee Bucks', 'Cleveland Cavaliers', 113, 114, 2024),
                    ('2024-11-03', 'San Antonio Spurs', 'Minnesota Timberwolves', 113, 103, 2024),
                    ('2024-11-03', 'Washington Wizards', 'Miami Heat', 98, 118, 2024),
                    ('2024-11-03', 'Denver Nuggets', 'Utah Jazz', 129, 103, 2024),
                    ('2024-11-03', 'Phoenix Suns', 'Portland Trail Blazers', 103, 97, 2024),
                    ('2024-11-03', 'LA Clippers', 'Oklahoma City Thunder', 92, 105, 2024),
                    ('2024-11-03', 'Brooklyn Nets', 'Detroit Pistons', 92, 106, 2024),
                    ('2024-11-04', 'New Orleans Pelicans', 'Atlanta Hawks', 111, 126, 2024),
                    ('2024-11-04', 'Dallas Mavericks', 'Orlando Magic', 108, 85, 2024),
                    ('2024-11-05', 'Cleveland Cavaliers', 'Milwaukee Bucks', 116, 114, 2024),
                    ('2024-11-05', 'Washington Wizards', 'Golden State Warriors', 112, 125, 2024),
                    ('2024-11-05', 'Detroit Pistons', 'Los Angeles Lakers', 115, 103, 2024),
                    ('2024-11-05', 'Atlanta Hawks', 'Boston Celtics', 93, 123, 2024),
                    ('2024-11-05', 'Brooklyn Nets', 'Memphis Grizzlies', 106, 104, 2024),
                    ('2024-11-05', 'Miami Heat', 'Sacramento Kings', 110, 111, 2024),
                    ('2024-11-05', 'Chicago Bulls', 'Utah Jazz', 126, 135, 2024),
                    ('2024-11-05', 'Houston Rockets', 'New York Knicks', 109, 97, 2024),
                    ('2024-11-05', 'Minnesota Timberwolves', 'Charlotte Hornets', 114, 93, 2024),
                    ('2024-11-05', 'Oklahoma City Thunder', 'Orlando Magic', 102, 86, 2024),
                    ('2024-11-05', 'New Orleans Pelicans', 'Portland Trail Blazers', 100, 118, 2024),
                    ('2024-11-05', 'Dallas Mavericks', 'Indiana Pacers', 127, 134, 2024),
                    ('2024-11-05', 'Denver Nuggets', 'Toronto Raptors', 121, 119, 2024),
                    ('2024-11-05', 'Phoenix Suns', 'Philadelphia 76ers', 118, 116, 2024),
                    ('2024-11-05', 'LA Clippers', 'San Antonio Spurs', 113, 104, 2024),
                    ('2024-11-07', 'Charlotte Hornets', 'Detroit Pistons', 108, 107, 2024),
                    ('2024-11-07', 'Indiana Pacers', 'Orlando Magic', 118, 111, 2024),
                    ('2024-11-07', 'Atlanta Hawks', 'New York Knicks', 121, 116, 2024),
                    ('2024-11-07', 'Boston Celtics', 'Golden State Warriors', 112, 118, 2024),
                    ('2024-11-07', 'Houston Rockets', 'San Antonio Spurs', 127, 100, 2024),
                    ('2024-11-07', 'Memphis Grizzlies', 'Los Angeles Lakers', 131, 114, 2024),
                    ('2024-11-07', 'New Orleans Pelicans', 'Cleveland Cavaliers', 122, 131, 2024),
                    ('2024-11-07', 'Dallas Mavericks', 'Chicago Bulls', 119, 99, 2024),
                    ('2024-11-07', 'Denver Nuggets', 'Oklahoma City Thunder', 124, 122, 2024),
                    ('2024-11-07', 'Phoenix Suns', 'Miami Heat', 115, 112, 2024),
                    ('2024-11-07', 'LA Clippers', 'Philadelphia 76ers', 110, 98, 2024),
                    ('2024-11-07', 'Sacramento Kings', 'Toronto Raptors', 122, 107, 2024),
                    ('2024-11-08', 'Chicago Bulls', 'Minnesota Timberwolves', 119, 135, 2024),
                    ('2024-11-08', 'Milwaukee Bucks', 'Utah Jazz', 123, 100, 2024),
                    ('2024-11-08', 'San Antonio Spurs', 'Portland Trail Blazers', 118, 105, 2024),
                    ('2024-11-09', 'Charlotte Hornets', 'Indiana Pacers', 103, 83, 2024),
                    ('2024-11-09', 'Detroit Pistons', 'Atlanta Hawks', 122, 121, 2024),
                    ('2024-11-09', 'Orlando Magic', 'New Orleans Pelicans', 115, 88, 2024),
                    ('2024-11-09', 'Boston Celtics', 'Brooklyn Nets', 108, 104, 2024),
                    ('2024-11-09', 'Cleveland Cavaliers', 'Golden State Warriors', 136, 117, 2024),
                    ('2024-11-09', 'New York Knicks', 'Milwaukee Bucks', 116, 94, 2024),
                    ('2024-11-09', 'Dallas Mavericks', 'Phoenix Suns', 113, 114, 2024),
                    ('2024-11-09', 'Memphis Grizzlies', 'Washington Wizards', 128, 104, 2024),
                    ('2024-11-09', 'Oklahoma City Thunder', 'Houston Rockets', 126, 107, 2024),
                    ('2024-11-09', 'Minnesota Timberwolves', 'Portland Trail Blazers', 127, 102, 2024),
                    ('2024-11-09', 'Denver Nuggets', 'Miami Heat', 135, 122, 2024),
                    ('2024-11-09', 'Los Angeles Lakers', 'Philadelphia 76ers', 116, 106, 2024),
                    ('2024-11-09', 'Sacramento Kings', 'LA Clippers', 98, 107, 2024),
                    ('2024-11-09', 'San Antonio Spurs', 'Utah Jazz', 110, 111, 2024),
                    ('2024-11-10', 'Atlanta Hawks', 'Chicago Bulls', 113, 125, 2024),
                    ('2024-11-10', 'Cleveland Cavaliers', 'Brooklyn Nets', 105, 100, 2024),
                    ('2024-11-10', 'LA Clippers', 'Toronto Raptors', 105, 103, 2024),
                    ('2024-11-10', 'Detroit Pistons', 'Houston Rockets', 99, 101, 2024),
                    ('2024-11-10', 'Milwaukee Bucks', 'Boston Celtics', 107, 113, 2024),
                    ('2024-11-10', 'Indiana Pacers', 'New York Knicks', 132, 121, 2024),
                    ('2024-11-10', 'Orlando Magic', 'Washington Wizards', 121, 94, 2024),
                    ('2024-11-11', 'Philadelphia 76ers', 'Charlotte Hornets', 107, 105, 2024),
                    ('2024-11-11', 'Minnesota Timberwolves', 'Miami Heat', 94, 95, 2024),
                    ('2024-11-11', 'Oklahoma City Thunder', 'Golden State Warriors', 116, 127, 2024),
                    ('2024-11-11', 'Denver Nuggets', 'Dallas Mavericks', 122, 120, 2024),
                    ('2024-11-11', 'Phoenix Suns', 'Sacramento Kings', 118, 127, 2024),
                    ('2024-11-11', 'Portland Trail Blazers', 'Memphis Grizzlies', 89, 134, 2024),
                    ('2024-11-11', 'Los Angeles Lakers', 'Toronto Raptors', 123, 103, 2024),
                    ('2024-11-12', 'Chicago Bulls', 'Cleveland Cavaliers', 113, 119, 2024),
                    ('2024-11-12', 'Houston Rockets', 'Washington Wizards', 107, 92, 2024),
                    ('2024-11-12', 'New Orleans Pelicans', 'Brooklyn Nets', 105, 107, 2024),
                    ('2024-11-12', 'Oklahoma City Thunder', 'LA Clippers', 134, 128, 2024),
                    ('2024-11-12', 'San Antonio Spurs', 'Sacramento Kings', 116, 96, 2024),
                    ('2024-11-13', 'Boston Celtics', 'Atlanta Hawks', 116, 117, 2024),
                    ('2024-11-13', 'Detroit Pistons', 'Miami Heat', 123, 121, 2024),
                    ('2024-11-13', 'Orlando Magic', 'Charlotte Hornets', 114, 89, 2024),
                    ('2024-11-13', 'Philadelphia 76ers', 'New York Knicks', 99, 111, 2024),
                    ('2024-11-13', 'Milwaukee Bucks', 'Toronto Raptors', 99, 85, 2024),
                    ('2024-11-13', 'Utah Jazz', 'Phoenix Suns', 112, 120, 2024),
                    ('2024-11-13', 'Golden State Warriors', 'Dallas Mavericks', 120, 117, 2024),
                    ('2024-11-13', 'Portland Trail Blazers', 'Minnesota Timberwolves', 122, 108, 2024),
                    ('2024-11-14', 'Orlando Magic', 'Indiana Pacers', 94, 90, 2024),
                    ('2024-11-14', 'Brooklyn Nets', 'Boston Celtics', 114, 139, 2024),
                    ('2024-11-14', 'New York Knicks', 'Chicago Bulls', 123, 124, 2024),
                    ('2024-11-14', 'Philadelphia 76ers', 'Cleveland Cavaliers', 106, 114, 2024),
                    ('2024-11-14', 'Oklahoma City Thunder', 'New Orleans Pelicans', 106, 88, 2024),
                    ('2024-11-14', 'Houston Rockets', 'LA Clippers', 111, 103, 2024),
                    ('2024-11-14', 'Milwaukee Bucks', 'Detroit Pistons', 127, 120, 2024),
                    ('2024-11-14', 'San Antonio Spurs', 'Washington Wizards', 139, 130, 2024),
                    ('2024-11-14', 'Los Angeles Lakers', 'Memphis Grizzlies', 128, 123, 2024),
                    ('2024-11-14', 'Portland Trail Blazers', 'Minnesota Timberwolves', 106, 98, 2024),
                    ('2024-11-14', 'Sacramento Kings', 'Phoenix Suns', 127, 104, 2024),
                    ('2024-11-15', 'Utah Jazz', 'Dallas Mavericks', 115, 113, 2024),
                    ('2024-11-16', 'Indiana Pacers', 'Miami Heat', 111, 124, 2024),
                    ('2024-11-16', 'Orlando Magic', 'Philadelphia 76ers', 98, 86, 2024),
                    ('2024-11-16', 'Toronto Raptors', 'Detroit Pistons', 95, 99, 2024),
                    ('2024-11-16', 'Atlanta Hawks', 'Washington Wizards', 129, 117, 2024),
                    ('2024-11-16', 'Cleveland Cavaliers', 'Chicago Bulls', 144, 126, 2024),
                    ('2024-11-16', 'New York Knicks', 'Brooklyn Nets', 124, 122, 2024),
                    ('2024-11-16', 'San Antonio Spurs', 'Los Angeles Lakers', 115, 120, 2024),
                    ('2024-11-16', 'Houston Rockets', 'LA Clippers', 125, 104, 2024),
                    ('2024-11-16', 'New Orleans Pelicans', 'Denver Nuggets', 101, 94, 2024),
                    ('2024-11-16', 'Oklahoma City Thunder', 'Phoenix Suns', 99, 83, 2024),
                    ('2024-11-16', 'Golden State Warriors', 'Memphis Grizzlies', 123, 118, 2024),
                    ('2024-11-16', 'Sacramento Kings', 'Minnesota Timberwolves', 126, 130, 2024),
                    ('2024-11-16', 'Charlotte Hornets', 'Milwaukee Bucks', 115, 114, 2024),
                    ('2024-11-17', 'Boston Celtics', 'Toronto Raptors', 126, 123, 2024),
                    ('2024-11-17', 'New Orleans Pelicans', 'Los Angeles Lakers', 99, 104, 2024),
                    ('2024-11-17', 'Dallas Mavericks', 'San Antonio Spurs', 110, 93, 2024),
                    ('2024-11-17', 'Sacramento Kings', 'Utah Jazz', 121, 117, 2024),
                    ('2024-11-17', 'Minnesota Timberwolves', 'Phoenix Suns', 120, 117, 2024),
                    ('2024-11-17', 'Indiana Pacers', 'Miami Heat', 119, 110, 2024),
                    ('2024-11-17', 'Cleveland Cavaliers', 'Charlotte Hornets', 128, 114, 2024),
                    ('2024-11-17', 'Washington Wizards', 'Detroit Pistons', 104, 124, 2024),
                    ('2024-11-17', 'Memphis Grizzlies', 'Denver Nuggets', 105, 90, 2024),
                    ('2024-11-17', 'Portland Trail Blazers', 'Atlanta Hawks', 114, 110, 2024),
                    ('2024-11-18', 'New York Knicks', 'Brooklyn Nets', 114, 104, 2024),
                    ('2024-11-18', 'Chicago Bulls', 'Houston Rockets', 107, 143, 2024),
                    ('2024-11-18', 'Oklahoma City Thunder', 'Dallas Mavericks', 119, 121, 2024),
                    ('2024-11-18', 'LA Clippers', 'Utah Jazz', 116, 105, 2024),
                    ('2024-11-19', 'Detroit Pistons', 'Chicago Bulls', 112, 122, 2024),
                    ('2024-11-19', 'Miami Heat', 'Philadelphia 76ers', 106, 89, 2024),
                    ('2024-11-19', 'New York Knicks', 'Washington Wizards', 134, 106, 2024),
                    ('2024-11-19', 'Toronto Raptors', 'Indiana Pacers', 130, 119, 2024),
                    ('2024-11-19', 'Milwaukee Bucks', 'Houston Rockets', 101, 100, 2024),
                    ('2024-11-19', 'Phoenix Suns', 'Orlando Magic', 99, 109, 2024),
                    ('2024-11-19', 'Sacramento Kings', 'Atlanta Hawks', 108, 109, 2024),
                    ('2024-11-19', 'LA Clippers', 'Golden State Warriors', 102, 99, 2024),
                    ('2024-11-20', 'Boston Celtics', 'Cleveland Cavaliers', 120, 117, 2024),
                    ('2024-11-20', 'Brooklyn Nets', 'Charlotte Hornets', 116, 115, 2024),
                    ('2024-11-20', 'Memphis Grizzlies', 'Denver Nuggets', 110, 122, 2024),
                    ('2024-11-20', 'Dallas Mavericks', 'New Orleans Pelicans', 132, 91, 2024),
                    ('2024-11-20', 'San Antonio Spurs', 'Oklahoma City Thunder', 110, 104, 2024),
                    ('2024-11-20', 'Los Angeles Lakers', 'Utah Jazz', 124, 118, 2024),
                    ('2024-11-21', 'Cleveland Cavaliers', 'New Orleans Pelicans', 128, 100, 2024),
                    ('2024-11-21', 'Milwaukee Bucks', 'Chicago Bulls', 122, 106, 2024),
                    ('2024-11-21', 'Houston Rockets', 'Indiana Pacers', 130, 113, 2024),
                    ('2024-11-21', 'Memphis Grizzlies', 'Philadelphia 76ers', 117, 111, 2024),
                    ('2024-11-21', 'Oklahoma City Thunder', 'Portland Trail Blazers', 109, 99, 2024),
                    ('2024-11-21', 'Phoenix Suns', 'New York Knicks', 122, 138, 2024),
                    ('2024-11-21', 'Golden State Warriors', 'Atlanta Hawks', 120, 97, 2024),
                    ('2024-11-21', 'LA Clippers', 'Orlando Magic', 104, 93, 2024),
                    ('2024-11-22', 'Charlotte Hornets', 'Detroit Pistons', 123, 121, 2024),
                    ('2024-11-22', 'Toronto Raptors', 'Minnesota Timberwolves', 110, 105, 2024),
                    ('2024-11-22', 'San Antonio Spurs', 'Utah Jazz', 126, 118, 2024),
                    ('2024-11-22', 'Los Angeles Lakers', 'Orlando Magic', 118, 119, 2024),
                    ('2024-11-23', 'Philadelphia 76ers', 'Brooklyn Nets', 113, 98, 2024),
                    ('2024-11-23', 'Washington Wizards', 'Boston Celtics', 96, 108, 2024),
                    ('2024-11-23', 'New Orleans Pelicans', 'Golden State Warriors', 108, 112, 2024),
                    ('2024-11-23', 'Milwaukee Bucks', 'Indiana Pacers', 129, 117, 2024),
                    ('2024-11-23', 'Chicago Bulls', 'Atlanta Hawks', 136, 122, 2024),
                    ('2024-11-23', 'Houston Rockets', 'Portland Trail Blazers', 116, 88, 2024),
                    ('2024-11-23', 'Denver Nuggets', 'Dallas Mavericks', 120, 123, 2024),
                    ('2024-11-23', 'LA Clippers', 'Sacramento Kings', 104, 88, 2024),
                    ('2024-11-23', 'Utah Jazz', 'New York Knicks', 121, 106, 2024),
                    ('2024-11-24', 'Orlando Magic', 'Detroit Pistons', 111, 100, 2024),
                    ('2024-11-24', 'Chicago Bulls', 'Memphis Grizzlies', 131, 142, 2024),
                    ('2024-11-24', 'Houston Rockets', 'Portland Trail Blazers', 98, 104, 2024),
                    ('2024-11-24', 'Milwaukee Bucks', 'Charlotte Hornets', 125, 119, 2024),
                    ('2024-11-24', 'San Antonio Spurs', 'Golden State Warriors', 104, 94, 2024),
                    ('2024-11-24', 'Los Angeles Lakers', 'Denver Nuggets', 102, 127, 2024),
                    ('2024-11-24', 'Boston Celtics', 'Minnesota Timberwolves', 107, 105, 2024),
                    ('2024-11-24', 'Indiana Pacers', 'Washington Wizards', 115, 103, 2024),
                    ('2024-11-24', 'Miami Heat', 'Dallas Mavericks', 123, 118, 2024),
                    ('2024-11-24', 'Philadelphia 76ers', 'LA Clippers', 99, 125, 2024),
                    ('2024-11-25', 'Cleveland Cavaliers', 'Toronto Raptors', 122, 108, 2024),
                    ('2024-11-25', 'Sacramento Kings', 'Brooklyn Nets', 103, 108, 2024),
                    ('2024-11-26', 'Charlotte Hornets', 'Orlando Magic', 84, 95, 2024),
                    ('2024-11-26', 'Detroit Pistons', 'Toronto Raptors', 102, 100, 2024),
                    ('2024-11-26', 'Indiana Pacers', 'New Orleans Pelicans', 114, 110, 2024),
                    ('2024-11-26', 'Atlanta Hawks', 'Dallas Mavericks', 119, 129, 2024),
                    ('2024-11-26', 'Boston Celtics', 'LA Clippers', 126, 94, 2024),
                    ('2024-11-26', 'Memphis Grizzlies', 'Portland Trail Blazers', 123, 98, 2024),
                    ('2024-11-26', 'Denver Nuggets', 'New York Knicks', 118, 145, 2024),
                    ('2024-11-26', 'Golden State Warriors', 'Brooklyn Nets', 120, 128, 2024),
                    ('2024-11-26', 'Sacramento Kings', 'Oklahoma City Thunder', 109, 130, 2024),
                    ('2024-11-27', 'Washington Wizards', 'Chicago Bulls', 108, 127, 2024),
                    ('2024-11-27', 'Miami Heat', 'Milwaukee Bucks', 103, 106, 2024),
                    ('2024-11-27', 'Minnesota Timberwolves', 'Houston Rockets', 111, 117, 2024),
                    ('2024-11-27', 'Utah Jazz', 'San Antonio Spurs', 115, 128, 2024),
                    ('2024-11-27', 'Phoenix Suns', 'Los Angeles Lakers', 127, 100, 2024),
                    ('2024-11-28', 'Charlotte Hornets', 'Miami Heat', 94, 98, 2024),
                    ('2024-11-28', 'Cleveland Cavaliers', 'Atlanta Hawks', 124, 135, 2024),
                    ('2024-11-28', 'Indiana Pacers', 'Portland Trail Blazers', 121, 114, 2024),
                    ('2024-11-28', 'Orlando Magic', 'Chicago Bulls', 133, 119, 2024),
                    ('2024-11-28', 'Philadelphia 76ers', 'Houston Rockets', 115, 122, 2024),
                    ('2024-11-28', 'Washington Wizards', 'LA Clippers', 96, 121, 2024),
                    ('2024-11-28', 'Dallas Mavericks', 'New York Knicks', 129, 114, 2024),
                    ('2024-11-28', 'Memphis Grizzlies', 'Detroit Pistons', 131, 111, 2024),
                    ('2024-11-28', 'Minnesota Timberwolves', 'Sacramento Kings', 104, 115, 2024),
                    ('2024-11-28', 'New Orleans Pelicans', 'Toronto Raptors', 93, 119, 2024),
                    ('2024-11-28', 'San Antonio Spurs', 'Los Angeles Lakers', 101, 119, 2024),
                    ('2024-11-28', 'Phoenix Suns', 'Brooklyn Nets', 117, 127, 2024),
                    ('2024-11-28', 'Utah Jazz', 'Denver Nuggets', 103, 122, 2024),
                    ('2024-11-28', 'Golden State Warriors', 'Oklahoma City Thunder', 101, 105, 2024),
                    ('2024-11-29', 'Charlotte Hornets', 'New York Knicks', 98, 99, 2024),
                    ('2024-11-29', 'Atlanta Hawks', 'Cleveland Cavaliers', 117, 101, 2024),
                    ('2024-11-29', 'Memphis Grizzlies', 'New Orleans Pelicans', 120, 109, 2024),
                    ('2024-11-30', 'Brooklyn Nets', 'Orlando Magic', 100, 123, 2024),
                    ('2024-11-30', 'Minnesota Timberwolves', 'LA Clippers', 93, 92, 2024),
                    ('2024-11-30', 'Indiana Pacers', 'Detroit Pistons', 106, 130, 2024),
                    ('2024-11-30', 'Miami Heat', 'Toronto Raptors', 121, 111, 2024),
                    ('2024-11-30', 'Chicago Bulls', 'Boston Celtics', 129, 138, 2024),
                    ('2024-11-30', 'Los Angeles Lakers', 'Oklahoma City Thunder', 93, 101, 2024),
                    ('2024-11-30', 'Portland Trail Blazers', 'Sacramento Kings', 115, 106, 2024),
                    ('2024-11-30', 'Charlotte Hornets', 'Atlanta Hawks', 104, 107, 2024),
                    ('2024-12-01', 'Detroit Pistons', 'Philadelphia 76ers', 96, 111, 2024),
                    ('2024-12-01', 'Milwaukee Bucks', 'Washington Wizards', 124, 114, 2024),
                    ('2024-12-01', 'Phoenix Suns', 'Golden State Warriors', 113, 105, 2024),
                    ('2024-12-01', 'Utah Jazz', 'Dallas Mavericks', 94, 106, 2024),
                    ('2024-12-01', 'Brooklyn Nets', 'Orlando Magic', 92, 100, 2024),
                    ('2024-12-01', 'Memphis Grizzlies', 'Indiana Pacers', 136, 121, 2024),
                    ('2024-12-01', 'Cleveland Cavaliers', 'Boston Celtics', 115, 111, 2024),
                    ('2024-12-01', 'New York Knicks', 'New Orleans Pelicans', 118, 85, 2024),
                    ('2024-12-01', 'Toronto Raptors', 'Miami Heat', 119, 116, 2024),
                    ('2024-12-02', 'Houston Rockets', 'Oklahoma City Thunder', 119, 116, 2024),
                    ('2024-12-02', 'Utah Jazz', 'Los Angeles Lakers', 104, 105, 2024),
                    ('2024-12-02', 'Portland Trail Blazers', 'Dallas Mavericks', 131, 137, 2024),
                    ('2024-12-02', 'Sacramento Kings', 'San Antonio Spurs', 125, 127, 2024),
                    ('2024-12-02', 'LA Clippers', 'Denver Nuggets', 126, 122, 2024),
                    ('2024-12-03', 'Atlanta Hawks', 'New Orleans Pelicans', 124, 112, 2024),
                    ('2024-12-03', 'Boston Celtics', 'Miami Heat', 108, 89, 2024),
                    ('2024-12-03', 'Chicago Bulls', 'Brooklyn Nets', 128, 102, 2024),
                    ('2024-12-03', 'Minnesota Timberwolves', 'Los Angeles Lakers', 109, 80, 2024),
                    ('2024-12-04', 'Charlotte Hornets', 'Philadelphia 76ers', 104, 110, 2024),
                    ('2024-12-04', 'Cleveland Cavaliers', 'Washington Wizards', 118, 87, 2024),
                    ('2024-12-04', 'Detroit Pistons', 'Milwaukee Bucks', 107, 128, 2024),
                    ('2024-12-04', 'New York Knicks', 'Orlando Magic', 121, 106, 2024),
                    ('2024-12-04', 'Toronto Raptors', 'Indiana Pacers', 122, 111, 2024),
                    ('2024-12-04', 'Oklahoma City Thunder', 'Utah Jazz', 133, 106, 2024),
                    ('2024-12-04', 'Dallas Mavericks', 'Memphis Grizzlies', 121, 116, 2024),
                    ('2024-12-04', 'Phoenix Suns', 'San Antonio Spurs', 104, 93, 2024),
                    ('2024-12-04', 'Denver Nuggets', 'Golden State Warriors', 119, 115, 2024),
                    ('2024-12-04', 'Sacramento Kings', 'Houston Rockets', 120, 111, 2024),
                    ('2024-12-04', 'LA Clippers', 'Portland Trail Blazers', 127, 105, 2024),
                    ('2024-12-05', 'Boston Celtics', 'Detroit Pistons', 130, 120, 2024),
                    ('2024-12-05', 'Brooklyn Nets', 'Indiana Pacers', 99, 90, 2024),
                    ('2024-12-05', 'Miami Heat', 'Los Angeles Lakers', 134, 93, 2024),
                    ('2024-12-05', 'Philadelphia 76ers', 'Orlando Magic', 102, 106, 2024),
                    ('2024-12-05', 'Milwaukee Bucks', 'Atlanta Hawks', 104, 119, 2024),
                    ('2024-12-05', 'LA Clippers', 'Minnesota Timberwolves', 80, 108, 2024),
                    ('2024-12-06', 'Cleveland Cavaliers', 'Denver Nuggets', 126, 114, 2024),
                    ('2024-12-06', 'Washington Wizards', 'Dallas Mavericks', 101, 137, 2024),
                    ('2024-12-06', 'New York Knicks', 'Charlotte Hornets', 125, 101, 2024),
                    ('2024-12-06', 'Toronto Raptors', 'Oklahoma City Thunder', 92, 129, 2024),
                    ('2024-12-06', 'Memphis Grizzlies', 'Sacramento Kings', 115, 110, 2024),
                    ('2024-12-06', 'New Orleans Pelicans', 'Phoenix Suns', 126, 124, 2024),
                    ('2024-12-06', 'San Antonio Spurs', 'Chicago Bulls', 124, 139, 2024),
                    ('2024-12-06', 'Golden State Warriors', 'Houston Rockets', 99, 93, 2024),
                    ('2024-12-07', 'Philadelphia 76ers', 'Orlando Magic', 102, 94, 2024),
                    ('2024-12-07', 'Atlanta Hawks', 'Los Angeles Lakers', 134, 132, 2024),
                    ('2024-12-07', 'Boston Celtics', 'Milwaukee Bucks', 111, 105, 2024),
                    ('2024-12-07', 'Chicago Bulls', 'Indiana Pacers', 123, 132, 2024),
                    ('2024-12-07', 'San Antonio Spurs', 'Sacramento Kings', 113, 140, 2024),
                    ('2024-12-07', 'Golden State Warriors', 'Minnesota Timberwolves', 90, 107, 2024),
                    ('2024-12-07', 'Portland Trail Blazers', 'Utah Jazz', 99, 141, 2024),
                    ('2024-12-07', 'Charlotte Hornets', 'Cleveland Cavaliers', 102, 116, 2024),
                    ('2024-12-08', 'Washington Wizards', 'Denver Nuggets', 122, 113, 2024),
                    ('2024-12-08', 'New Orleans Pelicans', 'Oklahoma City Thunder', 109, 119, 2024),
                    ('2024-12-08', 'New York Knicks', 'Detroit Pistons', 111, 120, 2024),
                    ('2024-12-08', 'Toronto Raptors', 'Dallas Mavericks', 118, 125, 2024),
                    ('2024-12-08', 'Boston Celtics', 'Memphis Grizzlies', 121, 127, 2024),
                    ('2024-12-07', 'Miami Heat', 'Phoenix Suns', 121, 111, 2024),
                    ('2024-12-08', 'Chicago Bulls', 'Philadelphia 76ers', 100, 108, 2024),
                    ('2024-12-08', 'Brooklyn Nets', 'Milwaukee Bucks', 113, 118, 2024),
                    ('2024-12-08', 'Indiana Pacers', 'Charlotte Hornets', 109, 113, 2024),
                    ('2024-12-08', 'Atlanta Hawks', 'Denver Nuggets', 111, 141, 2024),
                    ('2024-12-08', 'Miami Heat', 'Cleveland Cavaliers', 122, 113, 2024),
                    ('2024-12-08', 'Orlando Magic', 'Phoenix Suns', 115, 110, 2024),
                    ('2024-12-09', 'Washington Wizards', 'Memphis Grizzlies', 112, 140, 2024),
                    ('2024-12-09', 'San Antonio Spurs', 'New Orleans Pelicans', 121, 116, 2024),
                    ('2024-12-09', 'Golden State Warriors', 'Minnesota Timberwolves', 114, 106, 2024),
                    ('2024-12-09', 'LA Clippers', 'Houston Rockets', 106, 117, 2024),
                    ('2024-12-09', 'Sacramento Kings', 'Utah Jazz', 141, 97, 2024),
                    ('2024-12-09', 'Los Angeles Lakers', 'Portland Trail Blazers', 107, 98, 2024),
                    ('2024-12-10', 'Toronto Raptors', 'New York Knicks', 108, 113, 2024),
                    ('2024-12-11', 'Milwaukee Bucks', 'Orlando Magic', 114, 109, 2024),
                    ('2024-12-11', 'Oklahoma City Thunder', 'Dallas Mavericks', 118, 104, 2024),
                    ('2024-12-12', 'New York Knicks', 'Atlanta Hawks', 100, 108, 2024),
                    ('2024-12-12', 'Houston Rockets', 'Golden State Warriors', 91, 90, 2024),
                    ('2024-12-13', 'Boston Celtics', 'Detroit Pistons', 123, 99, 2024),
                    ('2024-12-13', 'Miami Heat', 'Toronto Raptors', 114, 104, 2024),
                    ('2024-12-13', 'New Orleans Pelicans', 'Sacramento Kings', 109, 111, 2024),
                    ('2024-12-14', 'Cleveland Cavaliers', 'Washington Wizards', 115, 105, 2024),
                    ('2024-12-14', 'Philadelphia 76ers', 'Indiana Pacers', 107, 121, 2024),
                    ('2024-12-14', 'Minnesota Timberwolves', 'Los Angeles Lakers', 97, 87, 2024),
                    ('2024-12-14', 'Memphis Grizzlies', 'Brooklyn Nets', 135, 119, 2024),
                    ('2024-12-14', 'Chicago Bulls', 'Charlotte Hornets', 109, 95, 2024),
                    ('2024-12-14', 'Denver Nuggets', 'LA Clippers', 120, 98, 2024),
                    ('2024-12-14', 'Utah Jazz', 'Phoenix Suns', 126, 134, 2024),
                    ('2024-12-14', 'Portland Trail Blazers', 'San Antonio Spurs', 116, 118, 2024),
                    ('2024-12-14', 'Milwaukee Bucks', 'Atlanta Hawks', 110, 102, 2024),
                    ('2024-12-15', 'Oklahoma City Thunder', 'Houston Rockets', 111, 96, 2024),
                    ('2024-12-15', 'Indiana Pacers', 'New Orleans Pelicans', 119, 104, 2024),
                    ('2024-12-15', 'Washington Wizards', 'Boston Celtics', 98, 112, 2024),
                    ('2024-12-15', 'Orlando Magic', 'New York Knicks', 91, 100, 2024),
                    ('2024-12-16', 'San Antonio Spurs', 'Minnesota Timberwolves', 92, 106, 2024),
                    ('2024-12-16', 'Phoenix Suns', 'Portland Trail Blazers', 116, 109, 2024),
                    ('2024-12-16', 'Golden State Warriors', 'Dallas Mavericks', 133, 143, 2024),
                    ('2024-12-16', 'Los Angeles Lakers', 'Memphis Grizzlies', 116, 110, 2024),
                    ('2024-12-17', 'Detroit Pistons', 'Miami Heat', 125, 124, 2024),
                    ('2024-12-17', 'Charlotte Hornets', 'Philadelphia 76ers', 108, 121, 2024),
                    ('2024-12-17', 'Toronto Raptors', 'Chicago Bulls', 121, 122, 2024),
                    ('2024-12-17', 'Brooklyn Nets', 'Cleveland Cavaliers', 101, 130, 2024),
                    ('2024-12-17', 'Sacramento Kings', 'Denver Nuggets', 129, 130, 2024),
                    ('2024-12-17', 'LA Clippers', 'Utah Jazz', 144, 107, 2024),
                    ('2024-12-18', 'Oklahoma City Thunder', 'Milwaukee Bucks', 81, 97, 2024),
                    ('2024-12-20', 'Detroit Pistons', 'Utah Jazz', 119, 126, 2024),
                    ('2024-12-20', 'Orlando Magic', 'Oklahoma City Thunder', 99, 105, 2024),
                    ('2024-12-20', 'Washington Wizards', 'Charlotte Hornets', 123, 114, 2024),
                    ('2024-12-20', 'Boston Celtics', 'Chicago Bulls', 108, 117, 2024),
                    ('2024-12-20', 'Toronto Raptors', 'Brooklyn Nets', 94, 101, 2024),
                    ('2024-12-20', 'Houston Rockets', 'New Orleans Pelicans', 133, 113, 2024),
                    ('2024-12-20', 'Memphis Grizzlies', 'Golden State Warriors', 144, 93, 2024),
                    ('2024-12-20', 'San Antonio Spurs', 'Atlanta Hawks', 133, 126, 2024),
                    ('2024-12-20', 'Dallas Mavericks', 'LA Clippers', 95, 118, 2024),
                    ('2024-12-20', 'Phoenix Suns', 'Indiana Pacers', 111, 120, 2024),
                    ('2024-12-20', 'Minnesota Timberwolves', 'New York Knicks', 107, 133, 2024),
                    ('2024-12-20', 'Portland Trail Blazers', 'Denver Nuggets', 126, 124, 2024),
                    ('2024-12-20', 'Sacramento Kings', 'Los Angeles Lakers', 100, 113, 2024),
                    ('2024-12-21', 'Philadelphia 76ers', 'Charlotte Hornets', 108, 98, 2024),
                    ('2024-12-21', 'Cleveland Cavaliers', 'Milwaukee Bucks', 124, 101, 2024),
                    ('2024-12-21', 'Miami Heat', 'Oklahoma City Thunder', 97, 104, 2024),
                    ('2024-12-21', 'Sacramento Kings', 'Los Angeles Lakers', 99, 103, 2024),
                    ('2024-12-22', 'Orlando Magic', 'Miami Heat', 121, 114, 2024),
                    ('2024-12-22', 'Atlanta Hawks', 'Memphis Grizzlies', 112, 128, 2024),
                    ('2024-12-22', 'Brooklyn Nets', 'Utah Jazz', 94, 105, 2024),
                    ('2024-12-22', 'Cleveland Cavaliers', 'Philadelphia 76ers', 126, 99, 2024),
                    ('2024-12-22', 'Chicago Bulls', 'Boston Celtics', 98, 123, 2024),
                    ('2024-12-22', 'Milwaukee Bucks', 'Washington Wizards', 112, 101, 2024),
                    ('2024-12-22', 'Minnesota Timberwolves', 'Golden State Warriors', 103, 113, 2024),
                    ('2024-12-22', 'New Orleans Pelicans', 'New York Knicks', 93, 104, 2024),
                    ('2024-12-22', 'Dallas Mavericks', 'LA Clippers', 113, 97, 2024),
                    ('2024-12-22', 'San Antonio Spurs', 'Portland Trail Blazers', 114, 94, 2024),
                    ('2024-12-22', 'Phoenix Suns', 'Detroit Pistons', 125, 133, 2024),
                    ('2024-12-22', 'Toronto Raptors', 'Houston Rockets', 110, 114, 2024),
                    ('2024-12-22', 'Sacramento Kings', 'Indiana Pacers', 95, 122, 2024),
                    ('2024-12-23', 'New Orleans Pelicans', 'Denver Nuggets', 129, 132, 2024),
                    ('2024-12-24', 'Charlotte Hornets', 'Houston Rockets', 101, 114, 2024),
                    ('2024-12-24', 'Cleveland Cavaliers', 'Utah Jazz', 124, 113, 2024),
                    ('2024-12-24', 'Orlando Magic', 'Boston Celtics', 108, 104, 2024),
                    ('2024-12-24', 'Philadelphia 76ers', 'San Antonio Spurs', 111, 106, 2024),
                    ('2024-12-24', 'Atlanta Hawks', 'Minnesota Timberwolves', 117, 104, 2024),
                    ('2024-12-24', 'Miami Heat', 'Brooklyn Nets', 110, 95, 2024),
                    ('2024-12-24', 'New York Knicks', 'Toronto Raptors', 139, 125, 2024),
                    ('2024-12-24', 'Chicago Bulls', 'Milwaukee Bucks', 91, 112, 2024),
                    ('2024-12-24', 'Memphis Grizzlies', 'LA Clippers', 110, 114, 2024),
                    ('2024-12-24', 'Oklahoma City Thunder', 'Washington Wizards', 123, 105, 2024),
                    ('2024-12-24', 'Dallas Mavericks', 'Portland Trail Blazers', 132, 108, 2024),
                    ('2024-12-24', 'Denver Nuggets', 'Phoenix Suns', 117, 90, 2024),
                    ('2024-12-24', 'Golden State Warriors', 'Indiana Pacers', 105, 111, 2024),
                    ('2024-12-24', 'Los Angeles Lakers', 'Detroit Pistons', 114, 117, 2024),
                    ('2024-12-25', 'New York Knicks', 'San Antonio Spurs', 117, 114, 2024),
                    ('2024-12-25', 'Dallas Mavericks', 'Minnesota Timberwolves', 99, 105, 2024),
                    ('2024-12-25', 'Boston Celtics', 'Philadelphia 76ers', 114, 118, 2024),
                    ('2024-12-26', 'Golden State Warriors', 'Los Angeles Lakers', 113, 115, 2024),
                    ('2024-12-26', 'Phoenix Suns', 'Denver Nuggets', 110, 100, 2024),
                    ('2024-12-27', 'Indiana Pacers', 'Oklahoma City Thunder', 114, 120, 2024),
                    ('2024-12-27', 'Orlando Magic', 'Miami Heat', 88, 89, 2024),
                    ('2024-12-27', 'Washington Wizards', 'Charlotte Hornets', 113, 110, 2024),
                    ('2024-12-27', 'Atlanta Hawks', 'Chicago Bulls', 141, 133, 2024),
                    ('2024-12-27', 'Memphis Grizzlies', 'Toronto Raptors', 155, 126, 2024),
                    ('2024-12-27', 'Milwaukee Bucks', 'Brooklyn Nets', 105, 111, 2024),
                    ('2024-12-27', 'New Orleans Pelicans', 'Houston Rockets', 111, 128, 2024),
                    ('2024-12-27', 'Portland Trail Blazers', 'Utah Jazz', 122, 120, 2024),
                    ('2024-12-27', 'Sacramento Kings', 'Detroit Pistons', 113, 114, 2024),
                    ('2024-12-28', 'Orlando Magic', 'New York Knicks', 85, 108, 2024),
                    ('2024-12-28', 'Boston Celtics', 'Indiana Pacers', 142, 105, 2024),
                    ('2024-12-28', 'Brooklyn Nets', 'San Antonio Spurs', 87, 95, 2024),
                    ('2024-12-28', 'Houston Rockets', 'Minnesota Timberwolves', 112, 113, 2024),
                    ('2024-12-28', 'New Orleans Pelicans', 'Memphis Grizzlies', 124, 132, 2024),
                    ('2024-12-28', 'Denver Nuggets', 'Cleveland Cavaliers', 135, 149, 2024),
                    ('2024-12-28', 'Phoenix Suns', 'Dallas Mavericks', 89, 98, 2024),
                    ('2024-12-28', 'LA Clippers', 'Golden State Warriors', 102, 92, 2024),
                    ('2024-12-28', 'Atlanta Hawks', 'Miami Heat', 120, 110, 2024),
                    ('2024-12-28', 'Charlotte Hornets', 'Oklahoma City Thunder', 94, 106, 2024),
                    ('2024-12-29', 'Washington Wizards', 'New York Knicks', 132, 136, 2024),
                    ('2024-12-29', 'Chicago Bulls', 'Milwaukee Bucks', 116, 111, 2024),
                    ('2024-12-29', 'Golden State Warriors', 'Phoenix Suns', 109, 105, 2024),
                    ('2024-12-29', 'Denver Nuggets', 'Detroit Pistons', 134, 121, 2024),
                    ('2024-12-29', 'Utah Jazz', 'Philadelphia 76ers', 111, 114, 2024),
                    ('2024-12-29', 'Portland Trail Blazers', 'Dallas Mavericks', 126, 122, 2024),
                    ('2024-12-29', 'Los Angeles Lakers', 'Sacramento Kings', 132, 122, 2024),
                    ('2024-12-29', 'Orlando Magic', 'Brooklyn Nets', 102, 101, 2024),
                    ('2024-12-29', 'Boston Celtics', 'Indiana Pacers', 114, 123, 2024),
                    ('2024-12-29', 'Toronto Raptors', 'Atlanta Hawks', 107, 136, 2024),
                    ('2024-12-30', 'Houston Rockets', 'Miami Heat', 100, 104, 2024),
                    ('2024-12-30', 'Oklahoma City Thunder', 'Memphis Grizzlies', 130, 106, 2024),
                    ('2024-12-30', 'Minnesota Timberwolves', 'San Antonio Spurs', 112, 110, 2024),
                    ('2024-12-31', 'Charlotte Hornets', 'Chicago Bulls', 108, 115, 2024),
                    ('2024-12-31', 'Washington Wizards', 'New York Knicks', 106, 126, 2024),
                    ('2024-12-31', 'New Orleans Pelicans', 'LA Clippers', 113, 116, 2024),
                    ('2024-12-31', 'Utah Jazz', 'Denver Nuggets', 121, 132, 2024),
                    ('2024-12-31', 'Golden State Warriors', 'Cleveland Cavaliers', 95, 113, 2024),
                    ('2024-12-31', 'Portland Trail Blazers', 'Philadelphia 76ers', 103, 125, 2024),
                    ('2024-12-31', 'Sacramento Kings', 'Dallas Mavericks', 110, 100, 2024),
                    ('2024-12-31', 'Boston Celtics', 'Toronto Raptors', 125, 71, 2024),
                    ('2024-12-31', 'Indiana Pacers', 'Milwaukee Bucks', 112, 120, 2024),
                    ('2025-01-01', 'San Antonio Spurs', 'LA Clippers', 122, 86, 2024),
                    ('2025-01-01', 'Oklahoma City Thunder', 'Minnesota Timberwolves', 113, 105, 2024),
                    ('2025-01-01', 'Phoenix Suns', 'Memphis Grizzlies', 112, 117, 2024),
                    ('2025-01-01', 'Los Angeles Lakers', 'Cleveland Cavaliers', 110, 122, 2024),
                    ('2025-01-02', 'Detroit Pistons', 'Orlando Magic', 105, 96, 2024),
                    ('2025-01-02', 'Washington Wizards', 'Chicago Bulls', 125, 107, 2024),
                    ('2025-01-02', 'Miami Heat', 'New Orleans Pelicans', 119, 108, 2024),
                    ('2025-01-02', 'New York Knicks', 'Utah Jazz', 119, 103, 2024),
                    ('2025-01-02', 'Toronto Raptors', 'Brooklyn Nets', 130, 113, 2024),
                    ('2025-01-02', 'Houston Rockets', 'Dallas Mavericks', 110, 99, 2024),
                    ('2025-01-02', 'Denver Nuggets', 'Atlanta Hawks', 139, 120, 2024),
                    ('2025-01-02', 'Sacramento Kings', 'Philadelphia 76ers', 113, 107, 2024),
                    ('2025-01-03', 'Miami Heat', 'Indiana Pacers', 115, 128, 2024),
                    ('2025-01-03', 'Minnesota Timberwolves', 'Boston Celtics', 115, 118, 2024),
                    ('2025-01-03', 'Milwaukee Bucks', 'Brooklyn Nets', 110, 113, 2024),
                    ('2025-01-03', 'Oklahoma City Thunder', 'LA Clippers', 116, 98, 2024),
                    ('2025-01-03', 'Golden State Warriors', 'Philadelphia 76ers', 139, 105, 2024),
                    ('2025-01-03', 'Los Angeles Lakers', 'Portland Trail Blazers', 114, 106, 2024),
                    ('2025-01-04', 'Detroit Pistons', 'Charlotte Hornets', 98, 94, 2024),
                    ('2025-01-04', 'Toronto Raptors', 'Orlando Magic', 97, 106, 2024),
                    ('2025-01-04', 'Houston Rockets', 'Boston Celtics', 86, 109, 2024),
                    ('2025-01-04', 'New Orleans Pelicans', 'Washington Wizards', 132, 120, 2024),
                    ('2025-01-04', 'Oklahoma City Thunder', 'New York Knicks', 117, 107, 2024),
                    ('2025-01-04', 'Dallas Mavericks', 'Cleveland Cavaliers', 122, 134, 2024),
                    ('2025-01-04', 'Denver Nuggets', 'San Antonio Spurs', 110, 113, 2024),
                    ('2025-01-04', 'Sacramento Kings', 'Memphis Grizzlies', 138, 133, 2024),
                    ('2025-01-04', 'Los Angeles Lakers', 'Atlanta Hawks', 119, 102, 2024),
                    ('2025-01-04', 'Brooklyn Nets', 'Philadelphia 76ers', 94, 123, 2024),
                    ('2025-01-05', 'Detroit Pistons', 'Minnesota Timberwolves', 119, 105, 2024),
                    ('2025-01-05', 'Indiana Pacers', 'Phoenix Suns', 126, 108, 2024),
                    ('2025-01-05', 'Miami Heat', 'Utah Jazz', 100, 136, 2024),
                    ('2025-01-05', 'Chicago Bulls', 'New York Knicks', 139, 126, 2024),
                    ('2025-01-05', 'Milwaukee Bucks', 'Portland Trail Blazers', 102, 105, 2024),
                    ('2025-01-05', 'San Antonio Spurs', 'Denver Nuggets', 111, 122, 2024),
                    ('2025-01-05', 'Golden State Warriors', 'Memphis Grizzlies', 121, 113, 2024),
                    ('2025-01-05', 'LA Clippers', 'Atlanta Hawks', 131, 105, 2024),
                    ('2025-01-05', 'Oklahoma City Thunder', 'Boston Celtics', 105, 92, 2024),
                    ('2025-01-05', 'Cleveland Cavaliers', 'Charlotte Hornets', 115, 105, 2024),
                    ('2025-01-05', 'Washington Wizards', 'New Orleans Pelicans', 98, 110, 2024),
                    ('2025-01-05', 'Orlando Magic', 'Utah Jazz', 92, 105, 2024),
                    ('2025-01-06', 'Houston Rockets', 'Los Angeles Lakers', 119, 115, 2024),
                    ('2025-01-06', 'Golden State Warriors', 'Sacramento Kings', 99, 129, 2024),
                    ('2025-01-07', 'Detroit Pistons', 'Portland Trail Blazers', 118, 115, 2024),
                    ('2025-01-07', 'Philadelphia 76ers', 'Phoenix Suns', 99, 109, 2024),
                    ('2025-01-07', 'Brooklyn Nets', 'Indiana Pacers', 99, 113, 2024),
                    ('2025-01-07', 'New York Knicks', 'Orlando Magic', 94, 103, 2024),
                    ('2025-01-07', 'Toronto Raptors', 'Milwaukee Bucks', 104, 128, 2024),
                    ('2025-01-07', 'Chicago Bulls', 'San Antonio Spurs', 114, 110, 2024),
                    ('2025-01-07', 'Memphis Grizzlies', 'Dallas Mavericks', 119, 104, 2024),
                    ('2025-01-07', 'Minnesota Timberwolves', 'LA Clippers', 108, 106, 2024),
                    ('2025-01-07', 'Sacramento Kings', 'Miami Heat', 123, 118, 2024),
                    ('2025-01-08', 'Charlotte Hornets', 'Phoenix Suns', 115, 104, 2024),
                    ('2025-01-08', 'Washington Wizards', 'Houston Rockets', 112, 135, 2024),
                    ('2025-01-08', 'Dallas Mavericks', 'Los Angeles Lakers', 118, 97, 2024),
                    ('2025-01-08', 'New Orleans Pelicans', 'Minnesota Timberwolves', 97, 104, 2024),
                    ('2025-01-08', 'Utah Jazz', 'Atlanta Hawks', 121, 124, 2024),
                    ('2025-01-08', 'Denver Nuggets', 'Boston Celtics', 106, 118, 2024),
                    ('2025-01-08', 'Golden State Warriors', 'Miami Heat', 98, 114, 2024),
                    ('2025-01-09', 'Cleveland Cavaliers', 'Oklahoma City Thunder', 129, 122, 2024),
                    ('2025-01-09', 'Indiana Pacers', 'Chicago Bulls', 129, 113, 2024),
                    ('2025-01-09', 'Philadelphia 76ers', 'Washington Wizards', 109, 103, 2024),
                    ('2025-01-09', 'New York Knicks', 'Toronto Raptors', 112, 98, 2024),
                    ('2025-01-09', 'Brooklyn Nets', 'Detroit Pistons', 98, 113, 2024),
                    ('2025-01-09', 'New Orleans Pelicans', 'Portland Trail Blazers', 100, 119, 2024),
                    ('2025-01-09', 'Denver Nuggets', 'LA Clippers', 126, 103, 2024),
                    ('2025-01-09', 'Milwaukee Bucks', 'San Antonio Spurs', 121, 105, 2024),
                    ('2025-01-10', 'Cleveland Cavaliers', 'Toronto Raptors', 132, 126, 2024),
                    ('2025-01-10', 'Detroit Pistons', 'Golden State Warriors', 104, 107, 2024),
                    ('2025-01-10', 'Orlando Magic', 'Minnesota Timberwolves', 89, 104, 2024),
                    ('2025-01-10', 'Dallas Mavericks', 'Portland Trail Blazers', 117, 111, 2024),
                    ('2025-01-10', 'Memphis Grizzlies', 'Houston Rockets', 115, 119, 2024),
                    ('2025-01-10', 'Phoenix Suns', 'Atlanta Hawks', 123, 115, 2024),
                    ('2025-01-10', 'Utah Jazz', 'Miami Heat', 92, 97, 2024),
                    ('2025-01-11', 'Indiana Pacers', 'Golden State Warriors', 108, 96, 2024),
                    ('2025-01-11', 'Orlando Magic', 'Milwaukee Bucks', 106, 109, 2024),
                    ('2025-01-11', 'Philadelphia 76ers', 'New Orleans Pelicans', 115, 123, 2024),
                    ('2025-01-11', 'Boston Celtics', 'Sacramento Kings', 97, 114, 2024),
                    ('2025-01-11', 'New York Knicks', 'Oklahoma City Thunder', 101, 126, 2024),
                    ('2025-01-11', 'Chicago Bulls', 'Washington Wizards', 138, 105, 2024),
                    ('2025-01-11', 'Denver Nuggets', 'Brooklyn Nets', 124, 105, 2024),
                    ('2025-01-11', 'Phoenix Suns', 'Utah Jazz', 114, 106, 2024),
                    ('2025-01-12', 'Detroit Pistons', 'Toronto Raptors', 123, 114, 2024),
                    ('2025-01-12', 'Minnesota Timberwolves', 'Memphis Grizzlies', 125, 127, 2024),
                    ('2025-01-12', 'Portland Trail Blazers', 'Miami Heat', 98, 119, 2024),
                    ('2025-01-12', 'New York Knicks', 'Milwaukee Bucks', 140, 106, 2024),
                    ('2025-01-12', 'Dallas Mavericks', 'Denver Nuggets', 101, 112, 2024),
                    ('2025-01-12', 'Chicago Bulls', 'Sacramento Kings', 119, 124, 2024),
                    ('2025-01-12', 'Boston Celtics', 'New Orleans Pelicans', 120, 119, 2024),
                    ('2025-01-12', 'Cleveland Cavaliers', 'Indiana Pacers', 93, 108, 2024),
                    ('2025-01-12', 'Orlando Magic', 'Philadelphia 76ers', 104, 99, 2024),
                    ('2025-01-12', 'Washington Wizards', 'Oklahoma City Thunder', 95, 136, 2024),
                    ('2025-01-13', 'Utah Jazz', 'Brooklyn Nets', 112, 111, 2024),
                    ('2025-01-13', 'Phoenix Suns', 'Charlotte Hornets', 120, 113, 2024),
                    ('2025-01-14', 'Washington Wizards', 'Minnesota Timberwolves', 106, 120, 2024),
                    ('2025-01-14', 'New York Knicks', 'Detroit Pistons', 119, 124, 2024),
                    ('2025-01-14', 'Toronto Raptors', 'Golden State Warriors', 104, 101, 2024),
                    ('2025-01-14', 'Houston Rockets', 'Memphis Grizzlies', 120, 118, 2024),
                    ('2025-01-14', 'Los Angeles Lakers', 'San Antonio Spurs', 102, 126, 2024),
                    ('2025-01-14', 'LA Clippers', 'Miami Heat', 109, 98, 2024),
                    ('2025-01-15', 'Indiana Pacers', 'Cleveland Cavaliers', 117, 127, 2024),
                    ('2025-01-15', 'Philadelphia 76ers', 'Oklahoma City Thunder', 102, 118, 2024),
                    ('2025-01-15', 'Atlanta Hawks', 'Phoenix Suns', 122, 117, 2024),
                    ('2025-01-15', 'Chicago Bulls', 'New Orleans Pelicans', 113, 119, 2024),
                    ('2025-01-15', 'Milwaukee Bucks', 'Sacramento Kings', 130, 115, 2024),
                    ('2025-01-15', 'Dallas Mavericks', 'Denver Nuggets', 99, 118, 2024),
                    ('2025-01-15', 'Portland Trail Blazers', 'Brooklyn Nets', 114, 132, 2024),
                    ('2025-01-16', 'Philadelphia 76ers', 'New York Knicks', 119, 125, 2024),
                    ('2025-01-16', 'Toronto Raptors', 'Boston Celtics', 110, 97, 2024),
                    ('2025-01-16', 'Chicago Bulls', 'Atlanta Hawks', 94, 110, 2024),
                    ('2025-01-16', 'Milwaukee Bucks', 'Orlando Magic', 122, 93, 2024),
                    ('2025-01-16', 'New Orleans Pelicans', 'Dallas Mavericks', 119, 116, 2024),
                    ('2025-01-16', 'San Antonio Spurs', 'Memphis Grizzlies', 115, 129, 2024),
                    ('2025-01-16', 'Denver Nuggets', 'Houston Rockets', 108, 128, 2024),
                    ('2025-01-16', 'Utah Jazz', 'Charlotte Hornets', 112, 117, 2024),
                    ('2025-01-16', 'Minnesota Timberwolves', 'Golden State Warriors', 115, 116, 2024),
                    ('2025-01-16', 'Los Angeles Lakers', 'Miami Heat', 117, 108, 2024),
                    ('2025-01-16', 'LA Clippers', 'Brooklyn Nets', 126, 67, 2024),
                    ('2025-01-17', 'Detroit Pistons', 'Indiana Pacers', 100, 111, 2024),
                    ('2025-01-17', 'Washington Wizards', 'Phoenix Suns', 123, 130, 2024),
                    ('2025-01-17', 'Oklahoma City Thunder', 'Cleveland Cavaliers', 134, 114, 2024),
                    ('2025-01-17', 'Portland Trail Blazers', 'LA Clippers', 89, 118, 2024),
                    ('2025-01-17', 'Sacramento Kings', 'Houston Rockets', 132, 127, 2024),
                    ('2025-01-18', 'Boston Celtics', 'Orlando Magic', 121, 94, 2024),
                    ('2025-01-18', 'New York Knicks', 'Minnesota Timberwolves', 99, 116, 2024),
                    ('2025-01-18', 'Miami Heat', 'Denver Nuggets', 113, 133, 2024),
                    ('2025-01-18', 'Milwaukee Bucks', 'Toronto Raptors', 130, 112, 2024),
                    ('2025-01-18', 'New Orleans Pelicans', 'Utah Jazz', 136, 123, 2024),
                    ('2025-01-18', 'Chicago Bulls', 'Charlotte Hornets', 123, 125, 2024),
                    ('2025-01-18', 'Dallas Mavericks', 'Oklahoma City Thunder', 106, 98, 2024),
                    ('2025-01-18', 'San Antonio Spurs', 'Memphis Grizzlies', 112, 140, 2024),
                    ('2025-01-18', 'Los Angeles Lakers', 'Brooklyn Nets', 102, 101, 2024),
                    ('2025-01-18', 'Detroit Pistons', 'Phoenix Suns', 121, 125, 2024),
                    ('2025-01-19', 'Boston Celtics', 'Atlanta Hawks', 115, 119, 2024),
                    ('2025-01-19', 'Indiana Pacers', 'Philadelphia 76ers', 115, 102, 2024),
                    ('2025-01-19', 'Golden State Warriors', 'Washington Wizards', 122, 114, 2024),
                    ('2025-01-19', 'Minnesota Timberwolves', 'Cleveland Cavaliers', 117, 124, 2024),
                    ('2025-01-19', 'Portland Trail Blazers', 'Houston Rockets', 103, 125, 2024),
                    ('2025-01-19', 'Miami Heat', 'San Antonio Spurs', 128, 107, 2024),
                    ('2025-01-19', 'Orlando Magic', 'Denver Nuggets', 100, 113, 2024),
                    ('2025-01-20', 'Milwaukee Bucks', 'Philadelphia 76ers', 123, 109, 2024),
                    ('2025-01-20', 'Oklahoma City Thunder', 'Brooklyn Nets', 127, 101, 2024),
                    ('2025-01-20', 'LA Clippers', 'Los Angeles Lakers', 116, 102, 2024),
                    ('2025-01-20', 'Portland Trail Blazers', 'Chicago Bulls', 113, 102, 2024),
                    ('2025-01-20', 'Sacramento Kings', 'Washington Wizards', 123, 100, 2024),
                    ('2025-01-20', 'Charlotte Hornets', 'Dallas Mavericks', 110, 105, 2024),
                    ('2025-01-20', 'Houston Rockets', 'Detroit Pistons', 96, 107, 2024),
                    ('2025-01-20', 'Memphis Grizzlies', 'Minnesota Timberwolves', 108, 106, 2024),
                    ('2025-01-20', 'New York Knicks', 'Atlanta Hawks', 119, 110, 2024),
                    ('2025-01-20', 'Cleveland Cavaliers', 'Phoenix Suns', 118, 92, 2024),
                    ('2025-01-20', 'Golden State Warriors', 'Boston Celtics', 85, 125, 2024),
                    ('2025-01-21', 'New Orleans Pelicans', 'Utah Jazz', 123, 119, 2024),
                    ('2025-01-21', 'LA Clippers', 'Chicago Bulls', 99, 112, 2024),
                    ('2025-01-22', 'Brooklyn Nets', 'New York Knicks', 95, 99, 2024),
                    ('2025-01-22', 'Miami Heat', 'Portland Trail Blazers', 107, 116, 2024),
                    ('2025-01-22', 'Toronto Raptors', 'Orlando Magic', 109, 93, 2024),
                    ('2025-01-22', 'Denver Nuggets', 'Philadelphia 76ers', 144, 109, 2024),
                    ('2025-01-22', 'Los Angeles Lakers', 'Washington Wizards', 111, 88, 2024),
                    ('2025-01-23', 'Atlanta Hawks', 'Detroit Pistons', 104, 114, 2024),
                    ('2025-01-23', 'Brooklyn Nets', 'Phoenix Suns', 94, 108, 2024),
                    ('2025-01-23', 'Dallas Mavericks', 'Minnesota Timberwolves', 114, 115, 2024),
                    ('2025-01-23', 'Houston Rockets', 'Cleveland Cavaliers', 109, 108, 2024),
                    ('2025-01-23', 'Memphis Grizzlies', 'Charlotte Hornets', 132, 120, 2024),
                    ('2025-01-23', 'Oklahoma City Thunder', 'Utah Jazz', 123, 114, 2024),
                    ('2025-01-23', 'Sacramento Kings', 'Golden State Warriors', 123, 117, 2024),
                    ('2025-01-23', 'LA Clippers', 'Boston Celtics', 113, 117, 2024),
                    ('2025-01-23', 'Indiana Pacers', 'San Antonio Spurs', 110, 140, 2024),
                    ('2025-01-24', 'Orlando Magic', 'Portland Trail Blazers', 79, 101, 2024),
                    ('2025-01-24', 'Atlanta Hawks', 'Toronto Raptors', 119, 122, 2024),
                    ('2025-01-24', 'Oklahoma City Thunder', 'Dallas Mavericks', 115, 121, 2024),
                    ('2025-01-24', 'Milwaukee Bucks', 'Miami Heat', 125, 96, 2024),
                    ('2025-01-24', 'Denver Nuggets', 'Sacramento Kings', 132, 123, 2024),
                    ('2025-01-24', 'Golden State Warriors', 'Chicago Bulls', 131, 106, 2024),
                    ('2025-01-24', 'Los Angeles Lakers', 'Boston Celtics', 117, 96, 2024),
                    ('2025-01-24', 'LA Clippers', 'Washington Wizards', 110, 93, 2024),
                    ('2025-01-25', 'Charlotte Hornets', 'Portland Trail Blazers', 97, 102, 2024),
                    ('2025-01-25', 'Philadelphia 76ers', 'Cleveland Cavaliers', 132, 129, 2024),
                    ('2025-01-25', 'Memphis Grizzlies', 'New Orleans Pelicans', 139, 126, 2024),
                    ('2025-01-25', 'San Antonio Spurs', 'Indiana Pacers', 98, 136, 2024),
                    ('2025-01-25', 'Minnesota Timberwolves', 'Denver Nuggets', 133, 104, 2024),
                    ('2025-01-25', 'Dallas Mavericks', 'Boston Celtics', 107, 122, 2024),
                    ('2025-01-25', 'Brooklyn Nets', 'Miami Heat', 97, 106, 2024),
                    ('2025-01-26', 'Charlotte Hornets', 'New Orleans Pelicans', 123, 92, 2024),
                    ('2025-01-26', 'Orlando Magic', 'Detroit Pistons', 121, 113, 2024),
                    ('2025-01-26', 'Atlanta Hawks', 'Toronto Raptors', 94, 117, 2024),
                    ('2025-01-26', 'Cleveland Cavaliers', 'Houston Rockets', 131, 135, 2024),
                    ('2025-01-26', 'New York Knicks', 'Sacramento Kings', 143, 120, 2024),
                    ('2025-01-26', 'Chicago Bulls', 'Philadelphia 76ers', 97, 109, 2024),
                    ('2025-01-26', 'Memphis Grizzlies', 'Utah Jazz', 123, 103, 2024),
                    ('2025-01-26', 'Golden State Warriors', 'Los Angeles Lakers', 108, 118, 2024),
                    ('2025-01-26', 'Phoenix Suns', 'Washington Wizards', 119, 109, 2024),
                    ('2025-01-26', 'LA Clippers', 'Milwaukee Bucks', 127, 117, 2024),
                    ('2025-01-26', 'Portland Trail Blazers', 'Oklahoma City Thunder', 108, 118, 2024),
                    ('2025-01-28', 'Charlotte Hornets', 'Los Angeles Lakers', 107, 112, 2024),
                    ('2025-01-28', 'Cleveland Cavaliers', 'Detroit Pistons', 110, 91, 2024),
                    ('2025-01-28', 'Boston Celtics', 'Houston Rockets', 112, 114, 2024),
                    ('2025-01-28', 'Brooklyn Nets', 'Sacramento Kings', 96, 110, 2024),
                    ('2025-01-28', 'Miami Heat', 'Orlando Magic', 125, 119, 2024),
                    ('2025-01-28', 'New York Knicks', 'Memphis Grizzlies', 143, 106, 2024),
                    ('2025-01-28', 'Toronto Raptors', 'New Orleans Pelicans', 113, 104, 2024),
                    ('2025-01-28', 'Chicago Bulls', 'Denver Nuggets', 129, 121, 2024),
                    ('2025-01-28', 'Minnesota Timberwolves', 'Atlanta Hawks', 100, 92, 2024),
                    ('2025-01-28', 'Dallas Mavericks', 'Washington Wizards', 130, 108, 2024),
                    ('2025-01-28', 'Utah Jazz', 'Milwaukee Bucks', 110, 125, 2024),
                    ('2025-01-28', 'Phoenix Suns', 'LA Clippers', 111, 109, 2024),
                    ('2025-01-29', 'Atlanta Hawks', 'Houston Rockets', 96, 100, 2024),
                    ('2025-01-29', 'Philadelphia 76ers', 'Los Angeles Lakers', 118, 104, 2024),
                    ('2025-01-29', 'Golden State Warriors', 'Utah Jazz', 114, 103, 2024),
                    ('2025-01-29', 'Portland Trail Blazers', 'Milwaukee Bucks', 125, 112, 2024),
                    ('2025-01-30', 'Charlotte Hornets', 'Brooklyn Nets', 83, 104, 2024),
                    ('2025-01-30', 'Indiana Pacers', 'Detroit Pistons', 133, 119, 2024),
                    ('2025-01-30', 'Washington Wizards', 'Toronto Raptors', 82, 106, 2024),
                    ('2025-01-30', 'Boston Celtics', 'Chicago Bulls', 122, 100, 2024),
                    ('2025-01-30', 'Miami Heat', 'Cleveland Cavaliers', 106, 126, 2024),
                    ('2025-01-30', 'New York Knicks', 'Denver Nuggets', 122, 112, 2024),
                    ('2025-01-30', 'Philadelphia 76ers', 'Sacramento Kings', 117, 104, 2024),
                    ('2025-01-30', 'New Orleans Pelicans', 'Dallas Mavericks', 136, 137, 2024),
                    ('2025-01-30', 'San Antonio Spurs', 'LA Clippers', 116, 128, 2024),
                    ('2025-01-30', 'Phoenix Suns', 'Minnesota Timberwolves', 113, 121, 2024),
                    ('2025-01-30', 'Golden State Warriors', 'Oklahoma City Thunder', 116, 109, 2024),
                    ('2025-01-31', 'Washington Wizards', 'Los Angeles Lakers', 96, 134, 2024),
                    ('2025-01-31', 'Cleveland Cavaliers', 'Atlanta Hawks', 137, 115, 2024),
                    ('2025-01-31', 'Utah Jazz', 'Minnesota Timberwolves', 113, 138, 2024),
                    ('2025-01-31', 'Memphis Grizzlies', 'Houston Rockets', 120, 119, 2024),
                    ('2025-01-31', 'Portland Trail Blazers', 'Orlando Magic', 119, 90, 2024),
                    ('2025-02-01', 'Charlotte Hornets', 'LA Clippers', 104, 112, 2024),
                    ('2025-02-01', 'Detroit Pistons', 'Dallas Mavericks', 117, 102, 2024),
                    ('2025-02-01', 'Philadelphia 76ers', 'Denver Nuggets', 134, 137, 2024),
                    ('2025-02-01', 'Toronto Raptors', 'Chicago Bulls', 106, 122, 2024),
                    ('2025-02-01', 'New Orleans Pelicans', 'Boston Celtics', 116, 118, 2024),
                    ('2025-02-01', 'San Antonio Spurs', 'Milwaukee Bucks', 144, 118, 2024),
                    ('2025-02-01', 'Golden State Warriors', 'Phoenix Suns', 105, 130, 2024),
                    ('2025-02-01', 'Indiana Pacers', 'Atlanta Hawks', 132, 127, 2024),
                    ('2025-02-01', 'Utah Jazz', 'Orlando Magic', 113, 99, 2024),
                    ('2025-02-02', 'Charlotte Hornets', 'Denver Nuggets', 104, 107, 2024),
                    ('2025-02-02', 'Houston Rockets', 'Brooklyn Nets', 98, 110, 2024),
                    ('2025-02-02', 'Minnesota Timberwolves', 'Washington Wizards', 103, 105, 2024),
                    ('2025-02-02', 'Oklahoma City Thunder', 'Sacramento Kings', 144, 110, 2024),
                    ('2025-02-02', 'New York Knicks', 'Los Angeles Lakers', 112, 128, 2024),
                    ('2025-02-02', 'San Antonio Spurs', 'Miami Heat', 103, 105, 2024),
                    ('2025-02-02', 'Portland Trail Blazers', 'Phoenix Suns', 127, 108, 2024),
                    ('2025-02-02', 'Detroit Pistons', 'Chicago Bulls', 127, 119, 2024),
                    ('2025-02-02', 'Cleveland Cavaliers', 'Dallas Mavericks', 144, 101, 2024),
                    ('2025-02-02', 'Toronto Raptors', 'LA Clippers', 115, 108, 2024),
                    ('2025-02-02', 'Philadelphia 76ers', 'Boston Celtics', 110, 118, 2024),
                    ('2025-02-03', 'Milwaukee Bucks', 'Memphis Grizzlies', 119, 132, 2024),
                    ('2025-02-04', 'Charlotte Hornets', 'Washington Wizards', 114, 124, 2024),
                    ('2025-02-04', 'Detroit Pistons', 'Atlanta Hawks', 130, 132, 2024),
                    ('2025-02-04', 'New York Knicks', 'Houston Rockets', 124, 118, 2024),
                    ('2025-02-04', 'Memphis Grizzlies', 'San Antonio Spurs', 128, 109, 2024),
                    ('2025-02-04', 'Minnesota Timberwolves', 'Sacramento Kings', 114, 116, 2024),
                    ('2025-02-04', 'Oklahoma City Thunder', 'Milwaukee Bucks', 125, 96, 2024),
                    ('2025-02-04', 'Denver Nuggets', 'New Orleans Pelicans', 125, 113, 2024),
                    ('2025-02-04', 'Utah Jazz', 'Indiana Pacers', 111, 112, 2024),
                    ('2025-02-04', 'Golden State Warriors', 'Orlando Magic', 104, 99, 2024),
                    ('2025-02-04', 'Portland Trail Blazers', 'Phoenix Suns', 121, 119, 2024),
                    ('2025-02-05', 'Philadelphia 76ers', 'Dallas Mavericks', 118, 116, 2024),
                    ('2025-02-05', 'Cleveland Cavaliers', 'Boston Celtics', 105, 112, 2024),
                    ('2025-02-05', 'Brooklyn Nets', 'Houston Rockets', 99, 97, 2024),
                    ('2025-02-05', 'Toronto Raptors', 'New York Knicks', 115, 121, 2024),
                    ('2025-02-05', 'Chicago Bulls', 'Miami Heat', 133, 124, 2024),
                    ('2025-02-05', 'LA Clippers', 'Los Angeles Lakers', 97, 122, 2024),
                    ('2025-02-05', 'Portland Trail Blazers', 'Indiana Pacers', 112, 89, 2024),
                    ('2025-02-06', 'Charlotte Hornets', 'Milwaukee Bucks', 102, 112, 2024),
                    ('2025-02-06', 'Detroit Pistons', 'Cleveland Cavaliers', 115, 118, 2024),
                    ('2025-02-06', 'Atlanta Hawks', 'San Antonio Spurs', 125, 126, 2024),
                    ('2025-02-06', 'Brooklyn Nets', 'Washington Wizards', 102, 119, 2024),
                    ('2025-02-06', 'Philadelphia 76ers', 'Miami Heat', 101, 108, 2024),
                    ('2025-02-06', 'Toronto Raptors', 'Memphis Grizzlies', 107, 138, 2024),
                    ('2025-02-06', 'Minnesota Timberwolves', 'Chicago Bulls', 127, 108, 2024),
                    ('2025-02-06', 'Utah Jazz', 'Golden State Warriors', 131, 128, 2024),
                    ('2025-02-06', 'Denver Nuggets', 'New Orleans Pelicans', 144, 119, 2024),
                    ('2025-02-06', 'Oklahoma City Thunder', 'Phoenix Suns', 140, 109, 2024),
                    ('2025-02-06', 'Sacramento Kings', 'Orlando Magic', 111, 130, 2024),
                    ('2025-02-07', 'Boston Celtics', 'Dallas Mavericks', 120, 127, 2024),
                    ('2025-02-07', 'Minnesota Timberwolves', 'Houston Rockets', 127, 114, 2024),
                    ('2025-02-07', 'Denver Nuggets', 'Orlando Magic', 112, 90, 2024),
                    ('2025-02-07', 'Los Angeles Lakers', 'Golden State Warriors', 120, 112, 2024),
                    ('2025-02-07', 'Portland Trail Blazers', 'Sacramento Kings', 108, 102, 2024),
                    ('2025-02-07', 'LA Clippers', 'Indiana Pacers', 112, 119, 2024),
                    ('2025-02-08', 'Charlotte Hornets', 'San Antonio Spurs', 117, 116, 2024),
                    ('2025-02-08', 'Washington Wizards', 'Cleveland Cavaliers', 124, 134, 2024),
                    ('2025-02-08', 'Atlanta Hawks', 'Milwaukee Bucks', 115, 110, 2024),
                    ('2025-02-08', 'Brooklyn Nets', 'Miami Heat', 102, 86, 2024),
                    ('2025-02-08', 'Detroit Pistons', 'Philadelphia 76ers', 125, 112, 2024),
                    ('2025-02-08', 'Oklahoma City Thunder', 'Toronto Raptors', 121, 109, 2024),
                    ('2025-02-08', 'Phoenix Suns', 'Utah Jazz', 135, 127, 2024),
                    ('2025-02-08', 'Dallas Mavericks', 'Houston Rockets', 116, 105, 2024),
                    ('2025-02-08', 'Los Angeles Lakers', 'Indiana Pacers', 124, 117, 2024),
                    ('2025-02-09', 'Orlando Magic', 'San Antonio Spurs', 112, 111, 2024),
                    ('2025-02-09', 'Washington Wizards', 'Atlanta Hawks', 111, 125, 2024),
                    ('2025-02-09', 'Chicago Bulls', 'Golden State Warriors', 111, 132, 2024),
                    ('2025-02-09', 'Memphis Grizzlies', 'Oklahoma City Thunder', 112, 125, 2024),
                    ('2025-02-09', 'Minnesota Timberwolves', 'Portland Trail Blazers', 114, 98, 2024),
                    ('2025-02-09', 'New York Knicks', 'Boston Celtics', 104, 131, 2024),
                    ('2025-02-09', 'Phoenix Suns', 'Denver Nuggets', 105, 122, 2024),
                    ('2025-02-09', 'Sacramento Kings', 'New Orleans Pelicans', 123, 118, 2024),
                    ('2025-02-09', 'LA Clippers', 'Utah Jazz', 130, 110, 2024),
                    ('2025-02-09', 'Detroit Pistons', 'Charlotte Hornets', 112, 102, 2024),
                    ('2025-02-09', 'Houston Rockets', 'Toronto Raptors', 94, 87, 2024),
                    ('2025-02-09', 'Milwaukee Bucks', 'Philadelphia 76ers', 135, 127, 2024),
                    ('2025-02-11', 'Cleveland Cavaliers', 'Minnesota Timberwolves', 128, 107, 2024),
                    ('2025-02-11', 'Orlando Magic', 'Atlanta Hawks', 106, 112, 2024),
                    ('2025-02-11', 'Washington Wizards', 'San Antonio Spurs', 121, 131, 2024),
                    ('2025-02-11', 'Brooklyn Nets', 'Charlotte Hornets', 97, 89, 2024),
                    ('2025-02-11', 'Miami Heat', 'Boston Celtics', 85, 103, 2024),
                    ('2025-02-11', 'Milwaukee Bucks', 'Golden State Warriors', 111, 125, 2024),
                    ('2025-02-11', 'Oklahoma City Thunder', 'New Orleans Pelicans', 137, 101, 2024),
                    ('2025-02-11', 'Dallas Mavericks', 'Sacramento Kings', 128, 129, 2024),
                    ('2025-02-11', 'Denver Nuggets', 'Portland Trail Blazers', 146, 117, 2024),
                    ('2025-02-11', 'Los Angeles Lakers', 'Utah Jazz', 132, 113, 2024),
                    ('2025-02-12', 'Philadelphia 76ers', 'Toronto Raptors', 103, 106, 2024),
                    ('2025-02-12', 'Indiana Pacers', 'New York Knicks', 115, 128, 2024),
                    ('2025-02-12', 'Chicago Bulls', 'Detroit Pistons', 92, 132, 2024),
                    ('2025-02-12', 'Phoenix Suns', 'Memphis Grizzlies', 112, 119, 2024),
                    ('2025-02-13', 'Boston Celtics', 'San Antonio Spurs', 116, 103, 2024),
                    ('2025-02-13', 'Orlando Magic', 'Charlotte Hornets', 102, 86, 2024),
                    ('2025-02-13', 'Washington Wizards', 'Indiana Pacers', 130, 134, 2024),
                    ('2025-02-13', 'Brooklyn Nets', 'Philadelphia 76ers', 100, 96, 2024),
                    ('2025-02-13', 'New York Knicks', 'Atlanta Hawks', 149, 148, 2024),
                    ('2025-02-13', 'Toronto Raptors', 'Cleveland Cavaliers', 108, 131, 2024),
                    ('2025-02-13', 'Chicago Bulls', 'Detroit Pistons', 110, 128, 2024),
                    ('2025-02-13', 'Minnesota Timberwolves', 'Milwaukee Bucks', 101, 103, 2024),
                    ('2025-02-13', 'New Orleans Pelicans', 'Sacramento Kings', 111, 119, 2024),
                    ('2025-02-13', 'Oklahoma City Thunder', 'Miami Heat', 115, 101, 2024),
                    ('2025-02-13', 'Houston Rockets', 'Phoenix Suns', 119, 111, 2024),
                    ('2025-02-13', 'Denver Nuggets', 'Portland Trail Blazers', 132, 121, 2024),
                    ('2025-02-13', 'Utah Jazz', 'Los Angeles Lakers', 131, 119, 2024),
                    ('2025-02-13', 'Dallas Mavericks', 'Golden State Warriors', 111, 107, 2024),
                    ('2025-02-13', 'LA Clippers', 'Memphis Grizzlies', 128, 114, 2024),
                    ('2025-02-14', 'Houston Rockets', 'Golden State Warriors', 98, 105, 2024),
                    ('2025-02-14', 'New Orleans Pelicans', 'Sacramento Kings', 140, 133, 2024),
                    ('2025-02-14', 'Dallas Mavericks', 'Miami Heat', 118, 113, 2024),
                    ('2025-02-14', 'Minnesota Timberwolves', 'Oklahoma City Thunder', 116, 101, 2024),
                    ('2025-02-14', 'Utah Jazz', 'LA Clippers', 116, 120, 2024),
                    ('2025-02-20', 'Los Angeles Lakers', 'Charlotte Hornets', 97, 100, 2024),
                    ('2025-02-21', 'Indiana Pacers', 'Memphis Grizzlies', 127, 113, 2024),
                    ('2025-02-21', 'Philadelphia 76ers', 'Boston Celtics', 104, 124, 2024),
                    ('2025-02-21', 'Atlanta Hawks', 'Orlando Magic', 108, 114, 2024),
                    ('2025-02-21', 'Brooklyn Nets', 'Cleveland Cavaliers', 97, 110, 2024),
                    ('2025-02-21', 'New York Knicks', 'Chicago Bulls', 113, 111, 2024),
                    ('2025-02-21', 'Milwaukee Bucks', 'LA Clippers', 116, 110, 2024),
                    ('2025-02-21', 'Denver Nuggets', 'Charlotte Hornets', 129, 115, 2024),
                    ('2025-02-21', 'San Antonio Spurs', 'Phoenix Suns', 120, 109, 2024),
                    ('2025-02-21', 'Portland Trail Blazers', 'Los Angeles Lakers', 102, 110, 2024),
                    ('2025-02-22', 'Cleveland Cavaliers', 'New York Knicks', 142, 105, 2024),
                    ('2025-02-22', 'Orlando Magic', 'Memphis Grizzlies', 104, 105, 2024),
                    ('2025-02-22', 'Washington Wizards', 'Milwaukee Bucks', 101, 104, 2024),
                    ('2025-02-22', 'Toronto Raptors', 'Miami Heat', 111, 120, 2024),
                    ('2025-02-22', 'San Antonio Spurs', 'Detroit Pistons', 110, 125, 2024),
                    ('2025-02-22', 'Dallas Mavericks', 'New Orleans Pelicans', 111, 103, 2024),
                    ('2025-02-22', 'Houston Rockets', 'Minnesota Timberwolves', 121, 115, 2024),
                    ('2025-02-22', 'Utah Jazz', 'Oklahoma City Thunder', 107, 130, 2024),
                    ('2025-02-22', 'Sacramento Kings', 'Golden State Warriors', 108, 132, 2024),
                    ('2025-02-22', 'Chicago Bulls', 'Phoenix Suns', 117, 121, 2024),
                    ('2025-02-23', 'Philadelphia 76ers', 'Brooklyn Nets', 103, 105, 2024),
                    ('2025-02-23', 'Denver Nuggets', 'Los Angeles Lakers', 100, 123, 2024),
                    ('2025-02-23', 'Utah Jazz', 'Houston Rockets', 124, 115, 2024),
                    ('2025-02-23', 'Portland Trail Blazers', 'Charlotte Hornets', 141, 88, 2024),
                    ('2025-02-23', 'Boston Celtics', 'New York Knicks', 118, 105, 2024),
                    ('2025-02-23', 'Golden State Warriors', 'Dallas Mavericks', 126, 102, 2024),
                    ('2025-02-23', 'Indiana Pacers', 'LA Clippers', 129, 111, 2024),
                    ('2025-02-23', 'Atlanta Hawks', 'Detroit Pistons', 143, 148, 2024),
                    ('2025-02-23', 'Orlando Magic', 'Washington Wizards', 110, 90, 2024),
                    ('2025-02-23', 'Toronto Raptors', 'Phoenix Suns', 127, 109, 2024),
                    ('2025-02-23', 'Milwaukee Bucks', 'Miami Heat', 120, 113, 2024),
                    ('2025-02-24', 'New Orleans Pelicans', 'San Antonio Spurs', 114, 96, 2024),
                    ('2025-02-24', 'Cleveland Cavaliers', 'Memphis Grizzlies', 129, 123, 2024),
                    ('2025-02-24', 'Minnesota Timberwolves', 'Oklahoma City Thunder', 123, 130, 2024),
                    ('2025-02-25', 'Detroit Pistons', 'LA Clippers', 106, 97, 2024),
                    ('2025-02-25', 'Indiana Pacers', 'Denver Nuggets', 116, 125, 2024),
                    ('2025-02-25', 'Philadelphia 76ers', 'Chicago Bulls', 110, 142, 2024),
                    ('2025-02-25', 'Washington Wizards', 'Brooklyn Nets', 107, 99, 2024),
                    ('2025-02-25', 'Atlanta Hawks', 'Miami Heat', 98, 86, 2024),
                    ('2025-02-25', 'Oklahoma City Thunder', 'Minnesota Timberwolves', 128, 131, 2024),
                    ('2025-02-25', 'Utah Jazz', 'Portland Trail Blazers', 112, 114, 2024),
                    ('2025-02-25', 'Sacramento Kings', 'Charlotte Hornets', 130, 88, 2024),
                    ('2025-02-26', 'Toronto Raptors', 'Boston Celtics', 101, 111, 2024),
                    ('2025-02-26', 'Orlando Magic', 'Cleveland Cavaliers', 82, 122, 2024),
                    ('2025-02-26', 'Houston Rockets', 'Milwaukee Bucks', 100, 97, 2024),
                    ('2025-02-26', 'Memphis Grizzlies', 'Phoenix Suns', 151, 148, 2024),
                    ('2025-02-26', 'New Orleans Pelicans', 'San Antonio Spurs', 109, 103, 2024),
                    ('2025-02-26', 'Golden State Warriors', 'Charlotte Hornets', 128, 92, 2024),
                    ('2025-02-26', 'Los Angeles Lakers', 'Dallas Mavericks', 107, 99, 2024),
                    ('2025-02-27', 'Detroit Pistons', 'Boston Celtics', 117, 97, 2024),
                    ('2025-02-27', 'Indiana Pacers', 'Toronto Raptors', 111, 91, 2024),
                    ('2025-02-27', 'New York Knicks', 'Philadelphia 76ers', 110, 105, 2024),
                    ('2025-02-27', 'Washington Wizards', 'Portland Trail Blazers', 121, 129, 2024),
                    ('2025-02-27', 'Brooklyn Nets', 'Oklahoma City Thunder', 121, 129, 2024),
                    ('2025-02-27', 'Miami Heat', 'Atlanta Hawks', 131, 109, 2024),
                    ('2025-02-27', 'Chicago Bulls', 'LA Clippers', 117, 122, 2024),
                    ('2025-02-27', 'Utah Jazz', 'Sacramento Kings', 101, 118, 2024),
                    ('2025-02-27', 'Houston Rockets', 'San Antonio Spurs', 118, 106, 2024),
                    ('2025-02-28', 'Orlando Magic', 'Golden State Warriors', 115, 121, 2024),
                    ('2025-02-28', 'Milwaukee Bucks', 'Denver Nuggets', 121, 112, 2024),
                    ('2025-02-28', 'Dallas Mavericks', 'Charlotte Hornets', 103, 96, 2024),
                    ('2025-02-28', 'Phoenix Suns', 'New Orleans Pelicans', 116, 124, 2024),
                    ('2025-02-28', 'Los Angeles Lakers', 'Minnesota Timberwolves', 111, 102, 2024),
                    ('2025-03-01', 'Detroit Pistons', 'Denver Nuggets', 119, 134, 2024),
                    ('2025-03-01', 'Atlanta Hawks', 'Oklahoma City Thunder', 119, 135, 2024),
                    ('2025-03-01', 'Boston Celtics', 'Cleveland Cavaliers', 116, 123, 2024),
                    ('2025-03-01', 'Brooklyn Nets', 'Portland Trail Blazers', 102, 121, 2024),
                    ('2025-03-01', 'Miami Heat', 'Indiana Pacers', 125, 120, 2024),
                    ('2025-03-01', 'Chicago Bulls', 'Toronto Raptors', 125, 115, 2024),
                    ('2025-03-01', 'Memphis Grizzlies', 'New York Knicks', 113, 114, 2024),
                    ('2025-03-01', 'Phoenix Suns', 'New Orleans Pelicans', 125, 108, 2024),
                    ('2025-03-01', 'Utah Jazz', 'Minnesota Timberwolves', 117, 116, 2024),
                    ('2025-03-01', 'Los Angeles Lakers', 'LA Clippers', 106, 102, 2024),
                    ('2025-03-01', 'Charlotte Hornets', 'Washington Wizards', 100, 113, 2024),
                    ('2025-03-02', 'Detroit Pistons', 'Brooklyn Nets', 115, 94, 2024),
                    ('2025-03-02', 'Houston Rockets', 'Sacramento Kings', 103, 113, 2024),
                    ('2025-03-02', 'Memphis Grizzlies', 'San Antonio Spurs', 128, 130, 2024),
                    ('2025-03-02', 'Philadelphia 76ers', 'Golden State Warriors', 126, 119, 2024),
                    ('2025-03-02', 'Dallas Mavericks', 'Milwaukee Bucks', 117, 132, 2024),
                    ('2025-03-02', 'Boston Celtics', 'Denver Nuggets', 110, 103, 2024),
                    ('2025-03-02', 'Cleveland Cavaliers', 'Portland Trail Blazers', 133, 129, 2024),
                    ('2025-03-02', 'Indiana Pacers', 'Chicago Bulls', 127, 112, 2024),
                    ('2025-03-02', 'Miami Heat', 'New York Knicks', 112, 116, 2024),
                    ('2025-03-02', 'Orlando Magic', 'Toronto Raptors', 102, 104, 2024),
                    ('2025-03-03', 'San Antonio Spurs', 'Oklahoma City Thunder', 132, 146, 2024),
                    ('2025-03-03', 'Utah Jazz', 'New Orleans Pelicans', 121, 128, 2024),
                    ('2025-03-03', 'Phoenix Suns', 'Minnesota Timberwolves', 98, 116, 2024),
                    ('2025-03-03', 'Los Angeles Lakers', 'LA Clippers', 108, 102, 2024),
                    ('2025-03-04', 'Charlotte Hornets', 'Golden State Warriors', 101, 119, 2024),
                    ('2025-03-04', 'Philadelphia 76ers', 'Portland Trail Blazers', 102, 119, 2024),
                    ('2025-03-04', 'Miami Heat', 'Washington Wizards', 106, 90, 2024),
                    ('2025-03-04', 'Memphis Grizzlies', 'Atlanta Hawks', 130, 132, 2024),
                    ('2025-03-04', 'Oklahoma City Thunder', 'Houston Rockets', 137, 128, 2024),
                    ('2025-03-04', 'Dallas Mavericks', 'Sacramento Kings', 98, 122, 2024),
                    ('2025-03-04', 'Utah Jazz', 'Detroit Pistons', 106, 134, 2024),
                    ('2025-03-05', 'Indiana Pacers', 'Houston Rockets', 115, 102, 2024),
                    ('2025-03-05', 'Orlando Magic', 'Toronto Raptors', 113, 114, 2024),
                    ('2025-03-05', 'Atlanta Hawks', 'Milwaukee Bucks', 121, 127, 2024),
                    ('2025-03-05', 'New York Knicks', 'Golden State Warriors', 102, 114, 2024),
                    ('2025-03-05', 'Chicago Bulls', 'Cleveland Cavaliers', 117, 139, 2024),
                    ('2025-03-05', 'Minnesota Timberwolves', 'Philadelphia 76ers', 126, 112, 2024),
                    ('2025-03-05', 'San Antonio Spurs', 'Brooklyn Nets', 127, 113, 2024),
                    ('2025-03-05', 'Phoenix Suns', 'LA Clippers', 119, 117, 2024),
                    ('2025-03-05', 'Los Angeles Lakers', 'New Orleans Pelicans', 136, 115, 2024),
                    ('2025-03-06', 'Boston Celtics', 'Portland Trail Blazers', 128, 118, 2024),
                    ('2025-03-06', 'Charlotte Hornets', 'Minnesota Timberwolves', 110, 125, 2024),
                    ('2025-03-06', 'Cleveland Cavaliers', 'Miami Heat', 112, 107, 2024),
                    ('2025-03-06', 'Washington Wizards', 'Utah Jazz', 125, 122, 2024),
                    ('2025-03-06', 'Milwaukee Bucks', 'Dallas Mavericks', 137, 107, 2024),
                    ('2025-03-06', 'Denver Nuggets', 'Sacramento Kings', 116, 110, 2024),
                    ('2025-03-06', 'Memphis Grizzlies', 'Oklahoma City Thunder', 103, 120, 2024),
                    ('2025-03-06', 'LA Clippers', 'Detroit Pistons', 123, 115, 2024),
                    ('2025-03-07', 'Orlando Magic', 'Chicago Bulls', 123, 125, 2024),
                    ('2025-03-07', 'Atlanta Hawks', 'Indiana Pacers', 124, 118, 2024),
                    ('2025-03-07', 'Boston Celtics', 'Philadelphia 76ers', 123, 105, 2024),
                    ('2025-03-07', 'Brooklyn Nets', 'Golden State Warriors', 119, 121, 2024),
                    ('2025-03-07', 'New Orleans Pelicans', 'Houston Rockets', 97, 109, 2024),
                    ('2025-03-07', 'Los Angeles Lakers', 'New York Knicks', 113, 109, 2024),
                    ('2025-03-07', 'Charlotte Hornets', 'Cleveland Cavaliers', 117, 118, 2024),
                    ('2025-03-08', 'Toronto Raptors', 'Utah Jazz', 118, 109, 2024),
                    ('2025-03-08', 'Dallas Mavericks', 'Memphis Grizzlies', 111, 122, 2024),
                    ('2025-03-08', 'Miami Heat', 'Minnesota Timberwolves', 104, 106, 2024),
                    ('2025-03-08', 'Oklahoma City Thunder', 'Portland Trail Blazers', 107, 89, 2024),
                    ('2025-03-08', 'Denver Nuggets', 'Phoenix Suns', 149, 141, 2024),
                    ('2025-03-08', 'Sacramento Kings', 'San Antonio Spurs', 127, 109, 2024),
                    ('2025-03-08', 'LA Clippers', 'New York Knicks', 105, 95, 2024),
                    ('2025-03-08', 'Charlotte Hornets', 'Brooklyn Nets', 105, 102, 2024),
                    ('2025-03-09', 'Houston Rockets', 'New Orleans Pelicans', 146, 117, 2024),
                    ('2025-03-09', 'Atlanta Hawks', 'Indiana Pacers', 120, 118, 2024),
                    ('2025-03-09', 'Toronto Raptors', 'Washington Wizards', 117, 118, 2024),
                    ('2025-03-09', 'Miami Heat', 'Chicago Bulls', 109, 114, 2024),
                    ('2025-03-09', 'Milwaukee Bucks', 'Orlando Magic', 109, 111, 2024),
                    ('2025-03-09', 'Boston Celtics', 'Los Angeles Lakers', 111, 101, 2024),
                    ('2025-03-09', 'Golden State Warriors', 'Detroit Pistons', 115, 110, 2024),
                    ('2025-03-09', 'Oklahoma City Thunder', 'Denver Nuggets', 127, 103, 2024),
                    ('2025-03-09', 'Dallas Mavericks', 'Phoenix Suns', 116, 125, 2024),
                    ('2025-03-09', 'New Orleans Pelicans', 'Memphis Grizzlies', 104, 107, 2024),
                    ('2025-03-09', 'Philadelphia 76ers', 'Utah Jazz', 126, 122, 2024),
                    ('2025-03-10', 'Milwaukee Bucks', 'Cleveland Cavaliers', 100, 112, 2024),
                    ('2025-03-10', 'Minnesota Timberwolves', 'San Antonio Spurs', 141, 124, 2024),
                    ('2025-03-10', 'Portland Trail Blazers', 'Detroit Pistons', 112, 119, 2024),
                    ('2025-03-10', 'LA Clippers', 'Sacramento Kings', 111, 110, 2024),
                    ('2025-03-10', 'Atlanta Hawks', 'Philadelphia 76ers', 132, 123, 2024),
                    ('2025-03-10', 'Boston Celtics', 'Utah Jazz', 114, 108, 2024),
                    ('2025-03-10', 'Brooklyn Nets', 'Los Angeles Lakers', 111, 108, 2024),
                    ('2025-03-10', 'Miami Heat', 'Charlotte Hornets', 102, 105, 2024),
                    ('2025-03-10', 'Toronto Raptors', 'Washington Wizards', 119, 104, 2024),
                    ('2025-03-11', 'Chicago Bulls', 'Indiana Pacers', 121, 103, 2024),
                    ('2025-03-11', 'Houston Rockets', 'Orlando Magic', 97, 84, 2024),
                    ('2025-03-11', 'Memphis Grizzlies', 'Phoenix Suns', 120, 118, 2024),
                    ('2025-03-11', 'Oklahoma City Thunder', 'Denver Nuggets', 127, 140, 2024),
                    ('2025-03-11', 'San Antonio Spurs', 'Dallas Mavericks', 129, 133, 2024),
                    ('2025-03-11', 'Golden State Warriors', 'Portland Trail Blazers', 130, 120, 2024),
                    ('2025-03-11', 'Sacramento Kings', 'New York Knicks', 104, 133, 2024),
                    ('2025-03-11', 'Cleveland Cavaliers', 'Brooklyn Nets', 109, 104, 2024),
                    ('2025-03-11', 'Detroit Pistons', 'Washington Wizards', 123, 103, 2024),
                    ('2025-03-11', 'Indiana Pacers', 'Milwaukee Bucks', 115, 114, 2024),
                    ('2025-03-12', 'New Orleans Pelicans', 'LA Clippers', 127, 120, 2024),
                    ('2025-03-12', 'Atlanta Hawks', 'Charlotte Hornets', 123, 110, 2024),
                    ('2025-03-12', 'Boston Celtics', 'Oklahoma City Thunder', 112, 118, 2024),
                    ('2025-03-12', 'Toronto Raptors', 'Philadelphia 76ers', 118, 105, 2024),
                    ('2025-03-13', 'Miami Heat', 'LA Clippers', 104, 119, 2024),
                    ('2025-03-13', 'Houston Rockets', 'Phoenix Suns', 111, 104, 2024),
                    ('2025-03-13', 'Memphis Grizzlies', 'Utah Jazz', 122, 115, 2024),
                    ('2025-03-13', 'San Antonio Spurs', 'Dallas Mavericks', 126, 116, 2024),
                    ('2025-03-13', 'Denver Nuggets', 'Minnesota Timberwolves', 95, 115, 2024),
                    ('2025-03-13', 'Portland Trail Blazers', 'New York Knicks', 113, 114, 2024),
                    ('2025-03-13', 'Detroit Pistons', 'Washington Wizards', 125, 129, 2024),
                    ('2025-03-13', 'Milwaukee Bucks', 'Los Angeles Lakers', 126, 106, 2024),
                    ('2025-03-14', 'Chicago Bulls', 'Brooklyn Nets', 116, 110, 2024),
                    ('2025-03-14', 'New Orleans Pelicans', 'Orlando Magic', 93, 113, 2024),
                    ('2025-03-14', 'Golden State Warriors', 'Sacramento Kings', 130, 104, 2024),
                    ('2025-03-14', 'Miami Heat', 'Boston Celtics', 91, 103, 2024),
                    ('2025-03-14', 'Philadelphia 76ers', 'Indiana Pacers', 100, 112, 2024),
                    ('2025-03-14', 'Atlanta Hawks', 'LA Clippers', 98, 121, 2024),
                    ('2025-03-15', 'Houston Rockets', 'Dallas Mavericks', 133, 96, 2024),
                    ('2025-03-15', 'Memphis Grizzlies', 'Cleveland Cavaliers', 124, 133, 2024),
                    ('2025-03-15', 'Minnesota Timberwolves', 'Orlando Magic', 118, 111, 2024),
                    ('2025-03-15', 'San Antonio Spurs', 'Charlotte Hornets', 134, 145, 2024),
                    ('2025-03-15', 'Denver Nuggets', 'Los Angeles Lakers', 131, 126, 2024),
                    ('2025-03-15', 'Utah Jazz', 'Toronto Raptors', 118, 126, 2024),
                    ('2025-03-15', 'Phoenix Suns', 'Sacramento Kings', 122, 106, 2024),
                    ('2025-03-15', 'Brooklyn Nets', 'Boston Celtics', 113, 115, 2024),
                    ('2025-03-15', 'Detroit Pistons', 'Oklahoma City Thunder', 107, 113, 2024),
                    ('2025-03-16', 'Houston Rockets', 'Chicago Bulls', 117, 114, 2024),
                    ('2025-03-16', 'Memphis Grizzlies', 'Miami Heat', 125, 91, 2024),
                    ('2025-03-16', 'Milwaukee Bucks', 'Indiana Pacers', 126, 119, 2024),
                    ('2025-03-16', 'San Antonio Spurs', 'New Orleans Pelicans', 119, 115, 2024),
                    ('2025-03-16', 'Golden State Warriors', 'New York Knicks', 97, 94, 2024),
                    ('2025-03-16', 'Denver Nuggets', 'Washington Wizards', 123, 126, 2024),
                    ('2025-03-16', 'Dallas Mavericks', 'Philadelphia 76ers', 125, 130, 2024),
                    ('2025-03-16', 'Cleveland Cavaliers', 'Orlando Magic', 103, 108, 2024),
                    ('2025-03-16', 'Los Angeles Lakers', 'Phoenix Suns', 107, 96, 2024),
                    ('2025-03-16', 'Brooklyn Nets', 'Atlanta Hawks', 122, 114, 2024),
                    ('2025-03-16', 'Portland Trail Blazers', 'Toronto Raptors', 105, 102, 2024),
                    ('2025-03-16', 'LA Clippers', 'Charlotte Hornets', 123, 88, 2024),
                    ('2025-03-16', 'Minnesota Timberwolves', 'Utah Jazz', 128, 102, 2024),
                    ('2025-03-17', 'Milwaukee Bucks', 'Oklahoma City Thunder', 105, 121, 2024),
                    ('2025-03-17', 'New York Knicks', 'Miami Heat', 116, 95, 2024),
                    ('2025-03-18', 'Houston Rockets', 'Philadelphia 76ers', 144, 137, 2024),
                    ('2025-03-18', 'Minnesota Timberwolves', 'Indiana Pacers', 130, 132, 2024),
                    ('2025-03-18', 'New Orleans Pelicans', 'Detroit Pistons', 81, 127, 2024),
                    ('2025-03-18', 'Utah Jazz', 'Chicago Bulls', 97, 111, 2024),
                    ('2025-03-18', 'Golden State Warriors', 'Denver Nuggets', 105, 114, 2024),
                    ('2025-03-18', 'Phoenix Suns', 'Toronto Raptors', 129, 89, 2024),
                    ('2025-03-18', 'Sacramento Kings', 'Memphis Grizzlies', 132, 122, 2024),
                    ('2025-03-18', 'Portland Trail Blazers', 'Washington Wizards', 112, 97, 2024),
                    ('2025-03-18', 'Los Angeles Lakers', 'San Antonio Spurs', 125, 109, 2024),
                    ('2025-03-18', 'Charlotte Hornets', 'Atlanta Hawks', 102, 134, 2024),
                    ('2025-03-18', 'Boston Celtics', 'Brooklyn Nets', 104, 96, 2024),
                    ('2025-03-19', 'Golden State Warriors', 'Milwaukee Bucks', 104, 93, 2024),
                    ('2025-03-19', 'LA Clippers', 'Cleveland Cavaliers', 132, 119, 2024),
                    ('2025-03-19', 'Indiana Pacers', 'Dallas Mavericks', 135, 131, 2024),
                    ('2025-03-19', 'Orlando Magic', 'Houston Rockets', 108, 116, 2024),
                    ('2025-03-19', 'Miami Heat', 'Detroit Pistons', 113, 116, 2024),
                    ('2025-03-20', 'Minnesota Timberwolves', 'New Orleans Pelicans', 115, 119, 2024),
                    ('2025-03-20', 'Oklahoma City Thunder', 'Philadelphia 76ers', 133, 100, 2024),
                    ('2025-03-20', 'San Antonio Spurs', 'New York Knicks', 120, 105, 2024),
                    ('2025-03-20', 'Utah Jazz', 'Washington Wizards', 128, 112, 2024),
                    ('2025-03-20', 'Los Angeles Lakers', 'Denver Nuggets', 120, 108, 2024),
                    ('2025-03-20', 'Phoenix Suns', 'Chicago Bulls', 127, 121, 2024),
                    ('2025-03-20', 'Portland Trail Blazers', 'Memphis Grizzlies', 115, 99, 2024),
                    ('2025-03-20', 'Sacramento Kings', 'Cleveland Cavaliers', 123, 119, 2024),
                    ('2025-03-20', 'Charlotte Hornets', 'New York Knicks', 115, 98, 2024),
                    ('2025-03-20', 'Indiana Pacers', 'Brooklyn Nets', 105, 99, 2024),
                    ('2025-03-21', 'Golden State Warriors', 'Toronto Raptors', 117, 114, 2024),
                    ('2025-03-21', 'Sacramento Kings', 'Chicago Bulls', 116, 128, 2024),
                    ('2025-03-21', 'Los Angeles Lakers', 'Milwaukee Bucks', 89, 118, 2024),
                    ('2025-03-21', 'Washington Wizards', 'Orlando Magic', 105, 120, 2024),
                    ('2025-03-22', 'Miami Heat', 'Houston Rockets', 98, 102, 2024),
                    ('2025-03-22', 'Minnesota Timberwolves', 'New Orleans Pelicans', 134, 93, 2024),
                    ('2025-03-22', 'Oklahoma City Thunder', 'Charlotte Hornets', 141, 106, 2024),
                    ('2025-03-22', 'San Antonio Spurs', 'Philadelphia 76ers', 128, 120, 2024),
                    ('2025-03-22', 'Dallas Mavericks', 'Detroit Pistons', 123, 117, 2024),
                    ('2025-03-22', 'Utah Jazz', 'Boston Celtics', 99, 121, 2024),
                    ('2025-03-22', 'Phoenix Suns', 'Cleveland Cavaliers', 123, 112, 2024),
                    ('2025-03-22', 'Portland Trail Blazers', 'Denver Nuggets', 128, 109, 2024),
                    ('2025-03-22', 'LA Clippers', 'Memphis Grizzlies', 128, 108, 2024),
                    ('2025-03-22', 'Indiana Pacers', 'Brooklyn Nets', 108, 103, 2024),
                    ('2025-03-22', 'Atlanta Hawks', 'Golden State Warriors', 124, 115, 2024),
                    ('2025-03-23', 'New York Knicks', 'Washington Wizards', 122, 103, 2024),
                    ('2025-03-23', 'Sacramento Kings', 'Milwaukee Bucks', 108, 114, 2024),
                    ('2025-03-23', 'Los Angeles Lakers', 'Chicago Bulls', 115, 146, 2024),
                    ('2025-03-23', 'Detroit Pistons', 'New Orleans Pelicans', 136, 130, 2024),
                    ('2025-03-23', 'Utah Jazz', 'Cleveland Cavaliers', 91, 120, 2024),
                    ('2025-03-23', 'Atlanta Hawks', 'Philadelphia 76ers', 132, 119, 2024),
                    ('2025-03-23', 'Miami Heat', 'Charlotte Hornets', 122, 105, 2024),
                    ('2025-03-23', 'Toronto Raptors', 'San Antonio Spurs', 89, 123, 2024),
                    ('2025-03-23', 'Portland Trail Blazers', 'Boston Celtics', 116, 129, 2024),
                    ('2025-03-23', 'Houston Rockets', 'Denver Nuggets', 111, 116, 2024),
                    ('2025-03-24', 'LA Clippers', 'Oklahoma City Thunder', 101, 103, 2024),
                    ('2025-03-24', 'Indiana Pacers', 'Minnesota Timberwolves', 119, 103, 2024),
                    ('2025-03-24', 'Orlando Magic', 'Los Angeles Lakers', 118, 106, 2024),
                    ('2025-03-24', 'Washington Wizards', 'Toronto Raptors', 104, 112, 2024),
                    ('2025-03-24', 'Brooklyn Nets', 'Dallas Mavericks', 101, 120, 2024),
                    ('2025-03-25', 'New Orleans Pelicans', 'Philadelphia 76ers', 112, 99, 2024),
                    ('2025-03-25', 'Denver Nuggets', 'Chicago Bulls', 119, 129, 2024),
                    ('2025-03-25', 'Phoenix Suns', 'Milwaukee Bucks', 108, 106, 2024),
                    ('2025-03-25', 'Sacramento Kings', 'Boston Celtics', 95, 113, 2024),
                    ('2025-03-25', 'Charlotte Hornets', 'Orlando Magic', 104, 111, 2024),
                    ('2025-03-25', 'Detroit Pistons', 'San Antonio Spurs', 122, 96, 2024),
                    ('2025-03-25', 'Miami Heat', 'Golden State Warriors', 112, 86, 2024),
                    ('2025-03-25', 'New York Knicks', 'Dallas Mavericks', 128, 113, 2024),
                    ('2025-03-26', 'Houston Rockets', 'Atlanta Hawks', 121, 114, 2024),
                    ('2025-03-26', 'Utah Jazz', 'Memphis Grizzlies', 103, 140, 2024),
                    ('2025-03-26', 'Portland Trail Blazers', 'Cleveland Cavaliers', 111, 122, 2024),
                    ('2025-03-26', 'Sacramento Kings', 'Oklahoma City Thunder', 105, 121, 2024),
                    ('2025-03-26', 'Philadelphia 76ers', 'Washington Wizards', 114, 119, 2024),
                    ('2025-03-26', 'Brooklyn Nets', 'Toronto Raptors', 86, 116, 2024),
                    ('2025-03-26', 'Indiana Pacers', 'Los Angeles Lakers', 119, 120, 2024),
                    ('2025-03-26', 'New York Knicks', 'LA Clippers', 113, 126, 2024),
                    ('2025-03-27', 'Denver Nuggets', 'Milwaukee Bucks', 127, 117, 2024),
                    ('2025-03-27', 'Phoenix Suns', 'Boston Celtics', 102, 132, 2024),
                    ('2025-03-27', 'Cleveland Cavaliers', 'San Antonio Spurs', 124, 116, 2024),
                    ('2025-03-27', 'Orlando Magic', 'Dallas Mavericks', 92, 101, 2024),
                    ('2025-03-27', 'Washington Wizards', 'Indiana Pacers', 109, 162, 2024),
                    ('2025-03-27', 'Miami Heat', 'Atlanta Hawks', 122, 112, 2024),
                    ('2025-03-28', 'Chicago Bulls', 'Los Angeles Lakers', 119, 117, 2024),
                    ('2025-03-28', 'Oklahoma City Thunder', 'Memphis Grizzlies', 125, 104, 2024),
                    ('2025-03-28', 'Utah Jazz', 'Houston Rockets', 110, 121, 2024),
                    ('2025-03-28', 'Sacramento Kings', 'Portland Trail Blazers', 128, 107, 2024),
                    ('2025-03-28', 'Detroit Pistons', 'Cleveland Cavaliers', 133, 122, 2024),
                    ('2025-03-28', 'Brooklyn Nets', 'LA Clippers', 100, 132, 2024),
                    ('2025-03-28', 'Toronto Raptors', 'Charlotte Hornets', 108, 97, 2024),
                    ('2025-03-29', 'Milwaukee Bucks', 'New York Knicks', 107, 116, 2024),
                    ('2025-03-29', 'Minnesota Timberwolves', 'Phoenix Suns', 124, 109, 2024),
                    ('2025-03-29', 'New Orleans Pelicans', 'Golden State Warriors', 95, 111, 2024),
                    ('2025-03-29', 'Denver Nuggets', 'Utah Jazz', 129, 93, 2024),
                    ('2025-03-29', 'Orlando Magic', 'Sacramento Kings', 121, 91, 2024),
                    ('2025-03-29', 'Washington Wizards', 'Brooklyn Nets', 112, 115, 2024),
                    ('2025-03-29', 'Philadelphia 76ers', 'Miami Heat', 95, 118, 2024),
                    ('2025-03-30', 'Chicago Bulls', 'Dallas Mavericks', 119, 120, 2024),
                    ('2025-03-30', 'Memphis Grizzlies', 'Los Angeles Lakers', 127, 134, 2024),
                    ('2025-03-30', 'Oklahoma City Thunder', 'Indiana Pacers', 132, 111, 2024),
                    ('2025-03-29', 'San Antonio Spurs', 'Boston Celtics', 111, 121, 2024),
                    ('2025-03-30', 'Cleveland Cavaliers', 'LA Clippers', 127, 122, 2024),
                    ('2025-03-30', 'New York Knicks', 'Portland Trail Blazers', 110, 93, 2024),
                    ('2025-03-30', 'Milwaukee Bucks', 'Atlanta Hawks', 124, 145, 2024),
                    ('2025-03-30', 'Minnesota Timberwolves', 'Detroit Pistons', 123, 104, 2024),
                    ('2025-03-30', 'New Orleans Pelicans', 'Charlotte Hornets', 98, 94, 2024),
                    ('2025-03-30', 'San Antonio Spurs', 'Golden State Warriors', 106, 148, 2024),
                    ('2025-03-30', 'Philadelphia 76ers', 'Toronto Raptors', 109, 127, 2024),
                    ('2025-03-31', 'Phoenix Suns', 'Houston Rockets', 109, 148, 2024),
                    ('2025-03-31', 'Charlotte Hornets', 'Utah Jazz', 110, 106, 2024),
                    ('2025-03-31', 'Indiana Pacers', 'Sacramento Kings', 111, 109, 2024),
                    ('2025-03-31', 'Orlando Magic', 'LA Clippers', 87, 96, 2024),
                    ('2025-03-31', 'Washington Wizards', 'Miami Heat', 94, 120, 2024),
                    ('2025-03-31', 'Memphis Grizzlies', 'Boston Celtics', 103, 117, 2024),
                    ('2025-04-01', 'Oklahoma City Thunder', 'Chicago Bulls', 145, 117, 2024),
                    ('2025-04-01', 'Dallas Mavericks', 'Brooklyn Nets', 109, 113, 2024),
                    ('2025-04-01', 'Los Angeles Lakers', 'Houston Rockets', 104, 98, 2024),
                    ('2025-04-01', 'Atlanta Hawks', 'Portland Trail Blazers', 113, 127, 2024),
                    ('2025-04-01', 'New York Knicks', 'Philadelphia 76ers', 105, 91, 2024),
                    ('2025-04-01', 'Milwaukee Bucks', 'Phoenix Suns', 133, 123, 2024),
                    ('2025-04-02', 'San Antonio Spurs', 'Orlando Magic', 105, 116, 2024),
                    ('2025-04-02', 'Chicago Bulls', 'Toronto Raptors', 137, 118, 2024),
                    ('2025-04-02', 'Memphis Grizzlies', 'Golden State Warriors', 125, 134, 2024),
                    ('2025-04-02', 'Denver Nuggets', 'Minnesota Timberwolves', 139, 140, 2024),
                    ('2025-04-02', 'Cleveland Cavaliers', 'New York Knicks', 124, 105, 2024),
                    ('2025-04-02', 'Indiana Pacers', 'Charlotte Hornets', 119, 105, 2024),
                    ('2025-04-02', 'Washington Wizards', 'Sacramento Kings', 116, 111, 2024),
                    ('2025-04-02', 'Boston Celtics', 'Miami Heat', 103, 124, 2024),
                    ('2025-04-03', 'Houston Rockets', 'Utah Jazz', 143, 105, 2024),
                    ('2025-04-03', 'Dallas Mavericks', 'Atlanta Hawks', 120, 118, 2024),
                    ('2025-04-03', 'Denver Nuggets', 'San Antonio Spurs', 106, 113, 2024),
                    ('2025-04-03', 'Oklahoma City Thunder', 'Detroit Pistons', 119, 103, 2024),
                    ('2025-04-03', 'LA Clippers', 'New Orleans Pelicans', 114, 98, 2024),
                    ('2025-04-03', 'Washington Wizards', 'Orlando Magic', 97, 109, 2024),
                    ('2025-04-03', 'Philadelphia 76ers', 'Milwaukee Bucks', 113, 126, 2024),
                    ('2025-04-03', 'Brooklyn Nets', 'Minnesota Timberwolves', 90, 105, 2024),
                    ('2025-04-03', 'Miami Heat', 'Memphis Grizzlies', 108, 110, 2024),
                    ('2025-04-03', 'Toronto Raptors', 'Portland Trail Blazers', 103, 112, 2024),
                    ('2025-04-04', 'Los Angeles Lakers', 'Golden State Warriors', 116, 123, 2024),
                    ('2025-04-04', 'Charlotte Hornets', 'Sacramento Kings', 102, 125, 2024),
                    ('2025-04-04', 'Indiana Pacers', 'Utah Jazz', 140, 112, 2024),
                    ('2025-04-04', 'Boston Celtics', 'Phoenix Suns', 123, 103, 2024),
                    ('2025-04-04', 'Toronto Raptors', 'Detroit Pistons', 105, 117, 2024),
                    ('2025-04-05', 'Chicago Bulls', 'Portland Trail Blazers', 118, 113, 2024),
                    ('2025-04-05', 'Houston Rockets', 'Oklahoma City Thunder', 125, 111, 2024),
                    ('2025-04-05', 'San Antonio Spurs', 'Cleveland Cavaliers', 113, 114, 2024),
                    ('2025-04-05', 'Golden State Warriors', 'Denver Nuggets', 118, 104, 2024),
                    ('2025-04-05', 'Los Angeles Lakers', 'New Orleans Pelicans', 124, 108, 2024),
                    ('2025-04-05', 'LA Clippers', 'Dallas Mavericks', 114, 91, 2024),
                    ('2025-04-05', 'Atlanta Hawks', 'New York Knicks', 105, 121, 2024),
                    ('2025-04-05', 'Detroit Pistons', 'Memphis Grizzlies', 103, 109, 2024),
                    ('2025-04-05', 'Philadelphia 76ers', 'Minnesota Timberwolves', 109, 114, 2024),
                    ('2025-04-06', 'Miami Heat', 'Milwaukee Bucks', 115, 121, 2024),
                    ('2025-04-06', 'LA Clippers', 'Dallas Mavericks', 135, 104, 2024),
                    ('2025-04-06', 'Charlotte Hornets', 'Chicago Bulls', 117, 131, 2024),
                    ('2025-04-06', 'Brooklyn Nets', 'Toronto Raptors', 109, 120, 2024),
                    ('2025-04-06', 'Oklahoma City Thunder', 'Los Angeles Lakers', 99, 126, 2024),
                    ('2025-04-06', 'Atlanta Hawks', 'Utah Jazz', 147, 134, 2024),
                    ('2025-04-06', 'Boston Celtics', 'Washington Wizards', 124, 90, 2024),
                    ('2025-04-06', 'Cleveland Cavaliers', 'Sacramento Kings', 113, 120, 2024),
                    ('2025-04-06', 'Portland Trail Blazers', 'San Antonio Spurs', 120, 109, 2024),
                    ('2025-04-06', 'New York Knicks', 'Phoenix Suns', 112, 98, 2024),
                    ('2025-04-07', 'Denver Nuggets', 'Indiana Pacers', 120, 125, 2024),
                    ('2025-04-07', 'New Orleans Pelicans', 'Milwaukee Bucks', 107, 111, 2024),
                    ('2025-04-07', 'Golden State Warriors', 'Houston Rockets', 96, 106, 2024),
                    ('2025-04-07', 'Detroit Pistons', 'Sacramento Kings', 117, 127, 2024),
                    ('2025-04-07', 'Miami Heat', 'Philadelphia 76ers', 117, 105, 2024),
                    ('2025-04-08', 'Charlotte Hornets', 'Memphis Grizzlies', 100, 124, 2024),
                    ('2025-04-08', 'Cleveland Cavaliers', 'Chicago Bulls', 135, 113, 2024),
                    ('2025-04-08', 'Indiana Pacers', 'Washington Wizards', 104, 98, 2024),
                    ('2025-04-08', 'Orlando Magic', 'Atlanta Hawks', 119, 112, 2024),
                    ('2025-04-08', 'Brooklyn Nets', 'New Orleans Pelicans', 119, 114, 2024),
                    ('2025-04-08', 'New York Knicks', 'Boston Celtics', 117, 119, 2024),
                    ('2025-04-09', 'Milwaukee Bucks', 'Minnesota Timberwolves', 110, 103, 2024),
                    ('2025-04-09', 'Oklahoma City Thunder', 'Los Angeles Lakers', 136, 120, 2024),
                    ('2025-04-09', 'Phoenix Suns', 'Golden State Warriors', 95, 133, 2024),
                    ('2025-04-09', 'LA Clippers', 'San Antonio Spurs', 122, 117, 2024),
                    ('2025-04-09', 'Orlando Magic', 'Boston Celtics', 96, 76, 2024),
                    ('2025-04-09', 'Washington Wizards', 'Philadelphia 76ers', 103, 122, 2024),
                    ('2025-04-09', 'Toronto Raptors', 'Charlotte Hornets', 126, 96, 2024),
                    ('2025-04-09', 'Dallas Mavericks', 'Los Angeles Lakers', 97, 112, 2024),
                    ('2025-04-10', 'Chicago Bulls', 'Miami Heat', 119, 111, 2024),
                    ('2025-04-10', 'Utah Jazz', 'Portland Trail Blazers', 133, 126, 2024),
                    ('2025-04-10', 'Golden State Warriors', 'San Antonio Spurs', 111, 114, 2024),
                    ('2025-04-10', 'Phoenix Suns', 'Oklahoma City Thunder', 112, 125, 2024),
                    ('2025-04-10', 'Sacramento Kings', 'Denver Nuggets', 116, 124, 2024),
                    ('2025-04-10', 'LA Clippers', 'Houston Rockets', 134, 117, 2024),
                    ('2025-04-10', 'Detroit Pistons', 'New York Knicks', 115, 106, 2024),
                    ('2025-04-10', 'Indiana Pacers', 'Cleveland Cavaliers', 114, 112, 2024),
                    ('2025-04-10', 'Brooklyn Nets', 'Atlanta Hawks', 109, 133, 2024),
                    ('2025-04-11', 'Milwaukee Bucks', 'New Orleans Pelicans', 136, 111, 2024),
                    ('2025-04-11', 'Memphis Grizzlies', 'Minnesota Timberwolves', 125, 141, 2024),
                    ('2025-04-11', 'Detroit Pistons', 'Milwaukee Bucks', 119, 125, 2024),
                    ('2025-04-11', 'Indiana Pacers', 'Orlando Magic', 115, 129, 2024),
                    ('2025-04-11', 'Philadelphia 76ers', 'Atlanta Hawks', 110, 124, 2024),
                    ('2025-04-11', 'Boston Celtics', 'Charlotte Hornets', 130, 94, 2024),
                    ('2025-04-11', 'New York Knicks', 'Cleveland Cavaliers', 102, 108, 2024),
                    ('2025-04-12', 'Chicago Bulls', 'Washington Wizards', 119, 89, 2024),
                    ('2025-04-12', 'New Orleans Pelicans', 'Miami Heat', 104, 153, 2024),
                    ('2025-04-12', 'Dallas Mavericks', 'Toronto Raptors', 124, 102, 2024),
                    ('2025-04-12', 'Minnesota Timberwolves', 'Brooklyn Nets', 117, 91, 2024),
                    ('2025-04-12', 'Denver Nuggets', 'Memphis Grizzlies', 117, 109, 2024),
                    ('2025-04-12', 'Utah Jazz', 'Oklahoma City Thunder', 111, 145, 2024),
                    ('2025-04-12', 'Phoenix Suns', 'San Antonio Spurs', 117, 98, 2024),
                    ('2025-04-12', 'Portland Trail Blazers', 'Golden State Warriors', 86, 103, 2024),
                    ('2025-04-12', 'Sacramento Kings', 'LA Clippers', 100, 101, 2024),
                    ('2025-04-12', 'Los Angeles Lakers', 'Houston Rockets', 140, 109, 2024),
                    ('2025-04-13', 'Atlanta Hawks', 'Orlando Magic', 117, 105, 2024),
                    ('2025-04-13', 'Boston Celtics', 'Charlotte Hornets', 93, 86, 2024),
                    ('2025-04-13', 'Brooklyn Nets', 'New York Knicks', 105, 113, 2024),
                    ('2025-04-13', 'Cleveland Cavaliers', 'Indiana Pacers', 118, 126, 2024),
                    ('2025-04-13', 'Miami Heat', 'Washington Wizards', 118, 119, 2024),
                    ('2025-04-13', 'Philadelphia 76ers', 'Chicago Bulls', 102, 122, 2024),
                    ('2025-04-13', 'Milwaukee Bucks', 'Detroit Pistons', 140, 133, 2024),
                    ('2025-04-13', 'Houston Rockets', 'Denver Nuggets', 111, 126, 2024),
                    ('2025-04-13', 'Memphis Grizzlies', 'Dallas Mavericks', 132, 97, 2024),
                    ('2025-04-13', 'Minnesota Timberwolves', 'Utah Jazz', 116, 105, 2024),
                    ('2025-04-13', 'New Orleans Pelicans', 'Oklahoma City Thunder', 100, 115, 2024),
                    ('2025-04-13', 'San Antonio Spurs', 'Toronto Raptors', 125, 118, 2024),
                    ('2025-04-13', 'Golden State Warriors', 'LA Clippers', 119, 124, 2024),
                    ('2025-04-13', 'Portland Trail Blazers', 'Los Angeles Lakers', 109, 81, 2024),
                    ('2025-04-13', 'Sacramento Kings', 'Phoenix Suns', 109, 98, 2024);

INSERT INTO Analisi_Partita (ID_Membro, Data_partita, Squadra_casa, Punti, Rimbalzi, Assist) VALUES
                    (26, '2018-10-17', 'Boston Celtics', 20, 11, 3),
                    (26, '2018-10-18', 'Sacramento Kings', 26, 4, 4),
                    (26, '2018-10-19', 'Washington Wizards', 17, 1, 1),
                    (26, '2018-10-20', 'Toronto Raptors', 3, 6, 3),
                    (26, '2018-10-21', 'Miami Heat', 2, 7, 10),
                    (26, '2018-10-23', 'Portland Trail Blazers', 8, 8, 3),
                    (26, '2018-10-24', 'New Orleans Pelicans', 37, 14, 3),
                    (26, '2018-10-26', 'New Orleans Pelicans', 7, 1, 3),
                    (26, '2018-10-27', 'Houston Rockets', 8, 6, 5),
                    (26, '2018-11-06', 'Detroit Pistons', 10, 1, 10),
                    (26, '2018-11-12', 'Denver Nuggets', 39, 2, 7),
                    (26, '2018-11-14', 'Cleveland Cavaliers', 22, 3, 10),
                    (26, '2018-11-20', 'Philadelphia 76ers', 19, 9, 0),
                    (26, '2018-11-24', 'Washington Wizards', 12, 12, 7),
                    (26, '2018-11-26', 'Portland Trail Blazers', 5, 15, 10),
                    (33, '2018-10-17', 'Indiana Pacers', 9, 2, 5),
                    (33, '2018-10-19', 'Orlando Magic', 8, 5, 1),
                    (33, '2018-10-20', 'New Orleans Pelicans', 15, 14, 0),
                    (33, '2018-10-21', 'Denver Nuggets', 29, 8, 6),
                    (33, '2018-10-23', 'Utah Jazz', 11, 8, 7),
                    (33, '2018-10-25', 'Houston Rockets', 10, 13, 8),
                    (33, '2018-10-28', 'Memphis Grizzlies', 28, 8, 10),
                    (33, '2018-11-06', 'Orlando Magic', 10, 12, 10),
                    (33, '2018-11-08', 'Utah Jazz', 27, 11, 10),
                    (33, '2018-11-11', 'Memphis Grizzlies', 5, 9, 9),
                    (33, '2018-11-15', 'Milwaukee Bucks', 1, 6, 0),
                    (33, '2018-11-20', 'Philadelphia 76ers', 1, 10, 8),
                    (33, '2018-11-24', 'Los Angeles Lakers', 34, 8, 10),
                    (33, '2018-11-25', 'Dallas Mavericks', 10, 10, 10),
                    (53, '2018-10-18', 'San Antonio Spurs', 39, 7, 0),
                    (53, '2018-10-19', 'Portland Trail Blazers', 27, 14, 10),
                    (53, '2018-10-20', 'New York Knicks', 11, 1, 7),
                    (53, '2018-10-21', 'Denver Nuggets', 38, 1, 3),
                    (53, '2018-10-24', 'Miami Heat', 15, 11, 11),
                    (53, '2018-10-25', 'Chicago Bulls', 30, 8, 3),
                    (53, '2018-10-28', 'San Antonio Spurs', 32, 6, 4),
                    (53, '2018-10-29', 'New York Knicks', 19, 11, 11),
                    (53, '2018-11-01', 'Los Angeles Lakers', 6, 11, 8),
                    (53, '2018-11-09', 'Phoenix Suns', 13, 13, 7),
                    (53, '2018-11-15', 'Orlando Magic', 28, 15, 10),
                    (53, '2018-11-18', 'Chicago Bulls', 28, 9, 6),
                    (53, '2018-11-22', 'Cleveland Cavaliers', 15, 9, 4),
                    (53, '2018-11-25', 'Dallas Mavericks', 33, 13, 0),
                    (53, '2018-11-26', 'Portland Trail Blazers', 13, 8, 1),
                    (57, '2018-10-17', 'Charlotte Hornets', 37, 7, 5),
                    (57, '2018-10-18', 'Sacramento Kings', 3, 15, 5),
                    (57, '2018-10-20', 'Minnesota Timberwolves', 25, 15, 9),
                    (57, '2018-10-21', 'Denver Nuggets', 16, 8, 6),
                    (57, '2018-10-22', 'Boston Celtics', 28, 14, 1),
                    (57, '2018-10-23', 'Minnesota Timberwolves', 2, 1, 10),
                    (57, '2018-10-25', 'Milwaukee Bucks', 10, 7, 4),
                    (57, '2018-10-26', 'Charlotte Hornets', 29, 13, 8),
                    (57, '2018-10-29', 'LA Clippers', 40, 7, 9),
                    (57, '2018-11-01', 'Atlanta Hawks', 26, 6, 3),
                    (57, '2018-11-15', 'Indiana Pacers', 16, 9, 6),
                    (57, '2018-11-20', 'Philadelphia 76ers', 2, 1, 1),
                    (57, '2018-11-24', 'Los Angeles Lakers', 26, 2, 1),
                    (57, '2018-11-25', 'Dallas Mavericks', 35, 1, 1),
                    (60, '2018-10-17', 'Indiana Pacers', 24, 0, 9),
                    (60, '2018-10-21', 'Los Angeles Lakers', 21, 12, 1),
                    (60, '2018-10-22', 'LA Clippers', 3, 0, 5),
                    (60, '2018-10-25', 'Phoenix Suns', 15, 6, 0),
                    (60, '2018-10-27', 'Sacramento Kings', 12, 5, 4),
                    (60, '2018-10-31', 'Memphis Grizzlies', 40, 5, 1),
                    (60, '2018-11-01', 'Los Angeles Lakers', 14, 3, 1),
                    (60, '2018-11-11', 'Memphis Grizzlies', 21, 13, 8),
                    (60, '2018-11-15', 'Milwaukee Bucks', 21, 0, 9),
                    (60, '2018-11-20', 'Philadelphia 76ers', 33, 15, 8),
                    (60, '2018-11-24', 'Detroit Pistons', 27, 9, 7),
                    (60, '2018-11-25', 'Dallas Mavericks', 36, 2, 7),
                    (60, '2018-11-26', 'Sacramento Kings', 27, 1, 8),
                    (10, '2018-10-17', 'Boston Celtics', 30, 11, 7),
                    (10, '2018-10-18', 'Houston Rockets', 33, 14, 0),
                    (10, '2018-10-19', 'Philadelphia 76ers', 11, 9, 1),
                    (10, '2018-10-20', 'Minnesota Timberwolves', 21, 10, 0),
                    (10, '2018-10-21', 'Oklahoma City Thunder', 34, 13, 4),
                    (10, '2018-10-22', 'Boston Celtics', 40, 13, 5),
                    (10, '2018-10-23', 'Milwaukee Bucks', 39, 7, 9),
                    (10, '2018-10-24', 'Atlanta Hawks', 38, 0, 3),
                    (10, '2018-10-25', 'Chicago Bulls', 32, 13, 4),
                    (10, '2018-10-27', 'Houston Rockets', 3, 15, 8),
                    (10, '2018-10-30', 'Milwaukee Bucks', 3, 12, 4),
                    (10, '2018-11-01', 'Houston Rockets', 3, 0, 5),
                    (10, '2018-11-13', 'Miami Heat', 6, 15, 2),
                    (10, '2018-11-20', 'Philadelphia 76ers', 22, 14, 4),
                    (10, '2018-11-24', 'Atlanta Hawks', 16, 5, 7),
                    (30, '2018-10-17', 'Boston Celtics', 36, 13, 7),
                    (30, '2018-10-18', 'LA Clippers', 19, 8, 0),
                    (30, '2018-10-19', 'Washington Wizards', 23, 2, 9),
                    (30, '2018-10-20', 'Toronto Raptors', 33, 10, 3),
                    (30, '2018-10-24', 'New Orleans Pelicans', 4, 4, 1),
                    (30, '2018-10-25', 'Orlando Magic', 3, 9, 5),
                    (30, '2018-10-27', 'Detroit Pistons', 37, 0, 10),
                    (30, '2018-10-30', 'Milwaukee Bucks', 24, 11, 5),
                    (30, '2018-11-06', 'Detroit Pistons', 10, 15, 5),
                    (30, '2018-11-10', 'Philadelphia 76ers', 12, 14, 4),
                    (30, '2018-11-12', 'Denver Nuggets', 31, 0, 6),
                    (30, '2018-11-17', 'Washington Wizards', 14, 5, 6),
                    (30, '2018-11-22', 'Cleveland Cavaliers', 39, 8, 4),
                    (30, '2018-11-25', 'Dallas Mavericks', 26, 11, 11);





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
        AND p.Numero_Stagione = 2019
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
ORDER BY st.Totale_Triple_Doppie DESC;

-- QUERY 8 : Classifica degli N giocatori (numero scelto dall'utente) che hanno accumulato più punti in carriera
    -- specificando in quante partite hanno giocato

SELECT ms.Nome, ms.Cognome, COUNT(DISTINCT ap.Data_Partita) AS Partite_Giocate, SUM(ap.Punti) AS Totale_Punti
FROM Analisi_Partita ap
JOIN Membro_Squadra ms ON ap.ID_Membro = ms.ID_Membro
WHERE ms.Qualifica = 'Giocatore'
GROUP BY ms.ID_Membro, ms.Nome, ms.Cognome
ORDER BY Totale_Punti DESC, Partite_Giocate ASC
LIMIT 2;