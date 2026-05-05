import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

void main() => runApp(const PersonalAgentApp());

enum UserRole { admin, gestor, colaborador }

extension UserRoleX on UserRole {
  String get label => this == UserRole.admin ? 'Admin' : this == UserRole.gestor ? 'Gestor' : 'Colaborador';
  bool get canManageUsers => this == UserRole.admin;
  bool get canManageProjects => this != UserRole.colaborador;
  bool get canManageRequirements => this != UserRole.colaborador;
  bool get canCreatePullRequest => this != UserRole.colaborador;
}

UserRole roleFromString(String raw) => UserRole.values.firstWhere((e) => e.name == raw, orElse: () => UserRole.colaborador);

class Organization {
  Organization({required this.id, required this.name});
  final String id;
  final String name;
  Map<String, dynamic> toJson() => {'id': id, 'name': name};
  factory Organization.fromJson(Map<String, dynamic> j) => Organization(id: j['id'] as String, name: j['name'] as String);
}

class UserAccount {
  UserAccount({required this.email, required this.password, required this.name, required this.organizationId, required this.role});
  final String email;
  final String password;
  final String name;
  final String organizationId;
  final UserRole role;
  Map<String, dynamic> toJson() => {
        'email': email,
        'password': password,
        'name': name,
        'organizationId': organizationId,
        'role': role.name,
      };
  factory UserAccount.fromJson(Map<String, dynamic> j) => UserAccount(
        email: j['email'] as String,
        password: j['password'] as String,
        name: j['name'] as String,
        organizationId: j['organizationId'] as String,
        role: roleFromString(j['role'] as String? ?? 'colaborador'),
      );
}

class SessionData {
  SessionData({required this.authenticated, this.email});
  final bool authenticated;
  final String? email;
}

class LoginResult {
  LoginResult({required this.success, this.user});
  final bool success;
  final UserAccount? user;
}

class TaskItem {
  TaskItem({required this.title, required this.priority, this.done = false});
  final String title;
  final String priority;
  bool done;
  Map<String, dynamic> toJson() => {'title': title, 'priority': priority, 'done': done};
  factory TaskItem.fromJson(Map<String, dynamic> j) =>
      TaskItem(title: j['title'] as String, priority: j['priority'] as String, done: j['done'] as bool? ?? false);
}

class CompanyProject {
  CompanyProject({required this.name, required this.client, required this.status, required this.owner});
  final String name;
  final String client;
  final String status;
  final String owner;
  Map<String, dynamic> toJson() => {'name': name, 'client': client, 'status': status, 'owner': owner};
  factory CompanyProject.fromJson(Map<String, dynamic> j) =>
      CompanyProject(name: j['name'] as String, client: j['client'] as String, status: j['status'] as String, owner: j['owner'] as String);
}

class CompanyRequirement {
  CompanyRequirement({required this.title, required this.description, this.completed = false});
  final String title;
  final String description;
  bool completed;
  Map<String, dynamic> toJson() => {'title': title, 'description': description, 'completed': completed};
  factory CompanyRequirement.fromJson(Map<String, dynamic> j) =>
      CompanyRequirement(title: j['title'] as String, description: j['description'] as String, completed: j['completed'] as bool? ?? false);
}

class LocalDataService {
  static const _accounts = 'accounts';
  static const _orgs = 'organizations';
  static const _sAuth = 'session_auth';
  static const _sEmail = 'session_email';
  String _tasks(String org) => 'tasks_$org';
  String _projects(String org) => 'projects_$org';
  String _reqs(String org) => 'reqs_$org';

  Future<List<Organization>> loadOrganizations() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(_orgs);
    if (raw == null) {
      final seed = [Organization(id: 'org_default', name: 'Empresa Padrão')];
      await p.setString(_orgs, jsonEncode(seed.map((e) => e.toJson()).toList()));
      return seed;
    }
    final decoded = jsonDecode(raw) as List<dynamic>;
    return decoded.map((e) => Organization.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<void> saveOrganizations(List<Organization> orgs) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_orgs, jsonEncode(orgs.map((e) => e.toJson()).toList()));
  }

  Future<void> registerUser(UserAccount account) async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(_accounts);
    final users = raw == null ? <UserAccount>[] : (jsonDecode(raw) as List<dynamic>).map((e) => UserAccount.fromJson(e as Map<String, dynamic>)).toList();
    if (users.any((u) => u.email.toLowerCase() == account.email.toLowerCase())) throw Exception('E-mail já cadastrado.');
    users.add(account);
    await p.setString(_accounts, jsonEncode(users.map((e) => e.toJson()).toList()));
  }

  Future<LoginResult> login({required String email, required String password}) async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(_accounts);
    if (raw == null) return LoginResult(success: false);
    final users = (jsonDecode(raw) as List<dynamic>).map((e) => UserAccount.fromJson(e as Map<String, dynamic>)).toList();
    for (final u in users) {
      if (u.email.toLowerCase() == email.toLowerCase() && u.password == password) return LoginResult(success: true, user: u);
    }
    return LoginResult(success: false);
  }

  Future<List<UserAccount>> usersByOrg(String orgId) async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(_accounts);
    if (raw == null) return [];
    final users = (jsonDecode(raw) as List<dynamic>).map((e) => UserAccount.fromJson(e as Map<String, dynamic>)).toList();
    return users.where((u) => u.organizationId == orgId).toList();
  }

  Future<void> saveSession({required bool authenticated, String? email}) async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(_sAuth, authenticated);
    if (email == null) {
      await p.remove(_sEmail);
    } else {
      await p.setString(_sEmail, email);
    }
  }

  Future<SessionData> getSession() async {
    final p = await SharedPreferences.getInstance();
    return SessionData(authenticated: p.getBool(_sAuth) ?? false, email: p.getString(_sEmail));
  }

  Future<UserAccount?> getUserByEmail(String email) async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(_accounts);
    if (raw == null) return null;
    final users = (jsonDecode(raw) as List<dynamic>).map((e) => UserAccount.fromJson(e as Map<String, dynamic>)).toList();
    for (final u in users) {
      if (u.email.toLowerCase() == email.toLowerCase()) return u;
    }
    return null;
  }

  Future<void> saveTasks(String org, List<TaskItem> v) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_tasks(org), jsonEncode(v.map((e) => e.toJson()).toList()));
  }

  Future<List<TaskItem>> loadTasks(String org) async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(_tasks(org));
    if (raw == null) return [TaskItem(title: 'Revisar contratos da semana', priority: 'Alta')];
    final decoded = jsonDecode(raw) as List<dynamic>;
    return decoded.map((e) => TaskItem.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<void> saveProjects(String org, List<CompanyProject> v) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_projects(org), jsonEncode(v.map((e) => e.toJson()).toList()));
  }

  Future<List<CompanyProject>> loadProjects(String org) async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(_projects(org));
    if (raw == null) return [];
    final decoded = jsonDecode(raw) as List<dynamic>;
    return decoded.map((e) => CompanyProject.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<void> saveRequirements(String org, List<CompanyRequirement> v) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_reqs(org), jsonEncode(v.map((e) => e.toJson()).toList()));
  }

  Future<List<CompanyRequirement>> loadRequirements(String org) async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(_reqs(org));
    if (raw == null) return [CompanyRequirement(title: 'LGPD', description: 'Políticas de privacidade e base legal documentadas.')];
    final decoded = jsonDecode(raw) as List<dynamic>;
    return decoded.map((e) => CompanyRequirement.fromJson(e as Map<String, dynamic>)).toList();
  }
}

class GithubSnapshot {
  GithubSnapshot({required this.issues, required this.pullRequests, required this.commits});
  final List<String> issues;
  final List<String> pullRequests;
  final List<String> commits;
}

class GithubService {
  Map<String, String> _headers(String token) => {
        'Accept': 'application/vnd.github+json',
        'Authorization': 'Bearer $token',
        'X-GitHub-Api-Version': '2022-11-28',
      };

  Future<GithubSnapshot> fetchAll({required String owner, required String repo, required String token}) async {
    final issuesRes = await http.get(Uri.parse('https://api.github.com/repos/$owner/$repo/issues?state=open'), headers: _headers(token));
    final prsRes = await http.get(Uri.parse('https://api.github.com/repos/$owner/$repo/pulls?state=open'), headers: _headers(token));
    final commitsRes = await http.get(Uri.parse('https://api.github.com/repos/$owner/$repo/commits?per_page=10'), headers: _headers(token));
    if (issuesRes.statusCode != 200 || prsRes.statusCode != 200 || commitsRes.statusCode != 200) throw Exception('Falha ao ler dados do GitHub.');
    final issues = (jsonDecode(issuesRes.body) as List<dynamic>)
        .where((i) => i['pull_request'] == null)
        .map((i) => '#${i['number']} - ${i['title']}')
        .cast<String>()
        .toList();
    final prs = (jsonDecode(prsRes.body) as List<dynamic>).map((i) => '#${i['number']} - ${i['title']}').cast<String>().toList();
    final commits = (jsonDecode(commitsRes.body) as List<dynamic>).map((i) => '${(i['sha'] as String).substring(0, 7)} - ${i['commit']['message']}').cast<String>().toList();
    return GithubSnapshot(issues: issues, pullRequests: prs, commits: commits);
  }

  Future<String> createIssue({required String owner, required String repo, required String token, required String title, required String body}) async {
    final res = await http.post(
      Uri.parse('https://api.github.com/repos/$owner/$repo/issues'),
      headers: _headers(token),
      body: jsonEncode({'title': title, 'body': body}),
    );
    if (res.statusCode != 201) throw Exception('Falha ao criar issue (${res.statusCode}).');
    return (jsonDecode(res.body) as Map<String, dynamic>)['html_url'] as String;
  }

  Future<String> createPullRequest({
    required String owner,
    required String repo,
    required String token,
    required String title,
    required String body,
    required String base,
    required String head,
  }) async {
    final res = await http.post(
      Uri.parse('https://api.github.com/repos/$owner/$repo/pulls'),
      headers: _headers(token),
      body: jsonEncode({'title': title, 'body': body, 'base': base, 'head': head}),
    );
    if (res.statusCode != 201) throw Exception('Falha ao criar PR (${res.statusCode}). Verifique branches.');
    return (jsonDecode(res.body) as Map<String, dynamic>)['html_url'] as String;
  }
}

class PersonalAgentApp extends StatelessWidget {
  const PersonalAgentApp({super.key});
  @override
  Widget build(BuildContext context) => const MaterialApp(debugShowCheckedModeBanner: false, home: AppBootstrapper());
}

class AppBootstrapper extends StatefulWidget {
  const AppBootstrapper({super.key});
  @override
  State<AppBootstrapper> createState() => _AppBootstrapperState();
}

class _AppBootstrapperState extends State<AppBootstrapper> {
  final _data = LocalDataService();
  bool _loading = true;
  UserAccount? _user;

  @override
  void initState() {
    super.initState();
    _boot();
  }

  Future<void> _boot() async {
    final s = await _data.getSession();
    if (s.authenticated && s.email != null) _user = await _data.getUserByEmail(s.email!);
    setState(() => _loading = false);
  }

  Future<void> _login(UserAccount user) async {
    await _data.saveSession(authenticated: true, email: user.email);
    setState(() => _user = user);
  }

  Future<void> _logout() async {
    await _data.saveSession(authenticated: false);
    setState(() => _user = null);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    if (_user == null) return AuthPage(data: _data, onLogin: _login);
    return DashboardPage(data: _data, currentUser: _user!, onLogout: _logout);
  }
}

class AuthPage extends StatefulWidget {
  const AuthPage({super.key, required this.data, required this.onLogin});
  final LocalDataService data;
  final Future<void> Function(UserAccount) onLogin;
  @override
  State<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends State<AuthPage> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _name = TextEditingController();
  final _org = TextEditingController();
  bool _register = false;
  bool _loading = false;
  UserRole _role = UserRole.colaborador;
  String _status = 'Entre para acessar suas ferramentas operacionais.';

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _name.dispose();
    _org.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final email = _email.text.trim();
    final pass = _password.text.trim();
    if (email.isEmpty || pass.isEmpty) return;
    setState(() => _loading = true);
    try {
      if (_register) {
        final name = _name.text.trim();
        final orgName = _org.text.trim();
        if (name.isEmpty || orgName.isEmpty) throw Exception('Preencha nome e organização.');
        final orgId = 'org_${orgName.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '_')}_${DateTime.now().millisecondsSinceEpoch}';
        final orgs = await widget.data.loadOrganizations();
        orgs.add(Organization(id: orgId, name: orgName));
        await widget.data.saveOrganizations(orgs);
        await widget.data.registerUser(UserAccount(email: email, password: pass, name: name, organizationId: orgId, role: _role));
        setState(() {
          _register = false;
          _status = 'Cadastro concluído. Faça login.';
        });
      } else {
        final result = await widget.data.login(email: email, password: pass);
        if (!result.success || result.user == null) {
          setState(() => _status = 'Credenciais inválidas.');
        } else {
          await widget.onLogin(result.user!);
        }
      }
    } catch (e) {
      setState(() => _status = 'Erro: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 450),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              const Text('Gestor Operacional Pro', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text(_status),
              const SizedBox(height: 8),
              if (_register) ...[
                TextField(controller: _name, decoration: const InputDecoration(labelText: 'Nome', border: OutlineInputBorder())),
                const SizedBox(height: 8),
                TextField(controller: _org, decoration: const InputDecoration(labelText: 'Organização', border: OutlineInputBorder())),
                const SizedBox(height: 8),
                DropdownButtonFormField<UserRole>(
                  value: _role,
                  items: UserRole.values.map((r) => DropdownMenuItem(value: r, child: Text(r.label))).toList(),
                  onChanged: (v) => setState(() => _role = v ?? UserRole.colaborador),
                  decoration: const InputDecoration(labelText: 'Perfil', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 8),
              ],
              TextField(controller: _email, decoration: const InputDecoration(labelText: 'E-mail', border: OutlineInputBorder())),
              const SizedBox(height: 8),
              TextField(controller: _password, obscureText: true, decoration: const InputDecoration(labelText: 'Senha', border: OutlineInputBorder())),
              const SizedBox(height: 8),
              SizedBox(width: double.infinity, child: ElevatedButton(onPressed: _loading ? null : _submit, child: Text(_register ? 'Cadastrar' : 'Entrar'))),
              TextButton(onPressed: _loading ? null : () => setState(() => _register = !_register), child: Text(_register ? 'Já tenho conta' : 'Criar nova conta')),
            ]),
          ),
        ),
      ),
    );
  }
}

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key, required this.data, required this.currentUser, required this.onLogout});
  final LocalDataService data;
  final UserAccount currentUser;
  final Future<void> Function() onLogout;
  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  final _github = GithubService();
  final _secure = const FlutterSecureStorage();
  final _task = TextEditingController();
  final _projectName = TextEditingController();
  final _projectClient = TextEditingController();
  final _projectOwner = TextEditingController();
  final _projectStatus = TextEditingController();
  final _orgName = TextEditingController();
  final _ghOwner = TextEditingController();
  final _ghRepo = TextEditingController();
  final _ghToken = TextEditingController();
  final _issueTitle = TextEditingController();
  final _issueBody = TextEditingController();
  final _prTitle = TextEditingController();
  final _prBody = TextEditingController();
  final _prBase = TextEditingController(text: 'main');
  final _prHead = TextEditingController();

  List<Organization> _orgs = [];
  late String _activeOrg;
  List<TaskItem> _tasks = [];
  List<CompanyProject> _projects = [];
  List<CompanyRequirement> _requirements = [];
  final List<String> _activity = [];
  List<String> _ghIssues = [];
  List<String> _ghPrs = [];
  List<String> _ghCommits = [];
  String _ghStatus = 'Configure e sincronize o GitHub.';
  bool _loading = true;
  bool _ghBusy = false;

  UserRole get _role => widget.currentUser.role;
  bool get _canManageUsers => _role.canManageUsers;
  bool get _canManageProjects => _role.canManageProjects;
  bool get _canManageRequirements => _role.canManageRequirements;

  @override
  void initState() {
    super.initState();
    _activeOrg = widget.currentUser.organizationId;
    _boot();
  }

  Future<void> _boot() async {
    _orgs = await widget.data.loadOrganizations();
    await _loadTenant();
    _ghOwner.text = await _secure.read(key: 'gh_owner') ?? '';
    _ghRepo.text = await _secure.read(key: 'gh_repo') ?? '';
    _ghToken.text = await _secure.read(key: 'gh_token') ?? '';
    setState(() => _loading = false);
  }

  Future<void> _loadTenant() async {
    _tasks = await widget.data.loadTasks(_activeOrg);
    _projects = await widget.data.loadProjects(_activeOrg);
    _requirements = await widget.data.loadRequirements(_activeOrg);
    _log('Tenant ativo: ${_orgLabel(_activeOrg)}');
  }

  String _orgLabel(String id) => _orgs.firstWhere((o) => o.id == id, orElse: () => Organization(id: id, name: id)).name;

  void _log(String m) {
    setState(() {
      _activity.insert(0, m);
      if (_activity.length > 40) _activity.removeLast();
    });
  }

  Future<void> _switchTenant(String id) async {
    setState(() => _loading = true);
    _activeOrg = id;
    await _loadTenant();
    setState(() => _loading = false);
  }

  Future<void> _createOrg() async {
    if (!_canManageUsers) return;
    final name = _orgName.text.trim();
    if (name.isEmpty) return;
    final id = 'org_${name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '_')}_${DateTime.now().millisecondsSinceEpoch}';
    _orgs.add(Organization(id: id, name: name));
    await widget.data.saveOrganizations(_orgs);
    _orgName.clear();
    _log('Organização criada: $name');
  }

  Future<void> _addTask() async {
    final v = _task.text.trim();
    if (v.isEmpty) return;
    _tasks.insert(0, TaskItem(title: v, priority: 'Média'));
    _task.clear();
    await widget.data.saveTasks(_activeOrg, _tasks);
    _log('Tarefa criada.');
    setState(() {});
  }

  Future<void> _addProject() async {
    if (!_canManageProjects) return;
    final a = _projectName.text.trim();
    final b = _projectClient.text.trim();
    final c = _projectOwner.text.trim();
    final d = _projectStatus.text.trim();
    if ([a, b, c, d].any((e) => e.isEmpty)) return;
    _projects.insert(0, CompanyProject(name: a, client: b, status: d, owner: c));
    _projectName.clear();
    _projectClient.clear();
    _projectOwner.clear();
    _projectStatus.clear();
    await widget.data.saveProjects(_activeOrg, _projects);
    _log('Projeto criado: $a');
    setState(() {});
  }

  Future<void> _toggleReq(CompanyRequirement r, bool value) async {
    if (!_canManageRequirements) return;
    r.completed = value;
    await widget.data.saveRequirements(_activeOrg, _requirements);
    _log('Requisito atualizado: ${r.title}');
    setState(() {});
  }

  Future<void> _saveGithubConfig() async {
    await _secure.write(key: 'gh_owner', value: _ghOwner.text.trim());
    await _secure.write(key: 'gh_repo', value: _ghRepo.text.trim());
    await _secure.write(key: 'gh_token', value: _ghToken.text.trim());
  }

  Future<void> _syncGithub() async {
    final owner = _ghOwner.text.trim();
    final repo = _ghRepo.text.trim();
    final token = _ghToken.text.trim();
    if ([owner, repo, token].any((e) => e.isEmpty)) return;
    setState(() => _ghBusy = true);
    try {
      await _saveGithubConfig();
      final s = await _github.fetchAll(owner: owner, repo: repo, token: token);
      _ghIssues = s.issues;
      _ghPrs = s.pullRequests;
      _ghCommits = s.commits;
      _ghStatus = 'Sincronizado com sucesso.';
      _log('GitHub sincronizado.');
    } catch (e) {
      _ghStatus = 'Erro: $e';
    } finally {
      setState(() => _ghBusy = false);
    }
  }

  Future<void> _createIssue() async {
    try {
      final url = await _github.createIssue(
        owner: _ghOwner.text.trim(),
        repo: _ghRepo.text.trim(),
        token: _ghToken.text.trim(),
        title: _issueTitle.text.trim(),
        body: _issueBody.text.trim(),
      );
      _issueTitle.clear();
      _issueBody.clear();
      _ghStatus = 'Issue criada.';
      _log('Issue criada: $url');
      await _syncGithub();
    } catch (e) {
      setState(() => _ghStatus = 'Erro ao criar issue: $e');
    }
  }

  Future<void> _createPr() async {
    if (!_role.canCreatePullRequest) {
      setState(() => _ghStatus = 'Seu perfil não pode criar PR.');
      return;
    }
    try {
      final url = await _github.createPullRequest(
        owner: _ghOwner.text.trim(),
        repo: _ghRepo.text.trim(),
        token: _ghToken.text.trim(),
        title: _prTitle.text.trim(),
        body: _prBody.text.trim(),
        base: _prBase.text.trim(),
        head: _prHead.text.trim(),
      );
      _prTitle.clear();
      _prBody.clear();
      _ghStatus = 'PR criada.';
      _log('PR criada: $url');
      await _syncGithub();
    } catch (e) {
      setState(() => _ghStatus = 'Erro ao criar PR: $e');
    }
  }

  @override
  void dispose() {
    _task.dispose();
    _projectName.dispose();
    _projectClient.dispose();
    _projectOwner.dispose();
    _projectStatus.dispose();
    _orgName.dispose();
    _ghOwner.dispose();
    _ghRepo.dispose();
    _ghToken.dispose();
    _issueTitle.dispose();
    _issueBody.dispose();
    _prTitle.dispose();
    _prBody.dispose();
    _prBase.dispose();
    _prHead.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    final pending = _tasks.where((t) => !t.done).length;
    return DefaultTabController(
      length: 7,
      child: Scaffold(
        appBar: AppBar(
          title: Text('Gestor Operacional Pro - ${widget.currentUser.name} (${_role.label})'),
          actions: [IconButton(onPressed: widget.onLogout, icon: const Icon(Icons.logout))],
          bottom: const TabBar(
            isScrollable: true,
            tabs: [
              Tab(icon: Icon(Icons.apartment), text: 'Tenant'),
              Tab(icon: Icon(Icons.today), text: 'Dia a Dia'),
              Tab(icon: Icon(Icons.work), text: 'Projetos'),
              Tab(icon: Icon(Icons.rule), text: 'Requisitos'),
              Tab(icon: Icon(Icons.group), text: 'Perfis'),
              Tab(icon: Icon(Icons.cloud_sync), text: 'GitHub'),
              Tab(icon: Icon(Icons.timeline), text: 'Atividades'),
            ],
          ),
        ),
        body: TabBarView(children: [_tenantTab(), _dayTab(pending), _projectsTab(), _requirementsTab(), _profilesTab(), _githubTab(), _activityTab()]),
      ),
    );
  }

  Widget _tenantTab() => ListView(
        padding: const EdgeInsets.all(16),
        children: [
          DropdownButtonFormField<String>(
            value: _activeOrg,
            decoration: const InputDecoration(labelText: 'Organização ativa', border: OutlineInputBorder()),
            items: _orgs.map((o) => DropdownMenuItem(value: o.id, child: Text(o.name))).toList(),
            onChanged: (v) {
              if (v != null) _switchTenant(v);
            },
          ),
          const SizedBox(height: 8),
          TextField(controller: _orgName, decoration: const InputDecoration(labelText: 'Nova organização', border: OutlineInputBorder())),
          const SizedBox(height: 8),
          ElevatedButton(onPressed: _canManageUsers ? _createOrg : null, child: const Text('Criar organização (admin)')),
        ],
      );

  Widget _dayTab(int pending) => Padding(
        padding: const EdgeInsets.all(16),
        child: Column(children: [
          ListTile(title: const Text('Resumo de tarefas'), subtitle: Text('Pendentes: $pending/${_tasks.length}')),
          Row(children: [
            Expanded(child: TextField(controller: _task, decoration: const InputDecoration(labelText: 'Nova tarefa', border: OutlineInputBorder()))),
            const SizedBox(width: 8),
            ElevatedButton(onPressed: _addTask, child: const Text('Adicionar')),
          ]),
          const SizedBox(height: 8),
          Expanded(
            child: ListView.builder(
              itemCount: _tasks.length,
              itemBuilder: (context, i) {
                final t = _tasks[i];
                return CheckboxListTile(
                  title: Text(t.title),
                  subtitle: Text(t.priority),
                  value: t.done,
                  onChanged: (v) async {
                    setState(() => t.done = v ?? false);
                    await widget.data.saveTasks(_activeOrg, _tasks);
                  },
                );
              },
            ),
          ),
        ]),
      );

  Widget _projectsTab() => ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(controller: _projectName, decoration: const InputDecoration(labelText: 'Projeto', border: OutlineInputBorder())),
          const SizedBox(height: 8),
          TextField(controller: _projectClient, decoration: const InputDecoration(labelText: 'Cliente', border: OutlineInputBorder())),
          const SizedBox(height: 8),
          TextField(controller: _projectOwner, decoration: const InputDecoration(labelText: 'Responsável', border: OutlineInputBorder())),
          const SizedBox(height: 8),
          TextField(controller: _projectStatus, decoration: const InputDecoration(labelText: 'Status', border: OutlineInputBorder())),
          const SizedBox(height: 8),
          ElevatedButton(onPressed: _canManageProjects ? _addProject : null, child: const Text('Adicionar projeto')),
          if (!_canManageProjects) const Text('Somente admin/gestor podem criar projetos.'),
          ..._projects.map((p) => ListTile(title: Text(p.name), subtitle: Text('${p.client} | ${p.owner}'), trailing: Chip(label: Text(p.status)))),
        ],
      );

  Widget _requirementsTab() => ListView(
        padding: const EdgeInsets.all(16),
        children: _requirements
            .map((r) => SwitchListTile(title: Text(r.title), subtitle: Text(r.description), value: r.completed, onChanged: (v) => _toggleReq(r, v)))
            .toList(),
      );

  Widget _profilesTab() => FutureBuilder<List<UserAccount>>(
        future: widget.data.usersByOrg(_activeOrg),
        builder: (context, s) {
          final users = s.data ?? [];
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text('Seu perfil: ${_role.label}'),
              Text('Permissões: usuários=${_canManageUsers ? 'sim' : 'não'}, projetos=${_canManageProjects ? 'sim' : 'não'}, requisitos=${_canManageRequirements ? 'sim' : 'não'}'),
              const SizedBox(height: 8),
              ...users.map((u) => ListTile(title: Text(u.name), subtitle: Text(u.email), trailing: Chip(label: Text(u.role.label)))),
            ],
          );
        },
      );

  Widget _githubTab() => ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(controller: _ghOwner, decoration: const InputDecoration(labelText: 'Owner', border: OutlineInputBorder())),
          const SizedBox(height: 8),
          TextField(controller: _ghRepo, decoration: const InputDecoration(labelText: 'Repositório', border: OutlineInputBorder())),
          const SizedBox(height: 8),
          TextField(controller: _ghToken, obscureText: true, decoration: const InputDecoration(labelText: 'Token', border: OutlineInputBorder())),
          const SizedBox(height: 8),
          ElevatedButton(onPressed: _ghBusy ? null : _syncGithub, child: const Text('Sincronizar')),
          Text(_ghStatus),
          const Divider(),
          TextField(controller: _issueTitle, decoration: const InputDecoration(labelText: 'Título issue', border: OutlineInputBorder())),
          const SizedBox(height: 8),
          TextField(controller: _issueBody, maxLines: 3, decoration: const InputDecoration(labelText: 'Descrição issue', border: OutlineInputBorder())),
          const SizedBox(height: 8),
          ElevatedButton(onPressed: _ghBusy ? null : _createIssue, child: const Text('Criar Issue')),
          const Divider(),
          TextField(controller: _prTitle, decoration: const InputDecoration(labelText: 'Título PR', border: OutlineInputBorder())),
          const SizedBox(height: 8),
          TextField(controller: _prBody, maxLines: 3, decoration: const InputDecoration(labelText: 'Descrição PR', border: OutlineInputBorder())),
          const SizedBox(height: 8),
          TextField(controller: _prBase, decoration: const InputDecoration(labelText: 'Base', border: OutlineInputBorder())),
          const SizedBox(height: 8),
          TextField(controller: _prHead, decoration: const InputDecoration(labelText: 'Head', border: OutlineInputBorder())),
          const SizedBox(height: 8),
          ElevatedButton(onPressed: _ghBusy ? null : _createPr, child: const Text('Criar PR (admin/gestor)')),
          const Divider(),
          ..._ghIssues.map((e) => ListTile(title: Text(e))),
        ],
      );

  Widget _activityTab() => ListView.builder(itemCount: _activity.length, itemBuilder: (context, i) => ListTile(title: Text(_activity[i])));
}
