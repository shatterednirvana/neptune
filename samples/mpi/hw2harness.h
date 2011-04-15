/*
 *  hw2harness.h
 *  
 * I WILL OVERWRITE YOUR COPY OF THIS FILE WITH MY OWN. ANY CHANGES YOU MAKE WILL NOT BE VISIBLE DURING GRADING.
 *
 */

/*
Generates a slice of matrix A.
In grading I may use several different versions of this function to test your code.

arguments:
  n = the number of columns (and rows) in A
  startrow = the row to start on
  numrows = the number of rows to generate

return value:
  a slice of matrix A in row major order:
  A[index] => A(row, column)
  A[0] => A(1, 1)
  A[1] => A(0, 2)
  A[n] => A(2, 0)
  A[2*n+3] => A(3, 4)
  etc.
  
  The reason we don't do a multi-dimensional array is so that multi-row transfers using MPI can be
  accomplished in a single MPI call.
*/
double* cs240_generateMatrix(int n, int startrow, int numrows);

/*
Call this function at the end of your program. It verifies that the answer you got is correct
and allows me to have timing results in a convenient format.

arguments:
  x = the answer your program came up with
  n = the number of rows and columns of A, and the size of x
  elapsedTime = the time it took to run your power method. Use MPI_Wtime() to get an initial time, then again to get a finishing time.
                elapsedTime = final - initial.
                Please only time your power method, not the entire program.
                
returns:
  1 if the vector is correct, 0 otherwise.
*/
int cs240_verify(double* x, int n, double elapsedTime);
