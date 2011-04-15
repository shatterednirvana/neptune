import x10.lang.Math;
import x10.util.Timer;

public class MyPowerMethod {

	static val SUCCESS = 0;
	static val ERROR = 1;
	
	static val NUM_ITERATIONS = 30;
	static val EPSILON = 0.00001;
	
	static val N = 6400;
	static val P = Place.MAX_PLACES;
	
	/*
	 * X vector is of size n x 1 and lives on the first processor
	 * is initialized to one
	 */

	static val R1 <: Region = (0..N-1);
	static val D1 <: Dist = R1 -> Place.FIRST_PLACE;
	//static val F0 <: (Point(1)) => Double = ([i]:Point(1)) => 0.0;
	static val F1 <: (Point(1)) => Double = ([i]:Point(1)) => 1.0;
	static val X <: DistArray[Double] = DistArray.make[Double](D1, F1);
	
	/*
	 * A matrix is of size n x n and lives on all processors
	 * each proc gets a block of size (n/p) x n where p is the
	 * number of processors
	 * is initialized to zero
	 */

	static val R2 <: Region = (0..N-1) * (0..N-1);
	static val D2 <: Dist = Dist.makeBlock(R2);	
	static val F2 <: (Point(2)) => Double = ([i, j]:Point(2)) => 0.0;	
	static val A <: DistArray[Double] = DistArray.make[Double](D2, F2);
		
	public static def norm() {
		var theNorm : Double = 0.0;
		
		for (var index : Int = 0; index < N; index++) {
			theNorm += (X(index) * X(index));
		}
		
		return Math.sqrt(theNorm);
	}	

	public static def matVec() {
		// new way - should be nice and fast
		val D0 <: Dist = Dist.makeBlock(R1);
		val F0 <: (Point(1)) => Double = ([i]:Point(1)) => 0.0;
		val XTemp = DistArray.make[Double](D0, F0);

		finish {
			for (place in A.dist().places()) {
				async at (place) {
          				val DHere <: Dist = R1 -> here;
					val XCopy = DistArray.make[Double](DHere, F0);
					for (var i : Int = 0; i < N; i++) {
 						val index = i;
						XCopy(index) = at (Place.FIRST_PLACE) { X(index) };
 					}

					//Console.OUT.printf("my place id is %d, next id is %d\n", place.id, place.next().id);

					var startRow : Int = place.id * N / P;
					var endRow : Int = (place.id + 1) * N / P;
					//if (endRow == 0) { endRow = startRow + N / P; }
				
					//Console.OUT.printf("start row is %d, end row is %d\n", startRow, endRow);
	
					for (var row : Int = startRow; row < endRow; row++) {
						var sum : Double = 0;
						for (var col : Int = 0; col < N; col++) {
							val inner = col;
     							sum += (A(row,col) * XCopy(col));
							//val XPoint = at (Place.FIRST_PLACE) { X(inner) };
							//sum += (A(row,col) * XPoint);
    							//Console.OUT.printf("A(%d,%d) * X(%d) = %d * %d\n", row, col, inner, A(row,col), XPoint);
						}
						XTemp(row) = sum;
						//Console.OUT.printf("setting x(%d) to %f\n", row, sum);
					}
				}
			}
		}

		for (var index : Int = 0; index < N; index++) {
			val row = Point.make(index);
			val correctPlace = XTemp.dist.apply(row);
			val XNew = at (correctPlace) { XTemp(row) };
			X(index) = XNew;
			//Console.OUT.printf("actually setting x(%d) to %f\n", index, XNew);
		}

		// old way - slow on big sizes of N
		/* 	
		val D0 <: Dist = R1 -> here;
		val F0 <: (Point(1)) => Double = ([i]:Point(1)) => 0.0;
		val XTemp = DistArray.make[Double](D0, F0);		
		for (var outer : Int = 0; outer < N; outer++) {
			val sum : Array[Double](1) = new Array[Double](1);
			sum(0) = 0;
			for (var inner : Int = 0; inner < N; inner++) {
				val inner1DPoint = Point.make(inner);
				val inner2DPoint = Point.make(outer,inner);
				val correctPlace = A.dist.apply(inner2DPoint);
				val XPoint = X(inner1DPoint);
				sum(0) += at (correctPlace) {
					(A(inner2DPoint) * XPoint)
				};
				//Console.OUT.printf("[out] sum is now %f\n", sum(0));
			}
			XTemp(outer) = sum(0);
			//Console.OUT.printf("XTemp(%d) is now %f\n", outer, sum(0));
		}
		 
		//Console.OUT.println("After Matvec:");
		for (var index : Int = 0; index < N; index++) {
			X(index) = XTemp(index);
	        //Console.OUT.printf("x[%d] = %f\n", index, X(index));
		} 
	*/
		return;
	}	
	
	 public static def powerMethod() {
		var xNorm : Double = 0;		

		for (var iter : Int = 0; iter < NUM_ITERATIONS; iter++) {
			xNorm = norm();
			Console.OUT.printf("At iteration %d, the norm of x is %f\n", iter, xNorm);
			
			for (var index : Int = 0; index < N; index++) {
				val myIndex = index;
				val myXNorm = xNorm;
				X(myIndex) = X(myIndex) / myXNorm;
				//Console.OUT.printf("x[%d] = %f\n", index, X(index));
			}
		 	Console.OUT.printf("entering matvec\n");	
			matVec();
		}

		for (var index : Int = 0; index < N; index++) {
			val myIndex = index;
			val myXNorm = xNorm;
			//Console.OUT.printf("final x[%d] = %f\n", index, X(index));
		}

		return xNorm;
	 }

	public static def generateMatrix() {
		if (N % P != 0) {
			Console.OUT.println("n doesn't divide p evenly. Please enter n and try again.");
			return ERROR;
		}		
		
		// put the value N at the diagonals
		finish {	
			for (var i : Int = 0; i < N; i++) {
				val diagonal = Point.make(i, i);
				val correctPlace = A.dist.apply(diagonal);
				async at (correctPlace) {
					A(diagonal) = N;
				}
			}
		}

		return SUCCESS;
	}
	
	public static def verify() {
		val answer = Math.sqrt(N + 0.0f);
		for (var i : Int = 0; i < N; i++) {
			val diff = Math.abs(X(i) - answer);
			if (diff > EPSILON) {
				Console.OUT.printf("X(%d)'s value, %f, was too far away from %f\n", i, X(i), answer);
				return ERROR;
			}
		}
		
		return SUCCESS;
	}
	
	public static def printArray[T](array:DistArray[T]) {
		for (place in array.dist.places()) {
			at (place) {
				for (point in array.dist | here ) {
					val myPoint : String = "[" + point(0) + ", " + point(1) + "] ->" + array(point);
					Console.OUT.println(myPoint);
				}
			}
		}
		
		return;
	} 

    public static def main(args:Array[String](1)) {
    	//Console.OUT.println("str(x) = " + X);
    	//printArray(X);
    	//Console.OUT.println("str(a) = " + A);
    	//printArray(A);

		Console.OUT.println("n is " + N);
		Console.OUT.println("p is " + P);
		
    	val retval = generateMatrix();
    	if (retval == ERROR) {
    		Console.OUT.println("ERROR");
    		return;
    	}
    	
       	//Console.OUT.println("str(x) = " + X);
    	//printArray(X);
    	//Console.OUT.println("str(a) = " + A);
    	//printArray(A);

    	val startTime = Timer.milliTime();
    	val spectralRadius = powerMethod();
    	val endTime = Timer.milliTime();
    	val totalTime = (endTime - startTime) / 1000.0;
    	   
    	Console.OUT.printf("The spectral radius is %f\n", spectralRadius);
   		Console.OUT.printf("It took %f seconds\n", totalTime);

   		//printArray(X);

   		val result = verify();
   		if (result == SUCCESS) {
   			Console.OUT.printf("Yay, we win!\n");
   		} else {
   			Console.OUT.printf("Boo, we lose... again\n");
   		}   			
	}
}
