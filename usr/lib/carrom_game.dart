import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'dart:math' as math;

class CarromGameScreen extends StatefulWidget {
  const CarromGameScreen({super.key});

  @override
  State<CarromGameScreen> createState() => _CarromGameScreenState();
}

class _CarromGameScreenState extends State<CarromGameScreen> with SingleTickerProviderStateMixin {
  late Ticker _ticker;
  
  // Game State
  final List<CarromPiece> _pieces = [];
  late CarromPiece _striker;
  bool _isMoving = false;
  
  // Board Dimensions (will be set in build/layout)
  Size _boardSize = Size.zero;
  final double _pocketRadius = 25.0;
  
  // Interaction
  Offset? _dragStart;
  Offset? _dragCurrent;
  bool _isDragging = false;
  bool _canPlaceStriker = true;

  // Physics Constants
  final double _friction = 0.985;
  final double _wallBounce = 0.7; // Energy loss on wall bounce
  final double _stopThreshold = 0.2;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_gameLoop);
    _resetGame();
  }

  void _resetGame() {
    _pieces.clear();
    _ticker.stop();
    _isMoving = false;
    _canPlaceStriker = true;

    // Initialize Striker
    _striker = CarromPiece(
      position: const Offset(0, 0), // Will set when board size is known
      radius: 18,
      color: const Color(0xFFFFF8E1),
      mass: 2.0,
      isStriker: true,
    );

    // Initialize Coins (Simple formation)
    // Center is (0,0) relative to board center for setup, then offset
    // We will initialize positions in the build method or layout builder once we know size
    // For now, we defer initialization until we have board size.
  }

  void _initPieces(Size size) {
    if (_boardSize == size) return;
    _boardSize = size;
    
    double cx = size.width / 2;
    double cy = size.height / 2;

    _pieces.clear();
    
    // Queen
    _pieces.add(CarromPiece(position: Offset(cx, cy), color: Colors.red, radius: 12, mass: 1.0));

    // Inner Circle (6 coins)
    for (int i = 0; i < 6; i++) {
      double angle = i * (math.pi / 3);
      _pieces.add(CarromPiece(
        position: Offset(cx + 26 * math.cos(angle), cy + 26 * math.sin(angle)),
        color: i % 2 == 0 ? Colors.black : const Color(0xFFE0E0E0), // Black and White
        radius: 12,
        mass: 1.0,
      ));
    }
    
    // Outer Circle (12 coins) - simplified for demo
    for (int i = 0; i < 12; i++) {
      double angle = i * (math.pi / 6);
      _pieces.add(CarromPiece(
        position: Offset(cx + 50 * math.cos(angle), cy + 50 * math.sin(angle)),
        color: (i % 2 != 0) ? Colors.black : const Color(0xFFE0E0E0), // Alternating
        radius: 12,
        mass: 1.0,
      ));
    }

    // Reset Striker Position to baseline
    _resetStriker();
  }

  void _resetStriker() {
    if (_boardSize == Size.zero) return;
    _striker.position = Offset(_boardSize.width / 2, _boardSize.height - 80);
    _striker.velocity = Offset.zero;
    _canPlaceStriker = true;
    _isMoving = false;
    _ticker.stop();
    setState(() {});
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  void _gameLoop(Duration elapsed) {
    if (!_isMoving) return;

    bool stillMoving = false;
    
    // Update Striker
    if (_updatePiece(_striker)) stillMoving = true;

    // Update Pieces
    for (var piece in _pieces) {
      if (_updatePiece(piece)) stillMoving = true;
    }

    // Collisions
    _handleCollisions();

    // Check Pockets
    _checkPockets();

    if (!stillMoving) {
      _isMoving = false;
      _ticker.stop();
      _resetStriker();
    }

    setState(() {});
  }

  bool _updatePiece(CarromPiece piece) {
    if (piece.velocity.distanceSquared < _stopThreshold) {
      piece.velocity = Offset.zero;
      return false;
    }

    // Move
    piece.position += piece.velocity;

    // Friction
    piece.velocity *= _friction;

    // Wall Collisions
    if (piece.position.dx - piece.radius < 0) {
      piece.position = Offset(piece.radius, piece.position.dy);
      piece.velocity = Offset(-piece.velocity.dx * _wallBounce, piece.velocity.dy);
    }
    if (piece.position.dx + piece.radius > _boardSize.width) {
      piece.position = Offset(_boardSize.width - piece.radius, piece.position.dy);
      piece.velocity = Offset(-piece.velocity.dx * _wallBounce, piece.velocity.dy);
    }
    if (piece.position.dy - piece.radius < 0) {
      piece.position = Offset(piece.position.dx, piece.radius);
      piece.velocity = Offset(piece.velocity.dx, -piece.velocity.dy * _wallBounce);
    }
    if (piece.position.dy + piece.radius > _boardSize.height) {
      piece.position = Offset(piece.position.dx, _boardSize.height - piece.radius);
      piece.velocity = Offset(piece.velocity.dx, -piece.velocity.dy * _wallBounce);
    }

    return true;
  }

  void _checkPockets() {
    List<Offset> pockets = [
      const Offset(0, 0),
      Offset(_boardSize.width, 0),
      Offset(0, _boardSize.height),
      Offset(_boardSize.width, _boardSize.height),
    ];

    // Check pieces
    _pieces.removeWhere((piece) {
      for (var pocket in pockets) {
        if ((piece.position - pocket).distance < _pocketRadius) {
          return true; // Scored!
        }
      }
      return false;
    });

    // Check Striker (Foul)
    for (var pocket in pockets) {
      if ((_striker.position - pocket).distance < _pocketRadius) {
        _striker.velocity = Offset.zero;
        _resetStriker(); // Reset immediately implies foul logic (simplified here)
        break;
      }
    }
  }

  void _handleCollisions() {
    List<CarromPiece> allPieces = [_striker, ..._pieces];

    for (int i = 0; i < allPieces.length; i++) {
      for (int j = i + 1; j < allPieces.length; j++) {
        CarromPiece p1 = allPieces[i];
        CarromPiece p2 = allPieces[j];

        double distSq = (p1.position - p2.position).distanceSquared;
        double minDist = p1.radius + p2.radius;

        if (distSq < minDist * minDist) {
          // Collision detected
          Offset delta = p1.position - p2.position;
          double dist = math.sqrt(distSq);
          Offset normal = delta / dist;

          // Separate circles to prevent sticking
          double overlap = minDist - dist;
          Offset separation = normal * (overlap / 2);
          p1.position += separation;
          p2.position -= separation;

          // Elastic Collision Response
          Offset relativeVelocity = p1.velocity - p2.velocity;
          double velocityAlongNormal = relativeVelocity.dx * normal.dx + relativeVelocity.dy * normal.dy;

          if (velocityAlongNormal > 0) continue; // Moving apart

          double restitution = 0.8; // Bounciness
          double impulseScalar = -(1 + restitution) * velocityAlongNormal;
          impulseScalar /= (1 / p1.mass + 1 / p2.mass);

          Offset impulse = normal * impulseScalar;
          p1.velocity += impulse / p1.mass;
          p2.velocity -= impulse / p2.mass;
        }
      }
    }
  }

  void _onPanStart(DragStartDetails details) {
    if (_isMoving) return;
    
    Offset localPos = details.localPosition;

    // If touching striker, prepare to aim
    if ((localPos - _striker.position).distance < _striker.radius * 2) {
      _isDragging = true;
      _dragStart = localPos;
      _dragCurrent = localPos;
      setState(() {});
    } 
    // If touching baseline area, move striker
    else if (_canPlaceStriker && localPos.dy > _boardSize.height - 100 && localPos.dy < _boardSize.height - 60) {
       setState(() {
         _striker.position = Offset(localPos.dx.clamp(_striker.radius, _boardSize.width - _striker.radius), _striker.position.dy);
       });
    }
  }

  void _onPanUpdate(DragUpdateDetails details) {
    if (_isMoving) return;

    if (_isDragging) {
      setState(() {
        _dragCurrent = details.localPosition;
      });
    } else if (_canPlaceStriker && details.localPosition.dy > _boardSize.height - 100) {
       // Sliding striker
       setState(() {
         _striker.position = Offset(details.localPosition.dx.clamp(_striker.radius, _boardSize.width - _striker.radius), _striker.position.dy);
       });
    }
  }

  void _onPanEnd(DragEndDetails details) {
    if (_isDragging) {
      // Shoot
      Offset vector = _dragStart! - _dragCurrent!;
      
      // Cap max power
      double dist = vector.distance;
      double maxPull = 150.0;
      if (dist > maxPull) {
        vector = (vector / dist) * maxPull;
      }

      // Apply velocity
      double powerMultiplier = 0.3;
      _striker.velocity = vector * powerMultiplier;

      _isDragging = false;
      _dragStart = null;
      _dragCurrent = null;
      _isMoving = true;
      _canPlaceStriker = false;
      
      _ticker.start();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.brown[900],
      appBar: AppBar(
        title: const Text('Real Carrom'),
        backgroundColor: Colors.brown[800],
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              setState(() {
                _resetGame();
                _initPieces(_boardSize);
              });
            },
          )
        ],
      ),
      body: Center(
        child: LayoutBuilder(
          builder: (context, constraints) {
            // Keep board square
            double size = math.min(constraints.maxWidth, constraints.maxHeight) - 20;
            Size boardSize = Size(size, size);
            
            // Initialize pieces if needed
            WidgetsBinding.instance.addPostFrameCallback((_) {
               _initPieces(boardSize);
            });

            return GestureDetector(
              onPanStart: _onPanStart,
              onPanUpdate: _onPanUpdate,
              onPanEnd: _onPanEnd,
              child: Container(
                width: size,
                height: size,
                decoration: BoxDecoration(
                  color: const Color(0xFFF3E5AB), // Creamy wood color
                  border: Border.all(color: const Color(0xFF3E2723), width: 15),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: const [BoxShadow(blurRadius: 10, color: Colors.black54)],
                ),
                child: CustomPaint(
                  painter: CarromBoardPainter(
                    pieces: _pieces,
                    striker: _striker,
                    dragStart: _dragStart,
                    dragCurrent: _dragCurrent,
                    pocketRadius: _pocketRadius,
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class CarromPiece {
  Offset position;
  Offset velocity;
  double radius;
  Color color;
  double mass;
  bool isStriker;

  CarromPiece({
    required this.position,
    required this.color,
    this.velocity = Offset.zero,
    this.radius = 15,
    this.mass = 1.0,
    this.isStriker = false,
  });
}

class CarromBoardPainter extends CustomPainter {
  final List<CarromPiece> pieces;
  final CarromPiece striker;
  final Offset? dragStart;
  final Offset? dragCurrent;
  final double pocketRadius;

  CarromBoardPainter({
    required this.pieces,
    required this.striker,
    required this.dragStart,
    required this.dragCurrent,
    required this.pocketRadius,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Draw Pockets
    Paint pocketPaint = Paint()..color = Colors.black;
    canvas.drawCircle(Offset(0, 0), pocketRadius, pocketPaint);
    canvas.drawCircle(Offset(size.width, 0), pocketRadius, pocketPaint);
    canvas.drawCircle(Offset(0, size.height), pocketRadius, pocketPaint);
    canvas.drawCircle(Offset(size.width, size.height), pocketRadius, pocketPaint);

    // Draw Design Lines (Simplified)
    Paint linePaint = Paint()
      ..color = Colors.black54
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    
    // Center Design
    canvas.drawCircle(Offset(size.width/2, size.height/2), 60, linePaint);
    
    // Baseline (Striker Line)
    double baselineY = size.height - 80;
    canvas.drawLine(Offset(40, baselineY), Offset(size.width - 40, baselineY), linePaint);
    canvas.drawCircle(Offset(40, baselineY), 10, linePaint..style = PaintingStyle.fill..color = Colors.red);
    canvas.drawCircle(Offset(size.width - 40, baselineY), 10, linePaint..color = Colors.red);

    // Top Baseline (Opponent)
    double topBaselineY = 80;
    canvas.drawLine(Offset(40, topBaselineY), Offset(size.width - 40, topBaselineY), linePaint..color = Colors.black54..style = PaintingStyle.stroke);

    // Draw Pieces
    for (var piece in pieces) {
      _drawPiece(canvas, piece);
    }

    // Draw Striker
    _drawPiece(canvas, striker);

    // Draw Aim Line
    if (dragStart != null && dragCurrent != null) {
      Paint aimPaint = Paint()
        ..color = Colors.red.withOpacity(0.6)
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round;
      
      // Draw line from striker opposite to drag
      Offset vector = dragStart! - dragCurrent!;
      // Clamp visual length
      if (vector.distance > 150) {
        vector = (vector / vector.distance) * 150;
      }
      
      canvas.drawLine(striker.position, striker.position + vector, aimPaint);
      
      // Draw drag indicator
      Paint dragPaint = Paint()..color = Colors.blue.withOpacity(0.3);
      canvas.drawLine(striker.position, striker.position - vector, dragPaint);
    }
  }

  void _drawPiece(Canvas canvas, CarromPiece piece) {
    Paint paint = Paint()..color = piece.color;
    canvas.drawCircle(piece.position, piece.radius, paint);
    
    // Add some 3D effect/detail
    Paint border = Paint()
      ..color = Colors.black26
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    canvas.drawCircle(piece.position, piece.radius, border);
    
    Paint shine = Paint()..color = Colors.white24;
    canvas.drawCircle(piece.position - const Offset(3, 3), piece.radius * 0.4, shine);
  }

  @override
  bool shouldRepaint(covariant CarromBoardPainter oldDelegate) {
    return true; // Always repaint for animation
  }
}
