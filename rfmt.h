typedef struct
{
    int   tokenType;
    char *value;
    int   intValue;
} node;

typedef struct
{
    int   tokenType;
    char *name;
    node *value;
} field;


typedef struct listCell
{
    node            *payload;
    struct listCell *next;
} listCell;

typedef struct
{
    int       tokenType;
    int       length;
    listCell *head;
    listCell *tail;
} list;
