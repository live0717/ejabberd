%%%----------------------------------------------------------------------
%%% File    : ejabberd_ctl.erl
%%% Author  : Alexey Shchepin <alexey@sevcom.net>
%%% Purpose : Ejabberd admin tool
%%% Created : 11 Jan 2004 by Alexey Shchepin <alex@alex.sevcom.net>
%%% Id      : $Id$
%%%----------------------------------------------------------------------

-module(ejabberd_ctl).
-author('alexey@sevcom.net').

-export([start/0,
	 process/1]).

-include("ejabberd_ctl.hrl").

start() ->
    case init:get_plain_arguments() of
	[SNode | Args] ->
	    Node = list_to_atom(SNode),
	    Status = case rpc:call(Node, ?MODULE, process, [Args]) of
			 {badrpc, Reason} ->
			     io:format("RPC call failed on the node ~p: ~p~n",
				       [Node, Reason]),
			     ?STATUS_BADRPC;
			 S ->
			     S
		     end,
	    halt(Status);
	_ ->
	    print_usage(),
	    halt(?STATUS_USAGE)
    end.


process(["status"]) ->
    {InternalStatus, ProvidedStatus} = init:get_status(),
    io:format("Node ~p is ~p. Status: ~p~n",
	      [node(), InternalStatus, ProvidedStatus]),
    ?STATUS_SUCCESS;

process(["stop"]) ->
    init:stop(),
    ?STATUS_SUCCESS;

process(["restart"]) ->
    init:restart(),
    ?STATUS_SUCCESS;

process(["reopen-log"]) ->
    ejabberd_logger_h:reopen_log(),
    ?STATUS_SUCCESS;

process(["register", User, Server, Password]) ->
    case ejabberd_auth:try_register(User, Server, Password) of
	{atomic, ok} ->
	    ?STATUS_SUCCESS;
	{atomic, exists} ->
	    io:format("User ~p already registered at node ~p~n",
		      [User ++ "@" ++ Server, node()]),
	    ?STATUS_ERROR;
	{error, Reason} ->
	    io:format("Can't register user ~p at node ~p: ~p~n",
		      [User ++ "@" ++ Server, node(), Reason]),
	    ?STATUS_ERROR
    end;

process(["unregister", User, Server]) ->
    case ejabberd_auth:remove_user(User, Server) of
	{error, Reason} ->
	    io:format("Can't unregister user ~p at node ~p: ~p~n",
		      [User ++ "@" ++ Server, node(), Reason]),
	    ?STATUS_ERROR;
	_ ->
	    ?STATUS_SUCCESS
    end;

process(["backup", Path]) ->
    case mnesia:backup(Path) of
        ok ->
	    ?STATUS_SUCCESS;
	{error, Reason} ->
	    io:format("Can't store backup in ~p at node ~p: ~p~n",
		      [filename:absname(Path), node(), Reason]),
	    ?STATUS_ERROR
    end;

process(["dump", Path]) ->
    case dump_to_textfile(Path) of
	ok ->
	    ?STATUS_SUCCESS;
	{error, Reason} ->
            io:format("Can't store dump in ~p at node ~p: ~p~n",
                      [filename:absname(Path), node(), Reason]),
	    ?STATUS_ERROR
    end;

process(["load", Path]) ->
    case mnesia:load_textfile(Path) of
        {atomic, ok} ->
            ?STATUS_SUCCESS;
        {error, Reason} ->
            io:format("Can't load dump in ~p at node ~p: ~p~n",
                      [filename:absname(Path), node(), Reason]),
	    ?STATUS_ERROR
    end;

process(["restore", Path]) ->
    case mnesia:restore(Path, [{default_op, keep_tables}]) of
	{atomic, _} ->
	    ?STATUS_SUCCESS;
	{error, Reason} ->
	    io:format("Can't restore backup from ~p at node ~p: ~p~n",
		      [filename:absname(Path), node(), Reason]),
	    ?STATUS_ERROR
    end;

process(["install-fallback", Path]) ->
    case mnesia:install_fallback(Path) of
	ok ->
	    ?STATUS_SUCCESS;
	{error, Reason} ->
	    io:format("Can't install fallback from ~p at node ~p: ~p~n",
		      [filename:absname(Path), node(), Reason]),
	    ?STATUS_ERROR
    end;

process(["import-file", Path]) ->
    case jd2ejd:import_file(Path) of
        ok ->
            ?STATUS_SUCCESS;
        {error, Reason} ->
            io:format("Can't import jabberd 1.4 spool file ~p at node ~p: ~p~n",
                      [filename:absname(Path), node(), Reason]),
	    ?STATUS_ERROR
    end;

process(["import-dir", Path]) ->
    case jd2ejd:import_dir(Path) of
        ok ->
            ?STATUS_SUCCESS;
        {error, Reason} ->
            io:format("Can't import jabberd 1.4 spool dir ~p at node ~p: ~p~n",
                      [filename:absname(Path), node(), Reason]),
	    ?STATUS_ERROR
    end;

process(["registered-users"]) ->
    case ejabberd_auth:dirty_get_registered_users() of
	Users when is_list(Users) ->
	    NewLine = io_lib:format("~n", []),
	    SUsers = lists:sort(Users),
	    FUsers = lists:map(fun({U, S}) -> [U, $@, S, NewLine] end, SUsers),
	    io:format("~s", [FUsers]),
	    ?STATUS_SUCCESS;
	{error, Reason} ->
	    io:format("Can't get list of registered users at node ~p: ~p~n",
		      [node(), Reason]),
	    ?STATUS_ERROR
    end;

process(["delete-expired-messages"]) ->
    mod_offline:remove_expired_messages(),
    ?STATUS_SUCCESS;

process(_Args) ->
    print_usage(),
    ?STATUS_USAGE.



print_usage() ->
    io:format(
      "Usage: ejabberdctl node command~n"
      "~n"
      "Available commands:~n"
      "  status\t\t\tget ejabberd status~n"
      "  stop\t\t\t\tstop ejabberd~n"
      "  restart\t\t\trestart ejabberd~n"
      "  reopen-log\t\t\treopen log file~n"
      "  register user server password\tregister a user~n"
      "  unregister user server\tunregister a user~n"
      "  backup file\t\t\tstore a database backup to file~n"
      "  restore file\t\t\trestore a database backup from file~n"
      "  install-fallback file\t\tinstall a database fallback from file~n"
      "  dump file\t\t\tdump a database to a text file~n"
      "  load file\t\t\trestore a database from a text file~n"
      "  import-file file\t\timport user data from jabberd 1.4 spool file~n"
      "  import-dir dir\t\timport user data from jabberd 1.4 spool directory~n"
      "  registered-users\t\tlist all registered users~n"
      "  delete-expired-messages\tdelete expired offline messages from database~n"
      "~n"
      "Example:~n"
      "  ejabberdctl ejabberd@host restart~n"
     ).

dump_to_textfile(File) ->
    dump_to_textfile(mnesia:system_info(is_running), file:open(File, write)).
dump_to_textfile(yes, {ok, F}) ->
    Tabs1 = lists:delete(schema, mnesia:system_info(local_tables)),
    Tabs = lists:filter(
	     fun(T) ->
		     case mnesia:table_info(T, storage_type) of
			 disc_copies -> true;
			 disc_only_copies -> true;
			 _ -> false
		     end
	     end, Tabs1),
    Defs = lists:map(
	     fun(T) -> {T, [{record_name, mnesia:table_info(T, record_name)},
			    {attributes, mnesia:table_info(T, attributes)}]} 
	     end,
	     Tabs),
    io:format(F, "~p.~n", [{tables, Defs}]),
    lists:foreach(fun(T) -> dump_tab(F, T) end, Tabs),
    file:close(F);
dump_to_textfile(_, {ok, F}) ->
    file:close(F),
    {error, mnesia_not_running};
dump_to_textfile(_, {error, Reason}) ->
    {error, Reason}.


dump_tab(F, T) ->
    W = mnesia:table_info(T, wild_pattern),
    {atomic,All} = mnesia:transaction(
		     fun() -> mnesia:match_object(T, W, read) end),
    lists:foreach(
      fun(Term) -> io:format(F,"~p.~n", [setelement(1, Term, T)]) end, All).

