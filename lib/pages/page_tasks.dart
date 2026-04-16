import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/task.dart';
import '../models/user.dart' as app_user;
import '../widgets/task_provider.dart';
import '../widgets/task_card.dart';
import '../widgets/task_dialog.dart';
import '../constants/app_colors.dart';
import '../pages/page_connexion.dart';

class PageTasks extends StatefulWidget {
  final app_user.User user;

  const PageTasks({super.key, required this.user});

  @override
  State<PageTasks> createState() => _PageTasksState();
}

class _PageTasksState extends State<PageTasks> {
  late TaskProvider _taskProvider;
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _taskProvider = TaskProvider(userId: widget.user.id);
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels == _scrollController.position.maxScrollExtent) {
      // Load more tasks if needed
      _loadMoreTasks();
    }
  }

  Future<void> _loadMoreTasks() async {
    if (!_taskProvider.isLoadingMore && !_taskProvider.isLoading) {
      // Implement pagination logic here
    }
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: _taskProvider,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('My Tasks'),
          leading: Builder(
            builder: (context) => IconButton(
              icon: const Icon(Icons.menu, color: Colors.pinkAccent),
              onPressed: () => Scaffold.of(context).openDrawer(),
            ),
          ),
          actions: [
            // Sync indicator
            Consumer<TaskProvider>(
              builder: (context, provider, child) {
                if (provider.pendingOperationsCount > 0) {
                  return Stack(
                    children: [
                      IconButton(
                        icon: provider.isSyncing
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.cloud_sync),
                        onPressed: provider.forceSync,
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
                            '${provider.pendingOperationsCount}',
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
                  );
                }
                return IconButton(
                  icon: const Icon(Icons.sync),
                  onPressed: provider.forceSync,
                );
              },
            ),
            // Profile avatar
            GestureDetector(
              onTap: () => _showProfileDialog(),
              child: Container(
                margin: const EdgeInsets.only(right: 16),
                child: CircleAvatar(
                  radius: 20,
                  backgroundImage: widget.user.photoUrl != null 
                      ? NetworkImage(widget.user.photoUrl!) 
                      : null,
                  child: widget.user.photoUrl == null
                      ? Text(
                          widget.user.fullname.isNotEmpty 
                              ? widget.user.fullname[0].toUpperCase()
                              : 'U',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        )
                      : null,
                  backgroundColor: widget.user.photoUrl == null 
                      ? Colors.blue 
                      : null,
                ),
              ),
            ),
          ],
        ),
        drawer: _buildDrawer(),
        body: Column(
          children: [
            // Search bar
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: TextField(
                decoration: InputDecoration(
                  hintText: 'Rechercher une tâche...',
                  prefixIcon: const Icon(Icons.search),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onChanged: (value) => _taskProvider.updateSearchQuery(value),
              ),
            ),
            // Filters
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: Consumer<TaskProvider>(
                builder: (context, provider, child) => Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<TaskStatus>(
                        decoration: const InputDecoration(labelText: 'Status'),
                        value: provider.filterStatus,
                        items: [
                          const DropdownMenuItem(value: null, child: Text('All')),
                          ...TaskStatus.values.map((s) => DropdownMenuItem(
                            value: s,
                            child: Text(_getStatusText(s)),
                          )),
                        ],
                        onChanged: (value) => provider.updateStatusFilter(value),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: DropdownButtonFormField<int>(
                        decoration: const InputDecoration(labelText: 'Priority'),
                        value: provider.filterPriority,
                        items: const [
                          DropdownMenuItem(value: null, child: Text('All')),
                          DropdownMenuItem(value: 1, child: Text('Low')),
                          DropdownMenuItem(value: 2, child: Text('Medium')),
                          DropdownMenuItem(value: 3, child: Text('High')),
                        ],
                        onChanged: (value) => provider.updatePriorityFilter(value),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            // Task list
            Expanded(
              child: Consumer<TaskProvider>(
                builder: (context, provider, child) {
                  if (provider.isLoading) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  
                  if (provider.filteredTasks.isEmpty) {
                    return const Center(child: Text('No tasks found'));
                  }
                  
                  return ListView.builder(
                  controller: _scrollController,
                  itemCount: provider.filteredTasks.length,
                  itemBuilder: (context, index) {
                    final task = provider.filteredTasks[index];
                    return TaskCard(
                      task: task,
                      onEdit: () => _showTaskDialog(task: task),
                      onDelete: () => _deleteTask(task.id),
                    );
                  },
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
      ),
    );
  }

  void _showTaskDialog({Task? task}) {
    showDialog(
      context: context,
      builder: (context) => TaskDialog(
        user: widget.user,
        initialTask: task,
        isCreating: task == null,
        onSave: ({
          required String title,
          required String description,
          required TaskStatus status,
          DateTime? dueDate,
          int? priority,
        }) async {
          if (task == null) {
            await _taskProvider.createTask(
              title: title,
              description: description,
              status: status,
              dueDate: dueDate,
              priority: priority,
            );
          } else {
            final updatedTask = task.copyWith(
              title: title,
              description: description,
              status: status,
              dueDate: dueDate,
              priority: priority,
              updatedAt: DateTime.now(),
            );
            await _taskProvider.updateTask(updatedTask);
          }
        },
      ),
    );
  }

  Future<void> _deleteTask(String taskId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirm Deletion'),
        content: const Text('Are you sure you want to delete this task?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _taskProvider.deleteTask(taskId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Task deleted successfully'),
            backgroundColor: Colors.green,
          ),
        );
      }
    }
  }

  void _showProfileDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircleAvatar(
              radius: 50,
              backgroundImage: widget.user.photoUrl != null 
                  ? NetworkImage(widget.user.photoUrl!) 
                  : null,
              child: widget.user.photoUrl == null
                  ? Text(
                      widget.user.fullname.isNotEmpty 
                          ? widget.user.fullname[0].toUpperCase()
                          : 'U',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 24,
                      ),
                    )
                  : null,
              backgroundColor: widget.user.photoUrl == null 
                  ? Colors.blue 
                  : null,
            ),
            const SizedBox(height: 16),
            Text(
              widget.user.fullname,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            Text(widget.user.email),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _logout();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.amber[600],
              foregroundColor: Colors.white,
            ),
            child: const Text('Logout'),
          ),
        ],
      ),
    );
  }

  void _logout() async {
    // Implement logout logic
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const PageConnexion()),
    );
  }

  Widget _buildDrawer() {
    return Drawer(
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          UserAccountsDrawerHeader(
            accountName: Text(
              widget.user.fullname,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
            accountEmail: Text(
              widget.user.email,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
              ),
            ),
            currentAccountPicture: CircleAvatar(
              radius: 30,
              backgroundImage: widget.user.photoUrl != null 
                  ? NetworkImage(widget.user.photoUrl!) 
                  : null,
              child: widget.user.photoUrl == null
                  ? Text(
                      widget.user.fullname.isNotEmpty 
                          ? widget.user.fullname[0].toUpperCase()
                          : 'U',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 24,
                      ),
                    )
                  : null,
              backgroundColor: widget.user.photoUrl == null 
                  ? Colors.pink[300] 
                  : null,
            ),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Colors.pink[300]!,
                  Colors.purple[400]!,
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.person, color: Colors.pink),
            title: const Text('My Profile'),
            onTap: () {
              Navigator.pop(context);
              _showProfileDialog();
            },
          ),
          ListTile(
            leading: const Icon(Icons.task_alt, color: Colors.pink),
            title: const Text('Tasks'),
            onTap: () {
              Navigator.pop(context);
              // Already on tasks page
            },
          ),
          ListTile(
            leading: const Icon(Icons.notification_important, color: Colors.pink),
            title: const Text('Reminder'),
            onTap: () {
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Reminders coming soon'),
                  backgroundColor: Colors.pink,
                ),
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.help, color: Colors.pink),
            title: const Text('Help & Support'),
            onTap: () {
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Help coming soon'),
                  backgroundColor: Colors.pink,
                ),
              );
            },
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.info, color: Colors.pink),
            title: const Text('About'),
            onTap: () {
              Navigator.pop(context);
              showAboutDialog(
                context: context,
                applicationName: 'MadTasks',
                applicationVersion: '1.0.0',
                applicationIcon: const Icon(Icons.task_alt, size: 48, color: Colors.pink),
                children: [
                  const Text('MadTasks task management application designed to be essential.\nAdd, track and complete your tasks quickly'),
                ],
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.logout, color: Colors.red),
            title: const Text('Logout'),
            onTap: () {
              Navigator.pop(context);
              _logout();
            },
          ),
        ],
      ),
    );
  }

  String _getStatusText(TaskStatus status) {
    switch (status) {
      case TaskStatus.pending:
        return 'En attente';
      case TaskStatus.in_progress:
        return 'En cours';
      case TaskStatus.completed:
        return 'Terminé';
      case TaskStatus.cancelled:
        return 'Annulé';
    }
  }
}
