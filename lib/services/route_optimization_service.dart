import 'dart:math';
import '../models/mission.dart';

class RouteOptimizationService {
  
  List<RouteStop> optimizeRoute({
    required RouteStop currentLocation,
    required List<RouteStop> unvisitedStops,
    required double priorityWeight,
  }) {
    List<RouteStop> remaining = List.from(unvisitedStops);
    List<RouteStop> optimizedRoute = [];
    RouteStop current = currentLocation;

    while (remaining.isNotEmpty) {
      RouteStop? nextStop;
      double lowestScore = double.infinity;

      for (var stop in remaining) {
        double travelTime = _calculateEstimatedTravelTime(current, stop);
        
        double score = travelTime - (stop.priority * priorityWeight);

        if (score < lowestScore) {
          lowestScore = score;
          nextStop = stop;
        }
      }

      if (nextStop != null) {
        optimizedRoute.add(nextStop);
        remaining.remove(nextStop);
        current = nextStop; 
      }
    }

    return optimizedRoute;
  }

  double _calculateEstimatedTravelTime(RouteStop start, RouteStop end) {
    const double earthRadiusKm = 6371.0;
    const double averageSpeedKmH = 40.0; 

    double dLat = _degreesToRadians(end.latitude - start.latitude);
    double dLon = _degreesToRadians(end.longitude - start.longitude);

    double a = sin(dLat / 2) * sin(dLat / 2) +
        cos(_degreesToRadians(start.latitude)) * cos(_degreesToRadians(end.latitude)) *
        sin(dLon / 2) * sin(dLon / 2);
    
    double c = 2 * atan2(sqrt(a), sqrt(1 - a));
    double distanceKm = earthRadiusKm * c;

    double timeHours = distanceKm / averageSpeedKmH;
    return timeHours * 60.0; 
  }

  double _degreesToRadians(double degrees) {
    return degrees * pi / 180.0;
  }
}