-module(ring).
-compile(export_all).

% spawn N processes
% M times, send message to proc 1 
% when proc i recv's a message, send it to i+1

% distributed version:
% global var for master node
% var with list of nodes
% if master:
%   no high-level changes
% else:
%   wait for master to give me work
%   loop until i receive a kill message
%   which breaks this loop and kills this node

% smaller changes:

start(Name, Next) ->
  %io:format("creating proc named ~p with next proc named ~p~n", [Name, Next]),
  register(Name, spawn(fun() -> ring:startMe(Next) end)),
  Name.

startMe(Next) ->
  receive
    stop ->
      void;
    {Message, Initiator} ->
      NextPid = whereis(Next),
      if
        is_pid(NextPid) ->
          %io:format("sending message to next proc, ~p~n", [Next]),
          NextPid ! {Message, Initiator},
          startMe(Next);
        true ->
          %io:format("no next proc to send message to!~n"),
          Initiator ! done,
          startMe(Next)
      end
  end.

generateProcs(Num) ->
  if
    Num > 0 ->
      [start(ring:i_to_a(Num), ring:i_to_a(Num-1)) | ring:generateProcs(Num-1)];
    true ->
      []
  end.

stopProcs([H | T]) ->
  HeadPid = whereis(H),
  HeadPid ! stop,
  stopProcs(T);
stopProcs([]) ->
    void.

sendMessageToFirst([H | T], Message) ->
  HeadPid = whereis(H),
  HeadPid ! {Message, self()},
  receive
    done -> void
  end.

a_to_i(A) ->
  list_to_integer(atom_to_list(A)).

i_to_a(I) ->
  list_to_atom(integer_to_list(I)).

times(Num, Fun) ->
  if Num > 0 ->
    Fun(),
    times(Num-1, Fun);
  true ->
    void
  end.

main() ->
  statistics(wall_clock),
  NumProcs = 503,
  NumMessages = 1000,
  Processes = ring:generateProcs(NumProcs),
  Message = "hello!",
  times(NumMessages, fun() -> sendMessageToFirst(Processes, Message) end),
  ring:stopProcs(Processes),
  {_, TotalTime} = statistics(wall_clock),
  TimeInMicroseconds = TotalTime * 1000,
  io:format("total time for N = ~p, M = ~p, is ~p microseconds~n", [NumProcs, NumMessages, TimeInMicroseconds]),
  exit('baz').
