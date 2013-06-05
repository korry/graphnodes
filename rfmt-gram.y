%{
#include <stdio.h>
#include <stdlib.h>
#include <stdbool.h>
#include <memory.h>
#include "rfmt.h"
#include "rfmt-gram.h"
#include <getopt.h>

typedef struct
{
	int		byteCount;
	char   *bits;
} bitmap;

typedef struct
{
	char	   *title;			/* Graph title (typically the text of a query/command)   */
	bool		numberNodes;	/* TRUE -> include numbers in each node					 */
	int			truncateTo;		/* Maximum string length to dump (longer strings elided) */
	bool		skipNulls;		/* Omit NULL pointers from graph?						 */
	int			maxStringList;	/* Maximum number of strings to print in a string list   */
	int			onlyBranch;		/* If non-zero, only graph descendents of this branch	 */
	node       *hilights;		/* Nodes to highlight							 		 */
	node	   *annotations;	/* Nodes to annotate									 */
	const char *hilightColor;	/* Color spec to use to highlight nodes					 */
} cmdLine;

static cmdLine options;

typedef struct
{
	FILE	*file;				/* Output file descriptor							     */
	int		 id;				/* Next node id										     */
	cmdLine *options;			/* Command-line options									 */
	bool     graph;				/* TRUE means graph this node (and descendents)			 */

} dumpCtx;

int main(int argc, char *argv[]);

static void     yyerror(char *msg);
static node	   *makeNode(int tokenType, char *value);
static field   *makeField(int tokenType, char *name, node *value);
static node	   *makeList(int tokenType, node *node);
static dumpCtx *makeDumpCtx(void);
static node	   *listAppend(node *cur, node *newNode);
static node	   *addListCell(list *list, node *payload);
static void		dumpBranch(dumpCtx *ctx, node *node);
static int		dumpNode(dumpCtx *ctx, node *nodePtr);
static int		graphNode(dumpCtx *ctx, node *nodePtr, int myID);
static void		dumpTree(dumpCtx *ctx, node *nodePtr);
static char    *escape(const dumpCtx *ctx, const char *in, int truncateTo);
static char    *stringConcat(const char *str1, const char *str2, const char *str3);
static bitmap  *parseHilights(const char *list);

%}

%union
{
	char  *strval;
	node  *nodeval;
	field *fieldval;
}

%token T_NODE_BEG 
%token T_NODE_END
%token T_LIST_BEG
%token T_LIST_END
%token <strval> T_STRING T_FIELDNAME T_IDENT T_NUMBER T_NULLPOINTER T_ENCODED_LITERAL

%type <nodeval>  value values node fields list opt_fields
%type <fieldval> field

%debug
%error-verbose
%output = "rfmt-gram.c"

%%

tree:		node
            {
				dumpTree(makeDumpCtx(), $1);
			};

node:		T_NODE_BEG T_IDENT opt_fields T_NODE_END
            {
				$$ = (node *)makeField(T_NODE_BEG, $2, $3);
			};

opt_fields: fields
            {
				$$ = $1;
			}
            | /* EMPTY */
            {
				$$ = NULL;
			};

fields:		fields field
            {
				$$ = listAppend($1, (node *)$2);
			}
            | field
            {
				$$ = makeList(T_LIST_BEG, (node *)$1);
			};
			
field:		T_FIELDNAME value
            {
				$$ = makeField(T_FIELDNAME, $1, $2);
			};

value:		list
            {

			}
            | T_NUMBER 
            {
				$$ = makeNode(T_NUMBER, $1);

			}
            | T_NUMBER T_ENCODED_LITERAL
            {
				$$ = makeNode(T_NUMBER, stringConcat( $1, " ", $2));

			}
            | T_STRING
			{
				$$ = makeNode(T_STRING, $1);
			}
            | node
			{
				$$ = $1;
			}	
            | T_IDENT
			{
				$$ = makeNode(T_IDENT, $1);
			}
            | T_NULLPOINTER
            {
				$$ = makeNode(T_NULLPOINTER, $1);
			};

values:		values value
            {
				$$ = listAppend($1, $2);
			}
            | value
            {
				$$ = makeList(T_LIST_BEG, $1);
			};

list:       T_LIST_BEG values T_LIST_END
            {
				$$ = $2;
			};

%%

extern void scanner_init(const char *src);

static void yyerror(char *msg)
{
	fprintf(stderr, "%s\n", msg);
}

static node *makeNode(int tokenType, char *value)
{
	node *result = malloc(sizeof(*result));

	result->tokenType = tokenType;
	result->value     = value;

	return result;
}

static field *makeField(int tokenType, char *name, node *value)
{
	field *result = malloc(sizeof(*result));

	result->tokenType = tokenType;
	result->value     = value;

	if (name[0] == ':')
		result->name = name + 1;
	else
		result->name = name;

	return result;
}

static node *makeList(int tokenType, node *payload)
{
	if (payload == NULL)
		return NULL;
	else
	{
		list	 *result = (list *)malloc(sizeof(*result));
		listCell *cell	 = (listCell *)malloc(sizeof(*cell));
		
		cell->payload = payload;
		cell->next    = NULL;

		result->tokenType = tokenType;
		result->head	  = cell;
		result->tail	  = cell;
		result->length	  = 1;
		
		return (node *)result;
	}
}

static node	 *listAppend(node *cur, node *payload)
{
	if (payload == NULL)
		return cur;
	else if (cur == NULL)
		return makeList(T_LIST_BEG, payload);
	else
		return addListCell((list *)cur, payload);
}

static node *addListCell(list *list, node *payload)
{
	listCell *newTail = (listCell *)malloc(sizeof(*newTail));

	newTail->next = NULL;
	newTail->payload = payload;

	list->tail->next = newTail;
	list->tail       = newTail;

	list->length++;

	return (node *)list;
}

static void addEdge(dumpCtx *ctx, char *fromField, int fromID, char *fromCompass, char *toField, int toID)
{
	if (ctx->graph)
		fprintf(ctx->file, "node_%d:%s:%s -> node_%d:%s;\n", fromID, fromField, fromCompass, toID, toField);
}

static int dumpNodeList(dumpCtx *ctx, node *nodePtr)
{
	list	 *nodes       = (list *)nodePtr;
	int		  myID		  = ctx->id++;
	int		  parentID	  = myID;
	char	 *parentField = "head";
	listCell *cell;
	int		  id;

	if (ctx->graph)
	{
		if (ctx->options->numberNodes)
			fprintf(ctx->file, "  node_%d [label=\"{<f0>(%d)\\nlist|length=%d}|{<head>head|<tail>tail}\"];\n", myID, myID, nodes->length);
		else
			fprintf(ctx->file, "  node_%d [label=\"{<f0>list|length=%d}|{<head>head|<tail>tail}\"];\n", myID, nodes->length);
	}

	for (cell = nodes->head; cell != NULL; cell = cell->next)
	{
		id = dumpNode(ctx, cell->payload);

		addEdge(ctx, parentField, parentID, "s", "f0", id);

		parentID	= id;
		parentField = "f0";
	}

	addEdge(ctx, "tail", myID, "s", "f0", id);

	return myID;
}

static int dumpList(dumpCtx *ctx, node *nodePtr)
{
	list	 *nodes = (list *)nodePtr;
	listCell *cell  = nodes->head;

	if (cell->payload->tokenType == T_NODE_BEG)
	{
		return dumpNodeList(ctx, nodePtr);
	}
	else if (cell->payload->tokenType == T_LIST_BEG)
	{
		int	myID = 0;

		for (cell = nodes->head; cell != NULL; cell = cell->next)
		{
			int id = dumpNodeList(ctx, cell->payload);

			if (myID == 0)
				myID = id;
		}

		return myID;
	}
	else
	{
		int	  count		= 0;
		int	  myID		= ctx->id++;
		char *delimiter = "";

		if (ctx->graph)
		{
			fprintf(ctx->file, "  node_%d [label=\"<f0>list|{", myID);

			for (cell = nodes->head; cell != NULL; cell = cell->next)
			{
				if (++count > ctx->options->maxStringList)
					break;
				else
				{
					char *value = escape(ctx, cell->payload->value, ctx->options->truncateTo);

					fprintf(ctx->file, "%s%s", delimiter, value);

					free(value);
				}
				
				delimiter = ",";
			}

			fprintf(ctx->file, "}\"];\n");
		}
		return myID;
	}
}

static const char *shouldHighlight(dumpCtx *ctx, int nodeID)
{
	if (ctx->options->hilights)
	{
		listCell *cell;

		for (cell = ((list *)(ctx->options->hilights))->head; cell != NULL; cell = cell->next)
		{
			if (nodeID == cell->payload->intValue)
				return cell->payload->value;
		}
	}

	return NULL;
}

static const char *shouldAnnotate(dumpCtx *ctx, int nodeID)
{
	if (ctx->options->annotations)
	{
		listCell *cell;

		for (cell = ((list *)(ctx->options->annotations))->head; cell != NULL; cell = cell->next)
		{
			if (nodeID == cell->payload->intValue)
				return cell->payload->value;
		}
	}

	return NULL;
}

static int dumpNode(dumpCtx *ctx, node *nodePtr)
{
	int myID = ctx->id++;

	if (ctx->options->onlyBranch == myID)
	{
		ctx->graph = true;
		graphNode(ctx, nodePtr, myID);
		ctx->graph = false;
	}
	else
	{
		graphNode(ctx, nodePtr, myID);
	}
}

static int graphNode(dumpCtx *ctx, node *nodePtr, int myID)
{
	field	   *node	  = (field *)nodePtr;
	list	   *values	  = (list *)node->value;
	listCell   *cell;
	char	   *delimiter = "";
	const char *color;
	const char *note;

	if (ctx->graph)
	{
		fprintf(ctx->file, "  node_%d [", myID);

		if ((color = shouldHighlight(ctx, myID)) != NULL)
			fprintf(ctx->file, "%s,", color);

		fprintf(ctx->file, "label=\"<f0>");
	
		if (ctx->options->numberNodes)
			fprintf(ctx->file, "(%d)\\n",myID);

		if ((note = shouldAnnotate(ctx, myID)) != NULL)
			fprintf(ctx->file, "%s\\n%s|{", node->name, note);
		else
		    fprintf(ctx->file, "%s|{", node->name);

		for (cell = values ? values->head : NULL; cell != NULL; cell = cell->next)
		{
			field *payload = (field *)cell->payload;

			if (payload->value->tokenType == T_NULLPOINTER)
			{
				if (ctx->options->skipNulls)
					continue;
				else
					fprintf(ctx->file, "%s%s=<>", delimiter, payload->name);
			}
			else if (payload->value->tokenType == T_NODE_BEG || payload->value->tokenType == T_LIST_BEG)
				fprintf(ctx->file, "%s<%s>%s", delimiter, payload->name, payload->name);
			else
				fprintf(ctx->file, "%s%s=%s", delimiter, payload->name, payload->value->value);

			delimiter = "|";
		}

		fprintf(ctx->file, "}\"];\n");
	}
	
	for (cell = values ? values->head : NULL; cell != NULL; cell = cell->next)
	{
		field *payload = (field *)cell->payload;
		int	   id;

		if (payload->value->tokenType == T_NODE_BEG)
			id = dumpNode(ctx, payload->value);
		else if (payload->value->tokenType == T_LIST_BEG)
			id = dumpList(ctx, payload->value);
		else
			continue;

		addEdge(ctx, payload->name, myID, "e", "f0", id);
	}

	return myID;
}

static void dumpField(dumpCtx *ctx, node *nodePtr)
{
	field	*node = (field *)nodePtr;

	if (node->value->tokenType == T_NULLPOINTER)
		return;
	else if (node->value->tokenType == T_NODE_BEG)
		fprintf(ctx->file, "|<%s-anchor>%s", node->name, node->name);
	else if (node->value->tokenType == T_LIST_BEG)
		fprintf(ctx->file, "|<%s-anchor>%s", node->name, node->name);
	else
		fprintf(ctx->file, "|%s=%s", node->name, node->value->value);
}

static void dumpBranch(dumpCtx *ctx, node *node)
{
	if (node == NULL)
		return;
	else
	{
		switch (node->tokenType)
		{
			case T_NODE_BEG:
			{
				dumpNode(ctx, node);
				break;
			}

			case T_FIELDNAME:
			{
				dumpField(ctx, node);
				break;
			}
			case T_LIST_BEG:
			{
				dumpList(ctx, node);
				break;
			}
		}
	}
}

static void dumpTree(dumpCtx *ctx, node *root)
{
	fprintf(ctx->file, "digraph AST\n{\n  node [shape=record,labeljust=\"l\"];\n");

	if (ctx->options->title)
		fprintf(ctx->file, "  graph [label=\"%s\",nojustify=\"true\",labeljust=\"l\"];\n", escape(ctx, ctx->options->title, 0));

	if (ctx->options->onlyBranch)
		ctx->graph = false;
	else
		ctx->graph = true;

	dumpNode(ctx, root);

	fprintf(ctx->file, "}");

}

static dumpCtx *makeDumpCtx(void)
{
	dumpCtx *result = (dumpCtx *)malloc(sizeof(*result));

	result->file		  = stdout;
	result->id			  = 1;
	result->options       = &options;

	return result;
}

static char *escape(const dumpCtx *ctx, const char *in, int truncateTo)
{
	size_t		  extras = 0;
	size_t		  inLen;
	unsigned int  i, o;
	char   		 *result;
	
	if (in == NULL)
		return strdup("");

	if ((inLen = strlen(in)) == 0)
		return strdup("");

	if ((truncateTo > 0) && (inLen > truncateTo))
	{
		inLen  = truncateTo;
		extras = 3;
	}

	for (i = 0; i < inLen; i++)
	{
		switch (in[i])
		{
			case '\"':
			case '\\':
			case '<':
			case '>':
			case '|':
			case '\'':
				extras++;
				break;

			case '\n':
				extras += 2;
				break;
			
			default:
				break;
		}

	}

	result = (char *)malloc(inLen + extras + 1);

	for (i = 0, o = 0; i < inLen; i++)
	{
		switch (in[i])
		{
			case '\"':
			case '\\':
			case '<':
			case '>':
			case '|':
			case '\'':
			{
				result[o++] = '\\';
				result[o++] = in[i];
				break;
			}

			case '\n':
			{
				result[o++] = '\\';
				result[o++] = 'n';
				break;
			}

			default:
			{
				result[o++] = in[i];
				break;
			}
		}
	}	

	if (strlen(in) > inLen)
	{
		memcpy(result+o, "...", 3);
		o += 3;
	}

	result[o] = '\0';

	return result;
}

char *escapeScan(const char *str)
{
	return escape(NULL, str, 0);
}

static char *stringConcat(const char *str1, const char *str2, const char *str3)
{
	char   *result = (char *)malloc(strlen(str1) + strlen(str2) + strlen(str3) + 1);
	
	strcpy(result, str1);
	strcat(result, str2);
	strcat(result, str3);

	return result;
}

static node *parseHilight(const char *src, node *hilights)
{
	node	   *hilight = makeNode(0, NULL);
	const char *p;

	hilight->intValue = atoi(src);

	if ((p = strchr(src, ':')) != NULL)
		hilight->value = strdup(p+1);
	else
		hilight->value = "fillcolor=deepskyblue,fontcolor=crimson";

	return listAppend(hilights, hilight);
}

static node *parseAnnotation(const char *src, node *annotations)
{
	node	   *annotation = makeNode(0, NULL);
	const char *p;

	annotation->intValue = atoi(src);

	if ((p = strchr(src, ':')) != NULL)
		annotation->value = strdup(p+1);
	else
		annotation->value = "*";

	return listAppend(annotations, annotation);
}

static void usage(const char *program, struct option *options)
{
	fprintf(stderr, "usage:\n" );
	fprintf(stderr, "  %s [options] [inputFile]\n", program );
	fprintf(stderr, "     or\n");
	fprintf(stderr, "  %s [options] < inputFile\n", program );
	fprintf(stderr, "\noptions := \n");

    fprintf(stderr, "    --statement=<text>           | -s <text>            Label for graph (typically text of SQL statement)\n");
    fprintf(stderr, "    --highlight=<node>[:<color>] | -v <node>[:<color>]  Node number to highlight and color spec in graphviz format\n");
	fprintf(stderr, "    --annotate=<node>[:<note>]   | -a <node>[:<note>]   Node number to annotate and note to attach to that node\n");
    fprintf(stderr, "    --color=<colorSpec>          | -c <colorSpec>       Color used to highlight nodes (in graphviz format)\n");
    fprintf(stderr, "    --number                     | -n                   Include node numbers in graph\n");
    fprintf(stderr, "    --truncate=<maxlength>       | -t <maxlength>       Maximum string length (before elision), default 20\n");
    fprintf(stderr, "    --maxstrings=<n>             | -m <n>               Maximum number of strings to print per string list, default 5\n");
    fprintf(stderr, "    --keepnulls                  | -k                   Include NULL pointers\n");
	fprintf(stderr, "    --branch=<n>                 | -b <n>               Only graph descendents of node <n>\n");

	fprintf(stderr, "Examples:\n");
	fprintf(stderr, "  %s --statement=\"SELECT * FROM foo\" < /tmp/parsetree\n", program);
	fprintf(stderr, "  %s --highlight=3:fillcolor=red,style=filled -a \"5:round()\" < /tmp/parsetree\n", program);
	fprintf(stderr, "  %s -s \"SELECT * FROM foo\" < /tmp/parsetree | dot -T pdf > /tmp/parse.pdf\n", program);
}

struct option longOptions[] =
{
	{ "statement",  required_argument, NULL, 's' },
	{ "highlight",  required_argument, NULL, 'v' },
	{ "annotate",   required_argument, NULL, 'a' },
	{ "color",      required_argument, NULL, 'c' },
	{ "truncate",   required_argument, NULL, 't' },
	{ "maxstrings", required_argument, NULL, 'm' },
    { "branch",     required_argument, NULL, 'b' },
	{ "number",     0,                 NULL, 'n' },
	{ "keepnulls",  0,                 NULL, 'k' },
	{ "help",       0,                 NULL, 'h' },
	{ NULL,         0,      		   NULL,  0  },

};

static const char *parseCommandLine(cmdLine *out, int argc, char *const argv[])
{
	int		opt;

	out->title		   = NULL;
	out->hilights	   = NULL;
	out->numberNodes   = false;
	out->truncateTo	   = 20;
	out->skipNulls	   = true;
	out->maxStringList = 5;
	out->hilightColor  = "fillcolor=deepskyblue,fontcolor=crimson";
	out->onlyBranch    = 0;

	while ((opt = getopt_long(argc, argv, "c:t:m:s:v:b:a:nkh", longOptions, NULL)) != -1)
	{
		switch (opt)
		{
			case 'b':
			{
				out->onlyBranch = atoi(optarg);
				break;
			}

			case 't':
			{
				out->truncateTo = atoi(optarg);
				break;
			}

			case 'm':
			{
				out->maxStringList = atoi(optarg);
				break;
			}
		  
			case 'k':
			{
				out->skipNulls = false;
				break;
			}

			case 'v':	
			{
				out->hilights = parseHilight(optarg, out->hilights);
				break;
			}

			case 'a':	
			{
				out->annotations = parseAnnotation(optarg, out->annotations);
				break;
			}

			case 's':	
			{
				out->title = strdup(optarg); 
				break;
			}

			case 'c':
			{
				out->hilightColor = strdup(optarg);
				break;
			}

			case 'n':
			{
				out->numberNodes = true;
				break;
			}


			case 'h':
			{
				usage(argv[0], longOptions);

				exit(EXIT_SUCCESS);

				break;
			}

			default:
			{
				fprintf(stderr, "unexpected command-line option (%c)\n", opt);

				usage(argv[0], longOptions);

				exit(EXIT_FAILURE);
			}
		}
	}

	if (optind < argc)
		return argv[optind];
	else
		return NULL;
}


int main(int argc, char *argv[])
{
	scanner_init(parseCommandLine(&options, argc, argv));
	
	yyparse();
}


