import Flutter
import UIKit
import EventKit

extension UIColor {
    convenience init(argb: Int) {
        let mask = 0x000000FF
        let a = Int(argb >> 24) & mask
        let r = Int(argb >> 16) & mask
        let g = Int(argb >> 8) & mask
        let b = Int(argb >> 0) & mask

        let red   = CGFloat(r) / 255.0
        let green = CGFloat(g) / 255.0
        let blue  = CGFloat(b) / 255.0
        let alpha = CGFloat(a) / 255.0

        self.init(red: red, green: green, blue: blue, alpha: alpha)
    }
}

extension CGColor {
    var argb: Int? {
        get {
            guard let components = components, components.count == 4 else {
                return nil
            }
            let a = components[3]*CGFloat(255<<24)
            let r = components[0]*CGFloat(255<<16)
            let g = components[1]*CGFloat(255<<8)
            let b = components[2]*CGFloat(255)
            return (Int)(a) | (Int)(r) | (Int)(g) | (Int)(b)
        }
    }
}

public class SwiftDeviceCalendarPlugin: NSObject, FlutterPlugin {
    struct Calendar: Codable {
        let id: String
        let name: String
        let isReadOnly: Bool
        let color: Int
    }
    
    struct Event: Codable {
        let eventId: String
        let calendarId: String
        let title: String
        let description: String?
        let start: Int
        let end: Int
        let allDay: Bool
        let attendees: [Attendee]
        let location: String?
        let alarms: [Int]?
    }
    
    struct Attendee: Codable {
        let name: String
    }
    
    struct Location: Codable {
        let latitude: Double
        let longitude: Double
    }
    
    static let channelName = "plugins.builttoroam.com/device_calendar"
    let notFoundErrorCode = "404";
    let notAllowed = "405";
    let genericError = "500"
    let unauthorizedErrorCode = "401"
    let unauthorizedErrorMessage = "The user has not allowed this application to modify their calendar(s)"
    let calendarNotFoundErrorMessageFormat = "The calendar with the ID %@ could not be found"
    let calendarReadOnlyErrorMessageFormat = "Calendar with ID %@ is read-only"
    let eventNotFoundErrorMessageFormat = "The event with the ID %@ could not be found"
    let eventStore = EKEventStore()
    let requestPermissionsMethod = "requestPermissions"
    let hasPermissionsMethod = "hasPermissions"
    let retrieveCalendarsMethod = "retrieveCalendars"
    let retrieveCalendarMethod = "retrieveCalendar"
    let deleteCalendarMethod = "deleteCalendar"
    let retrieveEventsMethod = "retrieveEvents"
    let createOrUpdateEventMethod = "createOrUpdateEvent"
    let deleteEventMethod = "deleteEvent"
    let calendarColorArgument = "calendarColor"
    let calendarTitleArgument = "calendarTitle"
    let calendarIdArgument = "calendarId"
    let startDateArgument = "startDate"
    let endDateArgument = "endDate"
    let eventIdArgument = "eventId"
    let eventIdsArgument = "eventIds"
    let eventTitleArgument = "eventTitle"
    let eventDescriptionArgument = "eventDescription"
    let eventStartDateArgument =  "eventStartDate"
    let eventEndDateArgument = "eventEndDate"
    let eventAlarmsArgument = "eventAlarms"
    
    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(name: channelName, binaryMessenger: registrar.messenger())
        let instance = SwiftDeviceCalendarPlugin()
        registrar.addMethodCallDelegate(instance, channel: channel)
    }
    
    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case requestPermissionsMethod:
            requestPermissions(result)
        case hasPermissionsMethod:
            hasPermissions(result)
        case retrieveCalendarsMethod:
            retrieveCalendars(result)
        case retrieveEventsMethod:
            retrieveEvents(call, result)
        case createOrUpdateEventMethod:
            createOrUpdateEvent(call, result)
        case deleteEventMethod:
            deleteEvent(call, result)
        case deleteCalendarMethod:
            deleteCalendar(call, result)
        case retrieveCalendarMethod:
            retrieveCalendar(call, result)
        default:
            result(FlutterMethodNotImplemented)
        }
    }
    
    private func hasPermissions(_ result: FlutterResult) {
        let hasPermissions = self.hasPermissions()
        result(hasPermissions)
    }
    
    private func retrieveCalendars(_ result: @escaping FlutterResult) {
        checkPermissionsThenExecute(permissionsGrantedAction: {
            let ekCalendars = self.eventStore.calendars(for: .event)
            var calendars = [Calendar]()
            for ekCalendar in ekCalendars {
                let argb = ekCalendar.cgColor.argb!
                let calendar = Calendar(id: ekCalendar.calendarIdentifier, name: ekCalendar.title, isReadOnly: !ekCalendar.allowsContentModifications, color: argb)
                calendars.append(calendar)
            }
            
            self.encodeJsonAndFinish(codable: calendars, result: result)
        }, result: result)
    }
    
    private func retrieveCalendar(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
        checkPermissionsThenExecute(permissionsGrantedAction: {
            let arguments = call.arguments as! Dictionary<String, AnyObject>
            
            guard let calendarId = arguments[calendarIdArgument] as? String else {
                self.finishWithCalendarNotFoundError(result: result, calendarId: "NOID")
                return
            }
            
            guard let ekCalendar = self.eventStore.calendar(withIdentifier: calendarId) else {
                self.finishWithCalendarNotFoundError(result: result, calendarId: calendarId)
                return
            }
            
            let argb = ekCalendar.cgColor.argb ?? 0
            let calendar = Calendar(id: ekCalendar.calendarIdentifier, name: ekCalendar.title, isReadOnly: !ekCalendar.allowsContentModifications, color: argb)
            
            self.encodeJsonAndFinish(codable: calendar, result: result)
        }, result: result)
    }

    
    private func deleteCalendar(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
        checkPermissionsThenExecute(permissionsGrantedAction: {
            let arguments = call.arguments as! Dictionary<String, AnyObject>
            let calendarId = arguments[self.calendarIdArgument] as! String
            let ekCalendar = self.eventStore.calendar(withIdentifier: calendarId)
            if (ekCalendar == nil) {
                self.finishWithCalendarNotFoundError(result: result, calendarId: calendarId)
                return
            }
            
            if (!(ekCalendar!.allowsContentModifications)) {
                self.finishWithCalendarReadOnlyError(result: result, calendarId: calendarId)
                return
            }
            
            do {
                try self.eventStore.removeCalendar(ekCalendar!, commit: true)
                result(true)
            } catch {
                self.eventStore.reset()
                result(FlutterError(code: self.genericError, message: error.localizedDescription, details: nil))
            }
        }, result: result)
    }
    
    private func retrieveEvents(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
        checkPermissionsThenExecute(permissionsGrantedAction: {
            let arguments = call.arguments as! Dictionary<String, AnyObject>
            let calendarId = arguments[self.calendarIdArgument] as! String
            let startDateMillisecondsSinceEpoch = arguments[self.startDateArgument] as? NSNumber
            let endDateDateMillisecondsSinceEpoch = arguments[self.endDateArgument] as? NSNumber
            let eventIds = arguments[self.eventIdsArgument] as? [String]
            var events = [Event]()
            let specifiedStartEndDates = startDateMillisecondsSinceEpoch != nil && endDateDateMillisecondsSinceEpoch != nil
            if (specifiedStartEndDates) {
                let startDate = Date (timeIntervalSince1970: startDateMillisecondsSinceEpoch!.doubleValue / 1000.0)
                let endDate = Date (timeIntervalSince1970: endDateDateMillisecondsSinceEpoch!.doubleValue / 1000.0)
                let ekCalendar = self.eventStore.calendar(withIdentifier: calendarId)
                let predicate = self.eventStore.predicateForEvents(withStart: startDate, end: endDate, calendars: [ekCalendar!])
                let ekEvents = self.eventStore.events(matching: predicate)
                for ekEvent in ekEvents {
                    let event = createEventFromEkEvent(calendarId: calendarId, ekEvent: ekEvent)
                    events.append(event)
                }
            }
            
            if (eventIds == nil) {
                self.encodeJsonAndFinish(codable: events, result: result)
                return
            }
            
            if (specifiedStartEndDates) {
                events = events.filter({ (e) -> Bool in
                    e.calendarId == calendarId && eventIds!.contains(e.eventId)
                })
                
                self.encodeJsonAndFinish(codable: events, result: result)
                return
            }
            
            for eventId in eventIds! {
                let ekEvent = self.eventStore.event(withIdentifier: eventId)
                if(ekEvent == nil) {
                    continue
                }
                let event = createEventFromEkEvent(calendarId: calendarId, ekEvent: ekEvent!)
                events.append(event)
            }
            
            self.encodeJsonAndFinish(codable: events, result: result)
        }, result: result)
    }
    
    private func createEventFromEkEvent(calendarId: String, ekEvent: EKEvent) -> Event {
        var attendees = [Attendee]()
        if (ekEvent.attendees != nil) {
            for ekParticipant in ekEvent.attendees! {
                if(ekParticipant.name == nil) {
                    continue
                }
                let attendee = Attendee(name: ekParticipant.name!)
                attendees.append(attendee)
            }
            
        }
        let alarms = ekEvent.alarms?.flatMap({ Int($0.relativeOffset) })
        let end = Int(ekEvent.endDate.timeIntervalSince1970) * 1000
        let start = Int(ekEvent.startDate.timeIntervalSince1970) * 1000
        let event = Event(eventId: ekEvent.eventIdentifier, calendarId: calendarId, title: ekEvent.title, description: ekEvent.notes, start: start, end: end, allDay: ekEvent.isAllDay, attendees: attendees, location: ekEvent.location, alarms: alarms)
        return event
    }
    
    private func createOrUpdateEvent(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
        checkPermissionsThenExecute(permissionsGrantedAction: {
            let arguments = call.arguments as! Dictionary<String, AnyObject>
            let calendarId = arguments[self.calendarIdArgument] as! String
            let eventId = arguments[self.eventIdArgument] as? String
            let startDateMillisecondsSinceEpoch = arguments[self.eventStartDateArgument] as! NSNumber
            let endDateDateMillisecondsSinceEpoch = arguments[self.eventEndDateArgument] as! NSNumber
            let startDate = Date (timeIntervalSince1970: startDateMillisecondsSinceEpoch.doubleValue / 1000.0)
            let endDate = Date (timeIntervalSince1970: endDateDateMillisecondsSinceEpoch.doubleValue / 1000.0)
            let title = arguments[self.eventTitleArgument] as! String
            let description = arguments[self.eventDescriptionArgument] as? String
            let alarms = arguments[self.eventAlarmsArgument] as? [NSNumber]
            let ekCalendar = self.eventStore.calendar(withIdentifier: calendarId)
            if (ekCalendar == nil) {
                self.finishWithCalendarNotFoundError(result: result, calendarId: calendarId)
                return
            }
            
            if (!(ekCalendar!.allowsContentModifications)) {
                self.finishWithCalendarReadOnlyError(result: result, calendarId: calendarId)
                return
            }
            
            var ekEvent: EKEvent?
            if(eventId == nil) {
                ekEvent = EKEvent.init(eventStore: self.eventStore)
            } else {
                ekEvent = self.eventStore.event(withIdentifier: eventId!)
                if(ekEvent == nil) {
                    self.finishWithEventNotFoundError(result: result, eventId: eventId!)
                    return
                }
            }

            if (alarms != nil) {
                let ekAlarms = alarms!.flatMap({ EKAlarm(relativeOffset: TimeInterval(exactly: $0)!) })
                ekEvent!.alarms = ekAlarms
            }
            
            ekEvent!.title = title
            ekEvent!.notes = description
            ekEvent!.startDate = startDate
            ekEvent!.endDate = endDate
            ekEvent!.calendar = ekCalendar!
            do {
                try self.eventStore.save(ekEvent!, span: EKSpan.futureEvents)
                result(ekEvent!.eventIdentifier)
            } catch {
                self.eventStore.reset()
                result(FlutterError(code: self.genericError, message: error.localizedDescription, details: nil))
            }
        }, result: result)
    }
    
    private func deleteEvent(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
        checkPermissionsThenExecute(permissionsGrantedAction: {
            let arguments = call.arguments as! Dictionary<String, AnyObject>
            let calendarId = arguments[self.calendarIdArgument] as! String
            let eventId = arguments[self.eventIdArgument] as! String
            let ekCalendar = self.eventStore.calendar(withIdentifier: calendarId)
            if (ekCalendar == nil) {
                self.finishWithCalendarNotFoundError(result: result, calendarId: calendarId)
                return
            }
            
            if (!(ekCalendar!.allowsContentModifications)) {
                self.finishWithCalendarReadOnlyError(result: result, calendarId: calendarId)
                return
            }
            
            let ekEvent = self.eventStore.event(withIdentifier: eventId)
            if (ekEvent == nil) {
                self.finishWithEventNotFoundError(result: result, eventId: eventId)
                return
            }
            
            do {
                try self.eventStore.remove(ekEvent!, span: .thisEvent)
                result(true)
            } catch {
                self.eventStore.reset()
                result(FlutterError(code: self.genericError, message: error.localizedDescription, details: nil))
            }
        }, result: result)
    }
    
    private func finishWithUnauthorizedError(result: @escaping FlutterResult) {
        result(FlutterError(code:self.unauthorizedErrorCode, message: self.unauthorizedErrorMessage, details: nil))
    }
    
    private func finishWithCalendarNotFoundError(result: @escaping FlutterResult, calendarId: String) {
        let errorMessage = String(format: self.calendarNotFoundErrorMessageFormat, calendarId)
        result(FlutterError(code:self.notFoundErrorCode, message: errorMessage, details: nil))
    }
    
    private func finishWithCalendarReadOnlyError(result: @escaping FlutterResult, calendarId: String) {
        let errorMessage = String(format: self.calendarReadOnlyErrorMessageFormat, calendarId)
        result(FlutterError(code:self.notAllowed, message: errorMessage, details: nil))
    }
    
    private func finishWithEventNotFoundError(result: @escaping FlutterResult, eventId: String) {
        let errorMessage = String(format: self.eventNotFoundErrorMessageFormat, eventId)
        result(FlutterError(code:self.notFoundErrorCode, message: errorMessage, details: nil))
    }
    
    
    private func encodeJsonAndFinish<T: Codable>(codable: T, result: @escaping FlutterResult) {
        do {
            let jsonEncoder = JSONEncoder();
            let jsonData = try jsonEncoder.encode(codable)
            let jsonString = String(data: jsonData, encoding: .utf8)
            result(jsonString)
        } catch {
            result(FlutterError(code: genericError, message: error.localizedDescription, details: nil))
        }
    }
    
    private func checkPermissionsThenExecute(permissionsGrantedAction: () -> Void, result: @escaping FlutterResult) {
        if(hasPermissions()) {
            permissionsGrantedAction()
            return
        }
        self.finishWithUnauthorizedError(result: result)
    }
    
    private func requestPermissions(completion: @escaping (Bool) -> Void) {
        if(hasPermissions()) {
            completion(true)
            return
        }
        eventStore.requestAccess(to: .event, completion: {
            (accessGranted: Bool, error: Error?) in
            completion(accessGranted)
        })
    }
    
    private func hasPermissions() -> Bool {
        let status = EKEventStore.authorizationStatus(for: .event)
        return status == EKAuthorizationStatus.authorized;
    }
    
    private func requestPermissions(_ result: @escaping FlutterResult) {
        if(hasPermissions()) {
            result(true)
        }
        eventStore.requestAccess(to: .event, completion: {
            (accessGranted: Bool, error: Error?) in
            result(accessGranted)
        })
    }
}
