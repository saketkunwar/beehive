-module (apps).

-include ("beehive.hrl").
-include ("common.hrl").

%% DATABASE STUFF
-export ([
          create/1,
          read/1,
          save/1,
          update/2,
          delete/1,
          find_by_name/1,
          find_all_by_name/1,
          exist/1,
          all/0
         ]).

-export ([
          new/1,
          update_by_name/1,
          restart_by_name/1,
          expand_by_name/1
         ]).

%% APPLICATION STUFF
-export ([
          to_proplist/1,
          build_app_env/2
         ]).

-define (DB, beehive_db_srv).

-export ([validate_app/1]).

create(App) ->
  case new(App) of
    NewApp when is_record(NewApp, app) ->
      ValidAppWithName = validate_unique_name(NewApp),
      NewApp1 = validate_app(ValidAppWithName),
      save(NewApp1);
    E -> {error, E}
  end.

save(App) when is_record(App, app) ->
  ok = ?DB:write(app, App#app.name, App),
  {ok, App};
save([]) -> invalid;
save(Proplists) when is_list(Proplists) ->
  case from_proplists(Proplists) of
    {error, _} = T -> T;
    App -> save(App)
  end;
save(Func) when is_function(Func) ->
  ?DB:save(Func);

save(Else) -> {error, {cannot_save, Else}}.

new([]) -> error;
new(App) when is_record(App, app) -> validate_app(App);
new(Proplist) when is_list(Proplist) -> validate_app(from_proplists(Proplist));
new(Else) -> {error, {cannot_make_new_app, Else}}.

read(Name) ->
  case find_by_name(Name) of
    App when is_record(App, app) -> App;
    _E -> {error, not_found}
  end.

delete(App) when is_record(App, app) ->
  ?DB:delete(app, App#app.name);
delete([]) -> invalid;
delete(Name) when is_list(Name) -> ?DB:delete(app, Name);
delete(Else) -> {error, {cannot_delete, Else}}.

all() -> ?DB:all(app).

exist(Name) ->
  case find_by_name(Name) of
    App when is_record(App, app) -> true;
    _ -> false
  end.

find_by_name(Name) ->
  case find_all_by_name(Name) of
    [H|_Rest] -> H;
    [] -> not_found;
    %% This should ALWAYS be not_found, but just to be safe
    E -> E
  end.

find_all_by_name(Name) ->
  case ?DB:read(app, Name) of
    Apps  when is_list(Apps) -> Apps;
    App   when is_record(App, app) -> [App];
    _ ->  []
  end.

%% APPLICATION STUFF
update_by_name(Name) ->
  case find_by_name(Name) of
    not_found -> {error, "Cannot find app to update"};
    App ->
      %% Should this be synchronous or asynchronous?
      NewApp = App#app{updated_at = date_util:now_to_seconds(), latest_error = undefined, revision = undefined},
      ?NOTIFY({app, updated, NewApp}),
      {ok, save(NewApp)}
  end.

expand_by_name(Name) ->
  case find_by_name(Name) of
    not_found -> {error, "Cannot find app"};
    App ->
      ?NOTIFY({app, expand, App}),
      {ok, App}
  end.

restart_by_name(Name) ->
  case find_by_name(Name) of
    not_found -> {error, "Cannot find app"};
    App ->
      NewApp = App#app{updated_at = date_util:now_to_seconds(), latest_error = undefined},
      ?NOTIFY({app, restart, NewApp}),
      {ok, save(NewApp)}
  end.


update([], _) -> ok;
update(App, OtherApp) when is_record(App, app) andalso is_record(OtherApp, app) ->
  update(App, to_proplist(OtherApp));
update(App, NewProps) when is_record(App, app) ->
  NewAppProps = misc_utils:update_proplist(to_proplist(App), NewProps),
  NewApp = from_proplists(NewAppProps),
  case App#app.revision =/= NewApp#app.revision of
    true -> ?NOTIFY({app, updated_revision, NewApp});
    false -> ok
  end,
  {ok, NewApp1} = save(validate_app(NewApp)),
  {updated, NewApp1};
update(Name, NewProps) ->
  case find_by_name(Name) of
    not_found -> false;
    App -> update(App, NewProps)
  end.

%%-------------------------------------------------------------------
%% @spec (App:app()) ->    {ok, Value}
%% @doc Build environment variables for the application
%%
%% @end
%%-------------------------------------------------------------------
build_app_env(App, Other) ->
  OtherEnvs = lists:map(fun build_env/1, Other),
  BeehivePath = config:search_for_application_value(path, "/usr/bin:/usr/local/bin:/bin"),
  LogDisk     = config:search_for_application_value(log_path, ?BEEHIVE_DIR("application_logs")),
  LogDir      = filename:join([LogDisk, App#app.name]),

  bh_file_utils:ensure_dir_exists([LogDir, LogDisk]),

  StdOut     = filename:join([LogDir, "beehive.out"]),
  StdErr     = filename:join([LogDir, "beehive.err"]),

  lists:flatten([
                 build_env({name, App#app.name}),
                 build_env({repos, App#app.repo_url}),
                 build_env({revision, App#app.revision}),
                 build_env({path, BeehivePath}),
                 build_env({branch, App#app.branch}),
                 {stdout, StdOut},
                 {stderr, StdErr},
                 OtherEnvs
                ]).

build_env({Key, Value}) ->
  RealValue = case Value of
                undefined -> "undefined";
                _ -> Value
              end,
  T = lists:flatten([
                     string:to_upper(erlang:atom_to_list(Key)),
                     "=",RealValue,""
                    ]),
  {env, T}.

%% If erlang had 'meta-programming,' we wouldn't have to do all this work to validate the proplists
from_proplists(Proplists) -> from_proplists(Proplists, #app{}).
from_proplists([], App)  -> App;
from_proplists([{name, V}|Rest], App) -> from_proplists(Rest, App#app{name = V});
from_proplists([{repo_url, V}|Rest], App) -> from_proplists(Rest, App#app{repo_url = V});
from_proplists([{repo_type, V}|Rest], App) ->
  from_proplists(Rest, App#app{repo_type = V});
from_proplists([{template, V}|Rest], App) ->
  from_proplists(Rest, App#app{template = V});
from_proplists([{timeout, V}|Rest], App) ->
  from_proplists(Rest, App#app{timeout = V});
from_proplists([{sticky, V}|Rest], App) ->
  from_proplists(Rest, App#app{sticky = V});
from_proplists([{min_instances, V}|Rest], App) ->
  from_proplists(Rest, App#app{min_instances = V});
from_proplists([{max_instances, V}|Rest], App) ->
  from_proplists(Rest, App#app{max_instances = V});
from_proplists([{revision, V}|Rest], App) ->
  from_proplists(Rest, App#app{revision = V});
from_proplists([{updated_at, V}|Rest], App) ->
  from_proplists(Rest, App#app{updated_at = V});
from_proplists([{routing_param, V}|Rest], App) ->
  from_proplists(Rest, App#app{routing_param = V});
from_proplists([{branch, V}|Rest], App) ->
  from_proplists(Rest, App#app{branch = V});
from_proplists([{deploy_env, V}|Rest], App) ->
  from_proplists(Rest, App#app{deploy_env = V});
from_proplists([_Other|Rest], App) -> from_proplists(Rest, App).


to_proplist(App) -> to_proplist(record_info(fields, app), App, []).

to_proplist([], _App, Acc) -> Acc;
to_proplist([name|Rest], #app{name = Name} = App, Acc) ->
  to_proplist(Rest, App, [{name, Name}|Acc]);
to_proplist([repo_url|Rest], #app{repo_url = Value} = App, Acc) ->
  to_proplist(Rest, App, [{repo_url, Value}|Acc]);
to_proplist([repo_type|Rest], #app{repo_type = Value} = App, Acc) ->
  to_proplist(Rest, App, [{repo_type, Value}|Acc]);
to_proplist([timeout|Rest], #app{timeout = Value} = App, Acc) ->
  to_proplist(Rest, App, [{timeout, Value}|Acc]);
to_proplist([sticky|Rest], #app{sticky = Value} = App, Acc) ->
  to_proplist(Rest, App, [{sticky, Value}|Acc]);
to_proplist([min_instances|Rest], #app{min_instances = Value} = App, Acc) ->
  to_proplist(Rest, App, [{min_instances, Value}|Acc]);
to_proplist([max_instances|Rest], #app{max_instances = Value} = App, Acc) ->
  to_proplist(Rest, App, [{max_instances, Value}|Acc]);
to_proplist([revision|Rest], #app{revision = Value} = App, Acc) ->
  to_proplist(Rest, App, [{revision, Value}|Acc]);
to_proplist([updated_at|Rest], #app{updated_at = Value} = App, Acc) ->
  to_proplist(Rest, App, [{updated_at, Value}|Acc]);
to_proplist([template|Rest], #app{template = Value} = App, Acc) ->
  to_proplist(Rest, App, [{template, Value}|Acc]);
to_proplist([routing_param|Rest], #app{routing_param = Value} = App, Acc) ->
  to_proplist(Rest, App, [{routing_param, Value}|Acc]);
to_proplist([branch|Rest], #app{branch = Value} = App, Acc) ->
  to_proplist(Rest, App, [{branch, Value}|Acc]);
to_proplist([deploy_env|Rest], #app{deploy_env = Value} = App, Acc) ->
  to_proplist(Rest, App, [{deploy_env, Value}|Acc]);
to_proplist([_H|T], App, Acc) -> to_proplist(T, App, Acc).

%%-------------------------------------------------------------------
%% @spec (Proplist) ->    ValidProplist
%% @doc Validate the proplist to create a new app record
%%
%% @end
%%-------------------------------------------------------------------
validate_app(App) when is_record(App, app) -> validate_app(record_info(fields, app), App).
validate_app([], App) ->  App;

%% Validate the branch
validate_app([branch|Rest], #app{branch = undefined} = App) ->
  validate_app(Rest, App#app{branch = "master"});
validate_app([branch|Rest], #app{branch = _V} = App) ->
  validate_app(Rest, App);
%% Validate the repo_url
validate_app([repo_url|Rest], #app{repo_url = _Url} = App) ->
  validate_app(Rest, App);
%% Validate the type, it can only be either static or dynamic
validate_app([repo_type|Rest], #app{repo_type = git} = App) ->
  validate_app(Rest, App);
validate_app([repo_type|Rest], #app{repo_type = _Else} = App) ->
  validate_app(Rest, App#app{repo_type = git});
%% Validate the timeout
validate_app([timeout|Rest], #app{timeout = undefined} = App) ->
  validate_app(Rest, App#app{timeout = 10*1000});
validate_app([timeout|Rest], #app{timeout = V} = App) ->
  validate_app(Rest, App#app{timeout = misc_utils:to_integer(V)*1000});
%% Validate the sticky parameter
validate_app([sticky|Rest], #app{sticky = "true"} = App) ->
  validate_app(Rest, App#app{sticky = true});
validate_app([sticky|Rest], #app{sticky = _Else} = App) ->
  validate_app(Rest, App#app{sticky = false});
%% Validate min/max instances
validate_app([min_instances|Rest], #app{min_instances = undefined} = App) ->
  validate_app(Rest, App#app{min_instances = 1});
validate_app([min_instances|Rest], #app{min_instances = V} = App) ->
  validate_app(Rest, App#app{min_instances = misc_utils:to_integer(V)});
validate_app([max_instances|Rest], #app{max_instances = undefined} = App) ->
  validate_app(Rest, App#app{max_instances = 1});
validate_app([max_instances|Rest], #app{max_instances = V} = App) ->
  validate_app(Rest, App#app{max_instances = misc_utils:to_integer(V)});
%% Validate the template
validate_app([template|Rest], #app{template = undefined} = App) ->
  validate_app(Rest, App#app{template = default});
validate_app([template|Rest], #app{template = Val} = App) ->
  validate_app(Rest, App#app{template = misc_utils:to_atom(Val)});
%% Validate the routing parameter
validate_app([routing_param|Rest], #app{routing_param = undefined} = App) ->
  validate_app(Rest, App#app{routing_param = 'Host'});
validate_app([routing_param|Rest], #app{routing_param = V} = App) ->
  validate_app(Rest, App#app{routing_param = misc_utils:to_atom(V)});
%% Validate others?
validate_app([_H|Rest], App) -> validate_app(Rest, App).


validate_unique_name(#app{name = undefined} = App) ->
  App#app{name = generate_unique_name(5)};
validate_unique_name(#app{name = Name} = App) ->
  case string:tokens(Name, "/") of
    [N] -> App#app{name = generate_unique_name(N, 5)};
    [A,B] -> App#app{name = generate_unique_name(A, 5), branch = B}
  end.

%%-------------------------------------------------------------------
%% @spec (Name) ->    {ok, Value}
%% @doc Generate a unique name based on a given name
%%
%% @end
%%-------------------------------------------------------------------
generate_unique_name(Name, Num) ->
  case catch find_by_name(Name) of
    A when is_record(A, app) -> misc_utils:generate_unique_name(Name, Num);
    not_found -> string:to_lower(Name)
  end.
generate_unique_name(Num) ->
  generate_unique_name(misc_utils:generate_unique_name(Num), Num).
