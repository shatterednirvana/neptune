#include <upc.h>
#include <upc_strict.h>
//#include <upc_relaxed.h>
#include <stdio.h>

#define NUM_MESSAGES 100

#define FROM_MASTER 0

#define size THREADS
#define rank MYTHREAD

#define MASTER(rank) (rank == 0)
#define SLAVE(rank) (!MASTER)

#define SUCCESS 0
#define FAILURE 1

#define DEBUG 0

shared int* a;
shared int* alldone;

int sendM(target, value) {
  a[target] = value;
  if (DEBUG) printf("[node %d] wrote value %d to location %d\n", rank, value, target);

  return 0;
}

int recvM(from, value) {
  int tempa = a[from];

  if (DEBUG) printf("[node %d] value at location %d is currently %d (should be %d)\n", rank, from, tempa, value);

  if (tempa == value) {
    if (DEBUG) printf("[node %d] returns success\n", rank);
    return SUCCESS;
  }
  else {
    if (DEBUG) printf("[node %d] returns failure\n", rank);
    return FAILURE;
  }
}

int main() {
  clock_t start_time, end_time;

  // start timing
  if (MASTER(rank)) {
    start_time = clock();
  }

  a = (shared int*) upc_all_alloc(size, sizeof(int));
  alldone = (shared int*) upc_all_alloc(1, sizeof(int));
  upc_barrier;

  if (MASTER(rank)) {
    int i = 0;
    for(i = 0; i < size; i++) {
      a[i] = 0;
      if (DEBUG) printf("A[%d] = %d\n", i, a[i]);
    }
  }

  alldone[0] = FAILURE;
  upc_barrier;

  int curr_msg = 1;
  for(curr_msg = 1; curr_msg <= NUM_MESSAGES; curr_msg++) {
    if (MASTER(rank)) a[0] = curr_msg;
    int msg_send = FAILURE;
    while(1) {
      int received = recvM(rank, curr_msg);
      if ((received == SUCCESS) && (rank + 1 == size)) {
          if (DEBUG) printf("got last message\n");
          alldone[0] = SUCCESS;
      } else if (received == SUCCESS) { 
        if (msg_send == FAILURE) {
          if (DEBUG) printf("[node %d] sends a message\n", rank);
          sendM(rank+1, curr_msg);
          msg_send = SUCCESS;
        }
        sleep(0.01);
      }

      upc_barrier;
      if (alldone[0] == SUCCESS) break;
    }

    upc_barrier;
    if (rank + 1 == size) alldone[0] = FAILURE;
    upc_barrier;
  }

  upc_barrier;
  if (DEBUG) {
    int i = 0;
    for(i = 0; i < size; i++) {
      printf("[node %d] says A[%d] = %d\n", rank, i, a[i]);
    }
  }

  // end timing
  if (MASTER(rank)) {
    end_time = clock();
  }

  if (MASTER(rank)) {
    double total_time = (double)(end_time - start_time) / CLOCKS_PER_SEC;
    printf("Total time taken to send %d messages across %d machines was %f\n", NUM_MESSAGES, size, total_time);
  }
  upc_barrier;
  return 0;
}

