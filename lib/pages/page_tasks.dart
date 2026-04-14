import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../models/task.dart';
import '../models/user.dart' as app_user;
import '../services/data_provider_service.dart';
import '../services/error_reporting_service.dart';
import '../services/sync_service.dart';
import '../services/offline_sync_service.dart';
import '../services/offline_service.dart';
import '../services/storage_service.dart';
import '../constants/app_colors.dart';
import 'package:intl/intl.dart';
import 'page_connexion.dart';

class PageTasks extends StatefulWidget {
  final app_user.User user;

  const PageTasks({super.key, required this.user});

  @override
  State<PageTasks> createState() => _PageTasksState();
}

class _PageTasksState extends State<PageTasks> {
  List<Task> _tasks = [];
  bool _isLoading = true;
  String _searchQuery = '';
  TaskStatus? _filterStatus;
  int? _filterPriority;
  bool _isSyncing = false;
  int _pendingOperationsCount = 0;

  @override
  void initState() {
    super.initState();
    _loadTasks();
    _setupSyncListener();
  }

  @override
  void dispose() {
    OfflineSyncService.removeSyncListener(_onSyncStatusChanged);
    super.dispose();
  }

  void _setupSyncListener() {
    // Écouter les changements de synchronisation
    OfflineSyncService.addSyncListener(_onSyncStatusChanged);
    
    // Initialiser le compteur d'opérations en attente
    setState(() {
      _pendingOperationsCount = OfflineSyncService.pendingOperationsCount;
    });
  }

  void _onSyncStatusChanged(List<OfflineOperation> operations) {
    if (mounted) {
      setState(() {
        _pendingOperationsCount = operations.length;
      });
    }
  }

  Future<void> _loadTasks() async {
    setState(() {
      _isLoading = true;
    });

    try {
      // Essai rapide avec timeout de 9 secondes pour détecter le mode hors ligne
      final tasks = await DataProviderService.getTasks(userId: widget.user.id).timeout(const Duration(seconds: 9));
      setState(() {
        _tasks = tasks;
        _isLoading = false;
      });
    } catch (e, stack) {
      // Mode détecté comme hors ligne ou erreur réseau
      debugPrint('Mode offline détecté pour le chargement: $e');
      try {
        final offlineTasks = await OfflineService.getOfflineTasks(userId: widget.user.id);
        setState(() {
          _tasks = offlineTasks;
          _isLoading = false;
        });
        debugPrint('Chargé ${offlineTasks.length} tâches locales');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Mode offline : ${offlineTasks.length} tâches locales chargées'),
              backgroundColor: Colors.orange,
            ),
          );
        }
      } catch (offlineError) {
        ErrorReportingService.reportError(offlineError, StackTrace.current, context: {'action': 'load_offline_tasks'});
        setState(() {
          _isLoading = false;
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Erreur chargement local: $offlineError')),
          );
        }
      }
    }
  }

  Future<void> _loadTasksOfflineOnly() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final offlineTasks = await OfflineService.getOfflineTasks(userId: widget.user.id);
      setState(() {
        _tasks = offlineTasks;
        _isLoading = false;
      });
      debugPrint('Chargement de ${offlineTasks.length} tâches locales');
    } catch (offlineError) {
      ErrorReportingService.reportError(offlineError, StackTrace.current, context: {'action': 'load_offline_tasks_only'});
      setState(() {
        _isLoading = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur chargement local: $offlineError')),
        );
      }
    }
  }

  Future<void> _loadTasksWithoutSync() async {
    setState(() {
      _isLoading = true;
    });

    try {
      // Charger les tâches SANS synchronisation automatique pour éviter les doublons
      final tasks = await DataProviderService.getTasks(userId: widget.user.id, enableSync: false);
      setState(() {
        _tasks = tasks;
        _isLoading = false;
      });
      debugPrint('Chargé ${tasks.length} tâches sans synchronisation');
    } catch (e, stack) {
      // En cas d'erreur, essayer le stockage offline
      try {
        final offlineTasks = await OfflineService.getOfflineTasks(userId: widget.user.id);
        setState(() {
          _tasks = offlineTasks;
          _isLoading = false;
        });
        debugPrint('Chargé ${offlineTasks.length} tâches locales (fallback)');
      } catch (offlineError) {
        ErrorReportingService.reportError(offlineError, StackTrace.current, context: {'action': 'load_tasks_no_sync'});
        setState(() {
          _isLoading = false;
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Erreur chargement: $offlineError')),
          );
        }
      }
    }
  }

  List<Task> get _filteredTasks {
    return _tasks.where((task) {
      final matchesSearch = task.title.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          task.description.toLowerCase().contains(_searchQuery.toLowerCase());
      final matchesStatus = _filterStatus == null || task.status == _filterStatus;
      final matchesPriority = _filterPriority == null || task.priority == _filterPriority;
      return matchesSearch && matchesStatus && matchesPriority;
    }).toList();
  }

  void _showTaskDialog({Task? task}) {
    showDialog(
      context: context,
      builder: (context) => _TaskDialog(
        user: widget.user,
        initialTask: task,
        isCreating: task == null,
        onSave: ({
          required String title,
          required String description,
          required TaskStatus status,
          DateTime? dueDate,
          int? priority,
          List<String>? tags,
        }) async {
          try {
            if (task == null) {
              final newTask = Task(
                id: Uuid().v4(), // Générer un UUID valide pour Supabase
                title: title,
                description: description,
                status: status,
                createdAt: DateTime.now(),
                dueDate: dueDate,
                userId: widget.user.id,
                priority: priority ?? 2,
                tags: tags ?? [],
              );
              
              // Vérifier la connectivité et créer la tâche
              try {
                // Essai rapide avec timeout de 9 secondes pour détecter le mode hors ligne
                await DataProviderService.createTask(newTask).timeout(const Duration(seconds: 9));
                // Recharger la liste des tâches après création réussie SANS synchronisation
                _loadTasksWithoutSync();
              } catch (e) {
                // Mode détecté comme hors ligne ou erreur réseau
                debugPrint('Mode offline détecté, création locale: $e');
                final createdTask = await OfflineSyncService.createTaskOffline(newTask);
                debugPrint('Tâche créée offline: ${createdTask.id} - ${createdTask.title}');
                
                // Ajouter immédiatement la tâche à la liste pour affichage
                setState(() {
                  _tasks.insert(0, createdTask); // Ajouter au début
                  debugPrint('Tâche ajoutée à la liste. Nombre total: ${_tasks.length}');
                });
                
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Tâche créée en mode offline, synchronisation automatique'),
                      backgroundColor: Colors.orange,
                    ),
                  );
                }
              }
            } else {
              final updatedTask = task.copyWith(
                title: title,
                description: description,
                status: status,
                dueDate: dueDate,
                priority: priority ?? 2,
                tags: tags ?? [],
                updatedAt: DateTime.now(),
              );
              
              // Essayer de mettre à jour normalement, si échec utiliser offline
              try {
                await DataProviderService.updateTask(updatedTask);
              } catch (e) {
                // En cas d'erreur, utiliser le mode offline
                await OfflineSyncService.updateTaskOffline(updatedTask);
                
                // Mettre à jour immédiatement la tâche dans la liste
                setState(() {
                  final taskIndex = _tasks.indexWhere((t) => t.id == updatedTask.id);
                  if (taskIndex != -1) {
                    _tasks[taskIndex] = updatedTask;
                  }
                });
                
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Tâche mise à jour en mode offline, synchronisation automatique'),
                      backgroundColor: Colors.orange,
                    ),
                  );
                }
              }
            }
            _loadTasks();
          } catch (e, stack) {
            ErrorReportingService.reportError(e, stack, context: {'action': 'save_task'});
            rethrow;
          }
        },
      ),
    );
  }

  Future<void> _deleteTask(String taskId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Supprimer la tâche'),
        content: const Text('Êtes-vous sûr de vouloir supprimer cette tâche ?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annuler'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await DataProviderService.deleteTask(taskId);
        _loadTasks();
      } catch (e) {
        // En cas d'erreur, utiliser le mode offline
        try {
          await OfflineSyncService.deleteTaskOffline(taskId);
          
          // Supprimer immédiatement la tâche de la liste
          setState(() {
            _tasks.removeWhere((t) => t.id == taskId);
          });
          
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Tâche supprimée en mode offline, synchronisation automatique'),
                backgroundColor: Colors.orange,
              ),
            );
          }
        } catch (offlineError) {
          ErrorReportingService.reportError(e, StackTrace.current, context: {'action': 'delete_task'});
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Erreur lors de la suppression: $e')),
            );
          }
        }
      }
    }
  }

  Future<void> _logout() async {
    try {
      // Afficher un dialogue de confirmation
      final confirm = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Déconnexion'),
          content: const Text('Êtes-vous sûr de vouloir vous déconnecter ?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Annuler'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Déconnexion'),
            ),
          ],
        ),
      );

      if (confirm == true) {
        // Déconnexion de tous les providers
        await DataProviderService.signOut();
        
        // Réinitialiser l'état d'onboarding pour forcer la réinitialisation
        await StorageService.setOnboardingCompleted(false);
        
        if (mounted) {
          // Rediriger vers la page de connexion
          Navigator.pushAndRemoveUntil(
            context,
            MaterialPageRoute(builder: (_) => const PageConnexion()),
            (route) => false,
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur lors de la déconnexion: $e')),
        );
      }
    }
  }

  Future<void> _forceSync() async {
    setState(() => _isSyncing = true);
    
    try {
      // Forcer la synchronisation offline
      final result = await OfflineSyncService.forceSync();
      
      // Synchronisation normale
      await SyncService.forceSyncNow();
      
      // Recharger les tâches SANS synchronisation pour éviter les doublons
      await _loadTasksWithoutSync();
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result.message),
            backgroundColor: result.success ? Colors.green : Colors.orange,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur de synchronisation: $e')),
        );
      }
    } finally {
      setState(() => _isSyncing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mes Tâches'),
        actions: [
          // Indicateur de synchronisation offline
          if (_pendingOperationsCount > 0)
            Stack(
              children: [
                IconButton(
                  icon: _isSyncing 
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.cloud_sync),
                  onPressed: _forceSync,
                ),
                Positioned(
                  right: 8,
                  top: 8,
                  child: Container(
                    padding: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      color: Colors.orange,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    constraints: const BoxConstraints(
                      minWidth: 16,
                      minHeight: 16,
                    ),
                    child: Text(
                      '$_pendingOperationsCount',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              ],
            ),
          
          // Bouton de synchronisation normal
          IconButton(
            icon: const Icon(Icons.sync),
            onPressed: _forceSync,
          ),
          // Bouton de déconnexion
          PopupMenuButton<String>(
            onSelected: (value) async {
              if (value == 'logout') {
                await _logout();
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'logout',
                child: Row(
                  children: [
                    Icon(Icons.logout, size: 20),
                    SizedBox(width: 8),
                    Text('Déconnexion'),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: TextField(
              decoration: InputDecoration(
                hintText: 'Rechercher une tâche...',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onChanged: (value) => setState(() => _searchQuery = value),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<TaskStatus>(
                    decoration: const InputDecoration(labelText: 'Statut'),
                    value: _filterStatus,
                    items: [
                      const DropdownMenuItem(value: null, child: Text('Tous')),
                      ...TaskStatus.values.map((s) => DropdownMenuItem(
                        value: s,
                        child: Text(s.name),
                      )),
                    ],
                    onChanged: (value) => setState(() => _filterStatus = value),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: DropdownButtonFormField<int>(
                    decoration: const InputDecoration(labelText: 'Priorité'),
                    value: _filterPriority,
                    items: const [
                      DropdownMenuItem(value: null, child: Text('Toutes')),
                      DropdownMenuItem(value: 1, child: Text('Basse')),
                      DropdownMenuItem(value: 2, child: Text('Moyenne')),
                      DropdownMenuItem(value: 3, child: Text('Haute')),
                    ],
                    onChanged: (value) => setState(() => _filterPriority = value),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _filteredTasks.isEmpty
                    ? const Center(child: Text('Aucune tâche trouvée'))
                    : ListView.builder(
                        itemCount: _filteredTasks.length,
                        itemBuilder: (context, index) {
                          final task = _filteredTasks[index];
                          return _TaskCard(
                            task: task,
                            onEdit: () => _showTaskDialog(task: task),
                            onDelete: () => _deleteTask(task.id),
                          );
                        },
                      ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showTaskDialog(),
        backgroundColor: AppColors.primary,
        child: const Icon(Icons.add, color: Colors.white),
      ),
    );
  }
}

class _TaskCard extends StatelessWidget {
  final Task task;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _TaskCard({
    required this.task,
    required this.onEdit,
    required this.onDelete,
  });

  Color _getPriorityColor(int priority) {
    switch (priority) {
      case 1: return Colors.green;
      case 2: return Colors.orange;
      case 3: return Colors.red;
      default: return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat('dd/MM/yyyy HH:mm');
    
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        title: Text(
          task.title,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(task.description, maxLines: 2, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 4),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: _getPriorityColor(task.priority).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    'Priorité ${task.priority}',
                    style: TextStyle(color: _getPriorityColor(task.priority), fontSize: 12),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  task.status.name,
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
                ),
              ],
            ),
            if (task.dueDate != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  'Échéance: ${dateFormat.format(task.dueDate!)}',
                  style: TextStyle(
                    fontSize: 11,
                    color: task.dueDate!.isBefore(DateTime.now()) ? Colors.red : Colors.grey[600],
                  ),
                ),
              ),
          ],
        ),
        isThreeLine: true,
        trailing: PopupMenuButton<String>(
          onSelected: (value) {
            if (value == 'edit') onEdit();
            if (value == 'delete') onDelete();
          },
          itemBuilder: (context) => [
            const PopupMenuItem(value: 'edit', child: Text('Modifier')),
            const PopupMenuItem(value: 'delete', child: Text('Supprimer')),
          ],
        ),
      ),
    );
  }
}

class _TaskDialog extends StatefulWidget {
  final app_user.User user;
  final Task? initialTask;
  final Future<void> Function({
    required String title,
    required String description,
    required TaskStatus status,
    DateTime? dueDate,
    int? priority,
    List<String>? tags,
  }) onSave;
  final bool isCreating;

  const _TaskDialog({
    required this.user,
    this.initialTask,
    required this.onSave,
    required this.isCreating,
  });

  @override
  State<_TaskDialog> createState() => _TaskDialogState();
}

class _TaskDialogState extends State<_TaskDialog> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _titleController;
  late TextEditingController _descController;
  late TaskStatus _status;
  late int _priority;
  DateTime? _dueDate;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.initialTask?.title ?? '');
    _descController = TextEditingController(text: widget.initialTask?.description ?? '');
    _status = widget.initialTask?.status ?? TaskStatus.pending;
    _priority = widget.initialTask?.priority ?? 2;
    _dueDate = widget.initialTask?.dueDate;
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.isCreating ? 'Nouvelle Tâche' : 'Modifier la Tâche'),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _titleController,
                decoration: const InputDecoration(labelText: 'Titre'),
                validator: (value) => value == null || value.isEmpty ? 'Champ requis' : null,
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _descController,
                decoration: const InputDecoration(labelText: 'Description'),
                maxLines: 3,
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<TaskStatus>(
                value: _status,
                decoration: const InputDecoration(labelText: 'Statut'),
                items: TaskStatus.values.map((s) => DropdownMenuItem(
                  value: s,
                  child: Text(s.name),
                )).toList(),
                onChanged: (value) => setState(() => _status = value!),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<int>(
                value: _priority,
                decoration: const InputDecoration(labelText: 'Priorité'),
                items: const [
                  DropdownMenuItem(value: 1, child: Text('Basse')),
                  DropdownMenuItem(value: 2, child: Text('Moyenne')),
                  DropdownMenuItem(value: 3, child: Text('Haute')),
                ],
                onChanged: (value) => setState(() => _priority = value!),
              ),
              const SizedBox(height: 8),
              ListTile(
                title: Text(_dueDate == null ? 'Aucune date d\'échéance' : 'Échéance: ${DateFormat('dd/MM/yyyy').format(_dueDate!)}'),
                trailing: const Icon(Icons.calendar_today),
                onTap: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: _dueDate ?? DateTime.now(),
                    firstDate: DateTime.now().subtract(const Duration(days: 365)),
                    lastDate: DateTime.now().add(const Duration(days: 365 * 2)),
                  );
                  if (picked != null) setState(() => _dueDate = picked);
                },
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSaving ? null : () => Navigator.pop(context),
          child: const Text('Annuler'),
        ),
        ElevatedButton(
          onPressed: _isSaving ? null : _save,
          child: _isSaving ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Enregistrer'),
        ),
      ],
    );
  }

  Future<void> _save() async {
    if (_formKey.currentState!.validate()) {
      setState(() => _isSaving = true);
      try {
        await widget.onSave(
          title: _titleController.text,
          description: _descController.text,
          status: _status,
          dueDate: _dueDate,
          priority: _priority,
          tags: widget.initialTask?.tags ?? [],
        );
        if (mounted) {
          setState(() => _isSaving = false);
          Navigator.pop(context);
        }
      } catch (e) {
        setState(() => _isSaving = false);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Erreur: $e')),
          );
        }
      }
    }
  }
}
