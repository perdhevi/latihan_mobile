class Exercise {
  final String id;
  final String name;
  final String description;
  final String category;
  final String muscleGroup;
  final String equipment;
  final DateTime createdAt;
  final DateTime updatedAt;

  Exercise({
    required this.id,
    required this.name,
    required this.description,
    required this.category,
    required this.muscleGroup,
    required this.equipment,
    required this.createdAt,
    required this.updatedAt,
  });
}
