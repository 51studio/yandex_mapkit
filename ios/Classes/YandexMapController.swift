import CoreLocation
import Flutter
import UIKit
import YandexMapKit

public class YandexMapController: NSObject, FlutterPlatformView {
  private let methodChannel: FlutterMethodChannel!
  private let pluginRegistrar: FlutterPluginRegistrar!
  private let mapObjectTapListener: MapObjectTapListener!
  private var userLocationObjectListener: UserLocationObjectListener?
  private var placemarks: [YMKPlacemarkMapObject] = []
  public let mapView: YMKMapView

  public required init(id: Int64, frame: CGRect, registrar: FlutterPluginRegistrar) {
    self.pluginRegistrar = registrar
    self.mapView = YMKMapView(frame: frame)
    self.methodChannel = FlutterMethodChannel(
      name: "yandex_mapkit/yandex_map_\(id)",
      binaryMessenger: registrar.messenger()
    )
    self.mapObjectTapListener = MapObjectTapListener(channel: methodChannel)
    super.init()
    self.methodChannel.setMethodCallHandler(self.handle)
  }

  public func view() -> UIView {
    return self.mapView
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "showUserLayer":
      showUserLayer(call)
      result(nil)
    case "hideUserLayer":
      hideUserLayer()
      result(nil)
    case "move":
      move(call)
      result(nil)
    case "setBounds":
      setBounds(call)
      result(nil)
    case "addPlacemark":
      addPlacemark(call)
      result(nil)
    case "removePlacemark":
      removePlacemark(call)
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  public func showUserLayer(_ call: FlutterMethodCall) {
    if (!hasLocationPermission()) { return }

    let params = call.arguments as! [String: Any]
    self.userLocationObjectListener = UserLocationObjectListener(
      pluginRegistrar: pluginRegistrar,
      iconName: params["iconName"] as! String
    )
    let userLocationLayer = mapView.mapWindow.map.userLocationLayer
    userLocationLayer.isEnabled = true
    userLocationLayer.isHeadingEnabled = true
    userLocationLayer.setObjectListenerWith(userLocationObjectListener!)
  }

  public func hideUserLayer() {
    if (!hasLocationPermission()) { return }

    let userLocationLayer = mapView.mapWindow.map.userLocationLayer
    userLocationLayer.isEnabled = false
  }

  public func move(_ call: FlutterMethodCall) {
    let params = call.arguments as! [String: Any]
    let point = YMKPoint(latitude: params["latitude"] as! Double, longitude: params["longitude"] as! Double)
    let cameraPosition = YMKCameraPosition(
      target: point,
      zoom: params["zoom"] as! Float,
      azimuth: params["azimuth"] as! Float,
      tilt: params["tilt"] as! Float
    )

    moveWithParams(params, cameraPosition)
  }

  public func setBounds(_ call: FlutterMethodCall) {
    let params = call.arguments as! [String: Any]
    let cameraPosition = mapView.mapWindow.map.cameraPosition(with:
      YMKBoundingBox(
        southWest: YMKPoint(
          latitude: params["southWestLatitude"] as! Double,
          longitude: params["southWestLongitude"] as! Double
        ),
        northEast: YMKPoint(
          latitude: params["northEastLatitude"] as! Double,
          longitude: params["northEastLongitude"] as! Double
        )
      )
    )

    moveWithParams(params, cameraPosition)
  }

  public func addPlacemark(_ call: FlutterMethodCall) {
    addPlacemarkToMap(call.arguments as! [String: Any])
  }


  public func removePlacemark(_ call: FlutterMethodCall) {
    let params = call.arguments as! [String: Any]
    let mapObjects = mapView.mapWindow.map.mapObjects
    let placemark = placemarks.first(where: { $0.userData as! Int == params["hashCode"] as! Int })

    if (placemark != nil) {
      mapObjects.remove(with: placemark!)
      placemarks.remove(at: placemarks.index(of: placemark!)!)
    }
  }

  private func addPlacemarkToMap(_ params: [String: Any]) {
    let point = YMKPoint(latitude: params["latitude"] as! Double, longitude: params["longitude"] as! Double)
    let mapObjects = mapView.mapWindow.map.mapObjects
    let placemark = mapObjects.addPlacemark(with: point)
    let iconName = params["iconName"] as? String

    placemark.addTapListener(with: mapObjectTapListener)
    placemark.userData = params["hashCode"] as! Int
    placemark.opacity = params["opacity"] as! Float
    placemark.isDraggable = params["isDraggable"] as! Bool

    if (iconName != nil) {
      placemark.setIconWith(UIImage(named: pluginRegistrar.lookupKey(forAsset: iconName!))!)
    }

    placemarks.append(placemark)
  }

  private func moveWithParams(_ params: [String: Any], _ cameraPosition: YMKCameraPosition) {
    if (params["animate"] as! Bool) {
      let type = params["smoothAnimation"] as! Bool ? YMKAnimationType.smooth : YMKAnimationType.linear
      let animationType = YMKAnimation(type: type, duration: params["animationDuration"] as! Float)

      mapView.mapWindow.map.move(with: cameraPosition, animationType: animationType)
    } else {
      mapView.mapWindow.map.move(with: cameraPosition)
    }
  }

  private func hasLocationPermission() -> Bool {
    if CLLocationManager.locationServicesEnabled() {
      switch CLLocationManager.authorizationStatus() {
      case .notDetermined, .restricted, .denied:
        return false
      case .authorizedAlways, .authorizedWhenInUse:
        return true
      }
    } else {
      return false
    }
  }

  internal class UserLocationObjectListener: NSObject, YMKUserLocationObjectListener {
    private let pluginRegistrar: FlutterPluginRegistrar!
    private let iconName: String!

    public required init(pluginRegistrar: FlutterPluginRegistrar, iconName: String) {
      self.pluginRegistrar = pluginRegistrar
      self.iconName = iconName
    }

    func onObjectAdded(with view: YMKUserLocationView) {
      view.pin.setIconWith(
        UIImage(named: pluginRegistrar.lookupKey(forAsset: self.iconName))!
      )
    }

    func onObjectRemoved(with view: YMKUserLocationView) {}

    func onObjectUpdated(with view: YMKUserLocationView, event: YMKObjectEvent) {}
  }

  internal class MapObjectTapListener: NSObject, YMKMapObjectTapListener {
    private let methodChannel: FlutterMethodChannel!

    public required init(channel: FlutterMethodChannel) {
      self.methodChannel = channel
    }

    func onMapObjectTap(with mapObject: YMKMapObject, point: YMKPoint) -> Bool {
      let arguments: [String:Any?] = [
        "hashCode": mapObject.userData,
        "latitude": point.latitude,
        "longitude": point.longitude
      ]
      methodChannel.invokeMethod("onMapObjectTap", arguments: arguments)

      return true
    }
  }
}
