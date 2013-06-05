%{
#include "rfmt.h"
#include "rfmt-gram.h"

extern char *escapeScan(const char *str);

%}

%option never-interactive
%option case-insensitive
%option outfile="rfmt-scan.c"
%option noyywrap 
%option debug


dquote          \"
quotedString    {dquote}[^\"]*{dquote}
space           [ \t\n\r\f]
spaces          {space}*        
identStart      [A-Za-z_]
identCont       [A-Za-z_0-9]
ident           {identStart}{identCont}*
digit           [0-9]
sign            "+"|"-"
integer         {sign}?{digit}+
optdigits       {digit}*
dot             \.
float1          {optdigits}{dot}{integer}
float2          {integer}{dot}
float           {float1}|{float2}
encodedLiteral  "["({space}|{integer})+"]"


%%

true                { yylval.strval = strdup(yytext); return T_STRING; }
false               { yylval.strval = strdup(yytext); return T_STRING; }
"{"                 { return T_NODE_BEG; }
"}"                 { return T_NODE_END; }
":"{ident}          { yylval.strval = strdup(yytext); return T_FIELDNAME; }
"("                 { return T_LIST_BEG; }
")"                 { return T_LIST_END; }
{quotedString}      { yylval.strval = escapeScan(yytext); return T_STRING; }
{ident}             { yylval.strval = strdup(yytext); return T_IDENT; }
"<>"                { yylval.strval = strdup(yytext); return T_NULLPOINTER; }
{float}             { yylval.strval = strdup(yytext); return T_NUMBER; }
{integer}           { yylval.strval = strdup(yytext); return T_NUMBER; }
{encodedLiteral}    { yylval.strval = strdup(yytext); return T_ENCODED_LITERAL; }
{spaces}    
%%

void scanner_init(const char *src)
{
    if (src != NULL)
        yy_scan_string(src);

    if (getenv("DEBUG"))
        yy_flex_debug = 1;
    else
        yy_flex_debug = 0;
}
