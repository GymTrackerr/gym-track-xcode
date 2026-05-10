//
//  WorkoutRoutesMapView.swift
//  GymTracker
//
//  Created by Daniel Kravec on 2025-12-30.
//

import SwiftUI
import MapKit
import Combine

@MainActor
final class RoutesVM: ObservableObject {
    @Published var all: [WorkoutRouteModel] = []
    @Published var visible: [WorkoutRouteModel] = []
    @Published var isLoading = false
    @Published var currentCenter: CLLocationCoordinate2D?
    @Published var currentRadiusMeters: Double = 1500

    func applyCenterFilter(center: CLLocationCoordinate2D, radiusMeters: Double) {
        currentCenter = center
        currentRadiusMeters = radiusMeters
        visible = all.filter { routeIntersects(center: center, radiusMeters: radiusMeters, locations: $0.locations) }
    }
    
    func calculateRadiusFromRegion(_ region: MKCoordinateRegion) -> Double {
        let centerLoc = CLLocation(latitude: region.center.latitude, longitude: region.center.longitude)
        let edgeLoc = CLLocation(latitude: region.center.latitude + region.span.latitudeDelta / 2, longitude: region.center.longitude)
        return centerLoc.distance(from: edgeLoc)
    }

    func load(hk: HealthKitManager) async {
        isLoading = true
        defer { isLoading = false }
        all = await hk.fetchWorkoutRoutes(days: 60)
        visible = all
    }
    
    func routeIntersects(center: CLLocationCoordinate2D, radiusMeters: Double, locations: [CLLocation]) -> Bool {
        let c = CLLocation(latitude: center.latitude, longitude: center.longitude)
        return locations.contains { $0.distance(from: c) <= radiusMeters }
    }
}

struct WorkoutRoutesMapView: View {
    @EnvironmentObject var hk: HealthKitManager
    @StateObject private var vm = RoutesVM()

    @State private var camera: MapCameraPosition = .automatic
    @State private var hasInitializedCamera = false
    
//    var filteredWorkouts: [HealthKitWorkout] {
//        switch selectedFilter {
//        case .all:
//            return hkManager.workouts
//        case .cardio:
//            return hkManager.workouts.filter { isCardioWorkout($0.type) }
//        case .strength:
//            return hkManager.workouts.filter { isStrengthWorkout($0.type) }
//        case .flexibility:
//            return hkManager.workouts.filter { isFlexibilityWorkout($0.type) }
//        }
//    }
    
    var body: some View {
        ZStack(alignment: .topLeading) {
            Map(position: $camera) {
                ForEach(vm.visible) { item in
                    MapPolyline(item.polyline)
                        .stroke(.blue, lineWidth: 3)
                }
            }
            .onMapCameraChange(frequency: .onEnd) { (context: MapCameraUpdateContext) in
                let center = context.region.center
                let radius = vm.calculateRadiusFromRegion(context.region)
                vm.applyCenterFilter(center: center, radiusMeters: radius)
                hasInitializedCamera = true
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("all=\(vm.all.count) visible=\(vm.visible.count)")
                    .font(.caption)
                    .padding(8)
                    .background(.yellow.opacity(0.95))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                
                Text("Radius: \(Int(vm.currentRadiusMeters))m")
                    .font(.caption)
                    .padding(8)
                    .background(.blue.opacity(0.8))
                    .foregroundColor(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                
                if vm.isLoading {
                    ProgressView()
                        .padding(8)
                        .background(.thinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
            }
            .padding()
            .zIndex(10)
        }
        .task { 
            await vm.load(hk: hk)
            
            // Fit map to show all loaded routes
            if !vm.all.isEmpty {
                let allLocations = vm.all.flatMap(\.locations)
                if !allLocations.isEmpty {
                    let coords = allLocations.map(\.coordinate)
                    
                    // Build a region that encompasses all coordinates
                    let lats = coords.map(\.latitude)
                    let lons = coords.map(\.longitude)
                    let minLat = lats.min() ?? 0
                    let maxLat = lats.max() ?? 0
                    let minLon = lons.min() ?? 0
                    let maxLon = lons.max() ?? 0
                    
                    let center = CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2, longitude: (minLon + maxLon) / 2)
                    let span = MKCoordinateSpan(latitudeDelta: (maxLat - minLat) * 1.2, longitudeDelta: (maxLon - minLon) * 1.2)
                    let region = MKCoordinateRegion(center: center, span: span)
                    camera = .region(region)
                    
                    // Apply filter after setting camera
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        if !hasInitializedCamera {
                            let radius = vm.calculateRadiusFromRegion(region)
                            vm.applyCenterFilter(center: center, radiusMeters: radius)
                            hasInitializedCamera = true
                        }
                    }
                }
            }
        }
    }
}
