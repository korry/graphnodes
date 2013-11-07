This tool (rfmt) will convert a parse or plan tree into a graphviz-formatted
graph (which you can then process with, for example, the dot utility).

To use this tool, run psql and do the following:

  1) `SET debug_print_parse = on`
      or
     `SET debug_print_plan = on`

  2) `SET client_min_messages = debug1`

  3) Execute a query 

  4) Copy the parse/plan tree that appears to a file

  5) Run the rfmt tool and pipe stdout to dot to produce a graph

For example:
<pre>
$ edb-psql sample

sample=# SET debug_print_parse = on;
SET                                 
sample=# SET client_min_messages = debug1;
SET                                                 
sample=# SELECT ename FROM emp;
LOG:  parse tree:
DETAIL:     {QUERY 
   :commandType 1  
   :querySource 0  
   ...
   :hints <>
   :setOperations <>
   }

</pre>

Now copy the parse tree (everything from the open brace to the close brace)
and save it in a file (say /tmp/parse.pg).

Then, to produce a graph in PDF form:

$ rfmt -s "SELECT ename FROM emp" < /tmp/parse.pg | dot -T pdf > /tmp/parse.pdf

Run "rfmt --help" for a list of command-line options

--------------------------------------------------------------------------------
The makepdf script is useful when you want to cut/paste a tree description 
and convert it to a PDF file.

To use makepdf, run:
<pre>
	makepdf filename [rfmt_arguments]
</pre>
When prompted, paste in the tree description and press Ctrl-D (eof).

The output will be written to `<filename>`

For example:
<pre>
  $makepdf /tmp/select.pdf -v 5 -n
  Paste text, then press Ctrl-D
  { ... tree goes here }
  ^D
  PDF file created: /tmp/select.pdf
</pre>
--------------------------------------------------------------------------------

     -- Korry
