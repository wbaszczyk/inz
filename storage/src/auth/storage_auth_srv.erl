%% @author Michal Liszcz
%% @doc Storage Server authentication module

-module(storage_auth_srv).
-include("shared.hrl").
-behaviour(gen_server).
-define(SERVER, ?MODULE).
% -define(CACHE, users_cache).
-define(EXPIRATION_TIME, 10*60*1000).	% 10-minute cache validity

%% ------------------------------------------------------------------
%% API Function Exports
%% ------------------------------------------------------------------

-export([start_link/0, stop/0]).

%% ------------------------------------------------------------------
%% gen_server Function Exports
%% ------------------------------------------------------------------

-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).

%% ------------------------------------------------------------------
%% API Function Definitions
%% ------------------------------------------------------------------

start_link() ->
	log:info("starting"),
	gen_server:start_link({local, ?SERVER}, ?MODULE, [], []).

stop() ->
	log:info("shutdown"),
	gen_server:cast(?SERVER, stop).

%% ------------------------------------------------------------------
%% gen_server Function Definitions
%% ------------------------------------------------------------------

init(_Args) ->

	filelib:ensure_dir(files:resolve_name("users.db")),
	db_users:init(files:resolve_name("users.db")),

	Cache = ets:new(users_cache, [public]),

	log:info("authenticator initialized"),
	{ok, Cache}.


handle_call({authenticate, #request{user=UserId, hmac=Hmac}=Request},
	From, State) ->
	log:info("authentication call for user ~p (id)", []),

	spawn_link(
		fun() ->

			% look in cache
			Now = util:timestamp(),

			AcceptedL1 = case ets:lookup(State, UserId) of

				% entry exists in cache and is valid
				[{UserId, Secret, Expires}] when Expires < Now ->

					% try to validate request with cached secret
					case Hmac == calculate_hmac(Request, Secret) of

						% everything ok, renew entry
						true ->
							ets:insert(State, {UserId, Secret, Now+?EXPIRATION_TIME}),
							true;

						% invalid secret or changed from last caching
						_ ->
							false
					end;

				% no entry or is expired
				_ ->
					false
			end,

			AcceptedL2 = case AcceptedL1 of
				true -> true;
				false ->

					% ask other nodes for user identity
					case fetch_user(UserId) of

						% obtained secret is valid, update cache and test hmac
						{ok, UserEntity} ->
							ets:insert(State, {UserEntity#user.id, UserEntity#user.secret,
								Now+?EXPIRATION_TIME}),
							Hmac == calculate_hmac(Request, UserEntity#user.secret);

						% dafuq are u?
						{error, _} -> false
					end
			end,

			case AcceptedL2 of
				true -> gen_server:reply(From, {ok, authenticated});
				false -> gen_server:reply(From, {error, authentication_failed})
			end

		end),
	{noreply, State};


handle_call({sign_request, #request{}=Request, Secret}, _From, State) ->
	SignedRequest = Request#request{hmac = calculate_hmac(Request, Secret)},
	{reply, {ok, SignedRequest}, State}.


handle_cast({{identity, UserId}, ReplyTo}, State) ->
	case db_users:select(UserId) of
		{ok, UserEntity} -> gen_server:reply(ReplyTo, {ok, UserEntity});
		{error, _} -> pass
	end,
	{noreply, State};


handle_cast(_Message, State) ->
	log:warn("unsupported cast"),
	{noreply, State}.


handle_info(_Info, State) ->
	{noreply, State}.


terminate(_Reason, _State) ->
	log:info("closing"),
	ok.


code_change(_OldVsn, State, _Extra) ->
	{ok, State}.

%% ------------------------------------------------------------------
%% Internal Function Definitions
%% ------------------------------------------------------------------

calculate_hmac(
	#request{
		type=Type,
		user=UserId,
		path=Path
	}, Secret) ->
	crypto:hmac(sha, Secret, list_to_binary([
		atom_to_list(Type),
		integer_to_list(UserId),
		Path
		])).

fetch_user(UserId) ->

	try gen_server:call({?DIST_SERVER, node()}, {broadcast, ?AUTH_SERVER, {identity, UserId}}) of
		{ok, UserEntity} -> {ok, UserEntity}
	catch
		_:{timeout, _} -> {error, not_found}
	end.