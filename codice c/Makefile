# Compilatore
CC = gcc

# Directory delle librerie e degli header
INCLUDES = -Iinclude
LIBS = -Llib -lpq

# Flag di compilazione
CFLAGS = -Wall -g $(INCLUDES)

# Sorgenti e oggetti
SRC = basi.c funzioni.c
OBJ = $(SRC:.c=.o)

# Output
TARGET = database

# Regole
all: $(TARGET)

$(TARGET): $(OBJ)
	$(CC) -o $@ $^ $(LIBS)

%.o: %.c
	$(CC) $(CFLAGS) -c $< -o $@

clean:
	rm -f $(OBJ) $(TARGET)

run: all
	clear
	./$(TARGET)

.PHONY: all clean run