import 'package:flutter/material.dart';

import '../../../../data/models/team_member.dart';
import '../team_page.dart';

class MemberListController extends ChangeNotifier {
  String _query = '';
  MemberFilter _filter = MemberFilter.all;
  Sort _sort = Sort.name;
  bool _grid = false;

  String get query => _query;
  MemberFilter get filter => _filter;
  Sort get sort => _sort;
  bool get grid => _grid;

  void setQuery(String v) {
    _query = v;
    notifyListeners();
  }

  void setFilter(MemberFilter f) {
    _filter = f;
    notifyListeners();
  }

  void setSort(Sort s) {
    _sort = s;
    notifyListeners();
  }

  void setGrid(bool g) {
    _grid = g;
    notifyListeners();
  }

  List<TeamMember> visible(List<TeamMember> members) {
    final q = _query.trim().toLowerCase();
    final list = members.where((m) {
      final matchesQuery =
          q.isEmpty ||
          m.displayName.toLowerCase().contains(q) ||
          m.email.toLowerCase().contains(q);
      final matchesFilter = switch (_filter) {
        MemberFilter.all => true,
        MemberFilter.working => m.isWorking && !m.isOnBreak,
        MemberFilter.onBreak => m.isOnBreak,
        MemberFilter.admins => m.isAdmin,
        MemberFilter.inactive => !m.isActive,
      };
      return matchesQuery && matchesFilter;
    }).toList();
    list.sort(switch (_sort) {
      Sort.name => (a, b) => a.displayName.toLowerCase().compareTo(
        b.displayName.toLowerCase(),
      ),
      Sort.today => (a, b) => b.today.compareTo(a.today),
      Sort.week => (a, b) => b.week.compareTo(a.week),
      Sort.month => (a, b) => b.month.compareTo(a.month),
      Sort.lastSeen =>
        (a, b) =>
            (b.isWorking ? DateTime.now() : b.lastSeenAt ?? DateTime(2000))
                .compareTo(
                  a.isWorking ? DateTime.now() : a.lastSeenAt ?? DateTime(2000),
                ),
    });
    return list;
  }
}
