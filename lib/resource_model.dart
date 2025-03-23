class MentalHealthResource {
  final String title;
  final String content;
  final String category;

  MentalHealthResource({
    required this.title, 
    required this.content, 
    this.category = 'General'
  });
}