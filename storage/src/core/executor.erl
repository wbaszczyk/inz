%% @author Michal Liszcz
%% @doc Per-File core executors

-module(executor).
-include("shared.hrl").
-define(EXECUTORS, proc_executors).
-define(EXECUTOR_LIFESPAN, 180000).

-export([ push/2 ]).

-export([ run/2 ]).


-ifdef(notrack).
-define(LOG_ACTION(X), true).
-else.
-define(LOG_ACTION(X), db_actions:store(X)).
-endif.


run(Name, MemoryLimit) ->
	receive
		{ReplyTo, #request{type=Type} = Request} ->

			case core:handle_req(Request) of
				{ok,	_}=Result -> gen_server:reply(ReplyTo, Result);
				{error,	_} -> pass
			end,

			?LOG_ACTION(Request),

			erlang:garbage_collect(self()),

			run(Name, MemoryLimit)

	after ?EXECUTOR_LIFESPAN ->
		?LOG_INFO("inactive executor terminates itself"),
		ets:delete(?EXECUTORS, Name)
	end.


%% @def pushes request to associated executor and returns immediately
push(ReplyTo, #request{user = IssuerId, addr = {UserId, VPath}}=Request) ->
	% get_executor(<< UserId/binary, VPath/binary >>) ! {ReplyTo, Request},
	get_executor(UserId++VPath) ! {ReplyTo, Request},
	{ok, request_pushed}.


%% @def retrieves (or creates) handler for given file
get_executor(Name) ->
	case ets:lookup(?EXECUTORS, Name) of
		[{Name, ExecutorPid}] -> ExecutorPid;
		[] -> ets:insert(?EXECUTORS, { Name, spawn(fun() -> run(Name, util:get_env(core_memory_quota)) end) }),
			  get_executor(Name);
		_ -> {error, handler_not_found}
	end.
