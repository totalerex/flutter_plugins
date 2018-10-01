part of device_calendar;

/// A calendar on the user's device
class Calendar {
  /// The unique identifier for this calendar
  String id;

  /// The name of this calendar
  String name;

  /// If the calendar is read-only
  bool isReadOnly;

  /// Calendar color (required for android)
  Color color;

  /// Account name (required for android)
  String accountName;

  Calendar({
    this.id,
    this.name,
    this.isReadOnly,
    this.color,
    this.accountName,
  });

  Calendar.fromJson(Map<String, dynamic> json) {
    id = json['id'];
    name = json['name'];
    isReadOnly = json['isReadOnly'];
    color = json['color'] != null ? Color(json['color']) : null;
    accountName = json['accountName'];
  }

  Map<String, dynamic> toJson() {
    final Map<String, dynamic> data = new Map<String, dynamic>();
    data['id'] = this.id;
    data['name'] = this.name;
    data['isReadOnly'] = this.isReadOnly;
    data['color'] = this.color.value;
    data['account'] = this.accountName;
    return data;
  }
}
