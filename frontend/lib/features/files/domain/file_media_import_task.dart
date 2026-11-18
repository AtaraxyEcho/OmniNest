class FileMediaImportTask {
  const FileMediaImportTask({required this.fileNodeId, required this.taskId});

  final String fileNodeId;
  final String taskId;

  factory FileMediaImportTask.fromJson(Map<String, dynamic> json) {
    return FileMediaImportTask(
      fileNodeId: json['fileNodeId']?.toString() ?? '',
      taskId: json['taskId']?.toString() ?? '',
    );
  }
}
