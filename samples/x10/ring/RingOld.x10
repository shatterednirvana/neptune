import x10.lang.Math;
import x10.util.Timer;

public class Ring {

  static val NUM_MESSAGES = 2;
  static val P = Place.MAX_PLACES;

  /* Can't do message passing directly - so we'll use shared memory
   * to achieve the same goal. The basic idea is to give each processor
   * a single integer and have them wait for it to change values */

  static val R <: Region = (0..P-1);
  static val D <: Dist = Dist.makeBlock(R);	
  static val F <: (Point(1)) => Int = ([i]:Point(1)) => -1;	
  static val A <: DistArray[Int] = DistArray.make[Int](D, F);

  public static def send(target:Int, value:Int) {
    at (Place.place(target)) {
      A(target) = value;
    }

    return;
  }

  public static def recv(from:Int, value:Int) {
    while (A(here.id) != value) {
      Activity.sleep(10l);
    }

    return;
  }
	
  public static def main(args:Array[String](1)) {
    val startTime = Timer.milliTime();

    for (var index : Int = 0; index < NUM_MESSAGES; index++) {
      val i = index;
      finish for (p in Place.places()) {
        async at (p) {
          if (p.id == 0) { 
            Console.OUT.printf("master is sending message to node 1\n");
            Ring.send(1, i);

            Console.OUT.printf("master is waiting for message from node %d\n", P - 1);
            Ring.recv(P - 1, i);
          } else {
            Ring.recv(p.id - 1, i);

            if (p.id + 1 == P) {
              Console.OUT.printf("node %d is sending a message to node 0\n", p.id);
              Ring.send(0, i);
            } else {
              Console.OUT.printf("node %d is sending a message to node %d\n", p.id, p.id + 1);
              Ring.send(p.id + 1, i);
            }
          }
        }
      }
    }

    val endTime = Timer.milliTime();
    val totalTime = (endTime - startTime) / 1000.0;
    	   
    Console.OUT.printf("It took %f seconds\n", totalTime);
  }
}

