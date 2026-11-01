import 'package:flutter/material.dart';

/// Recherche : écran construit dans une tâche suivante de la spec 007.
class SearchScreen extends StatelessWidget {
  const SearchScreen({super.key});

  @override
  Widget build(BuildContext context) =>
      const SafeArea(child: Center(child: Text('Recherche')));
}
