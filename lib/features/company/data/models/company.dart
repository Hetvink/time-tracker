enum CompanyStatus {
  pending,
  approved,
  rejected,
  suspended;

  static CompanyStatus fromString(String? value) => CompanyStatus.values
      .firstWhere((s) => s.name == value, orElse: () => CompanyStatus.pending);

  String get label => switch (this) {
    CompanyStatus.pending => 'Pending review',
    CompanyStatus.approved => 'Active',
    CompanyStatus.rejected => 'Rejected',
    CompanyStatus.suspended => 'Suspended',
  };
}

DateTime? _parseDate(Object? value) =>
    value == null ? null : DateTime.tryParse(value as String)?.toLocal();

class Company {
  final String id;
  final String name;
  final String slug;
  final String? website;
  final String? industry;
  final String? companySize;
  final String? country;
  final String? phone;
  final String? description;
  final CompanyStatus status;
  final String? createdBy;
  final DateTime? createdAt;
  final DateTime? reviewedAt;
  final String? rejectionReason;

  const Company({
    required this.id,
    required this.name,
    required this.slug,
    this.website,
    this.industry,
    this.companySize,
    this.country,
    this.phone,
    this.description,
    required this.status,
    this.createdBy,
    this.createdAt,
    this.reviewedAt,
    this.rejectionReason,
  });

  bool get isApproved => status == CompanyStatus.approved;

  factory Company.fromJson(Map<String, dynamic> json) => Company(
    id: json['id'] as String,
    name: json['name'] as String? ?? '',
    slug: json['slug'] as String? ?? '',
    website: json['website'] as String?,
    industry: json['industry'] as String?,
    companySize: json['company_size'] as String?,
    country: json['country'] as String?,
    phone: json['phone'] as String?,
    description: json['description'] as String?,
    status: CompanyStatus.fromString(json['status'] as String?),
    createdBy: json['created_by'] as String?,
    createdAt: _parseDate(json['created_at']),
    reviewedAt: _parseDate(json['reviewed_at']),
    rejectionReason: json['rejection_reason'] as String?,
  );
}

/// Company details submitted with a registration request or profile edit.
class CompanyDetails {
  final String name;
  final String? website;
  final String? industry;
  final String? companySize;
  final String? country;
  final String? phone;
  final String? description;

  const CompanyDetails({
    required this.name,
    this.website,
    this.industry,
    this.companySize,
    this.country,
    this.phone,
    this.description,
  });

  factory CompanyDetails.fromCompany(Company c) => CompanyDetails(
    name: c.name,
    website: c.website,
    industry: c.industry,
    companySize: c.companySize,
    country: c.country,
    phone: c.phone,
    description: c.description,
  );

  Map<String, dynamic> toRpcParams() => {
    'p_name': name,
    'p_website': website,
    'p_industry': industry,
    'p_company_size': companySize,
    'p_country': country,
    'p_phone': phone,
    'p_description': description,
  };
}

/// A company row as listed in the platform admin console.
class CompanyOverview {
  final Company company;
  final String? creatorName;
  final String? creatorEmail;
  final int memberCount;
  final int adminCount;
  final int workingNow;

  const CompanyOverview({
    required this.company,
    this.creatorName,
    this.creatorEmail,
    required this.memberCount,
    required this.adminCount,
    required this.workingNow,
  });

  factory CompanyOverview.fromJson(Map<String, dynamic> json) =>
      CompanyOverview(
        company: Company.fromJson(json),
        creatorName: json['creator_name'] as String?,
        creatorEmail: json['creator_email'] as String?,
        memberCount: (json['member_count'] as num?)?.toInt() ?? 0,
        adminCount: (json['admin_count'] as num?)?.toInt() ?? 0,
        workingNow: (json['working_now'] as num?)?.toInt() ?? 0,
      );
}

class PlatformStats {
  final int companiesTotal;
  final int companiesPending;
  final int companiesApproved;
  final int companiesSuspended;
  final int companiesRejected;
  final int usersTotal;
  final int usersWithoutCompany;
  final int workingNow;

  const PlatformStats({
    required this.companiesTotal,
    required this.companiesPending,
    required this.companiesApproved,
    required this.companiesSuspended,
    required this.companiesRejected,
    required this.usersTotal,
    required this.usersWithoutCompany,
    required this.workingNow,
  });

  factory PlatformStats.fromJson(Map<String, dynamic> json) {
    int n(String key) => (json[key] as num?)?.toInt() ?? 0;
    return PlatformStats(
      companiesTotal: n('companies_total'),
      companiesPending: n('companies_pending'),
      companiesApproved: n('companies_approved'),
      companiesSuspended: n('companies_suspended'),
      companiesRejected: n('companies_rejected'),
      usersTotal: n('users_total'),
      usersWithoutCompany: n('users_without_company'),
      workingNow: n('working_now'),
    );
  }
}
