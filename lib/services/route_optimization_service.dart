import 'dart:math';
import '../models/mission.dart';

class RouteOptimizationService {
  
  List<MissionStop> optimizeRoute({
    required MissionStop currentLocation,
    required List<MissionStop> unvisitedStops,
    required double priorityWeight,
  }) {
    List<MissionStop> remaining = List.from(unvisitedStops);
    List<MissionStop> optimizedRoute = [];
    MissionStop current = currentLocation;

    while (remaining.isNotEmpty) {
      MissionStop? nextStop;
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

  double _calculateEstimatedTravelTime(MissionStop start, MissionStop end) {
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