import 'package:cloud_firestore/cloud_firestore.dart';

enum TaskStatus { pending, in_progress, completed, cancelled }

class Task {
  final String id;
  final String title;
  final String description;
  final TaskStatus status;
  final DateTime createdAt;
  final DateTime? updatedAt;
  final DateTime? dueDate;
  final String? userId; // User who created the task
  final int priority; // 1=low, 2=medium, 3=high
  final List<String> tags;

  Task({
    required this.id,
    required this.title,
    required this.description,
    required this.status,
    required this.createdAt,
    this.updatedAt,
    this.dueDate,
    this.userId,
    this.priority = 2,
    this.tags = const [],
  });

  factory Task.fromJson(Map<String, dynamic> json) {
    return Task(
      id: json['id']?.toString() ?? '',
      title: json['title'] as String? ?? '',
      description: json['description'] as String? ?? '',
      status: _parseStatus(json['status'] as String? ?? 'pending'),
      createdAt: DateTime.parse(json['created_at'] ?? json['createdAt'] ?? DateTime.now().toIso8601String()),
      updatedAt: json['updated_at'] != null ? DateTime.parse(json['updated_at']) : 
                   json['updatedAt'] != null ? DateTime.parse(json['updatedAt']) : null,
      dueDate: json['due_date'] != null ? DateTime.parse(json['due_date']) : 
              json['dueDate'] != null ? DateTime.parse(json['dueDate']) : null,
      userId: json['user_id']?.toString() ?? json['userId']?.toString(),
      priority: json['priority'] as int? ?? 2,
      tags: (json['tags'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [],
    );
  }

  factory Task.fromSupabaseJson(Map<String, dynamic> json) {
    return Task(
      id: json['id']?.toString() ?? '',
      title: json['title'] as String? ?? '',
      description: json['description'] as String? ?? '',
      status: _parseStatus(json['status'] as String? ?? 'pending'),
      createdAt: DateTime.parse(json['created_at'] ?? DateTime.now().toIso8601String()),
      updatedAt: json['updated_at'] != null ? DateTime.parse(json['updated_at']) : null,
      dueDate: json['due_date'] != null ? DateTime.parse(json['due_date']) : null,
      userId: json['user_id']?.toString(),
      priority: json['priority'] as int? ?? 2,
      tags: (json['tags'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [],
    );
  }

  factory Task.fromFirebaseJson(String id, Map<String, dynamic> json) {
    return Task(
      id: id,
      title: json['title'] as String? ?? '',
      description: json['description'] as String? ?? '',
      status: _parseStatus(json['status'] as String? ?? 'pending'),
      createdAt: (json['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      updatedAt: (json['updatedAt'] as Timestamp?)?.toDate(),
      dueDate: (json['dueDate'] as Timestamp?)?.toDate(),
      userId: json['userId']?.toString(),
      priority: json['priority'] as int? ?? 2,
      tags: (json['tags'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [],
    );
  }

  static TaskStatus _parseStatus(String status) {
    switch (status.toLowerCase()) {
      case 'pending':
        return TaskStatus.pending;
      case 'in_progress':
      case 'inprogress':
        return TaskStatus.in_progress;
      case 'completed':
        return TaskStatus.completed;
      case 'cancelled':
        return TaskStatus.cancelled;
      default:
        return TaskStatus.pending;
    }
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'description': description,
      'status': status.name,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt?.toIso8601String(),
      'dueDate': dueDate?.toIso8601String(),
      'userId': userId,
      'priority': priority,
      'tags': tags,
    };
  }

  Map<String, dynamic> toSupabaseJson() {
    return {
      'id': id,
      'title': title,
      'description': description,
      'status': status.name,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt?.toIso8601String(),
      'due_date': dueDate?.toIso8601String(),
      'user_id': userId,
      'priority': priority,
      'tags': tags,
    };
  }

  Map<String, dynamic> toFirebaseJson() {
    return {
      'supabaseId': id, // Ajouter l'ID Supabase pour la synchronisation
      'title': title,
      'description': description,
      'status': status.name,
      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt': updatedAt != null ? Timestamp.fromDate(updatedAt!) : FieldValue.serverTimestamp(),
      'dueDate': dueDate != null ? Timestamp.fromDate(dueDate!) : null,
      'userId': userId,
      'priority': priority,
      'tags': tags,
    };
  }

  Task copyWith({
    String? id,
    String? title,
    String? description,
    TaskStatus? status,
    DateTime? createdAt,
    DateTime? updatedAt,
    DateTime? dueDate,
    String? userId,
    int? priority,
    List<String>? tags,
  }) {
    return Task(
      id: id ?? this.id,
      title: title ?? this.title,
      description: description ?? this.description,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      dueDate: dueDate ?? this.dueDate,
      userId: userId ?? this.userId,
      priority: priority ?? this.priority,
      tags: tags ?? this.tags,
    );
  }

  // Helper methods
  String get statusText {
    switch (status) {
      case TaskStatus.pending:
        return 'En attente';
      case TaskStatus.in_progress:
        return 'En cours';
      case TaskStatus.completed:
        return 'Terminé';
      case TaskStatus.cancelled:
        return 'Annulé';
    }
  }

  String get priorityText {
    switch (priority) {
      case 1:
        return 'Basse';
      case 2:
        return 'Moyenne';
      case 3:
        return 'Haute';
      default:
        return 'Moyenne';
    }
  }

  bool get isOverdue {
    if (dueDate == null) return false;
    return DateTime.now().isAfter(dueDate!);
  }

  bool get isCompleted {
    return status == TaskStatus.completed;
  }

  bool get isPending {
    return status == TaskStatus.pending;
  }

  bool get isInProgress {
    return status == TaskStatus.in_progress;
  }
}
