#define PG_USER "postgres"
#define PG_PASS "password"
#define PG_DB "NBA"
#define PG_HOST "localhost"
#define PG_PORT 5432

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "include/libpq-fe.h"
#include "funzioni.h"

int main() {
    char conninfo[256];

    char c = '0';
    printf("si intendono modificare i parametri del database? digitare [Y/y] per sì o qualsiasi altro tasto per no: ");
    scanf(" %c", &c);
    while (getchar() != '\n');
    
    if(c != 'Y' && c != 'y'){
        sprintf(conninfo, "user=%s password=%s dbname=%s host=%s port=%d", PG_USER, PG_PASS, PG_DB, PG_HOST, PG_PORT);
    }else{
        char user[64];
        char password[64];
        char database[64];
        char host[64];
        int porta;

        printf("inserire nome user: ");
        scanf("%s", user);

        printf("inserire password: ");
        scanf("%s", password);

        printf("inserire nome del database: ");
        scanf("%s", database);

        printf("inserire nome dell'host: ");
        scanf("%s", host);

        printf("inserire la porta: ");
        scanf("%d", &porta);

        sprintf(conninfo, "user=%s password=%s dbname=%s host=%s port=%d", user, password, database, host, porta); 
    }   

    PGconn *conn = PQconnectdb(conninfo);

    if (!checkConn(conn)){
        return 1;
    }

    printf("\033[1;32m\nConnessione al DataBase avvenuta con successo!\033[0m\n\n\n");

    char x;
while (true) {
    printf("\n\033[1;33mScegliere una operazione digitandone il numero corrispondente, digitare [X/x] per interrompere il programma\033[0m\n\n");
    printList();
    
    char input[16];
    if (!fgets(input, sizeof(input), stdin)) {
        // errore di input (es. EOF)
        clearerr(stdin);
        continue;
    }

    // Se input troppo lungo, pulisci il buffer
    if (strchr(input, '\n') == NULL) {
        int c;
        while ((c = getchar()) != '\n' && c != EOF);  // svuota buffer
        printf("\033[1;31m\nInput troppo lungo: inserire un solo numero da 1 a 8\033[0m \n");
        continue;
    }

    if (input[0] == '\n') {
        printf("\033[2J\033[H");
        continue; // solo invio, ignora
    }

    x = input[0];

    if (input[1] != '\n') {
        printf("\033[2J\033[H");
        printf("\033[1;31m\nInput non valido: inserire un solo carattere (1-8 o x)\033[0m \n");
        continue;
    }

    if (x == 'x' || x=='X') break;

    int query = x - '0';
    SelezioneQuery(conn, query);
}
    
    PQfinish(conn);
    printf("\n\033[1;32m\nDisconnessione dal DataBase avvenuta con successo!\033[0m\n");
}