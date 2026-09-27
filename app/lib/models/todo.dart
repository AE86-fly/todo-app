class Todo {
  final int id;
  final String title;
  final bool done;

  const Todo({required this.id, required this.title, required this.done});

  factory Todo.fromJson(Map<String, dynamic> json) => Todo(
        id: json['id'] as int,
        title: json['title'] as String,
        done: json['done'] as bool,
      );
}
