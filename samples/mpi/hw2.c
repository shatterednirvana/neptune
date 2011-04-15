#include <stdio.h>
#include <stdlib.h>
#include <math.h>
#include "mpi.h"
#include "hw2harness.h"


#define NUM_ITERATIONS 10
#define FROM_MASTER 0

#define MASTER(rank) (rank == 0)
#define SLAVE(rank) (!MASTER)

double** A;
double* x;
int n, dim;

//-----------------------------------------------------------------------
void getNFromUser() {
  //printf("Please enter n, so that we can create an n x n matrix: ");
  //fflush(stdout);
  //scanf("%d", &n);
  
  n = 3072;

  MPI_Bcast(&n, 1, MPI_INT, FROM_MASTER, MPI_COMM_WORLD); 

  return;
}

//-----------------------------------------------------------------------
void receiveN() {
  MPI_Bcast(&n, 1, MPI_INT, FROM_MASTER, MPI_COMM_WORLD);
  return;
}

//-----------------------------------------------------------------------
int generateMatrix(int p, int rank) {
  MPI_Barrier(MPI_COMM_WORLD);

  if (MASTER(rank)) {
    getNFromUser();
  } else {
    receiveN();
  }

  MPI_Barrier(MPI_COMM_WORLD);

  if (n % p != 0) {
    if (MASTER(rank)) {
      printf("n doesn't divide p evenly. Please enter n and try again.\n");
    }
    return(1);
  }

  int starting = (n/p) * rank + 1;
  int ending = (n/p) * (rank + 1);
  dim = ending - starting + 1;
  //printf("Proc %d: Generating %d rows, %d through %d\n", rank, dim, starting, ending);

  double* A_tmp = cs240_generateMatrix(n,starting-1,dim);
  int cnt = 0;
  

  A = malloc(dim * sizeof(double*));
  int outer = 0;
  int inner = 0;
  for (outer = 0; outer < dim; outer++) {
    A[outer] = malloc(n * sizeof(double));
    for (inner = 0; inner < n; inner++) {
      //A[outer][inner] = 1.0f;
      A[outer][inner] = A_tmp[cnt];
      cnt++;
    }
  }

  x = malloc(n * sizeof(double));
  int index = 0;
  for (index = 0; index < n; index++) {
    x[index] = 1;
  }

  return(0);
}

//-----------------------------------------------------------------------
double norm() {
  double theNorm = 0;

  int index = 0;

  for (index = 0; index < n; index++) {
    theNorm += (x[index] * x[index]);
  }

  theNorm = sqrt(theNorm);

  return theNorm;
}

//-----------------------------------------------------------------------
void matVec(int rank) {
  int index = 0;
  MPI_Bcast(x, n, MPI_DOUBLE, FROM_MASTER, MPI_COMM_WORLD);
  MPI_Barrier(MPI_COMM_WORLD);

  double* result = malloc(dim * sizeof(double));
  int outer = 0;
  for (outer = 0; outer < dim; outer++) {
    double sum = 0;
    int inner = 0;
    for (inner = 0; inner < n; inner++) {
      sum += (A[outer][inner] * x[inner]);
    }
    result[outer] = sum;
  }

  MPI_Barrier(MPI_COMM_WORLD);
  MPI_Gather(result, dim, MPI_DOUBLE, x, dim, MPI_DOUBLE, FROM_MASTER, MPI_COMM_WORLD);
  MPI_Barrier(MPI_COMM_WORLD);
  free(result);
  return;
}

//-----------------------------------------------------------------------
double powerMethod(int rank) {
  MPI_Barrier(MPI_COMM_WORLD);
  double xNorm = 0;

  int iteration = 0;
  for (iteration = 0; iteration < NUM_ITERATIONS; iteration++) {
    if (MASTER(rank)) {
      xNorm = norm();
      //printf("At iteration %d, the norm of x is %f\n", iteration, xNorm);

      int index = 0;
      for (index = 0; index < n; index++) {
        x[index] = x[index] / xNorm;
        //printf("x[%d] = %f\n", index, x[index]);
      }
    }

    MPI_Barrier(MPI_COMM_WORLD);
    matVec(rank);
    MPI_Barrier(MPI_COMM_WORLD);
  }

  MPI_Barrier(MPI_COMM_WORLD);
  return xNorm;
}

//-----------------------------------------------------------------------

int main(int argc, char *argv[])
{
  int rank, size;
  double start_time,end_time;
  MPI_Init(&argc,&argv);

  MPI_Comm_size(MPI_COMM_WORLD, &size); // p
  MPI_Comm_rank(MPI_COMM_WORLD, &rank);

  MPI_Barrier(MPI_COMM_WORLD);
  int retval = generateMatrix(size, rank);    
  if (retval != 0) {
    MPI_Finalize();
    return retval;  
  }
  MPI_Barrier(MPI_COMM_WORLD);
  // start timing
  if (MASTER(rank)) {
    start_time = MPI_Wtime();
  }
  double spectralRadius = powerMethod(rank);
  if (MASTER(rank)) {
    end_time = MPI_Wtime();
  }
  // end timing

  if (MASTER(rank)) {
    printf("The spectral radius is %f\n", spectralRadius);
    printf("It took %f seconds\n", end_time-start_time);

    /*
    int index = 0;
    for (index = 0; index < n; index++) {
      printf("%f ", x[index]);
    }
    printf("\nsize of n is %d\n", n);
    */
    // checking
    if(cs240_verify(x,n,end_time-start_time)>0){
        printf("yay, we win!\n");
    }else{
        printf("Boo, we lose... again\n");
    }
  }


  //printf("calling MPI_Finalize()\n");
  MPI_Finalize();
  return(0);
}

//-----------------------------------------------------------------------
