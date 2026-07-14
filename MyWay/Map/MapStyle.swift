// Night map style — same JSON as Android's res/raw/map_dark.json so both platforms match.
enum MapStyle {
    static let darkJSON = """
    [
      { "elementType": "geometry", "stylers": [{ "color": "#0f172a" }] },
      { "elementType": "labels.text.fill", "stylers": [{ "color": "#94a3b8" }] },
      { "elementType": "labels.text.stroke", "stylers": [{ "color": "#0f172a" }] },
      { "featureType": "road", "elementType": "geometry", "stylers": [{ "color": "#1e293b" }] },
      { "featureType": "road", "elementType": "geometry.stroke", "stylers": [{ "color": "#0f172a" }] },
      { "featureType": "road", "elementType": "labels.text.fill", "stylers": [{ "color": "#cbd5e1" }] },
      { "featureType": "road.highway", "elementType": "geometry", "stylers": [{ "color": "#0097A7" }] },
      { "featureType": "road.highway", "elementType": "geometry.stroke", "stylers": [{ "color": "#0f172a" }] },
      { "featureType": "road.highway", "elementType": "labels.text.fill", "stylers": [{ "color": "#ffffff" }] },
      { "featureType": "water", "elementType": "geometry", "stylers": [{ "color": "#0e2433" }] },
      { "featureType": "water", "elementType": "labels.text.fill", "stylers": [{ "color": "#4e9fb5" }] },
      { "featureType": "poi", "elementType": "geometry", "stylers": [{ "color": "#1e293b" }] },
      { "featureType": "poi", "elementType": "labels.text.fill", "stylers": [{ "color": "#64748b" }] },
      { "featureType": "poi.park", "elementType": "geometry", "stylers": [{ "color": "#0f2a1e" }] },
      { "featureType": "poi.park", "elementType": "labels.text.fill", "stylers": [{ "color": "#4ade80" }] },
      { "featureType": "transit", "elementType": "geometry", "stylers": [{ "color": "#1e293b" }] },
      { "featureType": "transit.station", "elementType": "labels.text.fill", "stylers": [{ "color": "#94a3b8" }] },
      { "featureType": "administrative", "elementType": "geometry", "stylers": [{ "color": "#334155" }] },
      { "featureType": "administrative.country", "elementType": "labels.text.fill", "stylers": [{ "color": "#94a3b8" }] },
      { "featureType": "administrative.locality", "elementType": "labels.text.fill", "stylers": [{ "color": "#cbd5e1" }] }
    ]
    """
}
