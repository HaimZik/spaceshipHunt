package DDLS.data
{
	import DDLS.data.math.DDLSGeom2D;
	import DDLS.data.math.DDLSMatrix2D;
	import DDLS.data.math.DDLSPoint2D;
	import DDLS.iterators.IteratorFromVertexToOutgoingEdges;
	import DDLS.factories.DDLSPool;
    import flash.utils.Dictionary;
	
	public class DDLSMesh
	{
		protected var vertexToDelete:Vector.<DDLSVertex> = new Vector.<DDLSVertex>();
		
		private static var INC:int = 0;
		private var _id:int;
		
		private var _width:Number;
		private var _height:Number;
		private var _clipping:Boolean;
		
		private var _vertices:Vector.<DDLSVertex>;
		private var _edges:Vector.<DDLSEdge>;
		private var _faces:Vector.<DDLSFace>;
		private var _constraintShapes:Vector.<DDLSConstraintShape>;
		private var _objects:Vector.<DDLSObject>;
		
		// keep references of center vertex and bounding edges when split, useful to restore edges as Delaunay
		private var __centerVertex:DDLSVertex;
		private var __edgesToCheck:Vector.<DDLSEdge>;
		
		private var outgoingEdges:Vector.<DDLSEdge> = new Vector.<DDLSEdge>();
		private var boundTemp:Vector.<DDLSEdge> = new Vector.<DDLSEdge>();
		
		private var iterEdges:IteratorFromVertexToOutgoingEdges = new IteratorFromVertexToOutgoingEdges();
		
		public function DDLSMesh(width:Number, height:Number)
		{
			_id = INC;
			INC++;
			
			_width = width;
			_height = height;
			_clipping = true;
			
			_vertices = new Vector.<DDLSVertex>();
			_edges = new Vector.<DDLSEdge>();
			_faces = new Vector.<DDLSFace>();
			_constraintShapes = new Vector.<DDLSConstraintShape>();
			_objects = new Vector.<DDLSObject>();
			
			__edgesToCheck = new Vector.<DDLSEdge>();
		}
		
		public function get height():Number
		{
			return _height;
		}
		
		public function get width():Number
		{
			return _width;
		}
		
		public function get clipping():Boolean
		{
			return _clipping;
		}
		
		public function set clipping(value:Boolean):void
		{
			_clipping = value;
		}
		
		public function get id():int
		{
			return _id;
		}
		
		public function dispose():void
		{
			while (_vertices.length > 0)
				_vertices.pop().dispose();
			_vertices = null;
			while (_edges.length > 0)
				_edges.pop().dispose();
			_edges = null;
			while (_faces.length > 0)
				_faces.pop().dispose();
			_faces = null;
			while (_constraintShapes.length > 0)
				_constraintShapes.pop().dispose();
			_constraintShapes = null;
			while (_objects.length > 0)
				_objects.pop().dispose();
			_objects = null;
			
			__edgesToCheck = null;
			__centerVertex = null;
		}
		
		[Inline]
		public final function get __vertices():Vector.<DDLSVertex>
		{
			return _vertices;
		}
		
		public function get __edges():Vector.<DDLSEdge>
		{
			return _edges;
		}
		
		public function get __faces():Vector.<DDLSFace>
		{
			return _faces;
		}
		
		public function get __constraintShapes():Vector.<DDLSConstraintShape>
		{
			return _constraintShapes;
		}
		
		public function buildFromRecord(rec:String):void
		{
			var positions:Array = rec.split(';');
			for (var i:int = 0; i < positions.length; i += 4)
			{
				insertConstraintSegment(Number(positions[i]), Number(positions[i + 1]), Number(positions[i + 2]), Number(positions[i + 3]));
			}
		}
		
		public function insertObject(object:DDLSObject):void
		{
			if (object.constraintShape)
				deleteObject(object);
			
			var shape:DDLSConstraintShape = new DDLSConstraintShape();
			var segment:DDLSConstraintSegment;
			var coordinates:Vector.<Number> = object.coordinates;
			var m:DDLSMatrix2D = object.matrix;
			
			object.updateMatrixFromValues();
			var x1:Number;
			var y1:Number;
			var x2:Number;
			var y2:Number;
			var transfx1:Number;
			var transfy1:Number;
			var transfx2:Number;
			var transfy2:Number;
			
			for (var i:int = 0; i < coordinates.length; i += 4)
			{
				x1 = coordinates[i];
				y1 = coordinates[i + 1];
				x2 = coordinates[i + 2];
				y2 = coordinates[i + 3];
				transfx1 = m.transformX(x1, y1);
				transfy1 = m.transformY(x1, y1);
				transfx2 = m.transformX(x2, y2);
				transfy2 = m.transformY(x2, y2);
				
				segment = insertConstraintSegment(transfx1, transfy1, transfx2, transfy2);
				if (segment)
				{
					segment.fromShape = shape;
					shape.segments.push(segment);
				}
			}
			
			_constraintShapes.push(shape);
			object.constraintShape = shape;
			
			if (!__objectsUpdateInProgress)
			{
				_objects.push(object);
			}
		}
		
		public function deleteObject(object:DDLSObject):void
		{
			if (!object.constraintShape)
				return;
			
			deleteConstraintShape(object.constraintShape);
			object.constraintShape = null;
			
			if (!__objectsUpdateInProgress)
			{
				var index:int = _objects.indexOf(object);
				_objects.removeAt(index);
			}
		}
		
		private var __objectsUpdateInProgress:Boolean;
		
		public function updateObjects():void
		{
			__objectsUpdateInProgress = true;
			for (var i:int = 0; i < _objects.length; i++)
			{
				if (_objects[i].hasChanged)
				{
					deleteObject(_objects[i]);
					insertObject(_objects[i]);
					_objects[i].hasChanged = false;
				}
			}
			__objectsUpdateInProgress = false;
		}
		
		// insert a new collection of constrained edges.
		// Coordinates parameter is a list with form [x0, y0, x1, y1, x2, y2, x3, y3, x4, y4, ....]
		// where each 4-uple sequence (xi, yi, xi+1, yi+1) is a constraint segment (with i % 4 == 0)
		// and where each couple sequence (xi, yi) is a point.
		// Segments are not necessary connected.
		// Segments can overlap (then they will be automaticaly subdivided).
		public function insertConstraintShape(coordinates:Vector.<Number>):DDLSConstraintShape
		{
			var shape:DDLSConstraintShape = new DDLSConstraintShape();
			var segment:DDLSConstraintSegment;
			
			for (var i:int = 0; i < coordinates.length; i += 4)
			{
				segment = insertConstraintSegment(coordinates[i], coordinates[i + 1], coordinates[i + 2], coordinates[i + 3]);
				if (segment)
				{
					segment.fromShape = shape;
					shape.segments.push(segment);
				}
			}
			
			_constraintShapes.push(shape);
			
			return shape;
		}
		
		public function deleteConstraintShape(shape:DDLSConstraintShape):void
		{
			for (var i:int = 0; i < shape.segments.length; i++)
			{
				deleteConstraintSegment(shape.segments[i]);
			}
			
			shape.dispose();
			
			_constraintShapes.removeAt(_constraintShapes.indexOf(shape));
		}
		
		public function insertConstraintSegment(x1:Number, y1:Number, x2:Number, y2:Number):DDLSConstraintSegment
		{
			//trace("insertConstraintSegment");
			
			/* point positions relative to bounds
			   1 | 2 | 3
			   ------------
			   8 | 0 | 4
			   ------------
			   7 | 6 | 5
			 */
			var p1pos:int = findPositionFromBounds(x1, y1);
			var p2pos:int = findPositionFromBounds(x2, y2);
			
			var newX1:Number = x1;
			var newY1:Number = y1;
			var newX2:Number = x2;
			var newY2:Number = y2;
			// need clipping if activated and if one end point is outside bounds
			if (_clipping && (p1pos != 0 || p2pos != 0))
			{
				var intersectPoint:DDLSPoint2D = new DDLSPoint2D();
				
				// if both end points are outside bounds
				if (p1pos != 0 && p2pos != 0)
				{
					// if both end points are on same side
					if ((x1 <= 0 && x2 <= 0) || (x1 >= _width && x2 >= _width) || (y1 <= 0 && y2 <= 0) || (y1 >= _height && y2 >= _height))
						return null;
					
					// if end points are in separated left and right areas
					if ((p1pos == 8 && p2pos == 4) || (p1pos == 4 && p2pos == 8))
					{
						// intersection with left bound
						DDLSGeom2D.intersections2segments(x1, y1, x2, y2, 0, 0, 0, _height, intersectPoint);
						newX1 = intersectPoint.x;
						newY1 = intersectPoint.y;
						// intersection with right bound
						DDLSGeom2D.intersections2segments(x1, y1, x2, y2, _width, 0, _width, _height, intersectPoint);
						newX2 = intersectPoint.x;
						newY2 = intersectPoint.y;
					}
					// if end points are in separated top and bottom areas
					else if ((p1pos == 2 && p2pos == 6) || (p1pos == 6 && p2pos == 2))
					{
						// intersection with top bound
						DDLSGeom2D.intersections2segments(x1, y1, x2, y2, 0, 0, _width, 0, intersectPoint);
						newX1 = intersectPoint.x;
						newY1 = intersectPoint.y;
						// intersection with bottom bound
						DDLSGeom2D.intersections2segments(x1, y1, x2, y2, 0, _height, _width, _height, intersectPoint);
						newX2 = intersectPoint.x;
						newY2 = intersectPoint.y;
					}
					// if ends points are apart of the top-left corner
					else if ((p1pos == 2 && p2pos == 8) || (p1pos == 8 && p2pos == 2))
					{
						// check if intersection with top bound
						if (DDLSGeom2D.intersections2segments(x1, y1, x2, y2, 0, 0, _width, 0, intersectPoint))
						{
							newX1 = intersectPoint.x;
							newY1 = intersectPoint.y;
							
							// must have intersection with left bound
							DDLSGeom2D.intersections2segments(x1, y1, x2, y2, 0, 0, 0, _height, intersectPoint);
							newX2 = intersectPoint.x;
							newY2 = intersectPoint.y;
						}
						else
							return null
					}
					// if ends points are apart of the top-right corner
					else if ((p1pos == 2 && p2pos == 4) || (p1pos == 4 && p2pos == 2))
					{
						// check if intersection with top bound
						if (DDLSGeom2D.intersections2segments(x1, y1, x2, y2, 0, 0, _width, 0, intersectPoint))
						{
							newX1 = intersectPoint.x;
							newY1 = intersectPoint.y;
							
							// must have intersection with right bound
							DDLSGeom2D.intersections2segments(x1, y1, x2, y2, _width, 0, _width, _height, intersectPoint);
							newX2 = intersectPoint.x;
							newY2 = intersectPoint.y;
						}
						else
							return null
					}
					// if ends points are apart of the bottom-right corner
					else if ((p1pos == 6 && p2pos == 4) || (p1pos == 4 && p2pos == 6))
					{
						// check if intersection with bottom bound
						if (DDLSGeom2D.intersections2segments(x1, y1, x2, y2, 0, _height, _width, _height, intersectPoint))
						{
							newX1 = intersectPoint.x;
							newY1 = intersectPoint.y;
							
							// must have intersection with right bound
							DDLSGeom2D.intersections2segments(x1, y1, x2, y2, _width, 0, _width, _height, intersectPoint);
							newX2 = intersectPoint.x;
							newY2 = intersectPoint.y;
						}
						else
							return null
					}
					// if ends points are apart of the bottom-left corner
					else if ((p1pos == 8 && p2pos == 6) || (p1pos == 6 && p2pos == 8))
					{
						// check if intersection with bottom bound
						if (DDLSGeom2D.intersections2segments(x1, y1, x2, y2, 0, _height, _width, _height, intersectPoint))
						{
							newX1 = intersectPoint.x;
							newY1 = intersectPoint.y;
							
							// must have intersection with left bound
							DDLSGeom2D.intersections2segments(x1, y1, x2, y2, 0, 0, 0, _height, intersectPoint);
							newX2 = intersectPoint.x;
							newY2 = intersectPoint.y;
						}
						else
							return null
					}
					// other cases (could be optimized)
					else
					{
						var firstDone:Boolean = false;
						var secondDone:Boolean = false;
						// check top bound
						if (DDLSGeom2D.intersections2segments(x1, y1, x2, y2, 0, 0, _width, 0, intersectPoint))
						{
							newX1 = intersectPoint.x;
							newY1 = intersectPoint.y;
							firstDone = true;
						}
						// check right bound
						if (DDLSGeom2D.intersections2segments(x1, y1, x2, y2, _width, 0, _width, _height, intersectPoint))
						{
							if (!firstDone)
							{
								newX1 = intersectPoint.x;
								newY1 = intersectPoint.y;
								firstDone = true;
							}
							else
							{
								newX2 = intersectPoint.x;
								newY2 = intersectPoint.y;
								secondDone = true;
							}
						}
						// check bottom bound
						if (!secondDone && DDLSGeom2D.intersections2segments(x1, y1, x2, y2, 0, _height, _width, _height, intersectPoint))
						{
							if (!firstDone)
							{
								newX1 = intersectPoint.x;
								newY1 = intersectPoint.y;
								firstDone = true;
							}
							else
							{
								newX2 = intersectPoint.x;
								newY2 = intersectPoint.y;
								secondDone = true;
							}
						}
						// check left bound
						if (!secondDone && DDLSGeom2D.intersections2segments(x1, y1, x2, y2, 0, 0, 0, _height, intersectPoint))
						{
							newX2 = intersectPoint.x;
							newY2 = intersectPoint.y;
						}
						
						if (!firstDone)
							return null;
					}
				}
				// one end point of segment is outside bounds and one is inside
				else
				{
					// if one point is outside top
					if (p1pos == 2 || p2pos == 2)
					{
						// intersection with top bound
						DDLSGeom2D.intersections2segments(x1, y1, x2, y2, 0, 0, _width, 0, intersectPoint);
					}
					// if one point is outside right
					else if (p1pos == 4 || p2pos == 4)
					{
						// intersection with right bound
						DDLSGeom2D.intersections2segments(x1, y1, x2, y2, _width, 0, _width, _height, intersectPoint);
					}
					// if one point is outside bottom
					else if (p1pos == 6 || p2pos == 6)
					{
						// intersection with bottom bound
						DDLSGeom2D.intersections2segments(x1, y1, x2, y2, 0, _height, _width, _height, intersectPoint);
					}
					// if one point is outside left
					else if (p1pos == 8 || p2pos == 8)
					{
						// intersection with left bound
						DDLSGeom2D.intersections2segments(x1, y1, x2, y2, 0, 0, 0, _height, intersectPoint);
					}
					// other cases (could be optimized)
					else
					{
						// check top bound
						if (!DDLSGeom2D.intersections2segments(x1, y1, x2, y2, 0, 0, _width, 0, intersectPoint))
						{
							// check right bound
							if (!DDLSGeom2D.intersections2segments(x1, y1, x2, y2, _width, 0, _width, _height, intersectPoint))
							{
								// check bottom bound
								if (!DDLSGeom2D.intersections2segments(x1, y1, x2, y2, 0, _height, _width, _height, intersectPoint))
								{
									// check left bound
									DDLSGeom2D.intersections2segments(x1, y1, x2, y2, 0, 0, 0, _height, intersectPoint);
								}
							}
						}
					}
					
					if (p1pos == 0)
					{
						newX1 = x1;
						newY1 = y1;
					}
					else
					{
						newX1 = x2;
						newY1 = y2;
					}
					newX2 = intersectPoint.x;
					newY2 = intersectPoint.y;
				}
			}
			
			// we check the vertices insertions
			var vertexDown:DDLSVertex = insertVertex(newX1, newY1);
			if (!vertexDown)
				return null;
			var vertexUp:DDLSVertex = insertVertex(newX2, newY2);
			if (!vertexUp)
				return null;
			if (vertexDown == vertexUp)
				return null;
			
			//trace("vertices", vertexDown.id, vertexUp.id)
			
			var currVertex:DDLSVertex;
			var currEdge:DDLSEdge;
			var i:int;
			
			// the new constraint segment
			var segment:DDLSConstraintSegment = new DDLSConstraintSegment();
			
			var tempEdgeDownUp:DDLSEdge = DDLSPool.getDDLSEdge();
			var tempSdgeUpDown:DDLSEdge = DDLSPool.getDDLSEdge();
			tempEdgeDownUp.setDatas(vertexDown, tempSdgeUpDown, null, null, true, true);
			tempSdgeUpDown.setDatas(vertexUp, tempEdgeDownUp, null, null, true, true);
			
			var intersectedEdges:Vector.<DDLSEdge> = DDLSPool.getDDLSEdgeVector();
			var leftBoundingEdges:Vector.<DDLSEdge> = DDLSPool.getDDLSEdgeVector();
			var rightBoundingEdges:Vector.<DDLSEdge> = DDLSPool.getDDLSEdgeVector();
			
			var currObjet:Object;
			var pIntersect:DDLSPoint2D = DDLSPool.getPoint();
			var edgeLeft:DDLSEdge;
			var newEdgeDownUp:DDLSEdge;
			var newEdgeUpDown:DDLSEdge;
			var done:Boolean;
			currVertex = vertexDown;
			currObjet = currVertex;
			var iterationCount:int = 0;
			var maxIteration:int = 5000;
			while (true)
			{
				if (iterationCount > maxIteration)
				{
					trace("entered infinty loop in insertConstraintSegment");
					return segment;
				}
				iterationCount++;
				done = false;
				currVertex = currObjet as DDLSVertex
				if (currVertex)
				{
					//trace("case vertex");
					if (currVertex.edge == null)
					{
						trace("currVertex.edge was null");
						return null;
					}
					iterEdges.fromRealVertex = currVertex;
					currEdge = iterEdges.nextRealEdge();
					while (currEdge)
					{
						// if we meet directly the end vertex
						if (currEdge.destinationVertex == vertexUp)
						{
							//trace("we met the end vertex");
							if (!currEdge.isConstrained)
							{
								currEdge.isConstrained = true;
								currEdge.oppositeEdge.isConstrained = true;
							}
							currEdge.addFromConstraintSegment(segment);
							currEdge.oppositeEdge.fromConstraintSegments = currEdge.fromConstraintSegments;
							vertexDown.addFromConstraintSegment(segment);
							vertexUp.addFromConstraintSegment(segment);
							segment.addEdge(currEdge);
							DDLSPool.putDDLSEdge(tempEdgeDownUp);
							DDLSPool.putDDLSEdge(tempSdgeUpDown);
							DDLSPool.putPoint(pIntersect);
	                        DDLSPool.putDDLSEdgeVector(intersectedEdges);
	                        DDLSPool.putDDLSEdgeVector(leftBoundingEdges);
	                        DDLSPool.putDDLSEdgeVector(rightBoundingEdges);
							return segment;
						}
						// if we meet a vertex
						if (DDLSGeom2D.distanceSquaredVertexToEdge(currEdge.destinationVertex, tempEdgeDownUp) <= DDLSConstants.EPSILON_SQUARED)
						{
							//trace("we met a vertex");
							if (!currEdge.isConstrained)
							{
								//trace("edge is not constrained");
								currEdge.isConstrained = true;
								currEdge.oppositeEdge.isConstrained = true;
							}
							currEdge.addFromConstraintSegment(segment);
							currEdge.oppositeEdge.fromConstraintSegments = currEdge.fromConstraintSegments;
							vertexDown.addFromConstraintSegment(segment);
							segment.addEdge(currEdge);
							vertexDown = currEdge.destinationVertex;
							tempEdgeDownUp.originVertex = vertexDown;
							currObjet = vertexDown;
							done = true;
							break;
						}
						currEdge = iterEdges.nextRealEdge();
					}
					
					if (done)
						continue;
					
					iterEdges.fromRealVertex = currVertex;
					currEdge = iterEdges.nextRealEdge();
					while (currEdge)
					{
						currEdge = currEdge.nextLeftEdge;
						if (DDLSGeom2D.intersections2edges(currEdge, tempEdgeDownUp, pIntersect))
						{
							//trace("edge intersection");
							if (currEdge.isConstrained)
							{
								//trace("edge is constrained");
								vertexDown = splitEdge(currEdge, pIntersect.x, pIntersect.y);
								iterEdges.fromRealVertex = currVertex;
								currEdge = iterEdges.nextRealEdge();
								while (currEdge)
								{
									if (currEdge.destinationVertex == vertexDown)
									{
										currEdge.isConstrained = true;
										currEdge.oppositeEdge.isConstrained = true;
										currEdge.addFromConstraintSegment(segment);
										currEdge.oppositeEdge.fromConstraintSegments = currEdge.fromConstraintSegments;
										segment.addEdge(currEdge);
										break;
									}
									currEdge = iterEdges.nextRealEdge();
								}
								currVertex.addFromConstraintSegment(segment);
								tempEdgeDownUp.originVertex = vertexDown;
								currObjet = vertexDown;
							}
							else
							{
								//trace("edge is not constrained");
								intersectedEdges.push(currEdge);
								leftBoundingEdges.unshift(currEdge.nextLeftEdge);
								rightBoundingEdges.push(currEdge.prevLeftEdge);
								currEdge = currEdge.oppositeEdge; // we keep the edge from left to right
								currObjet = currEdge;
							}
							break;
						}
						currEdge = iterEdges.nextRealEdge()
					}
				}
				else if ((currEdge = currObjet as DDLSEdge))
				{
					//trace("case edge");
					edgeLeft = currEdge.nextLeftEdge;
					if (edgeLeft.destinationVertex == vertexUp)
					{
						//trace("end point reached");
						leftBoundingEdges.unshift(edgeLeft.nextLeftEdge);
						rightBoundingEdges.push(edgeLeft);
						
						newEdgeDownUp = DDLSPool.getDDLSEdge();
						newEdgeUpDown = DDLSPool.getDDLSEdge();
						newEdgeDownUp.setDatas(vertexDown, newEdgeUpDown, null, null, true, true);
						newEdgeUpDown.setDatas(vertexUp, newEdgeDownUp, null, null, true, true);
						leftBoundingEdges.push(newEdgeDownUp);
						rightBoundingEdges.push(newEdgeUpDown);
						insertNewConstrainedEdge(segment, newEdgeDownUp, intersectedEdges, leftBoundingEdges, rightBoundingEdges);
						DDLSPool.putDDLSEdge(tempEdgeDownUp);
						DDLSPool.putDDLSEdge(tempSdgeUpDown);
						DDLSPool.putPoint(pIntersect);
						DDLSPool.putDDLSEdgeVector(intersectedEdges);
						DDLSPool.putDDLSEdgeVector(leftBoundingEdges);
						DDLSPool.putDDLSEdgeVector(rightBoundingEdges);
						return segment;
					}
					else if (DDLSGeom2D.distanceSquaredVertexToEdge(edgeLeft.destinationVertex, tempEdgeDownUp) <= DDLSConstants.EPSILON_SQUARED)
					{
						//trace("we met a vertex");
						leftBoundingEdges.unshift(edgeLeft.nextLeftEdge);
						rightBoundingEdges.push(edgeLeft);
						
						newEdgeDownUp = DDLSPool.getDDLSEdge();
						newEdgeUpDown = DDLSPool.getDDLSEdge();
						newEdgeDownUp.setDatas(vertexDown, newEdgeUpDown, null, null, true, true);
						newEdgeUpDown.setDatas(edgeLeft.destinationVertex, newEdgeDownUp, null, null, true, true);
						leftBoundingEdges.push(newEdgeDownUp);
						rightBoundingEdges.push(newEdgeUpDown);
						insertNewConstrainedEdge(segment, newEdgeDownUp, intersectedEdges, leftBoundingEdges, rightBoundingEdges);
						
						intersectedEdges.length = 0;
						leftBoundingEdges.length = 0;
						rightBoundingEdges.length = 0;
						
						vertexDown = edgeLeft.destinationVertex;
						tempEdgeDownUp.originVertex = vertexDown;
						currObjet = vertexDown;
					}
					else
					{
						if (DDLSGeom2D.intersections2edges(edgeLeft, tempEdgeDownUp, pIntersect))
						{
							//trace("1st left edge intersected");
							if (edgeLeft.isConstrained)
							{
								//trace("edge is constrained");
								currVertex = splitEdge(edgeLeft, pIntersect.x, pIntersect.y);
								
								iterEdges.fromRealVertex = currVertex;
								currEdge = iterEdges.nextRealEdge()
								while (currEdge)
								{
									if (currEdge.destinationVertex == leftBoundingEdges[0].originVertex)
									{
										leftBoundingEdges.unshift(currEdge);
									}
									if (currEdge.destinationVertex == rightBoundingEdges[rightBoundingEdges.length - 1].destinationVertex)
									{
										rightBoundingEdges.push(currEdge.oppositeEdge);
									}
									currEdge = iterEdges.nextRealEdge()
								}
								
								newEdgeDownUp = DDLSPool.getDDLSEdge();
								newEdgeUpDown = DDLSPool.getDDLSEdge();
								newEdgeDownUp.setDatas(vertexDown, newEdgeUpDown, null, null, true, true);
								newEdgeUpDown.setDatas(currVertex, newEdgeDownUp, null, null, true, true);
								leftBoundingEdges.push(newEdgeDownUp);
								rightBoundingEdges.push(newEdgeUpDown);
								insertNewConstrainedEdge(segment, newEdgeDownUp, intersectedEdges, leftBoundingEdges, rightBoundingEdges);
								
								intersectedEdges.length = 0;
								leftBoundingEdges.length = 0;
								rightBoundingEdges.length = 0;
								vertexDown = currVertex;
								tempEdgeDownUp.originVertex = vertexDown;
								currObjet = vertexDown;
							}
							else
							{
								//trace("edge is not constrained");
								intersectedEdges.push(edgeLeft);
								leftBoundingEdges.unshift(edgeLeft.nextLeftEdge);
								currEdge = edgeLeft.oppositeEdge; // we keep the edge from left to right
								currObjet = currEdge;
							}
						}
						else
						{
							//trace("2nd left edge intersected");
							edgeLeft = edgeLeft.nextLeftEdge;
							DDLSGeom2D.intersections2edges(edgeLeft, tempEdgeDownUp, pIntersect);
							if (edgeLeft.isConstrained)
							{
								//trace("edge is constrained");
								currVertex = splitEdge(edgeLeft, pIntersect.x, pIntersect.y);
								
								iterEdges.fromRealVertex = currVertex;
								currEdge = iterEdges.nextRealEdge();
								while (currEdge)
								{
									if (currEdge.destinationVertex == leftBoundingEdges[0].originVertex)
									{
										leftBoundingEdges.unshift(currEdge);
									}
									if (currEdge.destinationVertex == rightBoundingEdges[rightBoundingEdges.length - 1].destinationVertex)
									{
										rightBoundingEdges.push(currEdge.oppositeEdge);
									}
									currEdge = iterEdges.nextRealEdge();
								}
								
								newEdgeDownUp = DDLSPool.getDDLSEdge();
								newEdgeUpDown = DDLSPool.getDDLSEdge();
								newEdgeDownUp.setDatas(vertexDown, newEdgeUpDown, null, null, true, true);
								newEdgeUpDown.setDatas(currVertex, newEdgeDownUp, null, null, true, true);
								leftBoundingEdges.push(newEdgeDownUp);
								rightBoundingEdges.push(newEdgeUpDown);
								insertNewConstrainedEdge(segment, newEdgeDownUp, intersectedEdges, leftBoundingEdges, rightBoundingEdges);
								
								intersectedEdges.length = 0;
								leftBoundingEdges.length = 0;
								rightBoundingEdges.length = 0;
								vertexDown = currVertex;
								tempEdgeDownUp.originVertex = vertexDown;
								currObjet = vertexDown;
							}
							else
							{
								//trace("edge is not constrained");
								intersectedEdges.push(edgeLeft);
								rightBoundingEdges.push(edgeLeft.prevLeftEdge);
								currEdge = edgeLeft.oppositeEdge; // we keep the edge from left to right
								currObjet = currEdge;
							}
						}
					}
				}
			}
			DDLSPool.putDDLSEdge(tempEdgeDownUp);
			DDLSPool.putDDLSEdge(tempSdgeUpDown);
			DDLSPool.putPoint(pIntersect);
			DDLSPool.putDDLSEdgeVector(intersectedEdges);
			DDLSPool.putDDLSEdgeVector(leftBoundingEdges);
			DDLSPool.putDDLSEdgeVector(rightBoundingEdges);
			return segment;
		}
		
		private function insertNewConstrainedEdge(fromSegment:DDLSConstraintSegment, edgeDownUp:DDLSEdge, intersectedEdges:Vector.<DDLSEdge>, leftBoundingEdges:Vector.<DDLSEdge>, rightBoundingEdges:Vector.<DDLSEdge>):void
		{
			//trace("insertNewConstrainedEdge");
			_edges.push(edgeDownUp);
			_edges.push(edgeDownUp.oppositeEdge);
			
			edgeDownUp.addFromConstraintSegment(fromSegment);
			edgeDownUp.oppositeEdge.fromConstraintSegments = edgeDownUp.fromConstraintSegments;
			
			fromSegment.addEdge(edgeDownUp);
			
			edgeDownUp.originVertex.addFromConstraintSegment(fromSegment);
			edgeDownUp.destinationVertex.addFromConstraintSegment(fromSegment);
			
			untriangulate(intersectedEdges);
			
			triangulate(leftBoundingEdges, true);
			triangulate(rightBoundingEdges, true);
		}
		
		public function deleteConstraintSegment(segment:DDLSConstraintSegment):void
		{
			//trace("deleteConstraintSegment id", segment.id);
			var i:int;
			var edge:DDLSEdge;
			var vertex:DDLSVertex;
			var segmentEdgesLength:int = segment.edges.length;
			vertexToDelete.length = segmentEdgesLength + 1;
			for (i = 0; i < segmentEdgesLength; i++)
			{
				edge = segment.edges[i];
				//trace("unconstrain edge ", edge);
				edge.removeFromConstraintSegment(segment);
				if (edge.fromConstraintSegments.length == 0)
				{
					edge.isConstrained = false;
					edge.oppositeEdge.isConstrained = false;
				}
				
				vertex = edge.originVertex;
				vertex.removeFromConstraintSegment(segment);
				vertexToDelete[i] = vertex;
			}
			vertex = edge.destinationVertex;
			vertex.removeFromConstraintSegment(segment);
			vertexToDelete[segmentEdgesLength] = vertex;
			//trace("clean the useless vertices");
			for (i = 0; i < vertexToDelete.length; i++)
			{
				deleteVertex(vertexToDelete[i]);
				vertexToDelete[i] = null; //should be returned to pool here..
			}
			//trace("clean done");
			
			segment.dispose();
		}
		
		private function check():void
		{
			for (var i:int = 0; i < _edges.length; i++)
			{
				if (!_edges[i].nextLeftEdge)
				{
					trace("!!! missing nextLeftEdge");
					return;
				}
			}
			trace("check OK");
		
		}
		
		public function insertVertex(x:Number, y:Number):DDLSVertex
		{
			//trace("insertVertex", x, y);
			if (x < 0 || y < 0 || x > _width || y > _height)
				return null;
			
			__edgesToCheck.length = 0;
			
			var inObject:Object = DDLSGeom2D.locatePosition(x, y, this);
			var inVertex:DDLSVertex;
			var inEdge:DDLSEdge;
			var inFace:DDLSFace;
			var newVertex:DDLSVertex;
			inVertex = inObject as DDLSVertex;
			if (inVertex)
			{
				//trace("inVertex", inVertex.id);
				newVertex = inVertex;
			}
			else if ((inEdge = inObject as DDLSEdge))
			{
				//trace("inEdge", inEdge);
				newVertex = splitEdge(inEdge, x, y);
			}
			else if ((inFace = inObject as DDLSFace))
			{
				//trace("inFace");
				newVertex = splitFace(inFace, x, y);
			}
			
			restoreAsDelaunay();
			
			return newVertex;
		}
		
		public function flipEdge(edge:DDLSEdge):DDLSEdge
		{
			// retrieve and create useful objets
			var eBot_Top:DDLSEdge = edge;
			var eTop_Bot:DDLSEdge = edge.oppositeEdge;
			var eLeft_Right:DDLSEdge = DDLSPool.getDDLSEdge();
			var eRight_Left:DDLSEdge = DDLSPool.getDDLSEdge();
			var eTop_Left:DDLSEdge = eBot_Top.nextLeftEdge;
			var eLeft_Bot:DDLSEdge = eTop_Left.nextLeftEdge;
			var eBot_Right:DDLSEdge = eTop_Bot.nextLeftEdge;
			var eRight_Top:DDLSEdge = eBot_Right.nextLeftEdge;
			
			var vBot:DDLSVertex = eBot_Top.originVertex;
			var vTop:DDLSVertex = eTop_Bot.originVertex;
			var vLeft:DDLSVertex = eLeft_Bot.originVertex;
			var vRight:DDLSVertex = eRight_Top.originVertex;
			
			var fLeft:DDLSFace = eBot_Top.leftFace;
			var fRight:DDLSFace = eTop_Bot.leftFace;
			var fBot:DDLSFace = DDLSPool.getDDLSFace();
			var fTop:DDLSFace = DDLSPool.getDDLSFace();
			
			// add the new edges
			_edges.push(eLeft_Right);
			_edges.push(eRight_Left);
			
			// add the new faces
			_faces.push(fTop);
			_faces.push(fBot);
			
			// set vertex, edge and face references for the new LEFT_RIGHT and RIGHT-LEFT edges
			eLeft_Right.setDatas(vLeft, eRight_Left, eRight_Top, fTop, edge.isReal, edge.isConstrained);
			eRight_Left.setDatas(vRight, eLeft_Right, eLeft_Bot, fBot, edge.isReal, edge.isConstrained);
			
			// set edge references for the new TOP and BOTTOM faces
			fTop.setDatas(eLeft_Right);
			fBot.setDatas(eRight_Left);
			
			// check the edge references of TOP and BOTTOM vertices
			if (vTop.edge == eTop_Bot)
				vTop.setDatas(eTop_Left);
			if (vBot.edge == eBot_Top)
				vBot.setDatas(eBot_Right);
			
			// set the new edge and face references for the 4 bouding edges
			eTop_Left.nextLeftEdge = eLeft_Right;
			eTop_Left.leftFace = fTop;
			eLeft_Bot.nextLeftEdge = eBot_Right;
			eLeft_Bot.leftFace = fBot;
			eBot_Right.nextLeftEdge = eRight_Left;
			eBot_Right.leftFace = fBot;
			eRight_Top.nextLeftEdge = eTop_Left;
			eRight_Top.leftFace = fTop;
			
			// remove the old TOP-BOTTOM and BOTTOM-TOP edges
			DDLSPool.putDDLSEdge(eBot_Top);
			DDLSPool.putDDLSEdge(eTop_Bot);
			var i:int = _edges.length;
			while (_edges[--i] != eBot_Top);
			_edges.removeAt(i);
			i= _edges.length;
			while (_edges[--i] != eTop_Bot);
			_edges.removeAt(i);
			
			// remove the old LEFT and RIGHT faces
			DDLSPool.putDDLSFace(fLeft);
			DDLSPool.putDDLSFace(fRight);
			i = _faces.length;
			while (_faces[--i] != fLeft);
			_faces.removeAt(i);
			i = _faces.length;
			while (_faces[--i] != fRight);
			_faces.removeAt(i);
			
			return eRight_Left;
		}
		
		public function splitEdge(edge:DDLSEdge, x:Number, y:Number):DDLSVertex
		{
			// empty old references
			__edgesToCheck.length = 0;
			
			// retrieve useful objets
			var eLeft_Right:DDLSEdge = edge;
			var eRight_Left:DDLSEdge = eLeft_Right.oppositeEdge;
			var eRight_Top:DDLSEdge = eLeft_Right.nextLeftEdge;
			var eTop_Left:DDLSEdge = eRight_Top.nextLeftEdge;
			var eLeft_Bot:DDLSEdge = eRight_Left.nextLeftEdge;
			var eBot_Right:DDLSEdge = eLeft_Bot.nextLeftEdge;
			
			var vTop:DDLSVertex = eTop_Left.originVertex;
			var vLeft:DDLSVertex = eLeft_Right.originVertex;
			var vBot:DDLSVertex = eBot_Right.originVertex;
			var vRight:DDLSVertex = eRight_Left.originVertex;
			
			var fTop:DDLSFace = eLeft_Right.leftFace;
			var fBot:DDLSFace = eRight_Left.leftFace;
			
			// check distance from the position to edge end points
			if ((vLeft.pos.x - x) * (vLeft.pos.x - x) + (vLeft.pos.y - y) * (vLeft.pos.y - y) <= DDLSConstants.EPSILON_SQUARED)
				return vLeft;
			if ((vRight.pos.x - x) * (vRight.pos.x - x) + (vRight.pos.y - y) * (vRight.pos.y - y) <= DDLSConstants.EPSILON_SQUARED)
				return vRight;
			
			// new objects
			var vCenter:DDLSVertex = DDLSPool.getDDLSVertex();
			
			var eTop_Center:DDLSEdge = DDLSPool.getDDLSEdge();
			var eCenter_Top:DDLSEdge = DDLSPool.getDDLSEdge();
			var eBot_Center:DDLSEdge = DDLSPool.getDDLSEdge();
			var eCenter_Bot:DDLSEdge = DDLSPool.getDDLSEdge();
			
			var eLeft_Center:DDLSEdge = DDLSPool.getDDLSEdge();
			var eCenter_Left:DDLSEdge = DDLSPool.getDDLSEdge();
			var eRight_Center:DDLSEdge = DDLSPool.getDDLSEdge();
			var eCenter_Right:DDLSEdge = DDLSPool.getDDLSEdge();
			
			var fTopLeft:DDLSFace = DDLSPool.getDDLSFace();
			var fBotLeft:DDLSFace = DDLSPool.getDDLSFace();
			var fBotRight:DDLSFace = DDLSPool.getDDLSFace();
			var fTopRight:DDLSFace = DDLSPool.getDDLSFace();
			
			// add the new vertex
			_vertices.push(vCenter);
			var edgesLength:int = _edges.length+8;
			_edges.length = edgesLength;
			// add the new edges
			_edges[--edgesLength]=eCenter_Top;
			_edges[--edgesLength]=eTop_Center;
			_edges[--edgesLength]=eCenter_Left;
			_edges[--edgesLength]=eLeft_Center;
			_edges[--edgesLength] = eCenter_Bot;
			_edges[--edgesLength]=eBot_Center;
			_edges[--edgesLength] = eCenter_Right;
			_edges[--edgesLength] = eRight_Center;
			
			// add the new faces
			_faces.push(fTopRight);
			_faces.push(fBotRight);
			_faces.push(fBotLeft);
			_faces.push(fTopLeft);
			
			// set pos and edge reference for the new CENTER vertex
			vCenter.setDatas(fTop.isReal ? eCenter_Top : eCenter_Bot);
			vCenter.pos.x = x;
			vCenter.pos.y = y;
			DDLSGeom2D.projectOrthogonaly(vCenter.pos, eLeft_Right);
			
			// set the new vertex, edge and face references for the new 8 center crossing edges
			eCenter_Top.setDatas(vCenter, eTop_Center, eTop_Left, fTopLeft, fTop.isReal);
			eTop_Center.setDatas(vTop, eCenter_Top, eCenter_Right, fTopRight, fTop.isReal);
			eCenter_Left.setDatas(vCenter, eLeft_Center, eLeft_Bot, fBotLeft, edge.isReal, edge.isConstrained);
			eLeft_Center.setDatas(vLeft, eCenter_Left, eCenter_Top, fTopLeft, edge.isReal, edge.isConstrained);
			eCenter_Bot.setDatas(vCenter, eBot_Center, eBot_Right, fBotRight, fBot.isReal);
			eBot_Center.setDatas(vBot, eCenter_Bot, eCenter_Left, fBotLeft, fBot.isReal);
			eCenter_Right.setDatas(vCenter, eRight_Center, eRight_Top, fTopRight, edge.isReal, edge.isConstrained);
			eRight_Center.setDatas(vRight, eCenter_Right, eCenter_Bot, fBotRight, edge.isReal, edge.isConstrained);
			
			// set the new edge references for the new 4 faces
			fTopLeft.setDatas(eCenter_Top, fTop.isReal);
			fBotLeft.setDatas(eCenter_Left, fBot.isReal);
			fBotRight.setDatas(eCenter_Bot, fBot.isReal);
			fTopRight.setDatas(eCenter_Right, fTop.isReal);
			
			// check the edge references of LEFT and RIGHT vertices
			if (vLeft.edge == eLeft_Right)
				vLeft.setDatas(eLeft_Center);
			if (vRight.edge == eRight_Left)
				vRight.setDatas(eRight_Center);
			
			// set the new edge and face references for the 4 bounding edges
			eTop_Left.nextLeftEdge = eLeft_Center;
			eTop_Left.leftFace = fTopLeft;
			eLeft_Bot.nextLeftEdge = eBot_Center;
			eLeft_Bot.leftFace = fBotLeft;
			eBot_Right.nextLeftEdge = eRight_Center;
			eBot_Right.leftFace = fBotRight;
			eRight_Top.nextLeftEdge = eTop_Center;
			eRight_Top.leftFace = fTopRight;
			
			// if the edge was constrained, we must:
			// - add the segments the edge is from to the 2 new
			// - update the segments the edge is from by deleting the old edge and inserting the 2 new
			// - add the segments the edge is from to the new vertex
			if (eLeft_Right.isConstrained)
			{
				var fromSegments:Vector.<DDLSConstraintSegment> = eLeft_Right.fromConstraintSegments;
				var fromSegmentsLength:int = fromSegments.length;
				var i:int = 0;
				eLeft_Center.fromConstraintSegments.length = fromSegmentsLength;
				eCenter_Right.fromConstraintSegments.length = fromSegmentsLength;
				for (i = 0; i < fromSegmentsLength; i++)
				{
					eLeft_Center.fromConstraintSegments[i] = fromSegments[i];
					eCenter_Right.fromConstraintSegments[i] = fromSegments[i];
				}
				eCenter_Left.fromConstraintSegments = eLeft_Center.fromConstraintSegments;
				eRight_Center.fromConstraintSegments = eCenter_Right.fromConstraintSegments;
				
				var edges:Vector.<DDLSEdge>;
				var index:int;
				for (i = 0; i < fromSegmentsLength; i++)
				{
					edges = eLeft_Right.fromConstraintSegments[i].edges;
					index = edges.indexOf(eLeft_Right);
					if (index != -1)
					{
						edges[index] = eLeft_Center;
						edges.insertAt(index + 1, eCenter_Right);
					}
					else
					{
						index = edges.indexOf(eRight_Left);
						if (index == -1)
						{
							index += edges.length;
						}
						edges[index] = eRight_Center;
						edges.insertAt(index + 1, eCenter_Left);
					}
				}
				vCenter.fromConstraintSegments.length = fromSegmentsLength;
				for (i = 0; i < fromSegmentsLength; i++)
				{
					vCenter.fromConstraintSegments[i] = fromSegments[i];
				}
			}
			
			// remove the old LEFT-RIGHT and RIGHT-LEFT edges
			DDLSPool.putDDLSEdge(eLeft_Right);
			DDLSPool.putDDLSEdge(eRight_Left);
			//edge more likly to be found at the start or end of the array
			var j:int = _edges.lastIndexOf(eLeft_Right, _edges.length * 0.2);
			if (j ==-1)
			{
				j = _edges.lastIndexOf(eLeft_Right);
			}
			_edges.removeAt(j);
			_edges.removeAt(_edges.indexOf(eRight_Left));
			
			// remove the old TOP and BOTTOM faces
			DDLSPool.putDDLSFace(fTop);
			DDLSPool.putDDLSFace(fBot);
			_faces.removeAt(_faces.indexOf(fTop));
			_faces.removeAt(_faces.indexOf(fBot));
			
			// add new bounds references for Delaunay restoring
			__centerVertex = vCenter;
			__edgesToCheck.push(eTop_Left);
			__edgesToCheck.push(eLeft_Bot);
			__edgesToCheck.push(eBot_Right);
			__edgesToCheck.push(eRight_Top);
			
			return vCenter;
		}
		
		public function splitFace(face:DDLSFace, x:Number, y:Number):DDLSVertex
		{
			// empty old references
			__edgesToCheck.length = 0;
			
			// retrieve useful objects
			var eTop_Left:DDLSEdge = face.edge;
			var eLeft_Right:DDLSEdge = eTop_Left.nextLeftEdge;
			var eRight_Top:DDLSEdge = eLeft_Right.nextLeftEdge;
			
			var vTop:DDLSVertex = eTop_Left.originVertex;
			var vLeft:DDLSVertex = eLeft_Right.originVertex;
			var vRight:DDLSVertex = eRight_Top.originVertex;
			
			// create new objects
			var vCenter:DDLSVertex = DDLSPool.getDDLSVertex();
			
			var eTop_Center:DDLSEdge = DDLSPool.getDDLSEdge();
			var eCenter_Top:DDLSEdge = DDLSPool.getDDLSEdge();
			var eLeft_Center:DDLSEdge = DDLSPool.getDDLSEdge();
			var eCenter_Left:DDLSEdge = DDLSPool.getDDLSEdge();
			var eRight_Center:DDLSEdge = DDLSPool.getDDLSEdge();
			var eCenter_Right:DDLSEdge = DDLSPool.getDDLSEdge();
			
			var fTopLeft:DDLSFace = DDLSPool.getDDLSFace();
			var fBot:DDLSFace = DDLSPool.getDDLSFace();
			var fTopRight:DDLSFace = DDLSPool.getDDLSFace();
			
			// add the new vertex
			_vertices.push(vCenter);
			
			// add the new edges
			_edges.push(eTop_Center);
			_edges.push(eCenter_Top);
			_edges.push(eLeft_Center);
			_edges.push(eCenter_Left);
			_edges.push(eRight_Center);
			_edges.push(eCenter_Right);
			
			// add the new faces
			_faces.push(fTopLeft);
			_faces.push(fBot);
			_faces.push(fTopRight);
			
			// set pos and edge reference for the new CENTER vertex
			vCenter.setDatas(eCenter_Top);
			vCenter.pos.x = x;
			vCenter.pos.y = y;
			
			// set the new vertex, edge and face references for the new 6 center crossing edges
			eTop_Center.setDatas(vTop, eCenter_Top, eCenter_Right, fTopRight);
			eCenter_Top.setDatas(vCenter, eTop_Center, eTop_Left, fTopLeft);
			eLeft_Center.setDatas(vLeft, eCenter_Left, eCenter_Top, fTopLeft);
			eCenter_Left.setDatas(vCenter, eLeft_Center, eLeft_Right, fBot);
			eRight_Center.setDatas(vRight, eCenter_Right, eCenter_Left, fBot);
			eCenter_Right.setDatas(vCenter, eRight_Center, eRight_Top, fTopRight);
			
			// set the new edge references for the new 3 faces
			fTopLeft.setDatas(eCenter_Top);
			fBot.setDatas(eCenter_Left);
			fTopRight.setDatas(eCenter_Right);
			
			// set the new edge and face references for the 3 bounding edges
			eTop_Left.nextLeftEdge = eLeft_Center;
			eTop_Left.leftFace = fTopLeft;
			eLeft_Right.nextLeftEdge = eRight_Center;
			eLeft_Right.leftFace = fBot;
			eRight_Top.nextLeftEdge = eTop_Center;
			eRight_Top.leftFace = fTopRight;
			
			// we remove the old face
			DDLSPool.putDDLSFace(face);
			_faces.removeAt(_faces.lastIndexOf(face));
			
			// add new bounds references for Delaunay restoring
			__centerVertex = vCenter;
			__edgesToCheck.push(eTop_Left);
			__edgesToCheck.push(eLeft_Right);
			__edgesToCheck.push(eRight_Top);
			
			return vCenter;
		}
		
		public function restoreAsDelaunay():void
		{
			var edge:DDLSEdge;
			while (__edgesToCheck.length)
			{
				edge = __edgesToCheck.shift();
				if (edge.isReal && !edge.isConstrained && !DDLSGeom2D.isDelaunay(edge))
				{
					if (edge.nextLeftEdge.destinationVertex == __centerVertex)
					{
						__edgesToCheck.push(edge.nextRightEdge);
						__edgesToCheck.push(edge.prevRightEdge);
					}
					else
					{
						__edgesToCheck.push(edge.nextLeftEdge);
						__edgesToCheck.push(edge.prevLeftEdge);
					}
					flipEdge(edge);
				}
			}
		}
		
		// Delete a vertex IF POSSIBLE and then fill the hole with a new triangulation.
		// A vertex can be deleted if:
		// - it is free of constraint segment (no adjacency to any constrained edge)
		// - it is adjacent to exactly 2 contrained edges and is not an end point of any constraint segment
		public function deleteVertex(vertex:DDLSVertex):Boolean
		{
			//trace("tryToDeleteVertex id", vertex.id);
			var i:int;
			var freeOfConstraint:Boolean;
			iterEdges.fromAnyVertex = vertex;
			var edge:DDLSEdge;
			
			freeOfConstraint = vertex.fromConstraintSegments.length == 0;
			
			//trace("  -> freeOfConstraint", freeOfConstraint);
			var outgoingEdgesLength:int = outgoingEdges.length;		
			if (freeOfConstraint)
			{
				edge = iterEdges.next();
				var boundTempLength:int = 0;
				while (edge)
				{
					outgoingEdges[outgoingEdgesLength++]=edge;
					boundTemp[boundTempLength++]=edge.nextLeftEdge;
					edge = iterEdges.next()
				}
			}
			else
			{
				// we check if the vertex is an end point of a constraint segment
				var edges:Vector.<DDLSEdge>;
				for (i = 0; i < vertex.fromConstraintSegments.length; i++)
				{
					edges = vertex.fromConstraintSegments[i].edges;
					if (edges[0].originVertex == vertex || edges[edges.length - 1].destinationVertex == vertex)
					{
						//trace("  -> is end point of a constraint segment");
						return false;
					}
				}
				
				// we check the count of adjacent constrained edges
				var count:int = 0;
				edge = iterEdges.next();
				while (edge)
				{
					outgoingEdges[outgoingEdgesLength++]=edge;
					
					if (edge.isConstrained)
					{
						count++;
						if (count > 2)
						{
							outgoingEdges.length = 0;
							//trace("  -> count of adjacent constrained edges", count);
							return false;
						}
					}
					edge = iterEdges.next();
				}
				
				// if not disqualified, then we can process
				//trace("process vertex deletion");
				var boundA:Vector.<DDLSEdge> = DDLSPool.getDDLSEdgeVector();
				var boundB:Vector.<DDLSEdge> = DDLSPool.getDDLSEdgeVector();
				var constrainedEdgeA:DDLSEdge;
				var constrainedEdgeB:DDLSEdge;
				var edgeA:DDLSEdge = DDLSPool.getDDLSEdge();
				var edgeB:DDLSEdge = DDLSPool.getDDLSEdge();
				var realA:Boolean;
				var realB:Boolean;
				_edges.push(edgeA);
				_edges.push(edgeB);
				for (i = 0; i < outgoingEdgesLength; i++)
				{
					edge = outgoingEdges[i];
					if (edge.isConstrained)
					{
						if (!constrainedEdgeA)
						{
							edgeB.setDatas(edge.destinationVertex, edgeA, null, null, true, true);
							boundA.push(edgeA, edge.nextLeftEdge);
							boundB.push(edgeB);
							constrainedEdgeA = edge;
						}
						else if (!constrainedEdgeB)
						{
							edgeA.setDatas(edge.destinationVertex, edgeB, null, null, true, true);
							boundB.push(edge.nextLeftEdge);
							constrainedEdgeB = edge;
							CONFIG::debug
							{
								if (!constrainedEdgeB)
								{
									trace("Bug is here!");
								}
							}
						}
					}
					else
					{
						if (!constrainedEdgeA)
							boundB.push(edge.nextLeftEdge);
						else if (!constrainedEdgeB)
							boundA.push(edge.nextLeftEdge);
						else
							boundB.push(edge.nextLeftEdge);
					}
				}
				
				// keep infos about reality
				realA = constrainedEdgeA.leftFace.isReal;
				realB = constrainedEdgeB.leftFace.isReal;
				// we update the segments infos
				edgeA.fromConstraintSegments.length = constrainedEdgeA.fromConstraintSegments.length;
				for (i = 0; i < constrainedEdgeA.fromConstraintSegments.length; i++)
				{
					edgeA.fromConstraintSegments[i] = constrainedEdgeA.fromConstraintSegments[i];
				}
				edgeB.fromConstraintSegments = edgeA.fromConstraintSegments;
				var index:int;
				for (i = 0; i < vertex.fromConstraintSegments.length; i++)
				{
					edges = vertex.fromConstraintSegments[i].edges;
					index = edges.lastIndexOf(constrainedEdgeA);
					if (index != -1)
					{
						edges.removeAt(index - 1);
						edges[index - 1] = edgeA;
					}
					else
					{
						index = edges.indexOf(constrainedEdgeB) - 1;
						edges.removeAt(index);
						if (index < 0)
						{
							index += edges.length;
						}
						edges[index] = edgeB;
					}
				}
			}
			// Deletion of old faces and edges
			var faceToDelete:DDLSFace;
			for (i = 0; i < outgoingEdgesLength; i++)
			{
				edge = outgoingEdges[i];
				
				faceToDelete = edge.leftFace;
				_faces.removeAt(_faces.lastIndexOf(faceToDelete));
				DDLSPool.putDDLSFace(faceToDelete);
				
				edge.destinationVertex.edge = edge.nextLeftEdge;
				var j:int = _edges.length;
				while (_edges[--j] != edge && _edges[j] != edge.oppositeEdge)
					;
				if (_edges[j] == edge)
				{
					_edges.removeAt(j);
					while (_edges[--j] != edge.oppositeEdge)
						;
				}
				else
				{
					_edges.removeAt(j);
					while (_edges[--j] != edge)
						;
				}
				_edges.removeAt(j);
				DDLSPool.putDDLSEdge(edge.oppositeEdge);
				DDLSPool.putDDLSEdge(edge);
			}
			outgoingEdges.length = 0;
			_vertices.removeAt(_vertices.lastIndexOf(vertex));
			DDLSPool.putDDLSVertex(vertex);
			
			// finally we triangulate
			if (freeOfConstraint)
			{
				//trace("trigger single hole triangulation");
				triangulate(boundTemp, true);
				boundTemp.length = 0;
			}
			else
			{
				//trace("trigger dual holes triangulation");
				triangulate(boundA, realA);
				triangulate(boundB, realB);
				DDLSPool.putDDLSEdgeVector(boundA);
				DDLSPool.putDDLSEdgeVector(boundB);
			}
			//check();
			return true;
		}
		
		///// PRIVATE
		
		// untriangulate is usually used while a new edge insertion in order to delete the intersected edges
		// edgesList is a list of chained edges oriented from right to left
		private function untriangulate(edgesList:Vector.<DDLSEdge>):void
		{
			// we clean useless faces and adjacent vertices
			var i:int;
			var verticesCleaned:Dictionary = new Dictionary();
			var currEdge:DDLSEdge;
			var outEdge:DDLSEdge;
			for (i = 0; i < edgesList.length; i++)
			{
				currEdge = edgesList[i];
				//
				if (!verticesCleaned[currEdge.originVertex])
				{
					currEdge.originVertex.edge = currEdge.prevLeftEdge.oppositeEdge;
					verticesCleaned[currEdge.originVertex] = true;
				}
				if (!verticesCleaned[currEdge.destinationVertex])
				{
					currEdge.destinationVertex.edge = currEdge.nextLeftEdge;
					verticesCleaned[currEdge.destinationVertex] = true;
				}
				//
				_faces.removeAt(_faces.indexOf(currEdge.leftFace));
				DDLSPool.putDDLSFace(currEdge.leftFace);
				if (i == edgesList.length - 1)
				{
					_faces.removeAt(_faces.indexOf(currEdge.rightFace));
					DDLSPool.putDDLSFace(currEdge.rightFace);
				}
					//
			}
			
			// finally we delete the intersected edges
			for (i = 0; i < edgesList.length; i++)
			{
				currEdge = edgesList[i];
				_edges.removeAt(_edges.indexOf(currEdge.oppositeEdge));
				_edges.removeAt(_edges.indexOf(currEdge));
				DDLSPool.putDDLSEdge(currEdge.oppositeEdge);
				DDLSPool.putDDLSEdge(currEdge);
			}
		}
		
		// triangulate is usually used to fill the hole after deletion of a vertex from mesh or after untriangulation
		// - bounds is the list of edges in CCW bounding the surface to retriangulate,
		private function triangulate(bound:Vector.<DDLSEdge>, isReal:Boolean):void
		{
			if (bound.length < 2)
			{
				trace("BREAK ! the hole has less than 2 edges");
				return;
			}
			// if the hole is a 2 edges polygon, we have a big problem
			else if (bound.length == 2)
			{
				//throw new Error("BREAK ! the hole has only 2 edges! " + "  - edge0: " + bound[0].originVertex.id + " -> " + bound[0].destinationVertex.id + "  - edge1: " +  bound[1].originVertex.id + " -> " + bound[1].destinationVertex.id);
				trace("BREAK ! the hole has only 2 edges");
				trace("  - edge0:", bound[0].originVertex.id, "->", bound[0].destinationVertex.id);
				trace("  - edge1:", bound[1].originVertex.id, "->", bound[1].destinationVertex.id);
				return;
			}
			// if the hole is a 3 edges polygon:
			else if (bound.length == 3)
			{
				/*trace("the hole is a 3 edges polygon");
				   trace("  - edge0:", bound[0].originVertex.id, "->", bound[0].destinationVertex.id);
				   trace("  - edge1:", bound[1].originVertex.id, "->", bound[1].destinationVertex.id);
				   trace("  - edge2:", bound[2].originVertex.id, "->", bound[2].destinationVertex.id);*/
				var f:DDLSFace = DDLSPool.getDDLSFace();
				f.setDatas(bound[0], isReal);
				_faces.push(f);
				bound[0].leftFace = f;
				bound[1].leftFace = f;
				bound[2].leftFace = f;
				bound[0].nextLeftEdge = bound[1];
				bound[1].nextLeftEdge = bound[2];
				bound[2].nextLeftEdge = bound[0];
			}
			else // if more than 3 edges, we process recursively:
			{
				//trace("the hole has", bound.length, "edges");
				//for (i = 0; i < bound.length; i++)
				//{
				//trace("  - edge", i, ":", bound[i].originVertex.id, "->", bound[i].destinationVertex.id);
				//	}
				
				var baseEdge:DDLSEdge = bound[0];
				var vertexA:DDLSVertex = baseEdge.originVertex;
				var vertexB:DDLSVertex = baseEdge.destinationVertex;
				var vertexC:DDLSVertex;
				var vertexCheck:DDLSVertex;
				var circumcenter:DDLSPoint2D = DDLSPool.getPoint();
				var radiusSquared:Number;
				var distanceSquared:Number;
				var isDelaunay:Boolean;
				var index:int;
				var i:int;
				for (i = 2; i < bound.length; i++)
				{
					vertexC = bound[i].originVertex;
					if (DDLSGeom2D.getRelativePosition2(vertexC.pos.x, vertexC.pos.y, baseEdge) == 1)
					{
						index = i;
						isDelaunay = true;
						DDLSGeom2D.getCircumcenter(vertexA.pos.x, vertexA.pos.y, vertexB.pos.x, vertexB.pos.y, vertexC.pos.x, vertexC.pos.y, circumcenter);
						radiusSquared = (vertexA.pos.x - circumcenter.x) * (vertexA.pos.x - circumcenter.x) + (vertexA.pos.y - circumcenter.y) * (vertexA.pos.y - circumcenter.y);
						// for perfect regular n-sides polygons, checking strict delaunay circumcircle condition is not possible, so we substract EPSILON to circumcircle radius:
						radiusSquared -= DDLSConstants.EPSILON_SQUARED;
						for (var j:int = 2; j < bound.length; j++)
						{
							if (j != i)
							{
								vertexCheck = bound[j].originVertex;
								distanceSquared = (vertexCheck.pos.x - circumcenter.x) * (vertexCheck.pos.x - circumcenter.x) + (vertexCheck.pos.y - circumcenter.y) * (vertexCheck.pos.y - circumcenter.y);
								if (distanceSquared < radiusSquared)
								{
									isDelaunay = false;
									break;
								}
							}
						}
						
						if (isDelaunay)
							break;
					}
				}
				DDLSPool.putPoint(circumcenter);
				if (!isDelaunay)
				{
					// for perfect regular n-sides polygons, checking delaunay circumcircle condition is not possible
					trace("NO DELAUNAY FOUND");
					var s:String = "";
					for (i = 0; i < bound.length; i++)
					{
						s += bound[i].originVertex.pos.x + " , ";
						s += bound[i].originVertex.pos.y + " , ";
						s += bound[i].destinationVertex.pos.x + " , ";
						s += bound[i].destinationVertex.pos.y + " , ";
					}
					//trace(s);
					
					index = 2;
				}
				//trace("index", index, "on", bound.length);
				
				var edgeA:DDLSEdge;
				var edgeAopp:DDLSEdge;
				var edgeB:DDLSEdge;
				var edgeBopp:DDLSEdge;
				var boundA:Vector.<DDLSEdge>;
				var boundM:Vector.<DDLSEdge>;
				var boundB:Vector.<DDLSEdge>;
				var edgesLength:int;
				if (index < (bound.length - 1))
				{
					edgeA = DDLSPool.getDDLSEdge();
					edgeAopp = DDLSPool.getDDLSEdge();
					edgesLength = _edges.length;
					_edges[edgesLength++] = edgeA;
					_edges[edgesLength++] = edgeAopp;
					edgeA.setDatas(vertexA, edgeAopp, null, null, isReal, false);
					edgeAopp.setDatas(bound[index].originVertex, edgeA, null, null, isReal, false);
					boundA = DDLSPool.sliceDDLSEdgeVector(bound, index);
					boundA.push(edgeA);
					triangulate(boundA, isReal);
					DDLSPool.putDDLSEdgeVector(boundA);
				}
				
				if (index > 2)
				{
					edgeB = DDLSPool.getDDLSEdge();
					edgeBopp = DDLSPool.getDDLSEdge();
					edgesLength = _edges.length;
					_edges[edgesLength++] = edgeB;
					_edges[edgesLength++] = edgeBopp;
					edgeB.setDatas(bound[1].originVertex, edgeBopp, null, null, isReal, false);
					edgeBopp.setDatas(bound[index].originVertex, edgeB, null, null, isReal, false);
					boundB = DDLSPool.sliceDDLSEdgeVector(bound, 1, index);
					boundB.push(edgeBopp);
					triangulate(boundB, isReal);
					DDLSPool.putDDLSEdgeVector(boundB);
				}
				
				boundM = DDLSPool.getDDLSEdgeVector();
				if (index == 2)
					boundM.push(baseEdge, bound[1], edgeAopp);
				else if (index == (bound.length - 1))
					boundM.push(baseEdge, edgeB, bound[index]);
				else
					boundM.push(baseEdge, edgeB, edgeAopp);
				triangulate(boundM, isReal);
				DDLSPool.putDDLSEdgeVector(boundM);
			}
		}
		
		private function findPositionFromBounds(x:Number, y:Number):int
		{
			/* point positions relative to bounds
			   1 | 2 | 3
			   ------------
			   8 | 0 | 4
			   ------------
			   7 | 6 | 5
			 */
			
			if (x <= 0)
			{
				if (y <= 0)
					return 1;
				else if (y >= _height)
					return 7;
				else
					return 8;
			}
			else if (x >= _width)
			{
				if (y <= 0)
					return 3;
				else if (y >= _height)
					return 5;
				else
					return 4;
			}
			else
			{
				if (y <= 0)
					return 2;
				else if (y >= _height)
					return 6;
				else
					return 0;
			}
		}
		
		public function debug():void
		{
			var i:int;
			for (i = 0; i < __vertices.length; i++)
			{
				trace("-- vertex", _vertices[i].id);
				trace("  edge", _vertices[i].edge.id, " - ", _vertices[i].edge);
				trace("  edge isReal:", _vertices[i].edge.isReal);
			}
			for (i = 0; i < _edges.length; i++)
			{
				trace("-- edge", _edges[i]);
				trace("  isReal", _edges[i].id, " - ", _edges[i].isReal);
				trace("  nextLeftEdge", _edges[i].nextLeftEdge);
				trace("  oppositeEdge", _edges[i].oppositeEdge);
			}
		}
	
	}

}