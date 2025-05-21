#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <dirent.h>
#include <cjson/cJSON.h>

#define MAX_PATH 256
#define MAX_TEAM_NAME 100
#define MAX_TEAMS 32
#define FOLDER_PATH "/Users/riccardobaldin/Desktop/UNIVERSITA/BASI/creation_insert"
#define SEASON 2024

char *ignored_teams[MAX_TEAMS];
int ignored_teams_count = 0;

// Sposta questo in cima al file
void format_date(const char *input, char *output, size_t output_size) {
    strncpy(output, input, 10);
    output[10] = '\0';
}

// Aggiunge una squadra alla blacklist
void add_ignored_team(const char *team_name) {
    if (ignored_teams_count < MAX_TEAMS) {
        ignored_teams[ignored_teams_count] = strdup(team_name);
        ignored_teams_count++;
    }
}

// Controlla se una squadra è già nella blacklist
int is_ignored_team(const char *team_name) {
    for (int i = 0; i < ignored_teams_count; ++i) {
        if (strcmp(team_name, ignored_teams[i]) == 0) {
            return 1;
        }
    }
    return 0;
}

// Estrae il nome squadra dal nome file
void extract_team_name(const char *filename, char *team_name) {
    strncpy(team_name, filename, MAX_TEAM_NAME - 1);
    team_name[MAX_TEAM_NAME - 1] = '\0';
    char *dot = strrchr(team_name, '.');
    if (dot != NULL) *dot = '\0';  // rimuove ".json"
}

int main() {
    DIR *dir;
    struct dirent *entry;

    if ((dir = opendir(FOLDER_PATH)) == NULL) {
        perror("opendir");
        return 1;
    }

    FILE *sql_output = fopen(FOLDER_PATH "/output.sql", "w");
    if (sql_output == NULL) {
        perror("fopen output.sql");
        closedir(dir);
        return 1;
    }

    fprintf(sql_output, "INSERT INTO Partita (Data_Partita, Squadra_Casa, Squadra_Ospiti, Punteggio_Casa, Punteggio_Ospiti, Numero_Stagione) VALUES\n");

    while ((entry = readdir(dir)) != NULL) {
        if (strstr(entry->d_name, ".json") == NULL) continue;

        char file_path[MAX_PATH];
        snprintf(file_path, sizeof(file_path), "%s/%s", FOLDER_PATH, entry->d_name);

        char current_team[MAX_TEAM_NAME];
        extract_team_name(entry->d_name, current_team);

        FILE *fp = fopen(file_path, "r");
        if (fp == NULL) {
            perror("fopen");
            continue;
        }

        char buffer[20000];
        size_t len = fread(buffer, 1, sizeof(buffer) - 1, fp);
        buffer[len] = '\0';
        fclose(fp);

        cJSON *matches = cJSON_Parse(buffer);
        if (matches == NULL || !cJSON_IsArray(matches)) {
            fprintf(stderr, "Invalid JSON in file: %s\n", file_path);
            continue;
        }

        fprintf(sql_output, "-- File: %s\n", entry->d_name);

        int match_count = cJSON_GetArraySize(matches);
        int insert_count = 0;

        for (int i = 0; i < match_count; ++i) {
            cJSON *match = cJSON_GetArrayItem(matches, i);
            if (!cJSON_IsObject(match)) continue;

            cJSON *date = cJSON_GetObjectItemCaseSensitive(match, "DateUtc");
            cJSON *home = cJSON_GetObjectItemCaseSensitive(match, "HomeTeam");
            cJSON *away = cJSON_GetObjectItemCaseSensitive(match, "AwayTeam");
            cJSON *score_home = cJSON_GetObjectItemCaseSensitive(match, "HomeTeamScore");
            cJSON *score_away = cJSON_GetObjectItemCaseSensitive(match, "AwayTeamScore");

            if (!cJSON_IsString(date) || !cJSON_IsString(home) || !cJSON_IsString(away) ||
                !cJSON_IsNumber(score_home) || !cJSON_IsNumber(score_away)) {
                continue;
            }

            // Salta se la squadra di casa o ospite è già nella blacklist
            if (is_ignored_team(home->valuestring) || is_ignored_team(away->valuestring)) {
                continue;
            }

            char formatted_date[11];
            format_date(date->valuestring, formatted_date, sizeof(formatted_date));

            fprintf(sql_output, "('%s', '%s', '%s', %d, %d, %d)%s\n",
                   formatted_date,
                   home->valuestring,
                   away->valuestring,
                   score_home->valueint,
                   score_away->valueint,
                   SEASON,
                   (insert_count == match_count - 1) ? ";" : ",");

            insert_count++;
        }

        cJSON_Delete(matches);

        // Aggiungi squadra corrente alla blacklist
        add_ignored_team(current_team);
    }

    closedir(dir);

    // Libera memoria allocata
    for (int i = 0; i < ignored_teams_count; ++i) {
        free(ignored_teams[i]);
    }

    fclose(sql_output);

    return 0;
}