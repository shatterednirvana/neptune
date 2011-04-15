import x10.lang.Math;
import x10.util.Timer;

public class Ring {

  static val NUM_MESSAGES = 10;

  // A global datastructure with one integer cell per place
  static A = PlaceLocalHandle.make[Cell[Long]](Dist.makeUnique(), ()=>new Cell[Long](-1));

  public static def send (msg:Long, depth:Int) {
    A()() = msg;
    if (depth==0) return;
    async at (here.next()) send(msg, depth-1);
  }

  public static def main(args:Array[String](1)) {

    val startTime = Timer.milliTime();
    finish send(42L, NUM_MESSAGES * Place.MAX_PLACES);
    val endTime = Timer.milliTime();

    val totalTime = (endTime - startTime) / 1000.0;

    Console.OUT.printf("It took %f seconds\n", totalTime);
  }
}

