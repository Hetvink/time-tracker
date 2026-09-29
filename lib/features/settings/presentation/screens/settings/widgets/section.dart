import 'package:flutter/material.dart';

class Section {
  final String id;
  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget body;
  const Section(this.id, this.icon, this.title, this.body, {this.subtitle});
}
