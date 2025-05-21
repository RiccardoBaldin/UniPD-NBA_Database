#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "funzioni.h"
#include "dependencies/include/libpq-fe.h"


void checkResults(PGresult *res, const PGconn *conn){
    if(PQresultStatus(res) != PGRES_TUPLES_OK){
        printf("Risultati inconsistenti %s\n", PQerrorMessage(conn));
        PQclear(res);
        exit(1);
    }
}

bool checkConn(PGconn* conn){
    if(PQstatus(conn) != CONNECTION_OK){
        printf("Errore di connessione: %s\n", PQerrorMessage(conn));
        PQfinish(conn);
        return false;
    }
    return true;
}

void printList(){
    printf("\033[1;33mQuery 1\033[0m: Classifica delle prime 5 squadre della stagione, in base all' anno inserito dall'utente\n");
    printf("\033[1;33mQuery 2\033[0m: Giocatore (o giocatori in caso di parità) che ha collezionato più premi in tutta sua la carriera\n");
    printf("\033[1;33mQuery 3\033[0m: Giocatore (o giocatori in caso di parità) che ha collezionato più premi dello stesso tipo (scelto da utente tra i disponibili)\n");
    printf("\033[1;33mQuery 4\033[0m: Squadre che hanno più giocatori con x premi (numero scelto da utente)\n");
    printf("\033[1;33mQuery 5\033[0m: Giocatore che ha firmato il maggior numero di contratti negli ultimi vent'anni, e numero di squadre con le quali ha firmato\n");
    printf("\033[1;33mQuery 6\033[0m: Tra due squadre, scelte dall'utente, restituire la data della partita degli ultimi venti anni con più grande distacco di punti tra le due squadre e lo stadio in cui è stata giocata\n");
    printf("\033[1;33mQuery 7\033[0m: Squadre con giocatori che nell'anno selezionato dall'utente, hanno collezionato più triple-doppie"
    " (= punti >= 10, rimbalzi >= 10 e assist >= 10). Stampa anche il numero di triple-doppie e il giocatore che ne ha collezionate di più per ogni squadra\n");
    printf("\033[1;33mQuery 8\033[0m: Classifica degli N giocatori (numero scelto dall'utente) che hanno accumulato più punti in carriera specificando in quante partite hanno giocato\n");
}

void printResults(const PGresult* result) {
    int tuple = PQntuples(result);
    int campi = PQnfields(result);

    if(tuple == 0){
        printf("\033[1;31m\nDATI ASSENTI NEL DATABASE PER LA SCELTA ESEGUITA DALL'UTENTE :(\n\033[0m");
        return;
    }
    printf("\n");

    int widths[campi];

    // Calcola larghezza massima per ogni colonna
    for (int j = 0; j < campi; j++) {
        int max_width = strlen(PQfname(result, j));
        for (int i = 0; i < tuple; i++) {
            int len = strlen(PQgetvalue(result, i, j));
            if (len > max_width) {
                max_width = len;
            }
        }
        widths[j] = max_width + 3;
    }

    // Stampa intestazioni
    for (int j = 0; j < campi; j++) {
        if(j != 0) printf("┃ ");
        printf("%-*s", widths[j], PQfname(result, j));
    }
    printf("\n");
    printf("\n");

    // Stampa valori
    for (int i = 0; i < tuple; i++) {
        for (int j = 0; j < campi; j++) {
            if(j != 0) printf("┃ ");
            printf("%-*s", widths[j], PQgetvalue(result, i, j));
        }
        printf("\n");
    }
}

void SelezioneQuery(PGconn* conn, int x){
    printf("\033[2J\033[H");
    switch (x)
    {
    case 1:
        Query1(conn);
        break;
    case 2:
        Query2(conn);
        break;
    case 3:
        Query3(conn);
        break;
    case 4:
        Query4(conn);
        break;
    case 5:
        Query5(conn);
        break;
    case 6:
        Query6(conn);
        break;
    case 7:
        Query7(conn);
        break;
    case 8:
        Query8(conn);
        break;
    default:
        break;
    }
}

void Query1(PGconn* conn){
    printf("\033[1;32m\nselezionata la query 1!\n\033[0m");
    
    const char* parametri[1];
    char anno[16];
    int anno_int;

    printf("inserire l'anno di cui si vuole conoscere la classifica: ");
    fgets(anno, sizeof(anno), stdin);
    anno_int = atoi(anno);
    while(anno_int < 2005 || anno_int > 2025) {
        printf("anno non disponibile, inserirne uno compreso tra 2005 e 2025 -> ");
        fgets(anno, sizeof(anno), stdin);
        anno_int = atoi(anno);
    }

    char anno_str[8];
    snprintf(anno_str, sizeof(anno_str), "%d", anno_int);
    parametri[0] = anno_str;

    const char *query =
    "WITH Statistiche AS ( "
    "  SELECT "
    "    s.Nome_Squadra, "
    "    SUM(CASE "
    "          WHEN (p.Vincitore = TRUE AND p.Squadra_Casa = s.Nome_Squadra) OR "
    "               (p.Vincitore = FALSE AND p.Squadra_Ospiti = s.Nome_Squadra) "
    "          THEN 1 ELSE 0 "
    "        END) AS Vittorie, "
    "    SUM(CASE "
    "          WHEN (p.Vincitore = FALSE AND p.Squadra_Casa = s.Nome_Squadra) OR "
    "               (p.Vincitore = TRUE AND p.Squadra_Ospiti = s.Nome_Squadra) "
    "          THEN 1 ELSE 0 "
    "        END) AS Sconfitte "
    "  FROM Partita p "
    "  JOIN Squadra s ON s.Nome_Squadra = p.Squadra_Casa OR s.Nome_Squadra = p.Squadra_Ospiti "
    "  WHERE p.Numero_Stagione = $1 "
    "  GROUP BY s.Nome_Squadra "
    ") "
    "SELECT "
    "  Nome_Squadra, "
    "  CASE "
    "    WHEN (Vittorie + Sconfitte) = 0 THEN NULL "
    "    ELSE ROUND(CAST(Vittorie AS numeric) / (Vittorie + Sconfitte), 3) "
    "  END AS Rapporto_Vittorie_Partite, "
    "  Vittorie, "
    "  Sconfitte "
    "FROM Statistiche "
    "ORDER BY Rapporto_Vittorie_Partite DESC "
    "LIMIT 5; ";

    PGresult *res = PQprepare(conn, "query1", query, 1, NULL);

    res = PQexecPrepared(conn , "query1" , 1 , parametri , NULL , 0 , 0);
    checkResults(res, conn);
    printResults(res);
    PQclear(res);
}

void Query2(PGconn* conn){
    printf("\033[1;32m\nselezionata la query 2!\n\033[0m");
    const char *query = 
"    SELECT ms.Nome, ms.Cognome, COUNT(*) AS Numero_Premi "
"FROM Premio pr "
"JOIN Membro_Squadra ms ON pr.ID_Membro = ms.ID_Membro "
"WHERE ms.Qualifica = 'Giocatore' "
"GROUP BY ms.ID_Membro, ms.Nome, ms.Cognome "
"HAVING COUNT(*) = ( "
"    SELECT MAX(Numero_Premi) FROM ( "
"        SELECT COUNT(*) AS Numero_Premi "
"        FROM Premio pr "
"        JOIN Membro_Squadra ms ON pr.ID_Membro = ms.ID_Membro "
"        WHERE ms.Qualifica = 'Giocatore' "
"        GROUP BY ms.ID_Membro "
"    ) AS Premi_Giocatori "
"); ";

    PGresult *res;
    res = PQexec(conn, query);
    checkResults(res, conn);
    printResults(res);
    PQclear(res);
}

void Query3(PGconn* conn){
    printf("\033[1;32m\nselezionata la query 3!\n\033[0m");

    const char* premi[] = {"MVP","All-NBA Team", "NBA All-Defensive Team"};
    int num_premi = sizeof(premi) / sizeof(premi[0]);

    const char* parametri[1];
    int scelta;

    printf("Lista dei premi disponibili:\n");
    for(int i=0 ; i < num_premi ; i++){
        printf(" %d) %s\n", i+1,premi[i]);
    }

    printf("Inserire il numero del premio: ");
    scanf("%d", &scelta);
    getchar();

    while(scelta < 1 || scelta > num_premi){
        printf("Scelta non valida. Reinserire: ");
        scanf("%d", &scelta);
        getchar();
    }

    parametri[0] = premi[scelta-1];

    const char *query =
    "SELECT ms.Nome, ms.Cognome, COUNT(*) AS Premio_individuale "
    "FROM Premio pr "
    "JOIN Membro_Squadra ms ON pr.ID_Membro = ms.ID_Membro "
    "WHERE ms.Qualifica = 'Giocatore' "
    "AND pr.Nome_Premio = $1::premio_enum "
    "GROUP BY ms.ID_Membro, ms.Nome, ms.Cognome "
    "HAVING COUNT(*) = ( "
    "SELECT MAX(Premio_individuale) FROM ( "
    "SELECT COUNT(*) AS Premio_individuale "
    "FROM Premio pr "
    "JOIN Membro_Squadra ms ON pr.ID_Membro = ms.ID_Membro "
    "WHERE ms.Qualifica = 'Giocatore' "
    "AND pr.Nome_Premio = $1::premio_enum "
    "GROUP BY ms.ID_Membro "
    ") AS Premio_individuale "
    "); ";

    PGresult *res = PQprepare(conn, "query3", query, 1, NULL);

    res = PQexecPrepared(conn, "query3", 1, parametri, NULL, 0, 0);
    checkResults(res, conn);
    printResults(res);
    PQclear(res);
}

void Query4(PGconn* conn){
    printf("\033[1;32m\nselezionata la query 4!\n\033[0m");

    const char* parametri[1];
    int scelta;

    printf("Inserire il numero del premio: ");
    scanf("%d", &scelta);
    getchar();

    while(scelta < 1){
        printf("Scelta non valida. Inserire un numero maggiore di 0: ");
        scanf("%d", &scelta);
        getchar();
    }

    char scelta_str[4];
    snprintf(scelta_str, sizeof(scelta_str), "%d", scelta);

    parametri[0] = scelta_str;

    const char *query = 
    "    WITH Giocatori_Con_X_Premi AS ( "
    "    SELECT ID_Membro "
    "    FROM Premio "
    "    GROUP BY ID_Membro "
    "    HAVING COUNT(*) >= $1 "
    "), "
    " "
    "Giocatori_Squadre AS ( "
    "    SELECT DISTINCT c.Nome_Squadra, c.ID_Membro "
    "    FROM Contratto c "
    "    JOIN Giocatori_Con_X_Premi g ON g.ID_Membro = c.ID_Membro "
    "), "
    " "
    "Squadre_Con_Conteggio AS ( "
    "    SELECT gs.Nome_Squadra, COUNT(*) AS Giocatori_Con_Premi "
    "    FROM Giocatori_Squadre gs "
    "    GROUP BY gs.Nome_Squadra "
    "), "
    " "
    "Max_Valore AS ( "
    "    SELECT MAX(Giocatori_Con_Premi) AS Max_Premi "
    "    FROM Squadre_Con_Conteggio "
    ") "
    " "
    "SELECT s.Nome_Squadra, s.Giocatori_Con_Premi "
    "FROM Squadre_Con_Conteggio s "
    "JOIN Max_Valore m ON s.Giocatori_Con_Premi = m.Max_Premi; ";

    PGresult *res = PQprepare(conn, "query4", query, 1, NULL);

    res = PQexecPrepared(conn, "query4", 1, parametri, NULL, 0, 0);
    checkResults(res, conn);
    printResults(res);
    PQclear(res);

}

void Query5(PGconn* conn){
    printf("\033[1;32m\nselezionata la query 5!\n\033[0m");
    const char *query = 
    "SELECT ms.Nome, ms.Cognome, COUNT(*) AS Numero_Contratti, COUNT(DISTINCT c.Nome_Squadra) AS Squadre_Diverse "
    "FROM Contratto c "
    "JOIN Membro_Squadra ms ON c.ID_Membro = ms.ID_Membro "
    "WHERE ms.Qualifica = 'Giocatore' "
    "GROUP BY ms.ID_Membro, ms.Nome, ms.Cognome "
    "HAVING COUNT(*) = ( "
    "SELECT MAX(Numero_Contratti) FROM ( "
    "    SELECT COUNT(*) AS Numero_Contratti "
    "    FROM Contratto c JOIN Membro_Squadra ms ON c.ID_Membro = ms.ID_Membro "
    "    WHERE ms.Qualifica = 'Giocatore' "
	"	GROUP BY ms.ID_Membro "
    ") AS Numero_Contratti "
    "); ";


    PGresult *res;
    res = PQexec(conn, query);
    checkResults(res, conn);
    printResults(res);
    PQclear(res);
}

void Query6(PGconn* conn){
    printf("\033[1;32m\nselezionata la query 6!\n\033[0m");

    const char* squadre[] = {
        "Atlanta Hawks", "Boston Celtics", "Brooklyn Nets", "Charlotte Hornets", "Chicago Bulls",
        "Cleveland Cavaliers", "Dallas Mavericks", "Denver Nuggets", "Detroit Pistons", "Golden State Warriors",
        "Houston Rockets", "Indiana Pacers", "LA Clippers", "Los Angeles Lakers", "Memphis Grizzlies",
        "Miami Heat", "Milwaukee Bucks", "Minnesota Timberwolves", "New Orleans Pelicans", "New York Knicks",
        "Oklahoma City Thunder", "Orlando Magic", "Philadelphia 76ers", "Phoenix Suns", "Portland Trail Blazers",
        "Sacramento Kings", "San Antonio Spurs", "Toronto Raptors", "Utah Jazz", "Washington Wizards"
    };
    int num_squadre = sizeof(squadre) / sizeof(squadre[0]);

    const char* parametri[2];
    int scelta1 = -1, scelta2 = -1;

    printf("\n\033[1;33mLista delle squadre di NBA:\033[0m\n\n");
    for(int i=0 ; i < num_squadre ; i++){
        printf(" %2d) %s\n", i+1, squadre[i]);
    }

    printf("\n\033[1;33mInserire il numero della prima squadra: \033[0m");
    scanf("%d", &scelta1);
    getchar();

    while(scelta1 < 1 || scelta1 > num_squadre){
        printf("\033[1;31m\nScelta non valida. Reinserire: \033[0m");
        scanf("%d", &scelta1);
        getchar();
    }
    printf("\033[2J\033[H");
    printf("\n\033[1;33mLista delle squadre di NBA:\033[0m\n\n");
    for(int i=0 ; i < num_squadre ; i++){
        printf(" %2d) %s\n", i+1, squadre[i]);
    }

    printf("\n\033[1;33mInserire il numero della seconda squadra: \033[0m");
    scanf("%d", &scelta2);
    getchar();

    while(scelta2 < 1 || scelta2 > num_squadre || scelta1 == scelta2){
        printf("\033[1;31m\nScelta non valida o uguale alla prima. Reinserire: \033[0m");
        scanf("%d", &scelta2);
        getchar();
    }

    parametri[0] = squadre[scelta1-1];
    parametri[1] = squadre[scelta2-1];

    const char* query = 
    "SELECT  "
    "p.Data_Partita, "
    "ABS(p.Punteggio_Casa - p.Punteggio_Ospiti) AS Distacco, "
    "CASE  "
    "    WHEN p.Punteggio_Casa > p.Punteggio_Ospiti THEN p.Squadra_Casa "
    "    ELSE p.Squadra_Ospiti "
    "END AS Squadra_Vincente, "
	"sq.Nome_Stadio "
    "FROM Partita p "
    "JOIN Squadra sq ON p.Squadra_Casa = sq.Nome_Squadra "
    "WHERE ( "
    "(p.Squadra_Casa = $1 AND p.Squadra_Ospiti = $2) OR "
    "(p.Squadra_Casa = $2 AND p.Squadra_Ospiti = $1) "
    ") "
    "AND p.Data_Partita >= CURRENT_DATE - INTERVAL '20 years' "
    "AND ABS(p.Punteggio_Casa - p.Punteggio_Ospiti) = ( "
    "SELECT MAX(ABS(p2.Punteggio_Casa - p2.Punteggio_Ospiti)) "
    "FROM Partita p2 "
    "WHERE ( "
    "    (p2.Squadra_Casa = $1 AND p2.Squadra_Ospiti = $2) OR "
    "    (p2.Squadra_Casa = $2 AND p2.Squadra_Ospiti = $1) "
    ") "
    "AND p2.Data_Partita >= CURRENT_DATE - INTERVAL '20 years' "
    "); ";

    PGresult *res = PQprepare(conn, "query6", query, 2, NULL);

    res = PQexecPrepared(conn, "query6", 2, parametri, NULL, 0, 0);
    checkResults(res, conn);
    printResults(res);
    PQclear(res);
}

void Query7(PGconn* conn){
    printf("\033[1;32m\nselezionata la query 7!\n\033[0m");

    const char* parametri[1];
    char anno[16];
    int anno_int;

    printf("inserire l'anno di cui si vogliono conoscere le squadre con giocatori eccezionali: ");
    fgets(anno, sizeof(anno), stdin);
    anno_int = atoi(anno);
    while(anno_int < 2005 || anno_int > 2025) {
        printf("anno non disponibile, inserirne uno compreso tra 2005 e 2025 -> ");
        fgets(anno, sizeof(anno), stdin);
        anno_int = atoi(anno);
    }

    char anno_str[8];
    snprintf(anno_str, sizeof(anno_str), "%d", anno_int);
    parametri[0] = anno_str;


    const char *query = 
    "    WITH TripleDoppie AS ( "
    "    SELECT  "
    "        ap.ID_Membro, "
    "        p.Numero_Stagione, "
    "        c.Nome_Squadra, "
    "        COUNT(*) AS Num_Triple_Doppie "
    "    FROM Analisi_Partita ap "
    "    JOIN Partita p  "
    "        ON ap.Data_Partita = p.Data_Partita AND ap.Squadra_Casa = p.Squadra_Casa "
    "    JOIN Contratto c  "
    "        ON ap.ID_Membro = c.ID_Membro  "
    "        AND p.Data_Partita BETWEEN c.Inizio_Contratto AND c.Fine_Contratto "
    "    WHERE  "
    "        ((ap.Punti >= 10)::int + "
    "         (ap.Rimbalzi >= 10)::int + "
    "         (ap.Assist >= 10)::int) >= 3 "
    "        AND p.Numero_Stagione = $1  "
    "    GROUP BY ap.ID_Membro, p.Numero_Stagione, c.Nome_Squadra "
    "), "
    " "
    "SquadraTriple AS ( "
    "    SELECT  "
    "        Nome_Squadra, "
    "        SUM(Num_Triple_Doppie) AS Totale_Triple_Doppie "
    "    FROM TripleDoppie "
    "    GROUP BY Nome_Squadra "
    "), "
    " "
    "TopGiocatori AS ( "
    "    SELECT  "
    "        td.Nome_Squadra, "
    "        ms.Nome || ' ' || ms.Cognome AS Giocatore, "
    "        td.Num_Triple_Doppie, "
    "        ROW_NUMBER() OVER (PARTITION BY td.Nome_Squadra ORDER BY td.Num_Triple_Doppie DESC) AS rn "
    "    FROM TripleDoppie td "
    "    JOIN Membro_Squadra ms ON td.ID_Membro = ms.ID_Membro "
    ") "
    " "
    "SELECT  "
    "    st.Nome_Squadra, "
    "    st.Totale_Triple_Doppie, "
    "    tg.Giocatore, "
    "    tg.Num_Triple_Doppie AS Triple_Doppie_Giocatore "
    "FROM SquadraTriple st "
    "JOIN TopGiocatori tg  "
    "    ON st.Nome_Squadra = tg.Nome_Squadra AND tg.rn = 1 "
    "ORDER BY st.Totale_Triple_Doppie DESC; ";

    PGresult *res = PQprepare(conn, "query7", query, 1, NULL);

    res = PQexecPrepared(conn , "query7" , 1 , parametri , NULL , 0 , 0);
    checkResults(res, conn);
    printResults(res);
    PQclear(res);
}

void Query8(PGconn* conn){
    printf("\033[1;32m\nselezionata la query 8!\n\033[0m");

    const char* parametri[1];
    int scelta;

    printf("Inserire il numero di giocatori ai quali si è interessati: ");
    scanf("%d", &scelta);
    getchar();

    while(scelta < 1){
        printf("Scelta non valida. Inserire un numero maggiore di 0: ");
        scanf("%d", &scelta);
        getchar();
    }

    char scelta_str[4];
    snprintf(scelta_str, sizeof(scelta_str), "%d", scelta);

    parametri[0] = scelta_str;

    const char* query =
    "SELECT ms.Nome, ms.Cognome, COUNT(DISTINCT ap.Data_Partita) AS Partite_Giocate, SUM(ap.Punti) AS Totale_Punti "
    "FROM Analisi_Partita ap "
    "JOIN Membro_Squadra ms ON ap.ID_Membro = ms.ID_Membro "
    "WHERE ms.Qualifica = 'Giocatore' "
    "GROUP BY ms.ID_Membro, ms.Nome, ms.Cognome "
    "ORDER BY Totale_Punti DESC, Partite_Giocate ASC "
    "LIMIT $1; ";

    PGresult *res = PQprepare(conn, "query8", query, 1, NULL);

    res = PQexecPrepared(conn, "query8", 1, parametri, NULL, 0, 0);
    checkResults(res, conn);
    printResults(res);
    PQclear(res);
}