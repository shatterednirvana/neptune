
class TestErlang < Test::Unit::TestCase
  def test_ring_code
    STORAGE_TYPES.each { |storage|
      run_ring_code(storage)
    }
  end

  def test_nonexistent_source_code
    location = "baz" + TestHelper.get_random_alphanumeric
    main_file = "boo"
    compiled = "bazagain"

    msg = "Running a compile job with a non-existent source code location" +
      " should have thrown an exception, when in fact it did not."

    assert_raise(SystemExit, msg) {
      TestHelper.compile_code(location, main_file, compiled)
    }
  end

  def test_nonexistent_compiled_code
    location = "baz" + TestHelper.get_random_alphanumeric
    output = "/bazboo2"
    storage = "appdb"

    msg = "Running an Erlang compute job with a non-existent code location" +
      " should have thrown an exception, when in fact it did not."

    assert_raise(SystemExit, msg) {
      TestHelper.start_job("erlang", location, output, storage)
    }
  end

  def run_ring_code(storage)
    expected_output = "total time for"
    ring_code = <<BAZ
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
  NumProcs = 10,
  NumMessages = 1,
  Processes = ring:generateProcs(NumProcs),
  Message = "hello!",
  times(NumMessages, fun() -> sendMessageToFirst(Processes, Message) end),
  ring:stopProcs(Processes),
  {_, TotalTime} = statistics(wall_clock),
  TimeInMicroseconds = TotalTime * 1000,
  io:format("total time for N = ~p, M = ~p, is ~p microseconds~n", [NumProcs, NumMessages, TimeInMicroseconds]),
  exit('baz').

BAZ

    contents = TestHelper.get_random_alphanumeric(1024)
    folder = "ring-#{TestHelper.get_random_alphanumeric}"
    source = "ring.erl"

    tmp_folder = "/tmp/#{folder}"
    FileUtils.mkdir_p(tmp_folder)
    compiled = "#{tmp_folder}-compiled"
    compiled_code = "#{compiled}/ring.beam"

    local = "#{tmp_folder}/#{source}"
    TestHelper.write_file(local, ring_code)

    output = TestHelper.get_output_location(folder, storage)

    compile_erlang_code(tmp_folder, source, compiled)
    start_erlang_code(compiled_code, output, storage)
    get_erlang_output(output, expected_output, storage)

    FileUtils.rm_rf(tmp_folder)
    FileUtils.rm_rf(compiled)
  end

  def compile_erlang_code(location, main_file, compiled)
    std_out, std_err = TestHelper.compile_code(location, main_file, compiled)

    make = "HOME=/root erlc ring.erl"
    msg = "The Erlang Ring code did not compile as expected. It should have " +
      "compiled with the command [#{make}] instead of [#{std_out}]."
    assert(std_out.include?(make), msg)

    msg = "The Erlang Ring code did not compile successfully. It reported " +
      "the following error: #{std_err}"
    assert_nil(std_err, msg)
  end

  def start_erlang_code(code_location, output, storage)
    status = TestHelper.start_job("erlang", code_location, output, storage)

    msg = "Your job was not started successfully. The failure message " +
      "reported was #{status[:msg]}"
    assert_equal(status[:result], :success, msg)
  end

  def get_erlang_output(output, expected, storage)
    result = TestHelper.get_job_output(output, storage)

    msg = "The Erlang job you ran did not return the expected result. " +
      "We expected to see [#{expected}] but instead saw [#{result}]"
    out_contains = result.include?(expected)
    assert(out_contains, msg)
  end
end 

