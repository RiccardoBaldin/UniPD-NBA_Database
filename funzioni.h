#ifndef FUNZIONI_H
#define FUNZIONI_H

#include "dependencies/include/libpq-fe.h"
#include <stdio.h>
#include <stdbool.h>

void printList();
bool checkConn(PGconn*);
void checkResults(PGresult*, const PGconn*);

void printResults(const PGresult*);

void SelezioneQuery(PGconn*, int);

void Query1(PGconn*);
void Query2(PGconn*);
void Query3(PGconn*);
void Query4(PGconn*);
void Query5(PGconn*);
void Query6(PGconn*);
void Query7(PGconn*);
void Query8(PGconn*);

#endif //FUNZIONI_H