part of receive_sharing_intent;

class SharedMediaFile {
  /// Shared file path, url or the text
  /// NOTE. All files are copied to a temp cache folder
  final String path;

  final String? thumbnail;

  final String? title;

  final String? description;

  /// Video duration in milliseconds
  final double? duration;

  /// Shared media type
  final SharedMediaType type;

  /// Mime type of the file.
  /// i.e. image/jpeg, video/mp4, text/plain
  final String? mimeType;

  SharedMediaFile({
    required this.path,
    required this.type,
    this.thumbnail,
    this.title,
    this.description,
    this.duration,
    this.mimeType,
  });

  SharedMediaFile.fromMap(Map<String, dynamic> json)
      : path = json['path'],
        thumbnail = json['thumbnail'],
        title = json['title'],
        description = json['description'],
        duration = json['duration'],
        type = SharedMediaType.fromValue(json['type']),
        mimeType = json['mimeType'];

  Map<String, dynamic> toMap() {
    return {
      'path': path,
      'thumbnail': thumbnail,
      'title': title,
      'description': description,
      'duration': duration,
      'type': type.value,
      'mimeType': mimeType,
    };
  }
}

enum SharedMediaType {
  image('image'),
  video('video'),
  text('text'),
  file('file'),
  url('url');

  final String value;

  const SharedMediaType(this.value);

  static SharedMediaType fromValue(String value) {
    return SharedMediaType.values.firstWhere((e) => e.value == value);
  }
}
