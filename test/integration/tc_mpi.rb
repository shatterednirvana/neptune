
class TestMPI < Test::Unit::TestCase
  def test_hello_world_code
    num_procs = 1
  
    STORAGE_TYPES.each { |storage|
      run_hello_world_code(storage, num_procs)
    }
  end

  def test_not_enough_procs
    num_procs = 0
  
    STORAGE_TYPES.each { |storage|
      msg = "Running an MPI compute job with p < n should have thrown " +
        "an exception, when in fact it did not. Here we used #{storage} " +
        "as the storage backend."

      assert_raise(SystemExit, msg) {
        run_hello_world_code(storage, num_procs)
      }
    }
  end

  def test_bad_source_code
    location = "/tmp/baz" + TestHelper.get_random_alphanumeric
    output = "/bazboo2"
    storage = "appdb"

    msg = "Running an MPI compute job with a non-existent code location" +
      " should have thrown an exception, when in fact it did not."

    assert_raise(SystemExit, msg) {
      TestHelper.start_job("mpi", location, output, storage)
    }

    FileUtils.mkdir_p(location)

    bad_file_msg = "Running an MPI compute job with a code location that" +
      " is not a file should have thrown an exception, when in fact it did not."

    assert_raise(SystemExit, bad_file_msg) {
      TestHelper.start_job("mpi", location, output, storage)
    }

    FileUtils.rmdir(location)
  end

  def run_hello_world_code(storage, num_procs)
    expected_output = "0: We have 1 processors"
    ring_code = <<BAZ
 /*
  "Hello World" MPI Test Program
 */
 #include <mpi.h>
 #include <stdio.h>
 #include <string.h>
 
 #define BUFSIZE 128
 #define TAG 0
 
 int main(int argc, char *argv[])
 {
   char idstr[32];
   char buff[BUFSIZE];
   int numprocs;
   int myid;
   int i;
   MPI_Status stat;
 
   MPI_Init(&argc,&argv); /* all MPI programs start with MPI_Init; all 'N' processes exist thereafter */
   MPI_Comm_size(MPI_COMM_WORLD,&numprocs); /* find out how big the SPMD world is */
   MPI_Comm_rank(MPI_COMM_WORLD,&myid); /* and this processes' rank is */
 
   /* At this point, all programs are running equivalently, the rank distinguishes
      the roles of the programs in the SPMD model, with rank 0 often used specially... */
   if(myid == 0)
   {
     printf("%d: We have %d processors", myid, numprocs);
     for(i=1;i<numprocs;i++)
     {
       sprintf(buff, "Hello %d! ", i);
       MPI_Send(buff, BUFSIZE, MPI_CHAR, i, TAG, MPI_COMM_WORLD);
     }
     for(i=1;i<numprocs;i++)
     {
       MPI_Recv(buff, BUFSIZE, MPI_CHAR, i, TAG, MPI_COMM_WORLD, &stat);
       printf("%d: %s", myid, buff);
     }
   }
   else
   {
     /* receive from rank 0: */
     MPI_Recv(buff, BUFSIZE, MPI_CHAR, 0, TAG, MPI_COMM_WORLD, &stat);
     sprintf(idstr, "Processor %d ", myid);
     strncat(buff, idstr, BUFSIZE-1);
     strncat(buff, "reporting for duty", BUFSIZE-1);
     /* send to rank 0: */
     MPI_Send(buff, BUFSIZE, MPI_CHAR, 0, TAG, MPI_COMM_WORLD);
   }
 
   MPI_Finalize(); /* MPI Programs end with MPI Finalize; this is a weak synchronization point */
   return 0;
 }

BAZ

    contents = TestHelper.get_random_alphanumeric(1024)
    folder = "hello-world-#{TestHelper.get_random_alphanumeric}"
    source = "HelloWorld.c"

    tmp_folder = "/tmp/#{folder}"
    FileUtils.mkdir_p(tmp_folder)
    compiled = "#{tmp_folder}-compiled"
    compiled_code = "#{compiled}/HelloWorld"

    local = "#{tmp_folder}/#{source}"
    TestHelper.write_file(local, ring_code)

    output = TestHelper.get_output_location(folder, storage)

    compile_mpi_code(tmp_folder, source, compiled)
    start_mpi_code(compiled_code, num_procs, output, storage)
    get_mpi_output(output, expected_output, storage)

    FileUtils.rm_rf(tmp_folder)
    FileUtils.rm_rf(compiled)
  end

  def compile_mpi_code(location, main_file, compiled)
    std_out, std_err = TestHelper.compile_code(location, main_file, compiled)

    make = "mpicc HelloWorld.c -o HelloWorld -Wall"
    msg = "The MPI code did not compile as expected. It should have " +
      "compiled with the command [#{make}] instead of [#{std_out}]."
    assert_equal(std_out, make, msg)

    msg = "The MPI code did not compile successfully. It reported " +
      "the following error: #{std_err}"
    assert_nil(std_err, msg)
  end

  def start_mpi_code(code_location, num_procs, output, storage)
    params = { :procs_to_use => num_procs }
    status = TestHelper.start_job("mpi", code_location, output, storage, params)

    msg = "Your job was not started successfully. The failure message " +
      "reported was #{status[:msg]}"
    assert_equal(status[:result], :success, msg)
  end

  def get_mpi_output(output, expected, storage)
    result = TestHelper.get_job_output(output, storage)

    msg = "The MPI job you ran did not return the expected result. " +
      "We expected to see [#{expected}] but instead saw [#{result}]"
    assert_equal(result, expected, msg)
  end
end 

