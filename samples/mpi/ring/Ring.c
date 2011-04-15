#include <stdio.h>
#include <stdlib.h>
#include <math.h>
#include "mpi.h"

#define NUM_MESSAGES 10
#define FROM_MASTER 0

#define MASTER(rank) (rank == 0)
#define SLAVE(rank) (!MASTER)

//-----------------------------------------------------------------------

int main(int argc, char *argv[])
{
  int rank, size;
  double start_time = 0;
  double end_time = 0;
  MPI_Status status;

  MPI_Init(&argc,&argv);

  MPI_Comm_size(MPI_COMM_WORLD, &size); // p
  MPI_Comm_rank(MPI_COMM_WORLD, &rank);

  MPI_Barrier(MPI_COMM_WORLD);

  // start timing
  if (MASTER(rank)) {
    start_time = MPI_Wtime();
  }

  char* msg = "hello!";

  MPI_Barrier(MPI_COMM_WORLD);

  int index = 0;
  for (index = 0; index < NUM_MESSAGES; index++) {
    if (MASTER(rank)) {
      //printf("master is sending message to node 1\n");
      MPI_Send(&msg, 6, MPI_CHAR, 1, FROM_MASTER, MPI_COMM_WORLD);

      //printf("master is waiting for message from node %d\n", size - 1);
      MPI_Recv(&msg, 6, MPI_CHAR, size - 1, FROM_MASTER, MPI_COMM_WORLD, &status);
    } else {
      MPI_Recv(&msg, 6, MPI_CHAR, rank-1, FROM_MASTER, MPI_COMM_WORLD, &status);

      if (rank + 1 == size) {
        //printf("node %d is sending a message to node 0\n", rank);
        MPI_Send(&msg, 6, MPI_CHAR, 0, FROM_MASTER, MPI_COMM_WORLD);
      } else {
        //printf("node %d is sending a message to node %d\n", rank, rank + 1);
        MPI_Send(&msg, 6, MPI_CHAR, rank + 1, FROM_MASTER, MPI_COMM_WORLD);
      }
    }

    MPI_Barrier(MPI_COMM_WORLD);
  }

  MPI_Barrier(MPI_COMM_WORLD);
  if (MASTER(rank)) {
    end_time = MPI_Wtime();
  }
  // end timing

  if (MASTER(rank)) {
    printf("All done sending %d messages between %d nodes!\n", NUM_MESSAGES, size);
    printf("It took %f seconds\n", end_time-start_time);
  }

  //printf("calling MPI_Finalize()\n");
  MPI_Finalize();
  return(0);
}

//-----------------------------------------------------------------------
