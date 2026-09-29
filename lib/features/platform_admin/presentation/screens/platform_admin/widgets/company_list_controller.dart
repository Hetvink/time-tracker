import 'package:flutter/material.dart';
import 'package:time_trak/features/company/data/models/company.dart';

import 'sort.dart';

class CompanyListController extends ChangeNotifier {
  CompanyStatus? _filter;
  String _query = '';
  PlatformAdminSort _sort = PlatformAdminSort.newest;

  CompanyStatus? get filter => _filter;
  String get query => _query;
  PlatformAdminSort get sort => _sort;

  void setFilter(CompanyStatus? f) {
    _filter = f;
    notifyListeners();
  }

  void setQuery(String q) {
    _query = q;
    notifyListeners();
  }

  void setSort(PlatformAdminSort s) {
    _sort = s;
    notifyListeners();
  }
}
